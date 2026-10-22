/// CONTRACT §16.7 and §16.8: `confirmCardPayment` after validation (load
/// the order, encrypt, `/pay`, run `nextAction`, 3-D Secure, status
/// polling), and the state of the 3DS sheet. No widgets: the sheet renders
/// a [ThreeDsSession].
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../card/client_order.dart';
import '../../error.dart';
import '../../result.dart';
import '../../status.dart';
import '../logger.dart';
import '../native_bridge.dart';
import '../status_resolution.dart';
import '../strings.dart';
import '../url_policy.dart';
import 'card_clock.dart';
import 'card_crypto.dart';
import 'client_api.dart';
import 'next_action.dart';
import 'three_ds_policy.dart';
import 'three_ds_website_data.dart';

/// Status polling interval (CONTRACT §16.7 step 5).
const Duration cardPollInterval = Duration(milliseconds: 2500);

/// Status polling timeout.
const Duration cardPollTimeout = Duration(seconds: 120);

/// The wait between `/three-ds` polls.
const Duration threeDsPollInterval = Duration(seconds: 1);

/// How many times `/three-ds` is polled.
const int threeDsPollTries = 30;

/// The statuses that end status polling (`card_api.json`).
const Set<PayriffPaymentStatus> cardFinalStatuses = <PayriffPaymentStatus>{
  PayriffPaymentStatus.approved,
  PayriffPaymentStatus.preAuthApproved,
  PayriffPaymentStatus.declined,
  PayriffPaymentStatus.canceled,
  PayriffPaymentStatus.expired,
  PayriffPaymentStatus.preAuthExpired,
  PayriffPaymentStatus.refunded,
  PayriffPaymentStatus.partialRefund,
  PayriffPaymentStatus.reverse,
};

/// A `/status` payload as a [StatusReading].
StatusReading cardStatusReading(Map<String, Object?> payload) {
  final Object? raw = payload['status'];
  final Object? amount = payload['amount'];
  final Object? currency = payload['currency'];
  final String? rawStatus = raw is String ? raw : null;
  return StatusReading(
    status: PayriffPaymentStatus.parse(rawStatus),
    rawStatus: rawStatus,
    amount: switch (amount) {
      final num n => n,
      final String s => num.tryParse(s.trim()),
      _ => null,
    },
    currency: currency is String ? currency : null,
  );
}

/// CONTRACT §8.2 for the card flow: the result of a final [reading], or
/// `null` when it is not final. `transactionId` is `null`.
PayriffResult? cardResultFor(String orderId, StatusReading reading) {
  if (!cardFinalStatuses.contains(reading.status)) return null;
  return resultForFinalStatus(paymentFor(orderId, reading));
}

// ---------------------------------------------------------------------------
// 3DS sheet state

/// What the 3DS sheet shows.
enum ThreeDsView {
  /// The native loader (the 3-D Secure Method runs in hidden WebViews).
  loader,

  /// The bank page.
  page,

  /// The native loader while the status is resolved.
  verifying,
}

/// One load of a 3DS WebView: a GET, or a form POST of [body].
@immutable
final class ThreeDsRequest {
  /// A GET of [url].
  const ThreeDsRequest.get(this.url) : body = null;

  /// A POST of [body] (`application/x-www-form-urlencoded`) to [url].
  const ThreeDsRequest.post(this.url, Uint8List this.body);

  /// The URL.
  final Uri url;

  /// The form body of a POST; `null` for a GET. Never logged.
  final Uint8List? body;

  /// Whether this is a POST.
  bool get isPost => body != null;

  /// Loads this request into [controller] with a native POST or GET; the
  /// SDK never builds HTML.
  Future<void> loadInto(WebViewController controller) {
    final Uint8List? form = body;
    if (form == null) return controller.loadRequest(url);
    return controller.loadRequest(
      url,
      method: LoadRequestMethod.post,
      headers: const <String, String>{
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: form,
    );
  }

  @override
  String toString() =>
      'ThreeDsRequest(${isPost ? 'POST' : 'GET'} ${redactUrl(url.toString())})';
}

/// Commands from a [ThreeDsSession] to the sheet that shows it.
abstract interface class ThreeDsHost {
  /// Loads [request] in the visible WebView.
  void load(ThreeDsRequest request);

