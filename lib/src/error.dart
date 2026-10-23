import 'package:flutter/foundation.dart';

import 'card/card_types.dart';

/// Machine-readable error categories, shared by all Payriff mobile SDKs.
enum PayriffErrorCode {
  /// `Payriff.configure` was never called.
  notConfigured('NOT_CONFIGURED'),

  /// The configuration is not usable: `PayriffConfig.publishableKey` is
  /// missing or is not a publishable key (`pr_pk_live_…`).
  invalidConfig('INVALID_CONFIG'),

  /// The `orderId` or `clientSecret` passed to the SDK cannot be used. The
  /// message names the argument, never its value.
  invalidOrder('INVALID_ORDER'),

  /// Another payment from this SDK is running.
  paymentInProgress('PAYMENT_IN_PROGRESS'),

  /// There is no navigator to present the 3-D Secure sheet from.
  presentationFailed('PRESENTATION_FAILED'),

  /// HTTP 401: a wrong or revoked publishable key, or this app is not
  /// allowed for it. Fatal.
  unauthorized('UNAUTHORIZED'),

  /// HTTP 429. Fatal after the SDK's retries.
  rateLimited('RATE_LIMITED'),

  /// The card form is not valid. `PayriffError.fields` lists the
  /// invalid fields; no request was made.
  validationFailed('VALIDATION_FAILED'),

  /// HTTP 404: the order does not exist or its `clientSecret`
  /// expired. Fatal: create a new order.
  sessionExpired('SESSION_EXPIRED'),

  /// The order cannot be paid by card (already paid, not
  /// `CREATED` or `PENDING`, or `CARD` is not among its payment methods),
  /// or the API answered HTTP 400.
  orderNotPayable('ORDER_NOT_PAYABLE'),

  /// The API rejected the request format (HTTP 400 with code
  /// `15400`). An integration bug.
  invalidRequest('INVALID_REQUEST'),

  /// Any other unsuccessful answer. Carries Payriff's message;
  /// the customer may try again.
  paymentFailed('PAYMENT_FAILED'),

  /// The API's next step could not be understood and the order's
  /// status was not final.
  unexpectedResponse('UNEXPECTED_RESPONSE'),

  /// Card payments are refused on this device (CONTRACT §16.16): it is
  /// rooted or jailbroken, a hooking framework such as Frida is loaded, a
  /// debugger is attached to a release build, or the check could not
  /// complete, and `PayriffConfig.allowCompromisedDevices` is off (or
  /// ignored: it works only in debug builds). Nothing was sent. Not fatal:
  /// the order can still be paid on another device.
  deviceCompromised('DEVICE_COMPROMISED'),

  /// Payriff answered with an error envelope (`code` other than `00000`).
  /// Part of the code set shared by all Payriff SDKs (CONTRACT §5.3); the
  /// card flow maps its answers as in CONTRACT §16.3 and does not produce it.
  apiError('API_ERROR'),

  /// No HTTP response arrived: offline, DNS, TLS or timeout. When Payriff's
  /// server certificate fails the SDK's pinning (CONTRACT §16.15), the error
  /// is not retryable and says "Payriff's server certificate could not be
  /// verified."; nothing was sent.
  networkError('NETWORK_ERROR'),

  /// Anything else.
  unknown('UNKNOWN');

  const PayriffErrorCode(this.value);

  /// The canonical UPPER_SNAKE code, for example `NETWORK_ERROR`.
  final String value;
}

/// Describes why an SDK operation failed.
///
/// Payment outcomes are never errors: `Payriff.confirmCardPayment` returns a
/// `PayriffResult`. A [PayriffError] appears in `PayriffResultFailed` and
/// inside the [PayriffException] thrown by `Payriff.retrieveOrder`.
@immutable
final class PayriffError {
  /// Creates an error.
  const PayriffError({
    required this.code,
    required this.message,
    this.isRetryable = false,
    this.httpStatus,
    this.payriffCode,
    this.supportTicket,
    this.cause,
    this.isFatal = false,
    this.fields,
  });

  /// The error category.
  final PayriffErrorCode code;

  /// A human-readable description. For Payriff errors this is Payriff's
  /// message without the support-ticket suffix.
  final String message;

  /// Whether repeating the same call later may succeed.
  final bool isRetryable;

  /// The HTTP status, when a response arrived.
  final int? httpStatus;

  /// Payriff's envelope `code`, for example `01000`.
  final String? payriffCode;

  /// The digits of Payriff's `Support ticket: …` suffix, when present.
  final String? supportTicket;

  /// The underlying platform error, if any.
  final Object? cause;

  /// `true` means this order can no longer be paid from the app; create a
  /// new order (`UNAUTHORIZED`, `SESSION_EXPIRED`, `RATE_LIMITED`).
  final bool isFatal;

  /// `VALIDATION_FAILED` only: the invalid fields and why. Never contains
  /// what the customer typed.
  final List<PayriffCardFieldError>? fields;

  /// A JSON-friendly map of this error in the shared shape of CONTRACT §5.3
  /// (without [cause], [isFatal] and [fields]).
  Map<String, Object?> toJson() => <String, Object?>{
    'code': code.value,
    'message': message,
    'isRetryable': isRetryable,
    'httpStatus': httpStatus,
    'payriffCode': payriffCode,
    'supportTicket': supportTicket,
  };

  @override
  bool operator ==(Object other) =>
      other is PayriffError &&
      other.code == code &&
      other.message == message &&
      other.isRetryable == isRetryable &&
      other.httpStatus == httpStatus &&
      other.payriffCode == payriffCode &&
      other.supportTicket == supportTicket &&
      other.isFatal == isFatal &&
      listEquals(other.fields, fields);

  @override
  int get hashCode => Object.hash(
    code,
    message,
    isRetryable,
    httpStatus,
    payriffCode,
    supportTicket,
    isFatal,
    fields == null ? null : Object.hashAll(fields!),
  );

  @override
  String toString() {
    final StringBuffer buffer = StringBuffer('PayriffError(${code.value}');
    if (httpStatus != null) buffer.write(', HTTP $httpStatus');
    if (payriffCode != null) buffer.write(', payriffCode $payriffCode');
    if (supportTicket != null) buffer.write(', ticket $supportTicket');
    if (isFatal) buffer.write(', fatal');
    final List<PayriffCardFieldError>? invalid = fields;
    if (invalid != null && invalid.isNotEmpty) {
      buffer.write(
        ', fields ${invalid.map((PayriffCardFieldError f) => '${f.field.value}:${f.error.value}').join(',')}',
      );
    }
    buffer.write('): $message');
    return buffer.toString();
  }
}

/// Thrown by `Payriff.retrieveOrder`.
final class PayriffException implements Exception {
  /// Wraps [error].
  const PayriffException(this.error);

  /// What went wrong.
  final PayriffError error;

  @override
  String toString() => 'PayriffException: $error';
}
