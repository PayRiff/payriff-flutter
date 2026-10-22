part of 'sheet.dart';

/// The 3-D Secure sheet (CONTRACT §9.1, §16.8): the header with its drag
/// handle, title and close button, a native loader, a WebView for the bank
/// page, and the hidden WebViews of the 3-D Secure Method behind the loader.
/// It renders a [ThreeDsSession].
class PayriffThreeDsSheet extends StatefulWidget {
  /// Creates the sheet for [session].
  const PayriffThreeDsSheet({
    super.key,
    required this.session,
    required this.presenter,
    required this.logger,
  });

  /// The 3DS state it displays.
  final ThreeDsSession session;

  /// Opens dialogs on the root navigator.
  final SheetPresenter presenter;

  /// The SDK logger.
  final SdkLogger logger;

  @override
  State<PayriffThreeDsSheet> createState() => _PayriffThreeDsSheetState();
}

class _PayriffThreeDsSheetState extends State<PayriffThreeDsSheet>
    with SingleTickerProviderStateMixin
    implements ThreeDsHost {
  static const double _dismissDistance = 72;
  static const double _dismissVelocity = 700;

  late final WebViewController _web = _createThreeDsController();

  /// `false` when the WebView has no navigation rules; it then loads nothing.
  late final Future<bool> _configured = _configure();
  late final AnimationController _snapBack = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..addListener(_onSnapBack);
  late final Widget _webView = WebViewWidget(
    controller: _web,
    gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
      Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
    },
  );

  double _dragOffset = 0;
  double _snapFrom = 0;
  int _dialogs = 0;

  ThreeDsSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    // CONTRACT §16.0 item 4: no screenshots or app-switcher snapshots of the
    // bank page while the sheet exists.
    unawaited(NativeBridge.setSecure(true));
    unawaited(_configured);
    _session.attach(this);
  }

  @override
  void dispose() {
    _session.detach(this);
    _session.onSheetDismissed();
    unawaited(NativeBridge.setSecure(false));
    _snapBack.dispose();
    super.dispose();
  }

  Future<bool> _configure() => _configureThreeDsWebView(
    _web,
    NavigationDelegate(
      onNavigationRequest: (NavigationRequest request) => _session
          .decideNavigation(request.url, isMainFrame: request.isMainFrame),
      onPageStarted: _session.onMainFrameUrl,
      onPageFinished: _session.onPageFinished,
      onUrlChange: (UrlChange change) {
        final String? url = change.url;
        if (url != null) _session.onMainFrameUrl(url);
      },
      onWebResourceError: _session.onWebResourceError,
    ),
    widget.logger,
    alert: _showAlert,
    confirm: _showConfirm,
    prompt: _showPrompt,
  );

  // WKWebView drops JavaScript dialogs unless the app shows them (CONTRACT
  // §10). Each names the page's host, and the sheet shows at most
  // maxDialogsPerPage of them.
  bool _takeDialog() => mounted && _dialogs++ < maxDialogsPerPage;

  Future<void> _showAlert(JavaScriptAlertDialogRequest request) async {
    if (!_takeDialog()) return;
    await widget.presenter.alert(
      context,
      request.message,
      origin: dialogOrigin(request.url),
    );
  }

  Future<bool> _showConfirm(JavaScriptConfirmDialogRequest request) async {
    if (!_takeDialog()) return false;
    return widget.presenter.confirm(
      context,
      request.message,
      origin: dialogOrigin(request.url),
    );
  }

  Future<String> _showPrompt(JavaScriptTextInputDialogRequest request) async {
    if (!_takeDialog()) return '';
    return await widget.presenter.prompt(
          context,
          request.message,
          defaultText: request.defaultText,
          origin: dialogOrigin(request.url),
        ) ??
        '';
  }

  // ---------------------------------------------------------------------
  // ThreeDsHost

  @override
  void load(ThreeDsRequest request) => unawaited(_load(request));

  Future<void> _load(ThreeDsRequest request) async {
    final bool ready = await _configured;
    if (!mounted) return;
    if (!ready) {
      _session.onPageUnavailable();
      return;
    }
    _session.websiteData.record(request.url.toString());
    try {
      await request.loadInto(_web);
    } on Object catch (e) {
      widget.logger.warning('Could not load $request: ${redactError(e)}');
    }
  }

  @override
  void stopLoading() =>
      unawaited(_load(ThreeDsRequest.get(Uri.parse('about:blank'))));

  @override
  void reload() => unawaited(_reload());

  Future<void> _reload() async {
    final bool ready = await _configured;
    if (!mounted) return;
    if (!ready) {
      _session.onPageUnavailable();
      return;
    }
    try {
      await _web.reload();
    } on Object catch (e) {
      widget.logger.warning('Could not reload: ${redactError(e)}');
    }
  }

  @override
  Future<bool> confirmCancel() async {
    if (!mounted) return true;
    return widget.presenter.confirmCancel(context);
  }

  @override
  void dismissDialogs() => widget.presenter.dismissDialogs();

  // ---------------------------------------------------------------------
  // Header drag: the sheet follows the finger with resistance, springs back
  // and runs the close path when pulled far or fast enough.

  void _onDragUpdate(DragUpdateDetails details) {
    _snapBack.stop();
    final double resistance = 1 / (1 + _dragOffset / 160);
    setState(() {
      _dragOffset = (_dragOffset + details.delta.dy * resistance).clamp(
        0,
        double.infinity,
      );
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final bool dismiss =
        _dragOffset > _dismissDistance ||
        (details.primaryVelocity ?? 0) > _dismissVelocity;
    _springBack();
    if (dismiss) unawaited(_session.requestClose());
  }

  void _springBack() {
    if (_dragOffset == 0) return;
    _snapFrom = _dragOffset;
    unawaited(_snapBack.forward(from: 0));
  }

  void _onSnapBack() {
    setState(() {
      _dragOffset =
          _snapFrom * (1 - Curves.easeOutCubic.transform(_snapBack.value));
    });
  }

  // ---------------------------------------------------------------------
  // Build

  @override
  Widget build(BuildContext context) {
    final SheetStyle style = SheetStyle.of(
      context,
      material: widget.presenter.material,
    );
    final bool android = defaultTargetPlatform == TargetPlatform.android;
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) unawaited(_session.requestClose());
      },
      child: Transform.translate(
        offset: Offset(0, _dragOffset),
        child: _SheetClip(
          material: style.material,
          roundBottom: MediaQuery.viewPaddingOf(context).bottom > 0,
          child: ColoredBox(
            color: style.background,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: android ? MediaQuery.viewInsetsOf(context).bottom : 0,
                ),
                child: DefaultTextStyle(
                  style: style.body,
                  child: ListenableBuilder(
                    listenable: _session,
                    builder: (BuildContext context, Widget? child) =>
                        _buildContent(style),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(SheetStyle style) {
    final ThreeDsSession session = _session;
    final PayriffStrings strings = session.strings;
    final Widget? overlay = _overlay(style, strings);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Header(
          key: headerKey,
          style: style,
          title: strings[PayriffStringKey.title],
          closeLabel: strings[PayriffStringKey.close],
          closeEnabled: session.canClose,
          onClose: () => unawaited(session.requestClose()),
          onDragUpdate: _onDragUpdate,
          onDragEnd: _onDragEnd,
          onDragCancel: _springBack,
        ),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // Every page here is the bank's, so it is always inset.
              ColoredBox(
                color: bankPageBackdrop,
                child: Padding(padding: bankPageInsets, child: _webView),
              ),
              // The 3-D Secure Method runs behind the loader: laid out and
              // painted (so the platform views run normally), but covered.
              for (final (int i, ThreeDsRequest request)
                  in session.hidden.indexed)
                Positioned(
                  key: ValueKey<String>(
                    'payriff.3ds.hidden.${session.hiddenGeneration}.$i',
                  ),
                  left: 0,
                  top: 0,
                  width: 1,
                  height: 1,
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: _HiddenMethodWebView(
                        request: request,
                        apiBaseUrl: session.apiBaseUrl,
                        websiteData: session.websiteData,
                        logger: widget.logger,
                      ),
                    ),
                  ),
                ),
              ?overlay,
            ],
          ),
        ),
      ],
    );
  }

  Widget? _overlay(SheetStyle style, PayriffStrings strings) {
    final ThreeDsSession session = _session;
    switch (session.view) {
      case ThreeDsView.loader:
      case ThreeDsView.verifying:
        return _BusyPanel(
          style: style,
          message: strings[PayriffStringKey.verifying],
        );
      case ThreeDsView.page:
        break;
    }
    if (session.pageLoadFailed) {
      return _MessagePanel(
        style: style,
        glyph: Glyph.exclamation,
        tint: style.warning,
        title: null,
        message: strings[PayriffStringKey.pageLoadError],
        primaryLabel: strings[PayriffStringKey.retry],
        onPrimary: session.retryPageLoad,
        secondaryLabel: strings[PayriffStringKey.close],
        onSecondary: () => unawaited(session.requestClose()),
      );
    }
    if (!session.pageLoaded) return _LoadingVeil(style: style);
    return null;
  }
}