  /// Stops the visible WebView (a page that ends the flow never renders).
  void stopLoading();

  /// Reloads the visible WebView's current page.
  void reload();

  /// Asks the customer to confirm closing. Completes with `true` when they
  /// confirm.
  Future<bool> confirmCancel();

  /// Removes any dialog the sheet opened.
  void dismissDialogs();
}

/// The state of the 3DS sheet (CONTRACT §16.8): its view, its WebView
/// requests and the navigation rules. The card flow drives it; the sheet
/// renders it and reports WebView signals and customer actions.
final class ThreeDsSession extends ChangeNotifier {
  /// Creates the state for the API at [apiBaseUrl].
  ThreeDsSession({
    required this.apiBaseUrl,
    required this.strings,
    SdkLogger? logger,
    Future<bool> Function(String url)? openExternal,
  }) : _logger = logger ?? SdkLogger.silent,
       _openExternal = openExternal ?? NativeBridge.openExternal,
       _policy = ThreeDsNavigationPolicy(apiBaseUrl);

  /// The card flow's API base URL (for the callback rule).
  final String apiBaseUrl;

  /// The UI strings.
  final PayriffStrings strings;

  /// The sites this payment's WebViews loaded (CONTRACT §9.1a): the sheet
  /// records its pages here, the hidden 3-D Secure Method views theirs.
  final ThreeDsWebsiteData websiteData = ThreeDsWebsiteData();

  final SdkLogger _logger;
  final Future<bool> Function(String url) _openExternal;
  ThreeDsNavigationPolicy _policy;
  ThreeDsHost? _host;

  ThreeDsView _view = ThreeDsView.loader;
  ThreeDsRequest? _page;
  List<ThreeDsRequest> _hidden = const <ThreeDsRequest>[];
  int _hiddenGeneration = 0;
  bool _pageLoadFailed = false;
  bool _pageLoaded = false;
  bool _finished = false;
  bool _closedBySdk = false;
  bool _disposed = false;
  final StreamController<void> _callbackLoaded =
      StreamController<void>.broadcast(sync: true);
  final StreamController<void> _finish = StreamController<void>.broadcast(
    sync: true,
  );
  final Completer<void> _closeRequested = Completer<void>();

  /// What the sheet shows.
  ThreeDsView get view => _view;

  /// The bank page request, once one was shown.
  ThreeDsRequest? get page => _page;

  /// The hidden 3-D Secure Method requests; empty when none run.
  List<ThreeDsRequest> get hidden => _hidden;

  /// Changes whenever [hidden] is replaced, so the sheet rebuilds its hidden
  /// WebViews.
  int get hiddenGeneration => _hiddenGeneration;

  /// Whether the bank page failed to load.
  bool get pageLoadFailed => _pageLoadFailed;

  /// Whether the bank page has finished loading at least once.
  bool get pageLoaded => _pageLoaded;

  /// Fires when a gateway callback page has loaded (or failed to load).
  Stream<void> get callbackLoaded => _callbackLoaded.stream;

  /// Fires when the first main-frame navigation after the callback ended the
  /// flow.
  Stream<void> get finished => _finish.stream;

  /// Completes when the customer closed the sheet (confirmed), or the sheet
  /// disappeared without the SDK closing it.
  Future<void> get closeRequested => _closeRequested.future;

  /// Whether [closeRequested] has completed.
  bool get isCloseRequested => _closeRequested.isCompleted;

  /// Whether the customer may close the sheet now.
  bool get canClose => _view != ThreeDsView.verifying && !_finished;

  /// The sheet attaches itself.
  void attach(ThreeDsHost host) {
    _host = host;
    final ThreeDsRequest? page = _page;
    if (page != null && _view == ThreeDsView.page) host.load(page);
  }

  /// The sheet detaches itself.
  void detach(ThreeDsHost host) {
    if (identical(_host, host)) _host = null;
  }

  // -------------------------------------------------------------------
  // Card flow -> sheet

