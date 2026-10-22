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

/// Returns [url] in its loggable form (CONTRACT §11):
///
/// * `http` and `https` URLs (and relative ones) lose their query string and
///   fragment;
/// * any other scheme is reduced to `<scheme>:…`, so a `tel:` number, a
///   `mailto:` address or `data:` and `javascript:` content never reach the
///   logs.
String redactUrl(String url) {
  final Match? scheme = _leadingScheme.firstMatch(url);
  if (scheme != null) {
    final String name = scheme.group(1)!;
    final String lower = name.toLowerCase();
    if (lower != 'http' && lower != 'https') return '$name:…';
  }
  int end = url.length;
  final int query = url.indexOf('?');
  final int fragment = url.indexOf('#');
  if (query >= 0 && query < end) end = query;
  if (fragment >= 0 && fragment < end) end = fragment;
  return url.substring(0, end);
}

/// Describes a secret without revealing it: `***(<length>)`, or `none`.
String redactSecret(String? secret) =>
    secret == null ? 'none' : '***(${secret.length})';

// `scheme:rest` inside free text: a scheme directly followed by a colon and
// at least one non-space character (so "Exception: …" is not a URL).
final RegExp _urlInText = RegExp(r'([A-Za-z][A-Za-z0-9+.\-]*):(?=\S)\S*');

/// Returns [text] with every URL in it redacted like [redactUrl], for
/// logging.
String redactUrlsInText(String text) =>
    text.replaceAllMapped(_urlInText, (Match match) => redactUrl(match[0]!));

/// Describes [error] for logging. Platform errors can quote the full URL
/// they failed on (for example Android's "No Activity found to handle
/// intent { … }"), so URLs are redacted.
String redactError(Object error) => redactUrlsInText(error.toString());
