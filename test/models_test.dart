import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:payriff/payriff.dart';
import 'package:payriff/src/internal/card/client_api.dart';
import 'package:payriff/src/internal/logger.dart';
import 'package:payriff/src/internal/request.dart';
import 'package:payriff/src/internal/url_policy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(Payriff.debugReset);
  tearDown(Payriff.debugReset);

  group('results serialize to the shared JSON shape', () {
    const PayriffPayment payment = PayriffPayment(
      orderId: 'o1',
      status: PayriffPaymentStatus.approved,
      rawStatus: 'APPROVED',
      amount: 10.5,
      currency: 'AZN',
      transactionId: '884213',
    );

    test('success', () {
      expect(
        const PayriffResultSuccess(payment: payment).toJson(),
        <String, Object?>{
          'type': 'success',
          'payment': <String, Object?>{
            'orderId': 'o1',
            'status': 'APPROVED',
            'rawStatus': 'APPROVED',
            'amount': 10.5,
            'currency': 'AZN',
            'transactionId': '884213',
            // CONTRACT §16.9: always present.
            'originalOrderId': null,
          },
        },
      );
      expect(const PayriffResultSuccess(payment: payment).isSuccess, isTrue);
    });

    test('originalOrderId is serialized and compared (CONTRACT §16.9)', () {
      const PayriffPayment switched = PayriffPayment(
        orderId: 'retry-2',
        status: PayriffPaymentStatus.approved,
        originalOrderId: 'o1',
      );
      final Map<String, Object?> json =
          jsonDecode(jsonEncode(const PayriffResultSuccess(payment: switched)))
              as Map<String, Object?>;
      expect(
        (json['payment']! as Map<String, Object?>)['originalOrderId'],
        'o1',
      );
      expect(
        switched,
        isNot(
          const PayriffPayment(
            orderId: 'retry-2',
            status: PayriffPaymentStatus.approved,
          ),
        ),
      );
      expect(
        switched.hashCode,
        const PayriffPayment(
          orderId: 'retry-2',
          status: PayriffPaymentStatus.approved,
          originalOrderId: 'o1',
        ).hashCode,
      );
      expect(switched.toString(), contains('originalOrderId: o1'));
    });

    test('declined, cancelled, pending and failed', () {
      expect(
        const PayriffResultDeclined(payment: payment).toJson()['type'],
        'declined',
      );
      expect(
        const PayriffResultCancelled(
          reason: PayriffCancelReason.userClosed,
        ).toJson(),
        <String, Object?>{
          'type': 'cancelled',
          'reason': 'userClosed',
          'payment': null,
        },
      );
      expect(
        const PayriffResultPending(
          payment: payment,
          reason: PayriffPendingReason.verificationFailed,
        ).toJson()['reason'],
        'verificationFailed',
      );
      final Map<String, Object?> failed = const PayriffResultFailed(
        error: PayriffError(
          code: PayriffErrorCode.paymentFailed,
          message: 'Insufficient funds',
          isRetryable: true,
          httpStatus: 402,
          payriffCode: '01000',
          supportTicket: '123456',
        ),
      ).toJson();
      expect(failed, <String, Object?>{
        'type': 'failed',
        'error': <String, Object?>{
          'code': 'PAYMENT_FAILED',
          'message': 'Insufficient funds',
          'isRetryable': true,
          'httpStatus': 402,
          'payriffCode': '01000',
          'supportTicket': '123456',
        },
      });
      // The whole result encodes as JSON.
      expect(() => jsonEncode(failed), returnsNormally);
      expect(const PayriffResultDeclined(payment: payment).isSuccess, isFalse);
    });

    test('base-class helpers: payment, error, isSuccess', () {
      const PayriffError error = PayriffError(
        code: PayriffErrorCode.networkError,
        message: 'offline',
        isRetryable: true,
      );
      final List<PayriffResult> results = <PayriffResult>[
        const PayriffResultSuccess(payment: payment),
        const PayriffResultDeclined(payment: payment),
        const PayriffResultCancelled(
          reason: PayriffCancelReason.canceled,
          payment: payment,
        ),
        const PayriffResultCancelled(reason: PayriffCancelReason.userClosed),
        const PayriffResultPending(
          payment: payment,
          reason: PayriffPendingReason.notFinal,
        ),
        const PayriffResultFailed(error: error),
      ];
      expect(results.map((PayriffResult r) => r.isSuccess), <bool>[
        true,
        false,
        false,
        false,
        false,
        false,
      ]);
      expect(results.map((PayriffResult r) => r.payment), <PayriffPayment?>[
        payment,
        payment,
        payment,
        null,
        payment,
        null,
      ]);
      expect(results.map((PayriffResult r) => r.error), <PayriffError?>[
        null,
        null,
        null,
        null,
        null,
        error,
      ]);
    });

    test('value equality', () {
      expect(
        const PayriffResultSuccess(payment: payment),
        const PayriffResultSuccess(payment: payment),
      );
      expect(
        const PayriffResultSuccess(payment: payment),
        isNot(const PayriffResultDeclined(payment: payment)),
      );
    });
  });

  group('models', () {
    test('PayriffConfig has only the card-flow settings and hides the '
        'publishable key (CONTRACT §11)', () {
      const PayriffConfig config = PayriffConfig(
        publishableKey: ' pr_pk_live_SECRETISH ',
        environment: PayriffEnvironment.sandbox,
        language: PayriffLanguage.az,
        enableLogging: true,
        allowCompromisedDevices: true,
      );
      expect(
        config.toString(),
        'PayriffConfig(environment: sandbox, language: AZ, '
        'enableLogging: true, allowCompromisedDevices: true, '
        'publishableKey: ***(20))',
      );
      expect(config.toString(), isNot(contains('SECRETISH')));
      const PayriffConfig defaults = PayriffConfig();
      expect(defaults.environment, PayriffEnvironment.production);
      expect(defaults.language, isNull);
      expect(defaults.enableLogging, isFalse);
      // CONTRACT §16.16: compromised devices are refused by default.
      expect(defaults.allowCompromisedDevices, isFalse);
      expect(defaults.toString(), contains('allowCompromisedDevices: false'));
      expect(defaults.toString(), contains('publishableKey: null'));
      expect(
        const PayriffConfig(publishableKey: '   ').toString(),
        contains('publishableKey: null'),
      );
    });

    test('PayriffLogEntry.formatted is the console line', () {
      final PayriffLogEntry entry = PayriffLogEntry(
        level: PayriffLogLevel.warning,
        message: 'Something happened',
        timestamp: DateTime.utc(2026, 10, 6),
      );
      expect(entry.formatted, '[Payriff] [WARNING] Something happened');
      expect(entry.toString(), entry.formatted);
      for (final PayriffLogLevel level in PayriffLogLevel.values) {
        expect(
          PayriffLogEntry(
            level: level,
            message: 'm',
            timestamp: DateTime.utc(2026),
          ).formatted,
          '[Payriff] [${level.name.toUpperCase()}] m',
        );
      }
    });

    test('PayriffError.toString', () {
      expect(
        const PayriffError(
          code: PayriffErrorCode.unauthorized,
          message: 'Unauthorized',
          httpStatus: 401,
          payriffCode: '14013',
        ).toString(),
        'PayriffError(UNAUTHORIZED, HTTP 401, payriffCode 14013): Unauthorized',
      );
      expect(
        const PayriffException(
          PayriffError(code: PayriffErrorCode.unknown, message: 'x'),
        ).toString(),
        'PayriffException: PayriffError(UNKNOWN): x',
      );
    });

    test('every error code has its canonical UPPER_SNAKE value', () {
      expect(
        PayriffErrorCode.values.map((PayriffErrorCode c) => c.value),
        <String>[
          'NOT_CONFIGURED',
          'INVALID_CONFIG',
          'INVALID_ORDER',
          'PAYMENT_IN_PROGRESS',
          'PRESENTATION_FAILED',
          'UNAUTHORIZED',
          'RATE_LIMITED',
          // CONTRACT §16.9: the native card flow.
          'VALIDATION_FAILED',
          'SESSION_EXPIRED',
          'ORDER_NOT_PAYABLE',
          'INVALID_REQUEST',
          'PAYMENT_FAILED',
          'UNEXPECTED_RESPONSE',
          'DEVICE_COMPROMISED',
          // The shared result shape (result_json.json).
          'API_ERROR',
          'NETWORK_ERROR',
          'UNKNOWN',
        ],
      );
    });

    test('Payriff.version matches pubspec.yaml', () {
      final RegExpMatch? match = RegExp(
        r'^version:\s*(\S+)',
        multiLine: true,
      ).firstMatch(File('pubspec.yaml').readAsStringSync());
      expect(Payriff.version, match!.group(1));
    });

    test('the card flow uses the contract hosts (CONTRACT §16.2)', () {
      expect(
        clientApiBaseUrl(PayriffEnvironment.production),
        'https://api.payriff.com',
      );
      expect(
        clientApiBaseUrl(PayriffEnvironment.sandbox),
        'https://sb-api.payriff.com',
      );
    });

    test('the status parser is PayriffPaymentStatus.parse', () {
      expect(
        PayriffPaymentStatus.parse(' paid '),
        PayriffPaymentStatus.approved,
      );
      expect(PayriffPaymentStatus.parse(null), PayriffPaymentStatus.unknown);
    });
  });

  group('order ids', () {
    test('are trimmed and encoded as one path segment (CONTRACT §16.3)', () {
      expect(encodePathSegment('a.b/c d~_-'), 'a%2Eb%2Fc%20d~_-');
      expect(encodePathSegment('ə'), '%C9%99');
      expect(clientOrderPath(' x '), '/api/v3/client/orders/x');
      expect(
        clientOrderPath(' a/b ', '/status'),
        '/api/v3/client/orders/a%2Fb/status',
      );
      for (final String id in <String>['', '  ', '.', ' .. ']) {
        expect(
          () => clientOrderPath(id),
          throwsA(
            isA<PayriffException>().having(
              (PayriffException e) => e.error.code,
              'code',
              PayriffErrorCode.invalidOrder,
            ),
          ),
          reason: id,
        );
      }
    });
  });

  group('URL helpers', () {
    test('redactUrl: other hosts keep only scheme, host and port; other '
        'schemes become <scheme>:… (CONTRACT §11)', () {
      expect(
        redactUrl('https://merchant.example/cb?token=abc#x'),
        'https://merchant.example',
      );
      expect(redactUrl('https://a.example/p#frag'), 'https://a.example');
      expect(
        redactUrl('https://acs.bank.example/challenge/T0K3N-in-the-path'),
        'https://acs.bank.example',
      );
      expect(redactUrl('http://insecure.example/'), 'http://insecure.example');
      expect(redactUrl('https://bank.example'), 'https://bank.example');
      // Payriff's other hosts are not API hosts.
      expect(
        redactUrl('https://pay.payriff.com/r/o1?type=direct'),
        'https://pay.payriff.com',
      );
      expect(
        redactUrl('https://api.payriff.com.evil.example/api/v3/x'),
        'https://api.payriff.com.evil.example',
      );
      expect(redactUrl('tel:+994121234567'), 'tel:…');
      expect(redactUrl('mailto:support@payriff.com'), 'mailto:…');
      expect(redactUrl('data:text/html;base64,PGh0bWw+'), 'data:…');
      expect(redactUrl('javascript:alert(document.cookie)'), 'javascript:…');
      expect(redactUrl('intent://pay#Intent;scheme=x;end'), 'intent:…');
      expect(redactUrl('birbank://payment?id=1'), 'birbank:…');
      expect(redactUrl('about:blank'), 'about:…');
      expect(redactSecret('abcd'), '***(4)');
      expect(redactSecret(null), 'none');
    });

    test('redactUrl: Payriff API hosts keep the path, with segments of 16 '
        'or more characters shortened to their first and last 4', () {
      expect(
        redactUrl(
          'https://api.payriff.com/api/v3/client/orders/'
          '7c9e6679-7425-40de-944b-e07fc1f90ae7/pay?x=1#f',
        ),
        'https://api.payriff.com/api/v3/client/orders/7c9e…0ae7/pay',
      );
      expect(
        redactUrl('https://sb-api.payriff.com/api/v3/client/orders/o1/status'),
        'https://sb-api.payriff.com/api/v3/client/orders/o1/status',
      );
      // 15 characters stay, 16 are shortened.
      expect(
        redactUrl('https://api.payriff.com/a/123456789012345'),
        'https://api.payriff.com/a/123456789012345',
      );
      expect(
        redactUrl('https://api.payriff.com/a/1234567890123456'),
        'https://api.payriff.com/a/1234…3456',
      );
      expect(
        redactUrl('https://api.payriff.com/api/v3/gateway/kapital/callback/1'),
        'https://api.payriff.com/api/v3/gateway/kapital/callback/1',
      );
      expect(redactUrl('https://api.payriff.com'), 'https://api.payriff.com');
      expect(redactUrl('https://api.payriff.com/'), 'https://api.payriff.com/');
      expect(
        redactUrl('https://api.payriff.com?token=abc'),
        'https://api.payriff.com',
      );
      // Code points, not UTF-16 units: no character is cut in half.
      expect(
        redactUrl('https://api.payriff.com/😀😀abcdefghijklmn😀😀'),
        'https://api.payriff.com/😀😀ab…mn😀😀',
      );
    });

    test('redactUrl drops the user info, also on Payriff hosts', () {
      expect(
        redactUrl('https://user:pa55word@bank.example/acs?x=1'),
        'https://bank.example',
      );
      expect(
        redactUrl('https://user:pa55@word@api.payriff.com/api/v3/x'),
        'https://api.payriff.com/api/v3/x',
      );
      expect(
        redactUrl('https://token@bank.example:8443/p'),
        'https://bank.example:8443',
      );
      // The user info ends with the authority: an `@` in the path or query
      // is not one.
      expect(
        redactUrl('https://bank.example/a@b?c=@d'),
        'https://bank.example',
      );
      expect(
        redactUrl('https://api.payriff.com/x/@y?u=a@b'),
        'https://api.payriff.com/x/@y',
      );
      // An authority that is no host and port (a password with a `/`) is
      // not logged at all.
      expect(redactUrl('https://user:pa/ss@bank.example/x'), 'https://…');
    });

    test('redactUrl keeps the port and handles IP literals', () {
      expect(
        redactUrl('https://fp.bank-cdn.example:8443/frame?t=1'),
        'https://fp.bank-cdn.example:8443',
      );
      expect(
        redactUrl('https://api.payriff.com:443/api/v3/client/orders/o1'),
        'https://api.payriff.com:443/api/v3/client/orders/o1',
      );
      expect(
        redactUrl('http://[::1]:8080/secret/path?x=1'),
        'http://[::1]:8080',
      );
      expect(redactUrl('http://10.0.2.2:3000/a/b'), 'http://10.0.2.2:3000');
    });

    test('redactUrl reads upper-case schemes and hosts, and logs them in '
        'lower case', () {
      expect(redactUrl('HTTP://A.Example/p?x=1'), 'http://a.example');
      expect(
        redactUrl('HTTPS://API.PAYRIFF.COM/api/v3/client/orders/o1/pay'),
        'https://api.payriff.com/api/v3/client/orders/o1/pay',
      );
      expect(
        redactUrl('https://Sb-Api.Payriff.Com/api/v3/client/orders/o1'),
        'https://sb-api.payriff.com/api/v3/client/orders/o1',
      );
      expect(redactUrl('TEL:+994121234567'), 'TEL:…');
    });

    test('redactUrl reads a URL as a browser does: backslashes, extra '
        'slashes and white space around it', () {
      // `\` is a `/` in http(s) URLs, so the host here is evil.example.
      expect(
        redactUrl(r'https://evil.example\@api.payriff.com/api/v3/x'),
        'https://evil.example',
      );
      expect(
        redactUrl(r'https:\\bank.example\acs?x=1'),
        'https://bank.example',
      );
      expect(redactUrl('https:///bank.example/acs'), 'https://bank.example');
      expect(
        redactUrl('  https://bank.example/acs?x=1\n'),
        'https://bank.example',
      );
    });

    test('redactUrl: relative references have no known host', () {
      expect(redactUrl('/relative?x=1'), '…');
      expect(redactUrl('acs/challenge'), '…');
      expect(redactUrl(''), '…');
      expect(redactUrl('//bank.example/acs?x=1'), '//bank.example');
      expect(
        redactUrl('//api.payriff.com/api/v3/client/orders/o1'),
        '//api.payriff.com/api/v3/client/orders/o1',
      );
    });

    test('redactError redacts URLs quoted in error text', () {
      // Android's error when no app handles the URL.
      expect(
        redactError(
          Exception(
            'No Activity found to handle intent '
            '{ birbank://payment?id=1&token=T0K3N }',
          ),
        ),
        'Exception: No Activity found to handle intent { birbank:… }',
      );
      expect(
        redactUrlsInText(
          'GET https://backend.example/status?sig=abc#f failed, '
          'uri=intent://pay?id=1#Intent;scheme=x;end',
        ),
        'GET https://backend.example failed, uri=intent:…',
      );
      expect(
        redactUrlsInText(
          'Could not load https://user:pw@acs.bank.example/T0K3N/challenge '
          'from https://api.payriff.com/api/v3/client/orders/'
          '7c9e6679-7425-40de-944b-e07fc1f90ae7/three-ds',
        ),
        'Could not load https://acs.bank.example from '
        'https://api.payriff.com/api/v3/client/orders/7c9e…0ae7/three-ds',
      );
      expect(
        redactUrlsInText('Cannot open dat=tel:+994121234567 or mailto:a@b.c'),
        'Cannot open dat=tel:… or mailto:…',
      );
      // Text without URL queries is unchanged.
      const String plain =
          "SocketException: Failed host lookup: 'sb-api.payriff.com' "
          '(OS Error: nodename nor servname provided, errno = 8). Why?';
      expect(redactUrlsInText(plain), plain);
    });

    test(
      'only app schemes may leave the app (CONTRACT §7.5, §16.0 item 5)',
      () {
        for (final String url in <String>[
          'birbank://confirm?id=1',
          'intent://pay#Intent;scheme=abbpay;package=az.abb.mobile;end',
          'tel:+994121234567',
          'https://bank.example/app-link',
        ]) {
          expect(mayOpenExternally(url), isTrue, reason: url);
        }
        for (final String url in <String>[
          'file:///etc/hosts',
          'content://contacts/people/1',
          'javascript:alert(1)',
          'data:text/html,hi',
          'blob:https://bank.example/1',
          'about:blank',
          'no scheme',
        ]) {
          expect(mayOpenExternally(url), isFalse, reason: url);
        }
        expect(isBlankPageUrl(' ABOUT:BLANK#x '), isTrue);
        expect(isBlankPageUrl('about:srcdoc'), isFalse);
        expect(isAbsoluteHttpsUrl('https://acs.bank.example/c'), isTrue);
        expect(isAbsoluteHttpsUrl('http://acs.bank.example/c'), isFalse);
        expect(isAbsoluteHttpUrl('http://acs.bank.example/c'), isTrue);
        expect(isAbsoluteHttpUrl('/relative'), isFalse);
      },
    );
  });

  group('logging (CONTRACT §11)', () {
    MockClient okClient() => MockClient(
      (http.Request request) async => http.Response(
        jsonEncode(<String, Object?>{
          'code': '00000',
          'payload': <String, Object?>{
            'orderId': 'o1',
            'amount': 1,
            'currency': 'AZN',
            'status': 'CREATED',
            'paymentMethods': <String>['CARD'],
          },
        }),
        200,
      ),
    );

    test('entries reach logStream and never contain the keys', () async {
      final List<PayriffLogEntry> entries = <PayriffLogEntry>[];
      final StreamSubscription<PayriffLogEntry> subscription = Payriff.logStream
          .listen(entries.add);
      addTearDown(subscription.cancel);
      debugPayriffClientApiHttpClient = okClient;
      addTearDown(() => debugPayriffClientApiHttpClient = null);
      const String key = 'pr_pk_live_VERYSECRETPUBLISHABLE';
      const String secret = 'pr_cs_VERYSECRETCLIENT';
      Payriff.configure(
        const PayriffConfig(
          publishableKey: key,
          environment: PayriffEnvironment.sandbox,
          enableLogging: true,
        ),
      );
      final PayriffClientOrder order = await Payriff.retrieveOrder(
        orderId: 'o1',
        clientSecret: secret,
      );
      expect(order.isPayableByCard, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(entries, isNotEmpty);
      for (final PayriffLogEntry entry in entries) {
        expect(entry.message, isNot(contains('VERYSECRET')));
        expect(
          entry.toString(),
          startsWith('[Payriff] [${entry.level.name.toUpperCase()}] '),
        );
      }
      expect(
        entries.any(
          (PayriffLogEntry e) =>
              e.message ==
              'Configured: environment sandbox, publishable key '
                  '***(${key.length})',
        ),
        isTrue,
      );
    });

    test('nothing is logged when logging is off', () async {
      final List<PayriffLogEntry> entries = <PayriffLogEntry>[];
      final StreamSubscription<PayriffLogEntry> subscription = Payriff.logStream
          .listen(entries.add);
      addTearDown(subscription.cancel);
      Payriff.configure(
        const PayriffConfig(
          publishableKey: 'not-a-publishable-key',
          environment: PayriffEnvironment.sandbox,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(entries, isEmpty);
    });

    test(
      'a key that is not a publishable key is logged as an invalid '
      'configuration, never echoed, and refused (CONTRACT §3.0, §16.2)',
      () async {
        final List<PayriffLogEntry> entries = <PayriffLogEntry>[];
        final StreamSubscription<PayriffLogEntry> subscription = Payriff
            .logStream
            .listen(entries.add);
        addTearDown(subscription.cancel);
        Payriff.configure(
          const PayriffConfig(
            // The 32-hex shape of a merchant secret key.
            publishableKey: '0123456789ABCDEF0123456789ABCDEF',
            environment: PayriffEnvironment.sandbox,
            enableLogging: true,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        final PayriffLogEntry warning = entries.singleWhere(
          (PayriffLogEntry e) => e.level == PayriffLogLevel.warning,
        );
        expect(warning.message, startsWith('Invalid configuration: '));
        for (final PayriffLogEntry entry in entries) {
          expect(entry.message, isNot(contains('01234567')));
        }
        await expectLater(
          Payriff.retrieveOrder(orderId: 'o1', clientSecret: 'pr_cs_x'),
          throwsA(
            isA<PayriffException>().having(
              (PayriffException e) => e.error.code,
              'code',
              PayriffErrorCode.invalidConfig,
            ),
          ),
        );
      },
    );

    test('every call needs configure first: NOT_CONFIGURED', () async {
      await expectLater(
        Payriff.retrieveOrder(orderId: 'o1', clientSecret: 'pr_cs_x'),
        throwsA(
          isA<PayriffException>().having(
            (PayriffException e) => e.error.code,
            'code',
            PayriffErrorCode.notConfigured,
          ),
        ),
      );
      expect(Payriff.config, isNull);
      expect(Payriff.isPaymentInProgress, isFalse);
    });
  });
}