/// One hidden WebView of the 3-D Secure Method: it POSTs its request once,
/// follows the 3DS navigation rules without ever ending the flow or opening
/// apps, answers JavaScript dialogs silently, records the sites it loads in
/// the payment's [ThreeDsWebsiteData], and is destroyed with the widget.
class _HiddenMethodWebView extends StatefulWidget {
  const _HiddenMethodWebView({
    required this.request,
    required this.apiBaseUrl,
    required this.websiteData,
    required this.logger,
  });

  final ThreeDsRequest request;
  final String apiBaseUrl;
  final ThreeDsWebsiteData websiteData;
  final SdkLogger logger;

  @override
  State<_HiddenMethodWebView> createState() => _HiddenMethodWebViewState();
}

class _HiddenMethodWebViewState extends State<_HiddenMethodWebView> {
  late final WebViewController _web = _createThreeDsController();
  late final ThreeDsNavigationPolicy _policy = ThreeDsNavigationPolicy(
    widget.apiBaseUrl,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    final ThreeDsWebsiteData websiteData = widget.websiteData;
    final bool ready = await _configureThreeDsWebView(
      _web,
      NavigationDelegate(
        onNavigationRequest: (NavigationRequest request) {
          final NavigationDecision decision = decideHiddenNavigation(
            _policy,
            request.url,
            isMainFrame: request.isMainFrame,
          );
          if (decision == NavigationDecision.navigate) {
            websiteData.record(request.url);
          }
          return decision;
        },
        // Android does not report POST navigations as navigation requests.
        onPageStarted: websiteData.record,
        onUrlChange: (UrlChange change) {
          final String? url = change.url;
          if (url != null) websiteData.record(url);
        },
      ),
      widget.logger,
      alert: (_) async {},
      confirm: (_) async => false,
      prompt: (_) async => '',
      dialogsOnAllPlatforms: true,
    );
    // Without its navigation rules the method WebView loads nothing; the
    // `/three-ds` loop goes on regardless.
    if (!ready || !mounted) return;
    websiteData.record(widget.request.url.toString());
    try {
      await widget.request.loadInto(_web);
    } on Object catch (e) {
      widget.logger.warning(
        'Could not start the 3-D Secure Method: ${redactError(e)}',
      );
    }
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _web);
}

