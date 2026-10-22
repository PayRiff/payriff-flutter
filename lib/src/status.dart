/// A Payriff order `paymentStatus`.
///
/// Payriff sends upper-case strings; [value] holds the canonical one. Use
/// [PayriffPaymentStatus.parse] to read raw strings: it tolerates case,
/// hyphens, spaces and known aliases, and maps anything unrecognised to
/// [unknown].
enum PayriffPaymentStatus {
  /// `CREATED`: the order exists, nothing has been paid yet.
  created('CREATED'),

  /// `PENDING`: a payment is in progress.
  pending('PENDING'),

  /// `ACCEPTED`: accepted, not final yet.
  accepted('ACCEPTED'),

  /// `APPROVED`: paid (aliases `PAID`, `COMPLETED`, `SETTLED`,
  /// `SETTLE_PENDING`).
  approved('APPROVED'),

  /// `PREAUTH_APPROVED`: the pre-authorization hold succeeded.
  preAuthApproved('PREAUTH_APPROVED'),

  /// `DECLINED`: the payment was declined (alias `FAILED`).
  declined('DECLINED'),

  /// `CANCELED`: the payment was cancelled (alias `CANCELLED`).
  canceled('CANCELED'),

  /// `EXPIRED`: the order expired.
  expired('EXPIRED'),

  /// `PREAUTH_EXPIRED`: the pre-authorization expired.
  preAuthExpired('PREAUTH_EXPIRED'),

  /// `REFUNDED`.
  refunded('REFUNDED'),

  /// `PARTIAL_REFUND`.
  partialRefund('PARTIAL_REFUND'),

  /// `REFUND_IN_PROGRESS`.
  refundInProgress('REFUND_IN_PROGRESS'),

  /// `REVERSE` (alias `REVERSED`).
  reverse('REVERSE'),

  /// `PARTIAL`.
  partial('PARTIAL'),

  /// `CASH`.
  cash('CASH'),

  /// No status was resolved, or Payriff sent a value this SDK does not know.
  unknown('UNKNOWN');

  const PayriffPaymentStatus(this.value);

  /// The canonical upper-case value, for example `PREAUTH_APPROVED`.
  final String value;

  static const Map<String, PayriffPaymentStatus> _aliases =
      <String, PayriffPaymentStatus>{
        'PAID': approved,
        'COMPLETED': approved,
        'SETTLED': approved,
        'SETTLE_PENDING': approved,
        'FAILED': declined,
        'CANCELLED': canceled,
        'REVERSED': reverse,
      };

  /// Parses a raw Payriff status.
  ///
  /// The value is trimmed and upper-cased, and `-` and spaces become `_`
  /// before matching. `null`, empty and unrecognised values give [unknown].
  static PayriffPaymentStatus parse(String? raw) {
    if (raw == null) return unknown;
    final String normalized = raw
        .trim()
        .toUpperCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
    if (normalized.isEmpty) return unknown;
    final PayriffPaymentStatus? alias = _aliases[normalized];
    if (alias != null) return alias;
    for (final PayriffPaymentStatus status in values) {
      if (status != unknown && status.value == normalized) return status;
    }
    return unknown;
  }

  /// Whether this status ends the payment (it is not `CREATED`, `PENDING`,
  /// `ACCEPTED`, `PARTIAL` or `UNKNOWN`).
  bool get isFinal => switch (this) {
    created || pending || accepted || partial || unknown => false,
    _ => true,
  };
}
