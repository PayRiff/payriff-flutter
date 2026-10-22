// Every case of the native card flow vectors (CONTRACT §16):
// card_validation, card_format, card_strings, card_crypto (the plaintext and
// the key pin; the AES/RSA cases run in the native plugin tests),
// card_next_action, card_3ds_navigation and card_api.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:payriff/payriff.dart';
import 'package:payriff/src/internal/card/card_crypto.dart';
import 'package:payriff/src/internal/card/card_flow.dart';
import 'package:payriff/src/internal/card/card_strings.dart';
import 'package:payriff/src/internal/card/client_api.dart';
import 'package:payriff/src/internal/card/format.dart';
import 'package:payriff/src/internal/card/next_action.dart';
import 'package:payriff/src/internal/card/three_ds_policy.dart';
import 'package:payriff/src/internal/card/validation.dart';
import 'package:payriff/src/internal/status_resolution.dart';
import 'package:webview_flutter/webview_flutter.dart' show NavigationDecision;

import 'support/card_support.dart';

Map<String, Object?> _load(String name) =>
    jsonDecode(File('test/vectors/$name').readAsStringSync())
        as Map<String, Object?>;

List<Map<String, Object?>> _list(Object? value) =>
    (value! as List<Object?>).cast<Map<String, Object?>>();

String? _code(PayriffCardFieldErrorCode? code) => code?.value;

String? _brand(PayriffCardBrand? brand) => brand?.value;

