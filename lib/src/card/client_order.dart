import 'package:flutter/foundation.dart';

import '../status.dart';

/// The Apple Pay part of a [PayriffClientOrder] (CONTRACT §17.3): Payriff's
/// own Apple Pay merchant, for its web checkout. The SDK does not use it: in
/// the app, Apple Pay uses `PayriffApplePayConfig.merchantIdentifier`.
@immutable
final class PayriffClientOrderApplePay {
  /// Creates the Apple Pay part of an order.
  const PayriffClientOrderApplePay({this.merchantIdentifier});

  /// The Apple Pay merchant ID Payriff sent.
  final String? merchantIdentifier;

  /// A JSON-friendly map of this part.
  Map<String, Object?> toJson() => <String, Object?>{
    'merchantIdentifier': merchantIdentifier,
  };

  @override
  bool operator ==(Object other) =>
      other is PayriffClientOrderApplePay &&
      other.merchantIdentifier == merchantIdentifier;

  @override
  int get hashCode => merchantIdentifier.hashCode;

  @override
  String toString() =>
      'PayriffClientOrderApplePay(merchantIdentifier: $merchantIdentifier)';
}

/// The Google Pay part of a [PayriffClientOrder] (CONTRACT §17.3): the
/// tokenization parameters of the Google Pay request. Google Pay is offered
/// only when both are set.
@immutable
final class PayriffClientOrderGooglePay {
  /// Creates the Google Pay part of an order.
  const PayriffClientOrderGooglePay({this.gateway, this.gatewayMerchantId});

  /// The gateway, for example `payriff`.
  final String? gateway;

  /// The merchant's id at the gateway.
  final String? gatewayMerchantId;

  /// A JSON-friendly map of this part.
  Map<String, Object?> toJson() => <String, Object?>{
    'gateway': gateway,
    'gatewayMerchantId': gatewayMerchantId,
  };

  @override
  bool operator ==(Object other) =>
      other is PayriffClientOrderGooglePay &&
      other.gateway == gateway &&
      other.gatewayMerchantId == gatewayMerchantId;

  @override
  int get hashCode => Object.hash(gateway, gatewayMerchantId);

  @override
  String toString() =>
      'PayriffClientOrderGooglePay(gateway: $gateway, '
      'gatewayMerchantId: $gatewayMerchantId)';
}

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
    this.applePay,
    this.googlePay,
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
    final Object? applePay = payload['applePay'];
    final Object? googlePay = payload['googlePay'];
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
      applePay: applePay is Map
          ? PayriffClientOrderApplePay(
              merchantIdentifier: text(applePay['merchantIdentifier']),
            )
          : null,
      googlePay: googlePay is Map
          ? PayriffClientOrderGooglePay(
              gateway: text(googlePay['gateway']),
              gatewayMerchantId: text(googlePay['gatewayMerchantId']),
            )
          : null,
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

  /// The payment methods the order accepts: `CARD`, `APPLE_PAY`,
  /// `GOOGLE_PAY`.
  final List<String> paymentMethods;

  /// The order's Apple Pay part, when Payriff sent one. Apple Pay in the app
  /// does not need it (CONTRACT §17.3).
  final PayriffClientOrderApplePay? applePay;

  /// The order's Google Pay part, when Payriff sent one: the gateway
  /// parameters that Google Pay needs (CONTRACT §17.3).
  final PayriffClientOrderGooglePay? googlePay;

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
    'applePay': applePay?.toJson(),
    'googlePay': googlePay?.toJson(),
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
      listEquals(other.paymentMethods, paymentMethods) &&
      other.applePay == applePay &&
      other.googlePay == googlePay;

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
    applePay,
    googlePay,
  );

  @override
  String toString() =>
      'PayriffClientOrder(orderId: $orderId, amount: $amount, '
      'currency: $currency, status: ${rawStatus ?? status.value}, '
      'paymentMethods: $paymentMethods)';
}
