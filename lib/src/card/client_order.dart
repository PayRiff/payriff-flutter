import 'package:flutter/foundation.dart';

import '../status.dart';

/// An order as the Client API shows it to the app (`Payriff.retrieveOrder`,
/// CONTRACT §16.10): what the customer is paying and how.
@immutable
final class PayriffClientOrder {
  /// Creates an order description.
  const PayriffClientOrder({
    required this.orderId,
    this.amount,
    this.currency,
    this.description,
    this.merchantName,
    this.status = PayriffPaymentStatus.unknown,
    this.rawStatus,
    this.language,
    this.paymentMethods = const <String>[],
  });

  /// Reads the `payload` of `GET /api/v3/client/orders/{orderId}`.
  /// [requestedOrderId] is used when the payload has no `orderId`.
  factory PayriffClientOrder.fromPayload(
    Map<String, Object?> payload, {
    required String requestedOrderId,
  }) {
    String? text(Object? value) => value is String ? value : null;
    final Object? id = payload['orderId'];
    final Object? amount = payload['amount'];
    final Object? methods = payload['paymentMethods'];
    final String? rawStatus = text(payload['status']);
    return PayriffClientOrder(
      orderId: id is String && id.isNotEmpty ? id : requestedOrderId,
      amount: switch (amount) {
        final num n => n,
        final String s => num.tryParse(s.trim()),
        _ => null,
      },
      currency: text(payload['currency']),
      description: text(payload['description']),
      merchantName: text(payload['merchantName']),
      status: PayriffPaymentStatus.parse(rawStatus),
      rawStatus: rawStatus,
      language: text(payload['language']),
      paymentMethods: methods is List
          ? List<String>.unmodifiable(methods.whereType<String>())
          : const <String>[],
    );
  }

  /// The Payriff order id.
  final String orderId;

  /// The amount in major units.
  final num? amount;

  /// The ISO currency code.
  final String? currency;

  /// The order description.
  final String? description;

  /// The merchant's display name.
  final String? merchantName;

  /// The order status.
  final PayriffPaymentStatus status;

  /// The exact status string Payriff returned.
  final String? rawStatus;

  /// The order language as Payriff sent it, for example `AZ`.
  final String? language;

  /// The payment methods the order accepts, for example `CARD`.
  final List<String> paymentMethods;

  /// Whether the card flow can pay this order: its status is `CREATED` or
  /// `PENDING` and `CARD` is among its [paymentMethods].
  bool get isPayableByCard =>
      (status == PayriffPaymentStatus.created ||
          status == PayriffPaymentStatus.pending) &&
      paymentMethods.contains('CARD');

  /// A JSON-friendly map of this order.
  Map<String, Object?> toJson() => <String, Object?>{
    'orderId': orderId,
    'amount': amount,
    'currency': currency,
    'description': description,
    'merchantName': merchantName,
    'status': status.value,
    'rawStatus': rawStatus,
    'language': language,
    'paymentMethods': paymentMethods,
  };

  @override
  bool operator ==(Object other) =>
      other is PayriffClientOrder &&
      other.orderId == orderId &&
      other.amount == amount &&
      other.currency == currency &&
      other.description == description &&
      other.merchantName == merchantName &&
      other.status == status &&
      other.rawStatus == rawStatus &&
      other.language == language &&
      listEquals(other.paymentMethods, paymentMethods);

  @override
  int get hashCode => Object.hash(
    orderId,
    amount,
    currency,
    description,
    merchantName,
    status,
    rawStatus,
    language,
    Object.hashAll(paymentMethods),
  );

  @override
  String toString() =>
      'PayriffClientOrder(orderId: $orderId, amount: $amount, '
      'currency: $currency, status: ${rawStatus ?? status.value}, '
      'paymentMethods: $paymentMethods)';
}