WebViewController _createThreeDsController() {
  final PlatformWebViewControllerCreationParams params =
      WebViewPlatform.instance is WebKitWebViewPlatform
      ? WebKitWebViewControllerCreationParams(
          javaScriptCanOpenWindowsAutomatically: false,
        )
      : const PlatformWebViewControllerCreationParams();
  return WebViewController.fromPlatformCreationParams(params);
}

/// The WebView setup of CONTRACT §7.7 for a 3DS WebView: JavaScript on, zoom
/// off, the navigation rules, third-party cookies on Android (ACS iframes
/// need them), no file or content access, and the app look. No scripts,
/// JavaScript channels or console hooks; the user agent is left alone. Each
/// optional setting may fail without breaking the payment.
///
/// Completes with `false` when the navigation rules could not be installed:
/// such a WebView must never load a page (CONTRACT §16.8).
Future<bool> _configureThreeDsWebView(
  WebViewController web,
  NavigationDelegate delegate,
  SdkLogger logger, {
  required Future<void> Function(JavaScriptAlertDialogRequest) alert,
  required Future<bool> Function(JavaScriptConfirmDialogRequest) confirm,
  required Future<String> Function(JavaScriptTextInputDialogRequest) prompt,
  bool dialogsOnAllPlatforms = false,
}) async {
  // First and on its own: a failure in an optional setting below must never
  // leave the WebView without its navigation rules.
  try {
    await web.setNavigationDelegate(delegate);
  } on Object catch (e) {
    logger.error(
      '3-D Secure WebView without navigation rules: ${redactError(e)}',
    );
    return false;
  }
  try {
    await web.setJavaScriptMode(JavaScriptMode.unrestricted);
    await web.enableZoom(false);
    if (dialogsOnAllPlatforms || defaultTargetPlatform == TargetPlatform.iOS) {
      await web.setOnJavaScriptAlertDialog(alert);
      await web.setOnJavaScriptConfirmDialog(confirm);
      await web.setOnJavaScriptTextInputDialog(prompt);
    }
    final Object platform = web.platform;
    if (platform is WebKitWebViewController) {
      if (kDebugMode) {
        await platform.setInspectable(true).catchError((Object _) {});
      }
    } else if (platform is AndroidWebViewController) {
      await AndroidWebViewCookieManager(
        const PlatformWebViewCookieManagerCreationParams(),
      ).setAcceptThirdPartyCookies(platform, true);
    }
  } on Object catch (e) {
    logger.warning('3-D Secure WebView setup failed: ${redactError(e)}');
  }
  final Object platform = web.platform;
  if (platform is AndroidWebViewController) {
    try {
      await platform.setAllowFileAccess(false);
      await platform.setAllowContentAccess(false);
    } on Object catch (e) {
      logger.warning(
        'Could not turn off file and content access: ${redactError(e)}',
      );
    }
  }
  Future<void> attempt(Future<void> Function() setting) async {
    try {
      await setting();
    } on Object catch (e) {
      logger.debug('WebView look setting skipped: ${redactError(e)}');
    }
  }

  await attempt(() => web.setBackgroundColor(const Color(0xFFFFFFFF)));
  await attempt(() => web.setOverScrollMode(WebViewOverScrollMode.never));
  await attempt(() => web.setVerticalScrollBarEnabled(false));
  await attempt(() => web.setHorizontalScrollBarEnabled(false));
  if (platform is WebKitWebViewController) {
    await attempt(() => platform.setAllowsLinkPreview(false));
    await attempt(() => platform.setAllowsBackForwardNavigationGestures(false));
  }
  return true;
}
