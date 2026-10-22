import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// Installs a fresh fake WebView platform for each test.
FakeWebViewPlatform installFakeWebView() {
  final FakeWebViewPlatform platform = FakeWebViewPlatform();
  WebViewPlatform.instance = platform;
  return platform;
}

/// A fake WebView platform: records loads and exposes the navigation
/// delegate's callbacks so tests can play a bank page's navigations.
class FakeWebViewPlatform extends WebViewPlatform {
  /// The controllers created so far (one per sheet).
  final List<FakeWebViewController> controllers = <FakeWebViewController>[];

  /// The delegates created so far (one per sheet).
  final List<FakeNavigationDelegate> delegates = <FakeNavigationDelegate>[];

  /// The most recent controller.
  FakeWebViewController get controller => controllers.last;

  /// The most recent delegate.
  FakeNavigationDelegate get delegate => delegates.last;

  /// When true, new controllers fail to install a navigation delegate.
  bool failNavigationDelegates = false;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final FakeWebViewController controller = FakeWebViewController(params)
      ..failNavigationDelegate = failNavigationDelegates;
    controllers.add(controller);
    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    final FakeNavigationDelegate delegate = FakeNavigationDelegate(params);
    delegates.add(delegate);
    return delegate;
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _FakeWebViewWidget(params);

  @override
  PlatformWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) => throw UnimplementedError(
    'The SDK must not use the generic cookie manager',
  );
}

/// Records what the SDK asks of the WebView.
class FakeWebViewController extends PlatformWebViewController {
  FakeWebViewController(super.params) : super.implementation();

  /// Every URL passed to loadRequest, in order.
  final List<Uri> loads = <Uri>[];

  /// Every loadRequest with its method, headers and body, in order.
  final List<LoadRequestParams> requests = <LoadRequestParams>[];

  /// How many times the page was reloaded.
  int reloads = 0;

  /// The JavaScript mode set by the SDK.
  JavaScriptMode? javaScriptMode;

  /// The JavaScript dialog handlers the SDK installed (iOS only).
  Future<void> Function(JavaScriptAlertDialogRequest request)? onAlert;
  Future<bool> Function(JavaScriptConfirmDialogRequest request)? onConfirm;
  Future<String> Function(JavaScriptTextInputDialogRequest request)? onPrompt;

  /// Whether an alert handler was installed.
  bool get alertHandlerSet => onAlert != null;

  /// What [canGoBack] answers.
  bool canGoBackValue = false;

