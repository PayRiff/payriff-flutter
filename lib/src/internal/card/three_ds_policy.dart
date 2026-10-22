/// CONTRACT §16.8 (`card_3ds_navigation.json`): the navigation rules of the
/// 3DS sheet and of the hidden 3-D Secure Method WebViews. Pure.
library;

import '../url_policy.dart';

/// What to do with a 3DS navigation.
enum ThreeDsNavigationAction {
  /// Load it.
  allow,

  /// Payriff's bank callback: load it (it carries the bank's `cres`), never
  /// cancel it, and arm the flow.
  allowCallback,

  /// Cancel it, close the WebView and resolve the status.
  finish,

  /// Hand it to the operating system and keep the WebView.
  external,

  /// Cancel it silently.
  block,
}

const Set<String> _neverExternal = <String>{
  'http',
  'https',
  'file',
  'content',
  'javascript',
  'data',
  'blob',
  'about',
};

const Set<String> _inlineSubframeSchemes = <String>{
  'about',
  'data',
  'blob',
  'javascript',
};

/// The navigation rules of one 3DS WebView. Stateful: once a callback has
/// loaded, the next main-frame navigation that is neither another callback
/// nor `about:blank` ends the flow.
final class ThreeDsNavigationPolicy {
  /// Creates the rules for the API at [apiBaseUrl], for example
  /// `https://api.payriff.com`.
  ThreeDsNavigationPolicy(String apiBaseUrl)
    : _apiHost = _hostOf(Uri.parse(apiBaseUrl));

  final String _apiHost;
  bool _callbackSeen = false;

  /// Whether a gateway callback has loaded in the main frame.
  bool get callbackSeen => _callbackSeen;

  /// Decides what to do with a navigation to [url].
  ThreeDsNavigationAction decide(String url, {required bool isMainFrame}) {
    final Uri? uri = Uri.tryParse(url.trim());
    if (uri == null || uri.scheme.isEmpty) {
      return ThreeDsNavigationAction.block;
    }
    final String scheme = uri.scheme.toLowerCase();
    if (!isMainFrame) {
      // Subframes neither arm nor end the flow, and never leave the app.
      return scheme == 'https' ||
              scheme == 'http' ||
              _inlineSubframeSchemes.contains(scheme)
          ? ThreeDsNavigationAction.allow
          : ThreeDsNavigationAction.block;
    }
    if (isGatewayCallback(url)) {
      _callbackSeen = true;
      return ThreeDsNavigationAction.allowCallback;
    }
    if (isBlankPageUrl(url)) return ThreeDsNavigationAction.allow;
    if (_callbackSeen) return ThreeDsNavigationAction.finish;
    if (scheme == 'https') return ThreeDsNavigationAction.allow;
    if (!_neverExternal.contains(scheme)) {
      return ThreeDsNavigationAction.external;
    }
    return ThreeDsNavigationAction.block;
  }

  /// Whether [url] is Payriff's bank callback: an https URL on the API host
  /// (case-insensitive, default port) whose path starts with
  /// `/api/v3/gateway/` and has a `callback` segment.
  bool isGatewayCallback(String url) {
    final Uri? uri = Uri.tryParse(url.trim());
    if (uri == null || uri.scheme.toLowerCase() != 'https') return false;
    if (_hostOf(uri) != _apiHost || (uri.hasPort && uri.port != 443)) {
      return false;
    }
    final List<String> segments = uri.pathSegments;
    return uri.path.startsWith('/api/v3/gateway/') &&
        segments.length > 3 &&
        segments.skip(3).contains('callback');
  }

  static String _hostOf(Uri uri) {
    String host = uri.host.toLowerCase();
    if (host.endsWith('.')) host = host.substring(0, host.length - 1);
    return host;
  }
}
