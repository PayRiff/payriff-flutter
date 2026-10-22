/// Pure URL rules used by the 3-D Secure flow (CONTRACT §7.5, §16.8): URL
/// shapes and the schemes that may be handed to another app. No Flutter
/// imports, fully unit-testable.
library;

/// Parses [url]; `null` when it cannot be parsed or has no scheme.
Uri? _parse(String url) {
  final Uri? uri = Uri.tryParse(url);
  if (uri == null || uri.scheme.isEmpty) return null;
  return uri;
}

bool _isHttp(Uri uri) {
  final String scheme = uri.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https';
}

/// Whether [url] is `about:blank` (with an optional query or fragment).
bool isBlankPageUrl(String url) {
  final String lower = url.trim().toLowerCase();
  return lower == 'about:blank' ||
      lower.startsWith('about:blank?') ||
      lower.startsWith('about:blank#');
}

/// Whether [url] is an absolute `http` or `https` URL with a host.
bool isAbsoluteHttpUrl(String url) {
  final Uri? uri = _parse(url);
  return uri != null && _isHttp(uri) && uri.host.isNotEmpty;
}

/// Whether [url] is an absolute `https` URL with a host.
bool isAbsoluteHttpsUrl(String url) {
  final Uri? uri = _parse(url);
  return uri != null &&
      uri.scheme.toLowerCase() == 'https' &&
      uri.host.isNotEmpty;
}

/// Schemes that are never handed to another app (CONTRACT §7.5, §16.0
/// item 5): local files and content providers, and page-internal content.
const Set<String> _neverExternalSchemes = <String>{
  'file',
  'content',
  'javascript',
  'data',
  'blob',
  'about',
};

/// Whether [url] may be handed to the operating system: it parses, has a
/// scheme, and the scheme is not a local or page-internal one (`file`,
/// `content`, `javascript`, `data`, `blob`, `about`).
bool mayOpenExternally(String url) {
  final Uri? uri = _parse(url);
  return uri != null &&
      !_neverExternalSchemes.contains(uri.scheme.toLowerCase());
}
