import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config.dart';
import '../log.dart';

/// Receives every emitted log entry.
typedef LogSink = void Function(PayriffLogEntry entry);

final StreamController<PayriffLogEntry> _entries =
    StreamController<PayriffLogEntry>.broadcast();

/// The entries of every [sdkLoggerFor] logger (`Payriff.logStream`).
Stream<PayriffLogEntry> get sdkLogStream => _entries.stream;

/// The SDK's logger for [config]: on while `PayriffConfig.enableLogging` is.
SdkLogger sdkLoggerFor(PayriffConfig? config) =>
    SdkLogger(enabled: config?.enableLogging ?? false, sink: _emit);

// Entries reach logStream in every build mode, but only debug builds print
// them: a release build must not write the payment trail to the device log
// (logcat, os_log), where adb, Console or a log collector can read it.
void _emit(PayriffLogEntry entry) {
  _entries.add(entry);
  if (kDebugMode) debugPrint(entry.formatted);
}

/// The SDK's internal logger. Entries are dropped unless [enabled].
final class SdkLogger {
  /// Creates a logger that forwards to [sink] when [enabled].
  const SdkLogger({required this.enabled, required this.sink});

  /// A logger that drops everything.
  static final SdkLogger silent = SdkLogger(enabled: false, sink: (_) {});

  /// Whether entries are emitted.
  final bool enabled;

  /// Where entries go.
  final LogSink sink;

  /// Logs at [PayriffLogLevel.debug].
  void debug(String message) => log(PayriffLogLevel.debug, message);

  /// Logs at [PayriffLogLevel.info].
  void info(String message) => log(PayriffLogLevel.info, message);

  /// Logs at [PayriffLogLevel.warning].
  void warning(String message) => log(PayriffLogLevel.warning, message);

  /// Logs at [PayriffLogLevel.error].
  void error(String message) => log(PayriffLogLevel.error, message);

  /// Logs [message] at [level] when enabled.
  void log(PayriffLogLevel level, String message) {
    if (!enabled) return;
    sink(
      PayriffLogEntry(
        level: level,
        message: message,
        timestamp: DateTime.now(),
      ),
    );
  }
}

// A URL scheme at the start of a string: RFC 3986 `scheme ":"`.
final RegExp _leadingScheme = RegExp(r'^([A-Za-z][A-Za-z0-9+.\-]*):');

/// Payriff's API hosts, of every region and environment
/// (`PayriffConfig.apiBaseUrl`): the only hosts whose URL paths reach the
/// logs.
const Set<String> _payriffApiHosts = <String>{
  'api.payriff.com',
  'sb-api.payriff.com',
  'api.gccpay.sa',
};

/// A path segment this long or longer is logged as its first and last 4
/// characters.
const int _longPathSegment = 16;

// The host and optional port of an authority without its user info: an IP
// literal in brackets or a name without colons, then digits after a colon.
// Anything else (for example `user:pa` when a password holds a `/`) is not
// logged at all.
final RegExp _hostPort = RegExp(r'^(\[[^\]]*\]|[^:\[\]]*)(?::\d*)?$');

const int _slash = 0x2F; // /
const int _backslash = 0x5C; // \
const int _question = 0x3F; // ?
const int _hash = 0x23; // #

// Browsers read `\` like `/` in http(s) URLs.
bool _isSlash(int c) => c == _slash || c == _backslash;

/// Returns [url] in its loggable form (CONTRACT §11). Every URL that reaches
/// a log goes through here: the general log, the HTTP request and response
/// details, and URLs inside logged bodies and error texts.
///
/// * `http` and `https` URLs lose their user info (`user:password@`), query
///   string and fragment. Only Payriff's API hosts (`api.payriff.com`,
///   `sb-api.payriff.com`, `api.gccpay.sa`) keep the path, and every path
///   segment of 16 or more characters is shortened to its first and last 4
///   (`https://api.payriff.com/api/v3/client/orders/7c9e…0ae7/pay`). Any
///   other host, such as a bank's 3-D Secure page, is logged as
///   `scheme://host[:port]` only. Scheme and host are lower-cased.
/// * Any other scheme is reduced to `<scheme>:…`, so a `tel:` number, a
///   `mailto:` address or `data:` and `javascript:` content never reach the
///   logs.
/// * A relative reference has no known host: `//host/…` is logged as
///   `//host[:port]`, anything else as `…`.
String redactUrl(String url) {
  final String text = url.trim();
  final Match? scheme = _leadingScheme.firstMatch(text);
  final String prefix;
  int start = 0;
  if (scheme != null) {
    final String name = scheme.group(1)!;
    final String lower = name.toLowerCase();
    if (lower != 'http' && lower != 'https') return '$name:…';
    prefix = '$lower://';
    start = scheme.end;
  } else if (text.length >= 2 &&
      _isSlash(text.codeUnitAt(0)) &&
      _isSlash(text.codeUnitAt(1))) {
    prefix = '//';
  } else {
    return '…';
  }
  // As browsers read http(s) URLs: the slashes after the scheme are
  // skipped, and the authority runs to the next `/`, `\`, `?` or `#`.
  while (start < text.length && _isSlash(text.codeUnitAt(start))) {
    start++;
  }
  int end = start;
  while (end < text.length) {
    final int c = text.codeUnitAt(end);
    if (_isSlash(c) || c == _question || c == _hash) break;
    end++;
  }
  final String authority = text.substring(start, end);
  // The user info runs up to the last `@`.
  final String hostPort = authority
      .substring(authority.lastIndexOf('@') + 1)
      .toLowerCase();
  final Match? host = _hostPort.firstMatch(hostPort);
  if (host == null) return '$prefix…';
  if (!_payriffApiHosts.contains(host.group(1))) return '$prefix$hostPort';
  int pathEnd = end;
  while (pathEnd < text.length) {
    final int c = text.codeUnitAt(pathEnd);
    if (c == _question || c == _hash) break;
    pathEnd++;
  }
  final String path = text
      .substring(end, pathEnd)
      .split('/')
      .map(_shortenPathSegment)
      .join('/');
  return '$prefix$hostPort$path';
}

// A segment of [_longPathSegment] or more characters as its first and last
// 4, counted in code points so that no character is split.
String _shortenPathSegment(String segment) {
  final List<int> chars = segment.runes.toList();
  if (chars.length < _longPathSegment) return segment;
  return '${String.fromCharCodes(chars.take(4))}…'
      '${String.fromCharCodes(chars.skip(chars.length - 4))}';
}

/// Describes a secret without revealing it: `***(<length>)`, or `none`.
String redactSecret(String? secret) =>
    secret == null ? 'none' : '***(${secret.length})';

// `scheme:rest` inside free text: a scheme directly followed by a colon and
// at least one non-space character (so "Exception: …" is not a URL).
final RegExp _urlInText = RegExp(r'([A-Za-z][A-Za-z0-9+.\-]*):(?=\S)\S*');

/// Returns [text] with every URL in it redacted by [redactUrl], for
/// logging.
String redactUrlsInText(String text) =>
    text.replaceAllMapped(_urlInText, (Match match) => redactUrl(match[0]!));

/// Describes [error] for logging. Platform errors can quote the full URL
/// they failed on (for example Android's "No Activity found to handle
/// intent { … }"), so URLs are redacted.
String redactError(Object error) => redactUrlsInText(error.toString());
