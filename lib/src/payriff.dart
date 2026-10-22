import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'card/card_form.dart';
import 'card/card_types.dart';
import 'card/client_order.dart';
import 'config.dart';
import 'error.dart';
import 'internal/card/card_clock.dart';
import 'internal/card/card_crypto.dart';
import 'internal/card/card_flow.dart';
import 'internal/card/client_api.dart';
import 'internal/language.dart';
import 'internal/logger.dart';
import 'internal/native_bridge.dart';
import 'internal/request.dart';
import 'internal/strings.dart';
import 'internal/ui/presenter.dart';
import 'internal/ui/sheet.dart';
import 'log.dart';
import 'result.dart';

/// The Payriff SDK entry point.
///
/// 1. Call [configure] once, for example in `main`, with your publishable
///    key.
/// 2. Your server creates the order with its secret key and gives the app
///    the order's `orderId` and `clientSecret`.
/// 3. Show a [PayriffCardForm] and call [confirmCardPayment] with its
///    controller.
/// 4. Handle the returned [PayriffResult]. Only [PayriffResultSuccess] is
///    shown as paid; your server fulfils the order once it has confirmed the
///    payment with Payriff.
///
/// ```dart
/// Payriff.configure(const PayriffConfig(
///   publishableKey: 'pr_pk_live_…',
///   environment: PayriffEnvironment.sandbox,
/// ));
/// final order = await myBackend.startCheckout(cart);
/// final result = await Payriff.confirmCardPayment(
///   context,
///   cardController,
///   orderId: order.orderId,
///   clientSecret: order.clientSecret,
/// );
/// ```
abstract final class Payriff {
  /// The version of this package.
  static const String version = '1.0.0';

  static PayriffConfig? _config;
  static bool _cardPaymentActive = false;
  static final StreamController<PayriffLogEntry> _logs =
      StreamController<PayriffLogEntry>.broadcast();

  /// The configuration passed to [configure], or `null`.
  static PayriffConfig? get config => _config;

  /// Whether [confirmCardPayment] is running.
  static bool get isPaymentInProgress => _cardPaymentActive;

  /// SDK log entries, emitted while `PayriffConfig.enableLogging` is on.
  ///
  /// This is a broadcast stream; entries emitted while nobody listens are
  /// dropped. In debug builds each entry's `formatted` line is also printed
  /// to the console; profile and release builds print nothing.
  static Stream<PayriffLogEntry> get logStream => _logs.stream;

  /// Sets the SDK configuration. Calling it again replaces the configuration
  /// for later calls; a payment that is already running keeps the old one.
  ///
  /// Never throws. A publishable key that is not a `pr_pk_live_…` key is
  /// logged as a warning (`Invalid configuration: …`) and makes the card
  /// calls fail with [PayriffErrorCode.invalidConfig].
  static void configure(PayriffConfig config) {
    _config = config;
    final SdkLogger logger = _loggerFor(config);
    final String? key = trimToNull(config.publishableKey);
    logger.info(
      'Configured: environment ${config.environment.name}, '
      'publishable key ${redactSecret(key)}',
    );
    if (key != null && usablePublishableKey(key) == null) {
      logger.warning(
        'Invalid configuration: publishableKey is not a publishable key '
        '(pr_pk_live_…); confirmCardPayment and retrieveOrder fail with '
        'INVALID_CONFIG.',
      );
    }
  }