  /// Shows the bank page [request] with fresh navigation rules.
  void showPage(ThreeDsRequest request) {
    _policy = ThreeDsNavigationPolicy(apiBaseUrl);
    _page = request;
    _view = ThreeDsView.page;
    _pageLoadFailed = false;
    _pageLoaded = false;
    _finished = false;
    _logger.info('3-D Secure page: $request');
    _notify();
    _host?.load(request);
  }

  /// Runs [requests] in hidden WebViews (the 3-D Secure Method).
  void showHidden(List<ThreeDsRequest> requests) {
    _hidden = List<ThreeDsRequest>.unmodifiable(requests);
    _hiddenGeneration++;
    _notify();
  }

  /// Destroys the hidden WebViews.
  void clearHidden() {
    if (_hidden.isEmpty) return;
    _hidden = const <ThreeDsRequest>[];
    _hiddenGeneration++;
    _notify();
  }

  /// Shows the native loader while the status is resolved.
  void showVerifying() {
    if (_view == ThreeDsView.verifying) return;
    _view = ThreeDsView.verifying;
    _host?.dismissDialogs();
    _notify();
  }

  /// The SDK is about to close the sheet itself.
  void markClosedBySdk() => _closedBySdk = true;

  // -------------------------------------------------------------------
  // Sheet -> card flow

  /// The visible WebView's navigation request.
  NavigationDecision decideNavigation(String url, {required bool isMainFrame}) {
    if (_finished || _view != ThreeDsView.page) {
      return NavigationDecision.prevent;
    }
    final ThreeDsNavigationAction action = _policy.decide(
      url,
      isMainFrame: isMainFrame,
    );
    _logger.debug('3DS navigation ${redactUrl(url)}: ${action.name}');
    switch (action) {
      case ThreeDsNavigationAction.allow:
      case ThreeDsNavigationAction.allowCallback:
        websiteData.record(url);
        return NavigationDecision.navigate;
      case ThreeDsNavigationAction.finish:
        _onFinish();
        return NavigationDecision.prevent;
      case ThreeDsNavigationAction.external:
        unawaited(_launch(url));
        return NavigationDecision.prevent;
      case ThreeDsNavigationAction.block:
        return NavigationDecision.prevent;
    }
  }

  /// `onPageStarted` / `onUrlChange` of the visible WebView. Android does not
  /// report POST navigations (the bank's `cres` POST to the callback) as
  /// navigation requests, so main-frame URLs are classified here too.
  void onMainFrameUrl(String url) {
    // The WebView has requested this page, whatever the rules say now.
    websiteData.record(url);
    if (_finished || _view != ThreeDsView.page) return;
    final bool wasArmed = _policy.callbackSeen;
    final ThreeDsNavigationAction action = _policy.decide(
      url,
      isMainFrame: true,
    );
    if (action == ThreeDsNavigationAction.finish && wasArmed) {
      _host?.stopLoading();
      _onFinish();
    } else if (action == ThreeDsNavigationAction.block) {
      // A non-https main frame that bypassed the navigation request (a form
      // POST on Android) never stays on screen (CONTRACT §16.8).
      _logger.warning('Blocked 3-D Secure page ${redactUrl(url)}');
      _host?.stopLoading();
      _pageLoadFailed = true;
      _notify();
    }
  }

  /// `onPageFinished` of the visible WebView.
  void onPageFinished(String url) {
    websiteData.record(url);
    if (_finished || _view != ThreeDsView.page) return;
    if (!isBlankPageUrl(url)) {
      _pageLoaded = true;
      _notify();
    }
    if (_policy.isGatewayCallback(url)) _onCallbackLoaded('loaded');
  }

  /// `onWebResourceError` of the visible WebView.
  void onWebResourceError(WebResourceError error) {
    if (_finished || _view != ThreeDsView.page) return;
    if (!(error.isForMainFrame ?? false)) return;
    final String? url = error.url;
    if (url != null && _policy.isGatewayCallback(url)) {
      // The request carrying the bank's answer was sent; the status says
      // whether it arrived.
      _onCallbackLoaded('load error ${error.errorCode}');
      return;
    }
    // Errors that follow a cancelled load do not count (CONTRACT §9.4).
    if (error.errorCode == -999 ||
        error.errorCode == 102 ||
        error.description.contains('ERR_ABORTED')) {
      return;
    }
    if (url != null && !isAbsoluteHttpUrl(url)) {
      // A scheme hand-off that bypassed the navigation request.
      if (_policy.decide(url, isMainFrame: true) ==
          ThreeDsNavigationAction.external) {
        unawaited(_launch(url));
      }
      return;
    }
    _logger.warning(
      'The 3-D Secure page failed to load (${error.errorCode}): '
      '${url == null ? 'unknown URL' : redactUrl(url)}',
    );
    _pageLoadFailed = true;
    _notify();
  }