  /// How many times the SDK went back in the history.
  int goBackCalls = 0;

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    loads.add(params.uri);
    requests.add(params);
  }

  @override
  Future<void> reload() async => reloads++;

  @override
  Future<bool> canGoBack() async => canGoBackValue;

  @override
  Future<void> goBack() async => goBackCalls++;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {
    this.javaScriptMode = javaScriptMode;
  }

  /// When true, [setPlatformNavigationDelegate] throws.
  bool failNavigationDelegate = false;

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    if (failNavigationDelegate) {
      throw PlatformException(code: 'error', message: 'no delegate');
    }
  }

  @override
  Future<void> setOnJavaScriptAlertDialog(
    Future<void> Function(JavaScriptAlertDialogRequest request)
    onJavaScriptAlertDialog,
  ) async {
    onAlert = onJavaScriptAlertDialog;
  }

  @override
  Future<void> setOnJavaScriptConfirmDialog(
    Future<bool> Function(JavaScriptConfirmDialogRequest request)
    onJavaScriptConfirmDialog,
  ) async {
    onConfirm = onJavaScriptConfirmDialog;
  }

  @override
  Future<void> setOnJavaScriptTextInputDialog(
    Future<String> Function(JavaScriptTextInputDialogRequest request)
    onJavaScriptTextInputDialog,
  ) async {
    onPrompt = onJavaScriptTextInputDialog;
  }

  // Injecting scripts would disable Apple Pay (CONTRACT §7.7): fail loudly.

  @override
  Future<void> runJavaScript(String javaScript) =>
      throw StateError('The SDK must not run JavaScript');

  @override
  Future<Object> runJavaScriptReturningResult(String javaScript) =>
      throw StateError('The SDK must not run JavaScript');

  @override
  Future<void> addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams,
  ) => throw StateError('The SDK must not add JavaScript channels');

  /// The last values passed to the look settings (CONTRACT §7.7).
  WebViewOverScrollMode? overScrollMode;
  bool? verticalScrollBarEnabled;
  bool? horizontalScrollBarEnabled;
  Color? backgroundColor;

  @override
  Future<void> setOverScrollMode(WebViewOverScrollMode mode) async =>
      overScrollMode = mode;

  @override
  Future<void> setVerticalScrollBarEnabled(bool enabled) async =>
      verticalScrollBarEnabled = enabled;

  @override
  Future<void> setHorizontalScrollBarEnabled(bool enabled) async =>
      horizontalScrollBarEnabled = enabled;

  @override
  Future<void> setBackgroundColor(Color color) async => backgroundColor = color;

  /// The last value passed to [enableZoom]; null until it is called.
  bool? zoomEnabled;

  @override
  Future<void> enableZoom(bool enabled) async {
    // Only turning zoom off is allowed (CONTRACT §7.7).
    if (enabled) throw StateError('The SDK must not enable zoom');
    zoomEnabled = enabled;
  }

  @override
  Future<void> setOnConsoleMessage(
    void Function(JavaScriptConsoleMessage consoleMessage) onConsoleMessage,
  ) => throw StateError('The SDK must not hook the console');

  @override
  Future<void> setUserAgent(String? userAgent) =>
      throw StateError('The SDK must not change the user agent');
}

/// Exposes the callbacks the SDK registered.
class FakeNavigationDelegate extends PlatformNavigationDelegate {
  FakeNavigationDelegate(super.params) : super.implementation();

  NavigationRequestCallback? _onNavigationRequest;
  PageEventCallback? _onPageStarted;
  PageEventCallback? _onPageFinished;
  ProgressCallback? _onProgress;
  WebResourceErrorCallback? _onWebResourceError;
  UrlChangeCallback? _onUrlChange;

  /// Plays a navigation request and returns the SDK's decision.
  Future<NavigationDecision> navigate(
    String url, {
    bool isMainFrame = true,
  }) async => _onNavigationRequest!(
    NavigationRequest(url: url, isMainFrame: isMainFrame),
  );

  /// Plays `onPageStarted`.
  void pageStarted(String url) => _onPageStarted!(url);

  /// Plays `onPageFinished`.
  void pageFinished(String url) => _onPageFinished!(url);

  /// Plays `onProgress`.
  void progress(int value) => _onProgress!(value);

  /// Plays `onUrlChange`.
  void urlChanged(String url) => _onUrlChange!(UrlChange(url: url));

  /// Plays `onWebResourceError`.
  void error({
    required int code,
    String description = 'error',
    WebResourceErrorType? type,
    String? url,
    bool isForMainFrame = true,
  }) => _onWebResourceError!(
    WebResourceError(
      errorCode: code,
      description: description,
      errorType: type,
      url: url,
      isForMainFrame: isForMainFrame,
    ),
  );

  @override
  Future<void> setOnNavigationRequest(NavigationRequestCallback cb) async =>
      _onNavigationRequest = cb;

  @override
  Future<void> setOnPageStarted(PageEventCallback cb) async =>
      _onPageStarted = cb;

  @override
  Future<void> setOnPageFinished(PageEventCallback cb) async =>
      _onPageFinished = cb;

  @override
  Future<void> setOnProgress(ProgressCallback cb) async => _onProgress = cb;

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback cb) async =>
      _onWebResourceError = cb;

  @override
  Future<void> setOnUrlChange(UrlChangeCallback cb) async => _onUrlChange = cb;
}

class _FakeWebViewWidget extends PlatformWebViewWidget {
  _FakeWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) =>
      const SizedBox.expand(key: ValueKey<String>('fake-webview'));
}
