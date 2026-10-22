import 'package:flutter/foundation.dart';

/// Severity of a [PayriffLogEntry].
enum PayriffLogLevel {
  /// Detailed diagnostics: navigations, requests, status attempts.
  debug,

  /// Milestones: configured, payment finished.
  info,

  /// Something unexpected that the SDK handled.
  warning,

  /// A failure.
  error,
}

/// One line of SDK logging, delivered through `Payriff.logStream` when
/// `PayriffConfig.enableLogging` is on.
///
/// Log lines never contain card data, the order's client secret or the
/// publishable key. URLs are redacted: `http(s)` URLs lose their query
/// string and fragment, and any other scheme is logged as `<scheme>:…`.
@immutable
final class PayriffLogEntry {
  /// Creates a log entry.
  const PayriffLogEntry({
    required this.level,
    required this.message,
    required this.timestamp,
  });

  /// The severity.
  final PayriffLogLevel level;

  /// The message, without the `[Payriff] [LEVEL]` prefix.
  final String message;

  /// When the entry was created.
  final DateTime timestamp;

  /// The console form: `[Payriff] [LEVEL] message`, for example
  /// `[Payriff] [INFO] confirmCardPayment: order 7c9e6679-…`.
  String get formatted => '[Payriff] [${level.name.toUpperCase()}] $message';

  /// The same as [formatted].
  @override
  String toString() => formatted;
}
