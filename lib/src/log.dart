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
/// publishable key. URLs are redacted, in the HTTP details and logged bodies
/// too: `http(s)` URLs lose their user info, query string and fragment, and
/// only Payriff's API hosts keep the path, with segments of 16 or more
/// characters shortened (`/api/v3/client/orders/7c9e…0ae7/pay`); other
/// hosts, such as a bank's 3-D Secure pages, are logged as
/// `scheme://host[:port]`. Any other scheme is logged as `<scheme>:…`.
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
