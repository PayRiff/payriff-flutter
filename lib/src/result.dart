import 'package:flutter/foundation.dart';

import 'error.dart';
import 'status.dart';

/// Why a payment ended up [PayriffResultCancelled].
enum PayriffCancelReason {
  /// The customer closed the payment UI and no final status was found.
  /// `Payriff.confirmCardPayment` never returns it: once the card was sent,
  /// closing the 3-D Secure sheet gives a pending result unless the status
  /// is final (CONTRACT §16.8).
  userClosed,

  /// Payriff reported `CANCELED`.
  canceled,

  /// Payriff reported `EXPIRED` or `PREAUTH_EXPIRED`.
  expired,
}

/// Why a payment ended up [PayriffResultPending].
enum PayriffPendingReason {
  /// The status was still not final when polling ended.
  notFinal,

  /// There was no way to verify the status. Part of the shared result shape
  /// (CONTRACT §5); the card flow does not produce it.
  unverified,

  /// Every status request failed.
  verificationFailed,

  /// Payriff reported a final status outside the success, declined and
  /// cancelled groups, such as `REFUNDED`.
  unexpectedStatus,
}

/// What the SDK knows about the payment of one order.
///
/// The result in the app is for the user interface only. Fulfil an order on
/// your backend, after it confirms the order with Payriff and checks that the
/// order id, amount and currency are the ones it created (see "Fulfil on your
/// server" in the README).
@immutable
final class PayriffPayment {
  /// Creates a payment description.
  const PayriffPayment({
    required this.orderId,
    this.status = PayriffPaymentStatus.unknown,
    this.rawStatus,
    this.amount,
    this.currency,
    this.transactionId,
    this.originalOrderId,
  });

  /// The Payriff order id: the order passed to `Payriff.confirmCardPayment`.
  final String orderId;

  /// The resolved status; [PayriffPaymentStatus.unknown] when nothing was
  /// resolved.
  final PayriffPaymentStatus status;

  /// The exact status string Payriff returned.
  final String? rawStatus;

  /// The order amount from the status check, when Payriff sent one.
  final num? amount;

  /// The order currency from the status check.
  final String? currency;

  /// The Payriff transaction id. `null` in the card flow (CONTRACT §16.7);
  /// part of the shared result shape (CONTRACT §5.3).
  final String? transactionId;

  /// The order id the payment started with when it switched to another
  /// order. The card flow never switches orders, so it is always `null`;
  /// the key stays in the shared result shape (CONTRACT §16.9).
  final String? originalOrderId;

  /// A JSON-friendly map of this payment. Every key is present; unknown
  /// values are `null`.
  Map<String, Object?> toJson() => <String, Object?>{
    'orderId': orderId,
    'status': status.value,
    'rawStatus': rawStatus,
    'amount': amount,
    'currency': currency,
    'transactionId': transactionId,
    'originalOrderId': originalOrderId,
  };

  @override
  bool operator ==(Object other) =>
      other is PayriffPayment &&
      other.orderId == orderId &&
      other.status == status &&
      other.rawStatus == rawStatus &&
      other.amount == amount &&
      other.currency == currency &&
      other.transactionId == transactionId &&
      other.originalOrderId == originalOrderId;

  @override
  int get hashCode => Object.hash(
    orderId,
    status,
    rawStatus,
    amount,
    currency,
    transactionId,
    originalOrderId,
  );

  @override
  String toString() => 'PayriffPayment(${toJson()})';
}

/// The outcome of `Payriff.confirmCardPayment`.
///
/// Exactly one variant is returned per call, and payment outcomes are never
/// thrown. Show **only** [PayriffResultSuccess] as paid in the app; for
/// [PayriffResultPending], verify the order on your backend. The result is
/// for the user interface: fulfil orders on your backend after it confirms
/// them with Payriff.
///
/// ```dart
/// switch (result) {
///   case PayriffResultSuccess(:final payment):
///     showReceipt(payment.orderId);
///   case PayriffResultDeclined():
///     showMessage('Card declined');
///   case PayriffResultCancelled():
///     break;
///   case PayriffResultPending(:final payment):
///     checkOnBackend(payment.orderId);
///   case PayriffResultFailed(:final error):
///     showMessage(error.message);
/// }
/// ```
@immutable
sealed class PayriffResult {
  const PayriffResult();