  /// The sheet's WebView has no navigation rules, so it loads nothing: shown
  /// as the page-load error (closing checks the status).
  void onPageUnavailable() {
    if (_finished || _view != ThreeDsView.page) return;
    _pageLoadFailed = true;
    _notify();
  }

  /// "Try again" on the page-load error: reloads the page, or sends the
  /// first request again when no page has loaded yet.
  void retryPageLoad() {
    if (!_pageLoadFailed || _finished) return;
    _pageLoadFailed = false;
    _notify();
    final ThreeDsRequest? page = _page;
    if (!_pageLoaded && page != null) {
      _host?.load(page);
    } else {
      _host?.reload();
    }
  }

  /// The close button, the header drag or the back gesture: asks for
  /// confirmation, then ends the 3DS step (CONTRACT §16.8).
  Future<void> requestClose() async {
    if (!canClose || _closeRequested.isCompleted) return;
    final ThreeDsHost? host = _host;
    final bool confirmed = host == null || await host.confirmCancel();
    if (!confirmed || !canClose || _closeRequested.isCompleted) return;
    _logger.info('The customer closed the 3-D Secure sheet');
    showVerifying();
    _closeRequested.complete();
  }

  /// The sheet's route ended. Unless the SDK closed it, this is a close by
  /// the customer (for example the app replaced its Navigator).
  void onSheetDismissed() {
    if (_closedBySdk || _closeRequested.isCompleted) return;
    _closeRequested.complete();
  }

  void _onCallbackLoaded(String signal) {
    _logger.info('Payriff 3-D Secure callback $signal');
    if (!_callbackLoaded.isClosed) _callbackLoaded.add(null);
  }

  void _onFinish() {
    if (_finished) return;
    _finished = true;
    _logger.info('3-D Secure finished');
    _notify();
    if (!_finish.isClosed) _finish.add(null);
  }

  Future<void> _launch(String url) async {
    if (!mayOpenExternally(url)) return;
    _logger.info('Opening outside the app: ${redactUrl(url)}');
    if (!await _openExternal(url)) {
      _logger.warning('No app opened ${redactUrl(url)}');
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_callbackLoaded.close());
    unawaited(_finish.close());
    super.dispose();
  }
}

/// The navigation rules of a hidden 3-D Secure Method WebView: it may load
/// pages (including the callback) but never ends the flow, opens apps or
/// leaves https.
NavigationDecision decideHiddenNavigation(
  ThreeDsNavigationPolicy policy,
  String url, {
  required bool isMainFrame,
}) => switch (policy.decide(url, isMainFrame: isMainFrame)) {
  ThreeDsNavigationAction.allow ||
  ThreeDsNavigationAction.allowCallback => NavigationDecision.navigate,
  _ => NavigationDecision.prevent,
};

/// A presented 3DS sheet.
abstract interface class ThreeDsSheet {
  /// Closes the sheet if it is still shown.
  void close();
}

/// Presents the 3DS sheet for [session]; `null` when it cannot be shown.
typedef ThreeDsSheetOpener = ThreeDsSheet? Function(ThreeDsSession session);

// ---------------------------------------------------------------------------
// The card payment

/// One `confirmCardPayment` after the form validated (CONTRACT §16.7 steps
/// 2–5).
final class CardPayment {
  /// Creates a payment of [orderId] through [api].
  CardPayment({
    required this.api,
    required this.orderId,
    required this.clock,
    required this.strings,
    required ThreeDsSheetOpener openSheet,
    SdkLogger? logger,
    void Function()? onSubmitted,
  }) : _openSheet = openSheet,
       _logger = logger ?? SdkLogger.silent,
       _onSubmitted = onSubmitted;