  /// Pays the order [orderId] with the card typed into the [PayriffCardForm]
  /// of [controller], and completes with the verified result
  /// (CONTRACT §16.7).
  ///
  /// Your server creates the order with its secret key and gives the app
  /// its `orderId` and `clientSecret`. The app needs only
  /// `PayriffConfig.publishableKey`; the secret key is never used.
  ///
  /// 1. The form is validated. Invalid fields are shown and the result is
  ///    [PayriffResultFailed] with [PayriffErrorCode.validationFailed] and
  ///    `PayriffError.fields`; no request is made.
  /// 2. The order must be `CREATED` or `PENDING` and accept `CARD`, else
  ///    [PayriffErrorCode.orderNotPayable].
  /// 3. The card is encrypted on the device and sent; the form is locked
  ///    meanwhile ([PayriffCardController.isProcessing]).
  /// 4. 3-D Secure runs in the SDK's sheet when the bank asks for it, then
  ///    the status is polled (every 2.5 s, up to 120 s).
  ///
  /// Once the card was sent the result is never `cancelled(userClosed)`:
  /// closing the 3-D Secure sheet checks the status once and gives
  /// [PayriffResultPending] unless it is final. The card values are cleared
  /// after a final result. Never throws.
  ///
  /// The result is for the user interface: fulfil the order on your server
  /// after it confirms the payment with Payriff.
  static Future<PayriffResult> confirmCardPayment(
    BuildContext context,
    PayriffCardController controller, {
    required String orderId,
    required String clientSecret,
  }) async {
    if (isPaymentInProgress) {
      return const PayriffResultFailed(
        error: PayriffError(
          code: PayriffErrorCode.paymentInProgress,
          message: 'Another Payriff payment is already running.',
        ),
      );
    }
    final PayriffConfig? config = _config;
    if (config == null) {
      return PayriffResultFailed(
        error: notConfigured(
          'Call Payriff.configure before Payriff.confirmCardPayment.',
        ),
      );
    }
    final String? publishableKey = usablePublishableKey(config.publishableKey);
    if (publishableKey == null) return PayriffResultFailed(error: _keyError());
    final String id = orderId.trim();
    final String? secret = usableClientSecret(clientSecret);
    final PayriffError? argumentError = _cardArgumentError(id, secret);
    if (argumentError != null) {
      return PayriffResultFailed(error: argumentError);
    }
    final NavigatorState? navigator = context.mounted
        ? Navigator.maybeOf(context, rootNavigator: true)
        : null;
    if (navigator == null) {
      return const PayriffResultFailed(
        error: PayriffError(
          code: PayriffErrorCode.presentationFailed,
          message:
              'No Navigator was found above the BuildContext. Pass a context '
              'from a widget inside your MaterialApp or CupertinoApp.',
        ),
      );
    }

    // Step 1: validation, before any request.
    final CardFormCheck? check = checkCardForm(controller);
    if (check == null) {
      return const PayriffResultFailed(
        error: PayriffError(
          code: PayriffErrorCode.validationFailed,
          message:
              'Show a PayriffCardForm with this controller before calling '
              'confirmCardPayment.',
          fields: <PayriffCardFieldError>[],
        ),
      );
    }
    final CardPlaintext? card = check.card;
    if (card == null) {
      return PayriffResultFailed(
        error: PayriffError(
          code: PayriffErrorCode.validationFailed,
          message: 'The card details are not valid.',
          fields: List<PayriffCardFieldError>.unmodifiable(check.errors),
        ),
      );
    }

    final SdkLogger logger = _loggerFor(config);
    final PayriffStrings strings = PayriffStrings(
      config.language ?? deviceLanguage(),
    );
    final bool material = context.mounted
        ? SheetPresenter.prefersMaterial(context)
        : defaultTargetPlatform != TargetPlatform.iOS;
    final String apiBaseUrl = clientApiBaseUrl(config.environment);
    // Claimed before the first await, so a second tap cannot start another
    // payment.
    _cardPaymentActive = true;
    setCardFormProcessing(controller, true);
    bool submitted = false;
    ClientApi? api;
    PayriffResult result;
    try {
      final ClientApi client = api = ClientApi(
        baseUrl: apiBaseUrl,
        publishableKey: publishableKey,
        clientSecret: secret!,
        appId: await NativeBridge.appId(),
        clock: cardClock,
        logger: logger,
      );
      final CardPayment payment = CardPayment(
        api: client,
        orderId: id,
        clock: cardClock,
        strings: strings,
        logger: logger,
        onSubmitted: () => submitted = true,
        openSheet: (ThreeDsSession session) => _openThreeDsSheet(
          context.mounted ? context : navigator.context,
          navigator,
          material,
          strings,
          logger,
          session,
        ),
      );
      logger.info('confirmCardPayment: order $id');
      result = await payment.run(card);
    } finally {
      _cardPaymentActive = false;
      api?.close();
      setCardFormProcessing(controller, false);
    }
    final PayriffPayment? paid = result.payment;
    logger.info(
      'Card payment finished: ${result.type}'
      '${paid == null ? '' : ' (${paid.status.value})'}'
      '${result.error == null ? '' : ' (${result.error!.code.value})'}',
    );
    // CONTRACT §16.5: the card values do not outlive a final result (or a
    // card that was sent, or an order that can no longer be paid).
    if (submitted ||
        result is! PayriffResultFailed ||
        result.error.isFatal ||
        result.error.code == PayriffErrorCode.orderNotPayable) {
      clearCardForm(controller);
    }
    return result;
  }

