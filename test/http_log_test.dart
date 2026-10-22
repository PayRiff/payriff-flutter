// CONTRACT §11: the JSON request and response log never shows a secret.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:payriff/src/internal/http_log.dart';

void main() {
  group('redactHeaders', () {
    test('redacts secrets and keeps the rest', () {
      final Map<String, String> shown = redactHeaders(<String, String>{
        'Authorization': '0123456789ABCDEF0123456789ABCDEF',
        'X-Client-Secret': 'pr_cs_v1_secret',
        'x-secret-key': 'WRAPPED+/=',
        'X-Public-Key': 'pr_pk_live_TestPublishableKey00000000000000000000',
        'X-Client-App-Id': 'com.payriff.example.flutter',
        'Content-Type': 'application/json',
      });
      expect(shown, <String, String>{
        'Authorization': '***(32)',
        'Content-Type': 'application/json',
        'X-Client-App-Id': 'com.payriff.example.flutter',
        'X-Client-Secret': '***(15)',
        'X-Public-Key': 'pr_pk_live_***(49)',
        'x-secret-key': '***(10)',
      });
    });
  });

  group('redactBody', () {
    test('redacts secret fields at any depth and masks card numbers', () {
      final Object? shown = redactBody(
        '{"code":"00000","payload":{"orderId":"o1","clientSecret":"pr_cs_x",'
        '"items":[{"encryptedMessage":"ENC"}],"pan":"4111111111111111",'
        '"maskedPan":"411111******1111","creq":"CREQ","amount":1.5}}',
      );
      expect(shown, <String, Object?>{
        'code': '00000',
        'payload': <String, Object?>{
          'orderId': 'o1',
          'clientSecret': '***(7)',
          'items': <Object?>[
            <String, Object?>{'encryptedMessage': '***(3)'},
          ],
          'pan': '****1111',
          'maskedPan': '411111******1111',
          'creq': '***(4)',
          'amount': 1.5,
        },
      });
    });

    test('hides the values of the bank form fields (clientRequest)', () {
      final String shown = jsonEncode(
        redactBody(
          '{"clientRequest":[{"key":"creq","value":"CREQ-VALUE-42"},'
          '{"key":"threeDSSessionData","value":null},'
          '{"key":"other","value":"X-VALUE"}]}',
        ),
      );
      expect(shown, isNot(contains('CREQ-VALUE-42')));
      expect(shown, isNot(contains('X-VALUE')));
      expect(shown, contains('{"key":"creq","value":"***(13)"}'));
      expect(shown, contains('{"key":"threeDSSessionData","value":null}'));
    });

    test('strips URL queries and fragments', () {
      expect(
        redactBody(
          '{"paymentUrl":"https://pay.payriff.com/r/o1?type=direct#x"}',
        ),
        <String, Object?>{'paymentUrl': 'https://pay.payriff.com/r/o1'},
      );
    });

    test('describes empty, non-JSON and very long bodies', () {
      expect(redactBody(null), isNull);
      expect(redactBody(''), isNull);
      expect(redactBody('<html>secret</html>'), '(19 bytes, not JSON)');
      expect(
        redactBody('"${'a' * maxLoggedBodyChars}"'),
        '(${maxLoggedBodyChars + 2} characters of JSON, too long to log)',
      );
    });
  });

  test('requests and responses are pretty-printed JSON objects', () {
    final Uri url = Uri.parse(
      'https://api.payriff.com/api/v3/client/orders/o1/pay?x=1',
    );
    final String request = describeRequest('POST', url, <String, String>{
      'Authorization': '0123456789ABCDEF0123456789ABCDEF',
    }, '{"amount":0.1}');
    expect(jsonDecode(request), <String, Object?>{
      'method': 'POST',
      'url': 'https://api.payriff.com/api/v3/client/orders/o1/pay',
      'headers': <String, Object?>{'Authorization': '***(32)'},
      'body': <String, Object?>{'amount': 0.1},
    });
    expect(request, contains('\n  "method": "POST"'));

    final String response = describeResponse(200, 'POST', url, <String, String>{
      'content-type': 'application/json',
    }, '{"payload":{"clientSecret":"pr_cs_abc"}}');
    expect(jsonDecode(response), <String, Object?>{
      'status': 200,
      'method': 'POST',
      'url': 'https://api.payriff.com/api/v3/client/orders/o1/pay',
      'headers': <String, Object?>{'content-type': 'application/json'},
      'body': <String, Object?>{
        'payload': <String, Object?>{'clientSecret': '***(9)'},
      },
    });
  });
}