void main() {
  group('card_validation.json', () {
    final Map<String, Object?> v = _load('card_validation.json');

    test('brands, maxPanDigits and maxHolderLength', () {
      expect(<Object?>[
        for (final CardBrandRule r in cardBrandRules)
          <String, Object?>{
            'brand': r.brand.value,
            'ranges': <List<String>>[
              for (final (String lo, String hi) in r.ranges) <String>[lo, hi],
            ],
            'lengths': r.lengths,
          },
      ], v['brands']);
      expect(maxPanDigits, v['maxPanDigits']);
      expect(maxHolderLength, v['maxHolderLength']);
    });

    for (final Map<String, Object?> c in _list(v['number'])) {
      test('number ${jsonEncode(c['input'])}', () {
        final CardFieldValidation r = validateNumber(c['input']! as String);
        expect(r.valid, c['valid']);
        expect(r.empty, c['empty']);
        expect(_code(r.errorCode), c['errorCode']);
        expect(_brand(r.brand), c['brand']);
        expect(r.value, c['value']);
      });
    }

    for (final Map<String, Object?> c in _list(v['detectBrand'])) {
      test('detectBrand ${jsonEncode(c['digits'])}', () {
        final String digits = c['digits']! as String;
        expect(_brand(detectBrand(digits)), c['brand']);
        expect(maxPanLength(digits), c['maxLength']);
      });
    }

    final Map<String, Object?> expiry = v['expiry']! as Map<String, Object?>;
    final Map<String, Object?> now = expiry['now']! as Map<String, Object?>;
    final DateTime today = DateTime(
      now['year']! as int,
      now['month']! as int,
      15,
    );
    for (final Map<String, Object?> c in _list(expiry['cases'])) {
      test('expiry ${jsonEncode(c['input'])}', () {
        final ExpiryValidation r = validateExpiry(c['input']! as String, today);
        expect(r.valid, c['valid']);
        expect(r.empty, c['empty']);
        expect(_code(r.errorCode), c['errorCode']);
        final Map<String, Object?>? value = c['value'] as Map<String, Object?>?;
        expect(r.expiryMonth, value?['expiryMonth']);
        expect(r.expiryYear, value?['expiryYear']);
      });
    }

    for (final Map<String, Object?> c in _list(v['cvv'])) {
      test('cvv ${jsonEncode(c['input'])}', () {
        final CardFieldValidation r = validateCvv(c['input']! as String);
        expect(r.valid, c['valid']);
        expect(r.empty, c['empty']);
        expect(_code(r.errorCode), c['errorCode']);
        expect(r.value, c['value']);
      });
    }

    for (final Map<String, Object?> c in _list(v['holder'])) {
      test('holder ${jsonEncode(c['input'])}', () {
        final CardFieldValidation r = validateHolder(c['input']! as String);
        expect(r.valid, c['valid']);
        expect(r.empty, c['empty']);
        expect(_code(r.errorCode), c['errorCode']);
        expect(r.value, c['value']);
      });
    }

    for (final Map<String, Object?> c in _list(v['visibleError'])) {
      test('visibleError ${jsonEncode(c)}', () {
        final String? code = c['errorCode'] as String?;
        expect(
          _code(
            visibleError(
              code == null
                  ? null
                  : PayriffCardFieldErrorCode.values.byName(code),
              focused: c['focused']! as bool,
              touched: c['touched']! as bool,
              submitted: c['submitted']! as bool,
            ),
          ),
          c['expected'],
        );
      });
    }

    for (final Map<String, Object?> c in _list(v['luhn'])) {
      test('luhn ${jsonEncode(c['digits'])}', () {
        expect(luhn(c['digits']! as String), c['valid']);
      });
    }
  });

  group('card_format.json', () {
    final Map<String, Object?> v = _load('card_format.json');
    for (final Map<String, Object?> c in _list(v['number'])) {
      test('number ${jsonEncode(c['input'])}', () {
        expect(formatNumber(c['input']! as String), c['expected']);
      });
    }
    for (final Map<String, Object?> c in _list(v['expiry'])) {
      test('expiry ${jsonEncode(c['input'])} inserting ${c['inserting']}', () {
        expect(
          formatExpiry(
            c['input']! as String,
            inserting: c['inserting']! as bool,
          ),
          c['expected'],
        );
      });
    }
    for (final Map<String, Object?> c in _list(v['cvv'])) {
      test('cvv ${jsonEncode(c['input'])}', () {
        expect(formatCvv(c['input']! as String), c['expected']);
      });
    }
    for (final Map<String, Object?> c in _list(v['holder'])) {
      test('holder ${jsonEncode(c['input'])}', () {
        expect(formatHolder(c['input']! as String), c['expected']);
        // The form's formatter gives the same text.
        final TextEditingValue typed = const HolderInputFormatter()
            .formatEditUpdate(
              TextEditingValue.empty,
              TextEditingValue(text: c['input']! as String),
            );
        expect(typed.text, c['expected']);
      });
    }
  });

  group('card_strings.json', () {
    final Map<String, Object?> v = _load('card_strings.json');
    test('the embedded table equals the vector', () {
      expect(payriffCardStringTable, v['messages']);
    });
    test('every field error resolves, falling back to "invalid"', () {
      for (final PayriffLanguage language in PayriffLanguage.values) {
        final PayriffCardStrings strings = PayriffCardStrings(language);
        final Map<String, Object?> table =
            (v['messages']! as Map<String, Object?>)[language.value
                    .toLowerCase()]!
                as Map<String, Object?>;
        expect(
          strings.cardInformation,
          (table['group']! as Map<String, Object?>)['cardInformation'],
        );
        for (final PayriffCardField field in PayriffCardField.values) {
          final Map<String, Object?> messages =
              table[field.value]! as Map<String, Object?>;
          expect(
            strings.label(field),
            (table['label']! as Map<String, Object?>)[field.value],
          );
          expect(
            strings.placeholder(field),
            (table['placeholder']! as Map<String, Object?>)[field.value],
          );
          for (final PayriffCardFieldErrorCode code
              in PayriffCardFieldErrorCode.values) {
            expect(
              strings.error(field, code),
              messages[code.value] ?? messages['invalid'],
            );
          }
        }
      }
    });
  });

  group('card_crypto.json', () {
    final Map<String, Object?> v = _load('card_crypto.json');
    for (final Map<String, Object?> c in _list(v['aesGcm'])) {
      final Map<String, Object?> card = c['card']! as Map<String, Object?>;
      test('cardJson for ${card['pan']} is byte-exact', () {
        final Uint8List bytes = buildCardJsonBytes(
          CardPlaintext(
            pan: card['pan']! as String,
            cardHolder: card['cardHolder']! as String,
            expiryYear: card['expiryYear']! as String,
            expiryMonth: card['expiryMonth']! as String,
            cvv: card['cvv']! as String,
          ),
        );
        expect(bytes, utf8.encode(c['cardJson']! as String));
      });
    }

    test('the JSON builder escapes exactly like JSON.stringify', () {
      String json(String holder) => utf8.decode(
        buildCardJsonBytes(
          CardPlaintext(
            pan: '1',
            cardHolder: holder,
            expiryYear: '2030',
            expiryMonth: '01',
            cvv: '123',
          ),
        ),
      );
      expect(
        json('a\u0001\b\f\n\r\t"\\/é😀\uD800x'),
        '{"pan":"1","cardHolder":"a\\u0001\\b\\f\\n\\r\\t\\"\\\\/é😀\\ud800x",'
        '"expiryYear":"2030","expiryMonth":"01","cvv":"123"}',
      );
    });

    test('the pinned key is the vector key and its SHA-256 matches', () {
      expect(payriffPublicKeySpkiBase64, v['payriffPublicKeySpki']);
      expect(payriffPublicKeySha256, v['payriffPublicKeySha256']);
      expect(
        crypto.sha256.convert(payriffPublicKeyDer()).toString(),
        v['payriffPublicKeySha256'],
      );
    });

    test('CardPlaintext never prints the card', () {
      const CardPlaintext card = CardPlaintext(
        pan: '4111111111111111',
        cardHolder: 'TEST',
        expiryYear: '2030',
        expiryMonth: '12',
        cvv: '123',
      );
      expect(card.toString(), isNot(contains('4111')));
      expect(card.toString(), isNot(contains('123')));
    });
  });

  group('card_next_action.json', () {
    for (final Map<String, Object?> c in _list(
      _load('card_next_action.json')['cases'],
    )) {
      test(c['name']! as String, () {
        final Map<String, Object?> expected =
            c['expected']! as Map<String, Object?>;
        final NextAction action = classifyNextAction(c['payload']);
        final Map<String, Object?> actual = switch (action) {
          ChallengeAction(
            :final String url,
            :final List<(String, String)> form,
          ) =>
            <String, Object?>{
              'type': 'challenge',
              'url': url,
              'form': <List<String>>[
                for (final (String k, String v) in form) <String>[k, v],
              ],
            },
          MethodAction() => <String, Object?>{
            'type': 'method',
            'methodUrl': action.methodUrl,
            'methodData': action.methodData,
            'methodUrlServer': action.methodUrlServer,
          },
          WaitAction() => <String, Object?>{'type': 'wait'},
          RedirectAction(:final String url) => <String, Object?>{
            'type': 'redirect',
            'url': url,
          },
          CheckStatusAction() => <String, Object?>{'type': 'checkStatus'},
          InvalidAction() => <String, Object?>{'type': 'invalid'},
        };
        expect(actual, expected);
      });
    }

    test('the challenge form is form-urlencoded', () {
      expect(
        formUrlEncode(<(String, String)>[('creq', 'a b+/='), ('x', '')]),
        'creq=a+b%2B%2F%3D&x=',
      );
    });
  });

  group('card_3ds_navigation.json', () {
    for (final Map<String, Object?> c in _list(
      _load('card_3ds_navigation.json')['cases'],
    )) {
      test(c['name']! as String, () {
        final ThreeDsNavigationPolicy policy = ThreeDsNavigationPolicy(
          c['apiBase']! as String,
        );
        for (final Map<String, Object?> step in _list(c['steps'])) {
          expect(
            policy
                .decide(
                  step['url']! as String,
                  isMainFrame: step['isMainFrame']! as bool,
                )
                .name,
            step['expected'],
            reason: step['url']! as String,
          );
        }
      });
    }

    test('hidden Method WebViews never end the flow or open apps', () {
      final ThreeDsNavigationPolicy policy = ThreeDsNavigationPolicy(
        'https://api.payriff.com',
      );
      bool navigates(String url) =>
          decideHiddenNavigation(policy, url, isMainFrame: true) ==
          NavigationDecision.navigate;
      expect(navigates('https://acs.bank.example/m'), isTrue);
      expect(navigates('bank://open'), isFalse);
      expect(
        navigates('https://api.payriff.com/api/v3/gateway/atb/callback'),
        isTrue,
      );
      expect(navigates('https://merchant.example/'), isFalse);
    });
  });

  group('card_api.json', () {
    final Map<String, Object?> v = _load('card_api.json');

    for (final Map<String, Object?> c in _list(v['order'])) {
      test('order: ${c['name']}', () {
        final Map<String, Object?> expect0 =
            c['expect']! as Map<String, Object?>;
        final PayriffClientOrder order = PayriffClientOrder.fromPayload(
          parseClientResponse(c['httpStatus']! as int, c['body']! as String),
          requestedOrderId: 'o1',
        );
        expect(order.orderId, expect0['orderId']);
        expect(order.rawStatus, expect0['status']);
        expect(order.isPayableByCard, expect0['payable']);
        if (expect0.containsKey('amount')) {
          expect(order.amount, num.parse(expect0['amount']! as String));
          expect(order.currency, expect0['currency']);
          expect(order.paymentMethods, expect0['paymentMethods']);
        }
      });
    }

    for (final Map<String, Object?> c in _list(v['errors'])) {
      test('errors: ${c['name']}', () async {
        final Map<String, Object?> e = c['expect']! as Map<String, Object?>;
        final FakeCardClock clock = FakeCardClock();
        final List<http.Request> requests = <http.Request>[];
        debugPayriffClientApiHttpClient = () =>
            MockClient((http.Request request) async {
              requests.add(request);
              return http.Response.bytes(
                utf8.encode(c['body']! as String),
                c['httpStatus']! as int,
              );
            });
        addTearDown(() => debugPayriffClientApiHttpClient = null);
        final ClientApi api = testClientApi(clock);
        final PayriffError error = await api
            .pay('o1', testPayRequest())
            .then<PayriffError>(
              (_) => fail('expected an error'),
              onError: (Object e) => (e as PayriffException).error,
            );
        expect(error.code.value, e['code']);
        expect(error.isFatal, e['fatal']);
        expect(error.httpStatus, c['httpStatus']);
        if (e.containsKey('payriffCode')) {
          expect(error.payriffCode, e['payriffCode']);
        }
        if (e.containsKey('message')) expect(error.message, e['message']);
        if (e['retry'] == true) {
          // 429: three retries with backoff, same bytes, same key.
          expect(requests, hasLength(4));
          expect(clock.sleeps, rateLimitBackoff);
          expect(
            requests
                .map((http.Request r) => r.headers['X-Idempotency-Key'])
                .toSet(),
            hasLength(1),
          );
          expect(
            requests.map((http.Request r) => r.body).toSet(),
            hasLength(1),
          );
        } else {
          expect(requests, hasLength(1));
          expect(clock.sleeps, isEmpty);
        }
        expect(error.isRetryable, error.code == PayriffErrorCode.paymentFailed);
      });
    }

    for (final Map<String, Object?> c in _list(v['status'])) {
      test('status: ${c['name']}', () {
        final Map<String, Object?> e = c['expect']! as Map<String, Object?>;
        final StatusReading reading = cardStatusReading(
          parseClientResponse(c['httpStatus']! as int, c['body']! as String),
        );
        expect(reading.rawStatus, e['status']);
        expect(cardFinalStatuses.contains(reading.status), e['final']);
        expect(cardResultFor('o1', reading)?.type, e['result']);
      });
    }

    for (final Map<String, Object?> c in _list(v['requests'])) {
      test('requests: ${c['name']}', () async {
        final List<http.Request> requests = <http.Request>[];
        debugPayriffClientApiHttpClient = () =>
            MockClient((http.Request request) async {
              requests.add(request);
              return http.Response('{"code":"00000","payload":{}}', 200);
            });
        addTearDown(() => debugPayriffClientApiHttpClient = null);
        final ClientApi api = testClientApi(FakeCardClock());
        final String orderId = (c['orderId'] as String?) ?? 'o1';
        final String path = c['path']! as String;
        if (c['method'] == 'POST') {
          await api.pay(orderId, testPayRequest());
        } else if (path.endsWith('/three-ds')) {
          await api.threeDs(orderId);
        } else if (path.endsWith('/status')) {
          await api.status(orderId);
        } else {
          await api.retrieveOrder(orderId);
        }
        final http.Request request = requests.single;
        expect(request.method, c['method']);
        expect(request.url.path, path);
        expect(request.url.host, 'sb-api.payriff.com');
        expect(request.followRedirects, isFalse);
        final Map<String, Object?> headers =
            (c['headers'] as Map<String, Object?>?) ?? <String, Object?>{};
        headers.forEach((String name, Object? value) {
          expect(request.headers[name], value, reason: name);
        });
        for (final Object? name
            in (c['requiredHeaders'] as List<Object?>?) ?? <Object?>[]) {
          expect(request.headers[name! as String], isNotEmpty, reason: '$name');
        }
        for (final Object? name
            in (c['absentHeaders'] as List<Object?>?) ?? <Object?>[]) {
          expect(request.headers.containsKey(name), isFalse, reason: '$name');
        }
        final Object? body = c['body'];
        if (body is Map<String, Object?>) {
          final Object? sent = jsonDecode(request.body);
          expect((sent! as Map<String, Object?>).keys, body.keys);
          expect(request.body, '{"method":"CARD","encryptedMessage":"ENC+/="}');
        }
      });
    }

    for (final Map<String, Object?> c in _list(v['keys'])) {
      test('keys: ${c['name']}', () {
        expect(usablePublishableKey(c['value']! as String) != null, c['valid']);
      });
    }

    for (final Map<String, Object?> c in _list(v['clientSecrets'])) {
      test('clientSecrets: ${c['name']}', () {
        final String? usable = usableClientSecret(c['value']! as String);
        expect(usable != null, c['valid']);
        if (c.containsKey('sent')) expect(usable, c['sent']);
      });
    }

    test(
      '/pay without a response is retried once, after 1 s, unchanged',
      () async {
        final FakeCardClock clock = FakeCardClock();
        final List<http.Request> requests = <http.Request>[];
        debugPayriffClientApiHttpClient = () =>
            MockClient((http.Request request) async {
              requests.add(request);
              if (requests.length == 1) throw http.ClientException('offline');
              return http.Response('{"code":"00000","payload":{"a":1}}', 200);
            });
        addTearDown(() => debugPayriffClientApiHttpClient = null);
        final Map<String, Object?> payload = await testClientApi(
          clock,
        ).pay('o1', testPayRequest());
        expect(payload, <String, Object?>{'a': 1});
        expect(requests, hasLength(2));
        expect(clock.sleeps, <Duration>[payNetworkRetryDelay]);
        expect(requests[0].body, requests[1].body);
        expect(
          requests[0].headers['X-Idempotency-Key'],
          requests[1].headers['X-Idempotency-Key'],
        );
        expect(requests[0].headers['x-secret-key'], 'WRAPPED+/=');
      },
    );

    test(
      'a GET without a response is not retried; the error hides details',
      () async {
        final List<http.Request> requests = <http.Request>[];
        debugPayriffClientApiHttpClient = () =>
            MockClient((http.Request request) async {
              requests.add(request);
              throw http.ClientException('X-Client-Secret: pr_cs_TEST');
            });
        addTearDown(() => debugPayriffClientApiHttpClient = null);
        final Object error = await testClientApi(
          FakeCardClock(),
        ).status('o1').then<Object>((_) => 'ok', onError: (Object e) => e);
        expect(requests, hasLength(1));
        expect(
          (error as PayriffException).error.code,
          PayriffErrorCode.networkError,
        );
        expect(error.toString(), isNot(contains('pr_cs_')));
      },
    );

    test('the order id "." or ".." is refused before any request', () {
      for (final String id in <String>['.', '..', '  ']) {
        expect(
          () => clientOrderPath(id),
          throwsA(
            isA<PayriffException>().having(
              (PayriffException e) => e.error.code,
              'code',
              PayriffErrorCode.invalidOrder,
            ),
          ),
        );
      }
    });

    test('API hosts per environment (the sandbox host is provisional)', () {
      expect(
        clientApiBaseUrl(PayriffEnvironment.production),
        'https://api.payriff.com',
      );
      expect(
        clientApiBaseUrl(PayriffEnvironment.sandbox),
        'https://sb-api.payriff.com',
      );
    });

    test('idempotency keys are random version-4 UUIDs', () {
      final Set<String> keys = <String>{
        for (int i = 0; i < 50; i++) newIdempotencyKey(),
      };
      expect(keys, hasLength(50));
      for (final String key in keys) {
        expect(
          key,
          matches(
            RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            ),
          ),
        );
      }
    });
  });
}