  /// Reads the order [orderId] through the Client API
  /// (`GET /api/v3/client/orders/{orderId}`) with
  /// `PayriffConfig.publishableKey` and the order's [clientSecret], for
  /// example to show the amount next to the card form.
  ///
  /// Throws a [PayriffException]: [PayriffErrorCode.notConfigured] before
  /// [configure], [PayriffErrorCode.invalidConfig] without a usable
  /// publishable key, [PayriffErrorCode.invalidOrder] for an invalid id or
  /// client secret, and the Client API errors of CONTRACT §16.3.
  static Future<PayriffClientOrder> retrieveOrder({
    required String orderId,
    required String clientSecret,
  }) async {
    final PayriffConfig? config = _config;
    if (config == null) {
      throw PayriffException(
        notConfigured('Call Payriff.configure before Payriff.retrieveOrder.'),
      );
    }
    final String? publishableKey = usablePublishableKey(config.publishableKey);
    if (publishableKey == null) throw PayriffException(_keyError());
    final String id = orderId.trim();
    final String? secret = usableClientSecret(clientSecret);
    final PayriffError? argumentError = _cardArgumentError(id, secret);
    if (argumentError != null) throw PayriffException(argumentError);
    final ClientApi api = ClientApi(
      baseUrl: clientApiBaseUrl(config.environment),
      publishableKey: publishableKey,
      clientSecret: secret!,
      appId: await NativeBridge.appId(),
      clock: cardClock,
      logger: _loggerFor(config),
    );
    try {
      return PayriffClientOrder.fromPayload(
        await api.retrieveOrder(id),
        requestedOrderId: id,
      );
    } finally {
      api.close();
    }
  }

  /// Clears the configuration and the in-progress guard. For tests only.
  @visibleForTesting
  static void debugReset() {
    _config = null;
    _cardPaymentActive = false;
    NativeBridge.resetCache();
  }

  static PayriffError _keyError() => invalidConfig(
    'The card flow needs PayriffConfig.publishableKey: the publishable key '
    '(pr_pk_live_…) of your Payriff application, never the secret key.',
  );

  static PayriffError? _cardArgumentError(String orderId, String? secret) {
    if (orderId.isEmpty || orderId == '.' || orderId == '..') {
      return invalidOrder('orderId must be the Payriff order id.');
    }
    if (secret == null) {
      // Never echo the value.
      return invalidOrder(
        'clientSecret must be the order\'s client secret (pr_cs_…) from '
        'your server.',
      );
    }
    return null;
  }

  static ThreeDsSheet? _openThreeDsSheet(
    BuildContext context,
    NavigatorState navigator,
    bool material,
    PayriffStrings strings,
    SdkLogger logger,
    ThreeDsSession session,
  ) {
    if (!navigator.mounted) return null;
    final SheetPresenter presenter = SheetPresenter(
      navigator: navigator,
      material: material,
      strings: strings,
    );
    try {
      final Route<void> route = presenter.buildSheetRoute(
        context,
        (BuildContext context) => PayriffThreeDsSheet(
          session: session,
          presenter: presenter,
          logger: logger,
        ),
      );
      unawaited(
        navigator.push<void>(route).whenComplete(session.onSheetDismissed),
      );
    } on Object catch (e) {
      logger.error('Could not present the 3-D Secure sheet: ${redactError(e)}');
      return null;
    }
    return _PresentedThreeDsSheet(presenter);
  }

  static SdkLogger _loggerFor(PayriffConfig config) =>
      SdkLogger(enabled: config.enableLogging, sink: _emit);

  // Entries reach logStream in every build mode, but only debug builds print
  // them: a release build must not write the payment trail to the device log
  // (logcat, os_log), where adb, Console or a log collector can read it.
  static void _emit(PayriffLogEntry entry) {
    _logs.add(entry);
    if (kDebugMode) debugPrint(entry.formatted);
  }
}

final class _PresentedThreeDsSheet implements ThreeDsSheet {
  _PresentedThreeDsSheet(this._presenter);

  final SheetPresenter _presenter;

  @override
  void close() => _presenter.closeSheet();
}
