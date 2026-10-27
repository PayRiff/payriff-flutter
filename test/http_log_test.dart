// CONTRACT §11: the JSON request and response log never shows a secret,
// and every URL in it, and in the general log lines of an API call, is
// redacted by the one rule of redactUrl.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:payriff/payriff.dart';
import 'package:payriff/src/internal/card/card_clock.dart';
import 'package:payriff/src/internal/card/client_api.dart';
import 'package:payriff/src/internal/http_log.dart';
import 'package:payriff/src/internal/logger.dart';

/// A real-length order id: 36 characters, logged as `7c9e…0ae7`.
const String _longOrderId = '7c9e6679-7425-40de-944b-e07fc1f90ae7';

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

    test('redacts URLs: Location and any header whose value is a URL', () {
      expect(
        redactHeaders(<String, String>{
          'location': 'https://user:pw@acs.bank.example/T0K3N?x=1',
          'content-location': '/api/v3/client/orders/o1?token=abc',
          'link': 'https://bank.example/next?token=abc',
          'x-callback': 'birbank://confirm?id=1',
          'content-type': 'application/json; charset=utf-8',
          'date': 'Fri, 23 Oct 2026 10:00:00 GMT',
        }),
        <String, String>{
          'content-location': '…',
          'content-type': 'application/json; charset=utf-8',
          'date': 'Fri, 23 Oct 2026 10:00:00 GMT',
          'link': 'https://bank.example',
          'location': 'https://acs.bank.example',
          'x-callback': 'birbank:…',
        },
      );
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

    test('redacts URLs at any depth with the rule of redactUrl', () {
      expect(
        redactBody(
          jsonEncode(<String, Object?>{
            'paymentUrl': 'https://pay.payriff.com/r/o1?type=direct#x',
            'payload': <String, Object?>{
              'nextAction': <String, Object?>{
                'accessUrl': 'https://acs.bank.example/T0K3N/challenge?s=1',
                'urls': <Object?>[
                  'https://user:pw@3ds.bank.example:8443/method',
                  'HTTPS://SB-API.PAYRIFF.COM/api/v3/client/orders/'
                      '$_longOrderId/three-ds?x=1',
                ],
              },
              'callback':
                  'https://api.payriff.com/api/v3/gateway/kapital/'
                  'callback/$_longOrderId',
            },
          }),
        ),
        <String, Object?>{
          'paymentUrl': 'https://pay.payriff.com',
          'payload': <String, Object?>{
            'nextAction': <String, Object?>{
              'accessUrl': 'https://acs.bank.example',
              'urls': <Object?>[
                'https://3ds.bank.example:8443',
                'https://sb-api.payriff.com/api/v3/client/orders/7c9e…0ae7/'
                    'three-ds',
              ],
            },
            'callback':
                'https://api.payriff.com/api/v3/gateway/kapital/callback/'
                '7c9e…0ae7',
          },
        },
      );
    });

    test('URLs of other schemes show only the scheme; other text stays', () {
      expect(
        redactBody(
          jsonEncode(<String, Object?>{
            'redirect': 'birbank://confirm?id=1&token=abc',
            'support': 'tel:+994121234567',
            'mail': ' mailto:support@payriff.com ',
            'page': 'about:blank',
            'description': 'Order #42',
            'message': 'Note: the order is pending',
            'createdAt': '2026-10-23T10:00:00Z',
            'status': 'PENDING',
            'amount': 10.5,
          }),
        ),
        <String, Object?>{
          'redirect': 'birbank:…',
          'support': 'tel:…',
          'mail': 'mailto:…',
          'page': 'about:…',
          'description': 'Order #42',
          'message': 'Note: the order is pending',
          'createdAt': '2026-10-23T10:00:00Z',
          'status': 'PENDING',
          'amount': 10.5,
        },
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

  test('the url of a request and a response is redacted', () {
    final Uri url = Uri.parse(
      'https://user:pw@api.payriff.com/api/v3/client/orders/$_longOrderId'
      '/pay?token=abc#f',
    );
    const String shown =
        'https://api.payriff.com/api/v3/client/orders/7c9e…0ae7/pay';
    expect(
      (jsonDecode(describeRequest('POST', url, <String, String>{}, null))
          as Map<String, Object?>)['url'],
      shown,
    );
    expect(
      (jsonDecode(describeResponse(200, 'POST', url, <String, String>{}, ''))
          as Map<String, Object?>)['url'],
      shown,
    );
  });

  test('the general log lines of an API call shorten the order id like '
      'the HTTP details', () async {
    final List<String> lines = <String>[];
    debugPayriffClientApiHttpClient = () => MockClient(
      (http.Request request) async =>
          http.Response('{"code":"00000","payload":{}}', 200),
    );
    addTearDown(() => debugPayriffClientApiHttpClient = null);
    final ClientApi api = ClientApi(
      baseUrl: const PayriffConfig().apiBaseUrl,
      publishableKey: 'pr_pk_live_TEST',
      clientSecret: 'pr_cs_TEST',
      appId: null,
      clock: const SystemCardClock(),
      logger: SdkLogger(
        enabled: true,
        sink: (PayriffLogEntry entry) => lines.add(entry.message),
      ),
    );
    addTearDown(api.close);
    await api.status(_longOrderId);
    const String url =
        'https://api.payriff.com/api/v3/client/orders/7c9e…0ae7/status';
    expect(lines, contains('GET $url'));
    expect(lines, contains('GET $url -> HTTP 200'));
    expect(
      lines.where((String line) => line.contains('"url": "$url"')),
      hasLength(2),
      reason: 'the HTTP request and response details',
    );
    for (final String line in lines) {
      expect(line, isNot(contains(_longOrderId)), reason: line);
    }
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
