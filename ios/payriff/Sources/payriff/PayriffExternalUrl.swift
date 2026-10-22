import Foundation

/// Scheme rules for `openExternal` (CONTRACT §7.5, §16.0 item 5). Same rules as Android.
enum PayriffExternalUrl {
  static let refusedSchemes: Set<String> = ["file", "content", "javascript", "data", "blob", "about"]

  /// The lowercased scheme, or nil when `url` has no valid scheme.
  static func scheme(of url: String) -> String? {
    guard let colon = url.firstIndex(of: ":"), colon != url.startIndex else { return nil }
    let candidate = url[url.startIndex..<colon]
    guard let first = candidate.unicodeScalars.first, first.isASCII,
      CharacterSet.letters.contains(first),
      candidate.unicodeScalars.allSatisfy({
        $0.isASCII
          && (CharacterSet.alphanumerics.contains($0) || $0 == "+" || $0 == "." || $0 == "-")
      })
    else {
      return nil
    }
    return candidate.lowercased()
  }

  /// True when `url` may be handed to the OS: it has a scheme that is not refused, and no
  /// whitespace or control characters (a WebView or Dart `Uri` always encodes those).
  static func mayLaunch(_ url: String) -> Bool {
    guard !url.isEmpty,
      !url.unicodeScalars.contains(where: { $0.value <= 0x20 || $0.value == 0x7F })
    else {
      return false
    }
    guard let scheme = scheme(of: url) else { return false }
    return !refusedSchemes.contains(scheme)
  }
}
