/// CONTRACT §8.1–§8.2: status readings, outcome groups and the result of a
/// final status.
library;

import 'package:flutter/foundation.dart';

import '../result.dart';
import '../status.dart';

/// One status reading.
@immutable
final class StatusReading {
  /// Creates a reading.
  const StatusReading({
    required this.status,
    this.rawStatus,
    this.amount,
    this.currency,
  });

  /// The normalized status.
  final PayriffPaymentStatus status;

  /// The raw status string.
  final String? rawStatus;

  /// The order amount, when the source knows it.
  final num? amount;

  /// The order currency, when the source knows it.
  final String? currency;
}

/// The outcome groups of CONTRACT §8.2.
enum StatusOutcome {
  /// `APPROVED`, `PREAUTH_APPROVED`.
  success,

  /// `DECLINED`.
  declined,

  /// `CANCELED`, `EXPIRED`, `PREAUTH_EXPIRED`.
  cancelled,

  /// `REFUNDED`, `PARTIAL_REFUND`, `REFUND_IN_PROGRESS`, `REVERSE`, `CASH`.
  unexpectedFinal,

  /// `CREATED`, `PENDING`, `ACCEPTED`, `PARTIAL`, `UNKNOWN`: keep polling.
  nonFinal,
}

/// CONTRACT §8.2: the outcome group of [status].
StatusOutcome outcomeOf(PayriffPaymentStatus status) => switch (status) {
  PayriffPaymentStatus.approved ||
  PayriffPaymentStatus.preAuthApproved => StatusOutcome.success,
  PayriffPaymentStatus.declined => StatusOutcome.declined,
  PayriffPaymentStatus.canceled ||
  PayriffPaymentStatus.expired ||
  PayriffPaymentStatus.preAuthExpired => StatusOutcome.cancelled,
  PayriffPaymentStatus.refunded ||
  PayriffPaymentStatus.partialRefund ||
  PayriffPaymentStatus.refundInProgress ||
  PayriffPaymentStatus.reverse ||
  PayriffPaymentStatus.cash => StatusOutcome.unexpectedFinal,
  PayriffPaymentStatus.created ||
  PayriffPaymentStatus.pending ||
  PayriffPaymentStatus.accepted ||
  PayriffPaymentStatus.partial ||
  PayriffPaymentStatus.unknown => StatusOutcome.nonFinal,
};

/// Builds the [PayriffPayment] for [orderId] from [reading]; the status is
/// [PayriffPaymentStatus.unknown] without a reading.
PayriffPayment paymentFor(String orderId, StatusReading? reading) =>
    PayriffPayment(
      orderId: orderId,
      status: reading?.status ?? PayriffPaymentStatus.unknown,
      rawStatus: reading?.rawStatus,
      amount: reading?.amount,
      currency: reading?.currency,
    );

/// CONTRACT §8.2: the result for a payment whose status is final, or `null`
/// when the status is not final.
PayriffResult? resultForFinalStatus(PayriffPayment payment) =>
    switch (outcomeOf(payment.status)) {
      StatusOutcome.success => PayriffResultSuccess(payment: payment),
      StatusOutcome.declined => PayriffResultDeclined(payment: payment),
      StatusOutcome.cancelled => PayriffResultCancelled(
        reason: payment.status == PayriffPaymentStatus.canceled
            ? PayriffCancelReason.canceled
            : PayriffCancelReason.expired,
        payment: payment,
      ),
      StatusOutcome.unexpectedFinal => PayriffResultPending(
        payment: payment,
        reason: PayriffPendingReason.unexpectedStatus,
      ),
      StatusOutcome.nonFinal => null,
    };