  /// The Client API session.
  final ClientApi api;

  /// The trimmed order id.
  final String orderId;

  /// The clock for retries and polling.
  final CardClock clock;

  /// The UI strings of the 3DS sheet.
  final PayriffStrings strings;

  final ThreeDsSheetOpener _openSheet;
  final SdkLogger _logger;
  final void Function()? _onSubmitted;

  ThreeDsSession? _session;
  ThreeDsSheet? _sheet;
  StatusReading? _last;
  bool _sheetUnavailable = false;

  /// Whether `/pay` was sent: from then on the payment may have gone
  /// through, whatever happens in the app.
  bool _sent = false;

  /// Runs the payment of [card]. Never throws.
  Future<PayriffResult> run(CardPlaintext card) async {
    try {
      return await _run(card);
    } on Object catch (e) {
      _logger.error('The card payment failed unexpectedly: ${e.runtimeType}');
      if (_sent) {
        // The card was sent: as on a close, one status check decides and
        // anything else is pending, never a failure (CONTRACT §16.0 item 3).
        try {
          return await _closePath();
        } on Object {
          return PayriffResultPending(
            payment: paymentFor(orderId, _last),
            reason: PayriffPendingReason.notFinal,
          );
        }
      }
      return const PayriffResultFailed(
        error: PayriffError(
          code: PayriffErrorCode.unknown,
          message: 'The card payment failed unexpectedly.',
        ),
      );
    } finally {
      _closeSheet();
      final ThreeDsSession? session = _session;
      _session = null;
      if (session != null) {
        _removeWebsiteData(session.websiteData);
        session.dispose();
      }
    }
  }

  /// CONTRACT §9.1a: once the result is decided, removes the website data
  /// of the sites the payment's WebViews loaded. Fire-and-forget: it never
  /// delays or changes the result, and a failure is only logged. Nothing
  /// happens when no WebView loaded a page.
  void _removeWebsiteData(ThreeDsWebsiteData data) {
    if (data.isEmpty) return;
    final List<String> hosts = data.hosts;
    unawaited(() async {
      try {
        await NativeBridge.clearWebsiteData(
          hosts: hosts,
          origins: data.origins,
          urls: data.urls,
        );
        _logger.debug(
          'Removed the 3-D Secure website data of ${hosts.join(', ')}',
        );
      } on Object catch (e) {
        _logger.debug(
          'Could not remove the 3-D Secure website data: ${redactError(e)}',
        );
      }
    }());
  }

  Future<PayriffResult> _run(CardPlaintext card) async {
    // Step 2: the order must be payable by card.
    final PayriffClientOrder order;
    try {
      order = PayriffClientOrder.fromPayload(
        await api.retrieveOrder(orderId),
        requestedOrderId: orderId,
      );
    } on PayriffException catch (e) {
      return PayriffResultFailed(error: e.error);
    }
    if (!order.isPayableByCard) {
      _logger.warning(
        'Order $orderId is not payable by card '
        '(${order.rawStatus ?? 'no status'}, methods ${order.paymentMethods})',
      );
      return PayriffResultFailed(
        error: PayriffError(
          code: PayriffErrorCode.orderNotPayable,
          message: order.paymentMethods.contains('CARD')
              ? 'The order cannot be paid any more '
                    '(${order.rawStatus ?? 'unknown status'}).'
              : 'The order does not accept card payments.',
        ),
      );
    }

    // Step 3: encrypt natively and POST /pay.
    final Uint8List plaintext = buildCardJsonBytes(card);
    final ({String encryptedMessage, String wrappedKey}) sealed;
    try {
      sealed = await NativeBridge.encryptCard(plaintext, payriffPublicKeyDer());
    } on PayriffException catch (e) {
      _logger.error('Card encryption failed');
      return PayriffResultFailed(error: e.error);
    } finally {
      zeroBytes(plaintext);
    }
    final PayRequest request = PayRequest(
      body: payBody(sealed.encryptedMessage),
      wrappedKey: sealed.wrappedKey,
      idempotencyKey: newIdempotencyKey(),
    );
    _sent = true;
    _onSubmitted?.call();
    final Map<String, Object?> payload;
    try {
      payload = await api.pay(orderId, request);
    } on PayriffException catch (e) {
      return PayriffResultFailed(error: e.error);
    } finally {
      zeroBytes(request.body);
    }

    // Step 4.
    final NextAction action = classifyNextAction(payload);
    _logger.info('Next action: ${action.runtimeType}');
    return _runAction(action);
  }

