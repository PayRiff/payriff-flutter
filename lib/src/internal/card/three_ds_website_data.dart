/// CONTRACT §9.1a: the sites one payment's 3-D Secure WebViews loaded, so
/// their website data can be removed when the payment ends. The WebViews
/// come from `webview_flutter`, so the SDK cannot give them a data store of
/// their own. Pure.
library;

/// The http(s) pages and frames that one payment's 3-D Secure WebViews (the
/// sheet and the hidden 3-D Secure Method views) loaded: their hosts,
/// origins and URLs, each in the order first seen.
final class ThreeDsWebsiteData {
  /// The most hosts, origins and URLs kept, each. New ones after that are
  /// dropped, so a page cannot grow the lists without bound; the first ones
  /// are the pages the SDK itself opened.
  static const int maxEntries = 64;

  final Set<String> _hosts = <String>{};
  final Set<String> _origins = <String>{};
  final Set<String> _urls = <String>{};

  /// The hosts, lower-case and without a trailing dot, for example
  /// `acs.bank.example`.
  List<String> get hosts => List<String>.unmodifiable(_hosts);

  /// The origins, for example `https://acs.bank.example` or
  /// `https://acs.bank.example:8443`.
  List<String> get origins => List<String>.unmodifiable(_origins);

  /// The URLs without user info, query and fragment, for example
  /// `https://acs.bank.example/challenge`.
  List<String> get urls => List<String>.unmodifiable(_urls);

  /// Whether no site was recorded.
  bool get isEmpty => _hosts.isEmpty;

  /// Records [url] when it is an absolute `http` or `https` URL with a host.
  /// Anything else (`about:blank`, `data:`, app links) is ignored.
  void record(String url) {
    final Uri? uri = Uri.tryParse(url.trim());
    if (uri == null) return;
    final String scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return;
    final String host = uri.host.toLowerCase();
    final String site = host.endsWith('.')
        ? host.substring(0, host.length - 1)
        : host;
    if (site.isEmpty) return;
    if (!_hosts.contains(site) && _hosts.length >= maxEntries) return;
    _hosts.add(site);
    final String origin = Uri(
      scheme: scheme,
      host: host,
      port: uri.hasPort ? uri.port : null,
    ).toString();
    _add(_origins, origin);
    _add(_urls, '$origin${uri.path.isEmpty ? '/' : uri.path}');
  }

  static void _add(Set<String> entries, String entry) {
    if (entries.length < maxEntries) entries.add(entry);
  }
}
