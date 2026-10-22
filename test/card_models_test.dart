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
  });
}