  Future<PayriffResult> _runAction(NextAction action) async {
    switch (action) {
      case ChallengeAction(
        :final String url,
        :final List<(String, String)> form,
      ):
        return _runPage(
          ThreeDsRequest.post(Uri.parse(url), utf8.encode(formUrlEncode(form))),
        );
      case RedirectAction(:final String url):
        return _runPage(ThreeDsRequest.get(Uri.parse(url)));
      case MethodAction():
        return _runThreeDsLoop(action);
      case WaitAction():
        return _runThreeDsLoop(null);
      case CheckStatusAction():
        return _pollUntilDone();
      case InvalidAction():
        _logger.warning('The API returned a next step the SDK cannot run');
        return await _singleCheck() ??
            const PayriffResultFailed(
              error: PayriffError(
                code: PayriffErrorCode.unexpectedResponse,
                message: 'Payriff returned a next step the SDK cannot run.',
              ),
            );
    }
  }

  /// The 3-D Secure Method (hidden WebViews) and the `/three-ds` loop.
  Future<PayriffResult> _runThreeDsLoop(MethodAction? method) async {
    final String? methodUrl = method?.methodUrl;
    final String? methodUrlServer = method?.methodUrlServer;
    final List<ThreeDsRequest> hidden = <ThreeDsRequest>[
      if (methodUrl != null)
        ThreeDsRequest.post(
          Uri.parse(methodUrl),
          utf8.encode(
            formUrlEncode(<(String, String)>[
              ('threeDSMethodData', method?.methodData ?? ''),
            ]),
          ),
        ),
      if (methodUrlServer != null)
        ThreeDsRequest.post(Uri.parse(methodUrlServer), Uint8List(0)),
    ];
    final ThreeDsSession? session = hidden.isEmpty ? _session : _ensureSheet();
    session?.showHidden(hidden);
    try {
      for (int i = 0; i < threeDsPollTries; i++) {
        if (await _sleepUnlessClosed(threeDsPollInterval)) {
          return await _closePath();
        }
        final Map<String, Object?> payload;
        try {
          payload = await api.threeDs(orderId);
        } on PayriffException catch (e) {
          if (e.error.code == PayriffErrorCode.networkError) continue;
          _logger.warning('/three-ds failed (${e.error.code.value})');
          break;
        }
        if (_closeWasRequested) return await _closePath();
        final NextAction next = classifyNextAction(payload);
        // Only a step with something to do ends the loop.
        if (next is WaitAction || next is MethodAction) continue;
        session?.clearHidden();
        return await _runAction(next);
      }
    } finally {
      session?.clearHidden();
    }
    return _pollUntilDone();
  }

  /// A bank page in the 3DS sheet (challenge or redirect).
  Future<PayriffResult> _runPage(ThreeDsRequest request) async {
    final ThreeDsSession? session = _ensureSheet();
    if (session == null) {
      _logger.error('The 3-D Secure sheet could not be shown');
      return _pollUntilDone();
    }
    session.showPage(request);
    final Completer<PayriffResult> done = Completer<PayriffResult>();
    _Poll? poll;
    void startPolling() {
      if (poll != null) return;
      final _Poll started = _startPoll();
      poll = started;
      unawaited(
        started.result.then((PayriffResult r) {
          if (!done.isCompleted) done.complete(r);
        }),
      );
    }

    final List<StreamSubscription<void>> subscriptions =
        <StreamSubscription<void>>[
          // In parallel: a final status also ends the step.
          session.callbackLoaded.listen((_) => startPolling()),
          session.finished.listen((_) {
            _closeSheet();
            startPolling();
          }),
        ];
    unawaited(
      session.closeRequested.then((_) {
        if (done.isCompleted) return;
        poll?.cancel();
        done.complete(_closePath());
      }),
    );
    try {
      return await done.future;
    } finally {
      for (final StreamSubscription<void> s in subscriptions) {
        unawaited(s.cancel());
      }
      poll?.cancel();
    }
  }