  /// The variant name used in [toJson]: `success`, `declined`, `cancelled`,
  /// `pending` or `failed`.
  String get type;

  /// Whether the payment succeeded. Only a success means "paid".
  bool get isSuccess => this is PayriffResultSuccess;

  /// The payment details: always set for [PayriffResultSuccess],
  /// [PayriffResultDeclined] and [PayriffResultPending], set for
  /// [PayriffResultCancelled] when an order id is known, and `null` for
  /// [PayriffResultFailed].
  PayriffPayment? get payment;

  /// The error of a [PayriffResultFailed]; `null` for every other variant.
  PayriffError? get error => null;

  /// The JSON shape shared by all Payriff SDKs (CONTRACT §5.3). Every key is
  /// present; unknown values are `null`. For example
  /// `{"type": "success", "payment": {"orderId": "…", "status": "APPROVED",
  /// …}}` or `{"type": "cancelled", "reason": "userClosed", "payment": null}`.
  Map<String, Object?> toJson();

  @override
  String toString() => 'PayriffResult(${toJson()})';
}

/// The resolved status is `APPROVED` or `PREAUTH_APPROVED`.
final class PayriffResultSuccess extends PayriffResult {
  /// Creates a success result.
  const PayriffResultSuccess({required this.payment});

  /// The paid order.
  @override
  final PayriffPayment payment;

  @override
  String get type => 'success';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    'payment': payment.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is PayriffResultSuccess && other.payment == payment;

  @override
  int get hashCode => Object.hash(type, payment);
}

/// The resolved status is `DECLINED`.
final class PayriffResultDeclined extends PayriffResult {
  /// Creates a declined result.
  const PayriffResultDeclined({required this.payment});

  /// The declined order.
  @override
  final PayriffPayment payment;

  @override
  String get type => 'declined';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    'payment': payment.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is PayriffResultDeclined && other.payment == payment;

  @override
  int get hashCode => Object.hash(type, payment);
}

/// Payriff reported `CANCELED`, `EXPIRED` or `PREAUTH_EXPIRED`.
final class PayriffResultCancelled extends PayriffResult {
  /// Creates a cancelled result.
  const PayriffResultCancelled({required this.reason, this.payment});

  /// Why the payment was cancelled.
  final PayriffCancelReason reason;

  /// The order, with its last known status. `null` only when no order id is
  /// known.
  @override
  final PayriffPayment? payment;

  @override
  String get type => 'cancelled';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    'reason': reason.name,
    'payment': payment?.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is PayriffResultCancelled &&
      other.reason == reason &&
      other.payment == payment;

  @override
  int get hashCode => Object.hash(type, reason, payment);
}

/// The final status could not be confirmed. Verify the order on your backend
/// before fulfilling it.
final class PayriffResultPending extends PayriffResult {
  /// Creates a pending result.
  const PayriffResultPending({required this.payment, required this.reason});

  /// The order, with its last known status.
  @override
  final PayriffPayment payment;

  /// Why the status is not confirmed.
  final PayriffPendingReason reason;

  @override
  String get type => 'pending';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    'reason': reason.name,
    'payment': payment.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is PayriffResultPending &&
      other.reason == reason &&
      other.payment == payment;

  @override
  int get hashCode => Object.hash(type, reason, payment);
}

/// The payment could not start or run: invalid configuration or arguments,
/// an invalid card form, an order that cannot be paid, a Client API error,
/// or another payment is in progress.
final class PayriffResultFailed extends PayriffResult {
  /// Creates a failed result.
  const PayriffResultFailed({required this.error});

  /// What went wrong.
  @override
  final PayriffError error;

  @override
  String get type => 'failed';

  @override
  PayriffPayment? get payment => null;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    'error': error.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is PayriffResultFailed && other.error == error;

  @override
  int get hashCode => Object.hash(type, error);
}
