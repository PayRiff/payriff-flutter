// Card-flow models: publishableKey, PayriffError.isFatal/fields and
// PayriffClientOrder. Secrets never reach toString or toJson (CONTRACT §11,
// §16.5).
import 'package:flutter_test/flutter_test.dart';
import 'package:payriff/payriff.dart';

void main() {
  test('PayriffConfig.toString hides the publishable key', () {
    const PayriffConfig config = PayriffConfig(
      publishableKey: ' pr_pk_live_SECRETISH ',
    );
    expect(config.toString(), isNot(contains('SECRETISH')));
    expect(config.toString(), contains('publishableKey: ***(20)'));
    expect(const PayriffConfig().toString(), contains('publishableKey: null'));
  });

  test('PayriffConfig.toString shows the wallets; merchant IDs are not '
      'secret (CONTRACT §17.2)', () {
    expect(
      const PayriffConfig().toString(),
      allOf(contains('applePay: null'), contains('googlePay: null')),
    );
    const PayriffConfig wallets = PayriffConfig(
      applePay: PayriffApplePayConfig(
        merchantIdentifier: ' merchant.com.example.shop ',
      ),
      googlePay: PayriffGooglePayConfig(merchantId: 'BCR2DN4TABCDEF'),
    );
    expect(
      wallets.toString(),
      allOf(
        contains('applePay: merchant.com.example.shop,'),
        contains('googlePay: on'),
      ),
    );
    expect(
      const PayriffConfig(
        applePay: PayriffApplePayConfig(merchantIdentifier: 'com.shop'),
      ).toString(),
      contains('applePay: invalid'),
    );
    expect(
      const PayriffApplePayConfig(merchantIdentifier: 'merchant.a'),
      const PayriffApplePayConfig(merchantIdentifier: 'merchant.a'),
    );
    expect(
      const PayriffGooglePayConfig(merchantName: 'Shop'),
      isNot(const PayriffGooglePayConfig()),
    );
  });

  test('PayriffError.isFatal and fields: equality, toString, §5.3 JSON', () {
    const PayriffError fatal = PayriffError(
      code: PayriffErrorCode.sessionExpired,
      message: 'gone',
      isFatal: true,
    );
    expect(
      fatal,
      isNot(
        const PayriffError(
          code: PayriffErrorCode.sessionExpired,
          message: 'gone',
        ),
      ),
    );
    expect(fatal.toString(), contains('fatal'));
    // The shared JSON shape is unchanged.
    expect(fatal.toJson().keys, <String>[
      'code',
      'message',
      'isRetryable',
      'httpStatus',
      'payriffCode',
      'supportTicket',
    ]);
    const PayriffError invalid = PayriffError(
      code: PayriffErrorCode.validationFailed,
      message: 'invalid',
      fields: <PayriffCardFieldError>[
        PayriffCardFieldError(
          field: PayriffCardField.cvv,
          error: PayriffCardFieldErrorCode.incomplete,
        ),
      ],
    );
    expect(invalid.toString(), contains('fields cvv:incomplete'));
    expect(
      invalid,
      const PayriffError(
        code: PayriffErrorCode.validationFailed,
        message: 'invalid',
        fields: <PayriffCardFieldError>[
          PayriffCardFieldError(
            field: PayriffCardField.cvv,
            error: PayriffCardFieldErrorCode.incomplete,
          ),
        ],
      ),
    );
    expect(invalid.fields!.single.toJson(), <String, Object?>{
      'field': 'cvv',
      'error': 'incomplete',
    });
  });

  test('PayriffClientOrder JSON and payability', () {
    final PayriffClientOrder order = PayriffClientOrder.fromPayload(
      <String, Object?>{
        'amount': '10.50',
        'status': 'PENDING',
        'paymentMethods': <Object?>['CARD', 5, null],
      },
      requestedOrderId: 'o9',
    );
    expect(order.orderId, 'o9');
    expect(order.amount, 10.5);
    expect(order.paymentMethods, <String>['CARD']);
    expect(order.isPayableByCard, isTrue);
    expect(order.toJson()['status'], 'PENDING');
    expect(order.applePay, isNull);
    expect(order.googlePay, isNull);
  });

  test('PayriffClientOrder reads the wallet parts as the web SDK does '
      '(CONTRACT §17.3)', () {
    final PayriffClientOrder order = PayriffClientOrder.fromPayload(
      <String, Object?>{
        'status': 'CREATED',
        'paymentMethods': <Object?>['GOOGLE_PAY', 'APPLE_PAY'],
        'googlePay': <String, Object?>{
          'gateway': 'payriff',
          'gatewayMerchantId': 'BCR2DN4T',
        },
        'applePay': <String, Object?>{
          'merchantIdentifier': 'merchant.com.payriff',
        },
      },
      requestedOrderId: 'o9',
    );
    expect(
      order.googlePay,
      const PayriffClientOrderGooglePay(
        gateway: 'payriff',
        gatewayMerchantId: 'BCR2DN4T',
      ),
    );
    expect(
      order.applePay,
      const PayriffClientOrderApplePay(
        merchantIdentifier: 'merchant.com.payriff',
      ),
    );
    expect(order.isPayableByCard, isFalse);
    expect(order.toJson()['googlePay'], <String, Object?>{
      'gateway': 'payriff',
      'gatewayMerchantId': 'BCR2DN4T',
    });
    expect(order.toJson()['applePay'], <String, Object?>{
      'merchantIdentifier': 'merchant.com.payriff',
    });
    // Anything but an object is no wallet part.
    final PayriffClientOrder odd = PayriffClientOrder.fromPayload(
      <String, Object?>{'googlePay': 'x', 'applePay': <Object?>[]},
      requestedOrderId: 'o9',
    );
    expect(odd.googlePay, isNull);
    expect(odd.applePay, isNull);
  });
}