  /// CONTRACT §16.7 step 5, racing a close of a sheet that is still shown.
  Future<PayriffResult> _pollUntilDone() async {
    final ThreeDsSession? session = _sheet == null ? null : _session;
    session?.showVerifying();
    final _Poll poll = _startPoll();
    if (session == null) return poll.result;
    final PayriffResult? result = await Future.any(<Future<PayriffResult?>>[
      poll.result,
      session.closeRequested.then((_) => null),
    ]);
    if (result != null) return result;
    poll.cancel();
    return _closePath();
  }

  _Poll _startPoll() {
    final _Poll poll = _Poll();
    poll.result = () async {
      final DateTime started = clock.now();
      while (true) {
        try {
          final StatusReading reading = cardStatusReading(
            await api.status(orderId),
          );
          _last = reading;
          final PayriffResult? done = cardResultFor(orderId, reading);
          if (done != null) return done;
        } on PayriffException catch (e) {
          // Network blips (and other passing failures) keep polling; a fatal
          // answer will not fix itself. The card was submitted, so the result
          // stays pending: verify it on the backend.
          if (e.error.isFatal) {
            _logger.warning('Status polling stopped: ${e.error.code.value}');
            return PayriffResultPending(
              payment: paymentFor(orderId, _last),
              reason: PayriffPendingReason.verificationFailed,
            );
          }
        } on Object catch (e) {
          _logger.warning('Status check failed: ${e.runtimeType}');
        }
        if (poll.cancelled) break;
        if (clock.now().difference(started) + cardPollInterval >
            cardPollTimeout) {
          break;
        }
        await clock.sleep(cardPollInterval);
        if (poll.cancelled) break;
      }
      return PayriffResultPending(
        payment: paymentFor(orderId, _last),
        reason: PayriffPendingReason.notFinal,
      );
    }();
    return poll;
  }

  /// One status check: the mapped result when final, else `null`.
  Future<PayriffResult?> _singleCheck() async {
    try {
      final StatusReading reading = cardStatusReading(
        await api.status(orderId),
      );
      _last = reading;
      return cardResultFor(orderId, reading);
    } on PayriffException catch (e) {
      _logger.warning('Status check failed (${e.error.code.value})');
      return null;
    }
  }

  /// CONTRACT §16.8 close by the customer: a single check; anything but a
  /// final status is `pending(notFinal)`, because the card was submitted.
  Future<PayriffResult> _closePath() async {
    _session?.showVerifying();
    return await _singleCheck() ??
        PayriffResultPending(
          payment: paymentFor(orderId, _last),
          reason: PayriffPendingReason.notFinal,
        );
  }

  bool get _closeWasRequested => _session?.isCloseRequested ?? false;

  /// Sleeps [duration]; `true` when the customer closed the sheet first.
  Future<bool> _sleepUnlessClosed(Duration duration) async {
    final ThreeDsSession? session = _session;
    if (session == null || _sheet == null) {
      await clock.sleep(duration);
      return false;
    }
    if (_closeWasRequested) return true;
    return Future.any(<Future<bool>>[
      clock.sleep(duration).then((_) => _closeWasRequested),
      session.closeRequested.then((_) => true),
    ]);
  }

  ThreeDsSession? _ensureSheet() {
    if (_sheet != null) return _session;
    if (_sheetUnavailable) return null;
    final ThreeDsSession session =
        _session ??
        ThreeDsSession(
          apiBaseUrl: api.baseUrl,
          strings: strings,
          logger: _logger,
        );
    _session = session;
    final ThreeDsSheet? sheet = _openSheet(session);
    if (sheet == null) {
      _sheetUnavailable = true;
      return null;
    }
    _sheet = sheet;
    return session;
  }

  void _closeSheet() {
    final ThreeDsSheet? sheet = _sheet;
    if (sheet == null) return;
    _sheet = null;
    _session?.markClosedBySdk();
    sheet.close();
  }
}

final class _Poll {
  late final Future<PayriffResult> result;
  bool cancelled = false;

  void cancel() => cancelled = true;
}
