// CONTRACT §17.5–§17.8 and §17.12: Google Pay and Apple Pay payments end to
// end, with a fake Client API, a fake clock, a fake WebView and a mocked
// `payriff/native` channel standing in for PassKit and the Google Pay API.
// No network.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:payriff/payriff.dart';
import 'package:payriff/src/internal/card/card_clock.dart';
import 'package:payriff/src/internal/ui/sheet.dart';
import 'package:payriff/src/internal/wallet/wallet_payment.dart';
import 'package:payriff/src/internal/wallet/wallet_rules.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'support/card_support.dart';
import 'support/fake_webview.dart';

const String _callback =
    'https://sb-api.payriff.com/api/v3/gateway/kapital/callback/o1';

const PayriffConfig _googleConfig = PayriffConfig(
  environment: PayriffEnvironment.sandbox,
  publishableKey: testPublishableKey,
  enableLogging: true,
  googlePay: PayriffGooglePayConfig(merchantName: 'Shop'),
);

const PayriffConfig _appleConfig = PayriffConfig(
  environment: PayriffEnvironment.sandbox,
  publishableKey: testPublishableKey,
  enableLogging: true,
  applePay: PayriffApplePayConfig(
    merchantIdentifier: 'merchant.com.example.shop',
  ),
);

PayriffClientOrder _order(WalletKind kind) =>
    PayriffClientOrder.fromPayload(<String, Object?>{
      'orderId': testOrderId,
      'amount': 10.5,
      'currency': 'AZN',
      'merchantName': 'Test Merchant',
      'status': 'CREATED',
      'paymentMethods': <String>['CARD', kind.method],
      'googlePay': kind == WalletKind.googlePay ? testGooglePayGateway : null,
    }, requestedOrderId: testOrderId);

Map<String, Object?> _challenge() => <String, Object?>{
  'orderId': testOrderId,
  'nextAction': 'THREE_DS',
  'accessUrl': 'https://acs.bank.example/challenge',
  'clientRequest': <Object?>[
    <String, Object?>{'key': 'creq', 'value': 'CREQ-VALUE-42'},
  ],
};

class _Run {
  _Run(this.context, this.native, this.backend, this.logs);

  final BuildContext Function() context;
  final NativeCalls native;
  final FakeClientBackend backend;
  final List<PayriffLogEntry> logs;

  Future<PayriffResult?> pay(WalletKind kind) => payWithWallet(
    context(),
    kind: kind,
    order: _order(kind),
    orderId: testOrderId,
    clientSecret: testClientSecret,
  );

  List<String> get messages =>
      logs.map((PayriffLogEntry e) => e.message).toList();

  /// The statuses of `applePayComplete`, in order.
  List<String> get sheetStatuses => native
      .named('applePayComplete')
      .map(
        (MethodCall c) =>
            (c.arguments as Map<Object?, Object?>)['status']! as String,
      )
      .toList();

  /// The native wallet calls, in order.
  List<String> get walletCalls => native.calls
      .map((MethodCall c) => c.method)
      .where(
        (String m) => m.startsWith('applePay') || m.startsWith('googlePay'),
      )
      .toList();

  void expectNoSecretLogged() {
    for (final PayriffLogEntry entry in logs) {
      for (final String secret in <String>[
        testClientSecret,
        'MEQCIFakeSignature',
        'ZmFrZQ',
        '3+f4oOTwPa6f1UZ6tG',
        'MIAGCSqGSIb3DQEHAqCAMIACAQEx',
        'LbsUwAT6w1JV9tFXocU813TCHks',
      ]) {
        expect(entry.message, isNot(contains(secret)), reason: entry.message);
      }
    }
  }
}

Future<_Run> _start(
  WidgetTester tester,
  FakeClientBackend backend, {
  required PayriffConfig config,
  NativeCalls? native,
}) async {
  final NativeCalls calls = (native ?? NativeCalls())..install();
  backend.install();
  final List<PayriffLogEntry> logs = <PayriffLogEntry>[];
  final StreamSubscription<PayriffLogEntry> sub = Payriff.logStream.listen(
    logs.add,
  );
  addTearDown(sub.cancel);
  Payriff.configure(config);
  late BuildContext context;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext c) {
            context = c;
            return const SizedBox.expand();
          },
        ),
      ),
    ),
  );
  return _Run(() => context, calls, backend, logs);
}

const PayriffPayment _approved = PayriffPayment(
  orderId: testOrderId,
  status: PayriffPaymentStatus.approved,
  rawStatus: 'APPROVED',
  amount: 10.5,
  currency: 'AZN',
);

void _expectWalletFailed(PayriffResult? result, String message) {
  expect(result, isA<PayriffResultFailed>());
  final PayriffError error = result!.error!;
  expect(error.code, PayriffErrorCode.walletFailed);
  expect(error.code.value, 'WALLET_FAILED');
  expect(error.message, message);
  expect(error.isRetryable, isFalse);
  expect(error.isFatal, isFalse);
}

void main() {
  late FakeWebViewPlatform web;

  setUp(() {
    Payriff.debugReset();
    web = installFakeWebView();
    debugPayriffCardClock = FakeCardClock();
  });

  tearDown(() {
    debugPayriffCardClock = null;
    Payriff.debugReset();
  });

  group('Google Pay', () {
    testWidgets(
      'OK -> /pay -> checkStatus -> success; the request comes '
      'from Dart and the token goes to /pay as is',
      (WidgetTester tester) async {
        final _Run run = await _start(
          tester,
          FakeClientBackend(statuses: <String>['PENDING', 'APPROVED']),
          config: _googleConfig,
        );
        final PayriffResult? result = await pumpUntilDone(
          tester,
          run.pay(WalletKind.googlePay),
        );

        expect(result, const PayriffResultSuccess(payment: _approved));
        final Map<Object?, Object?> load =
            run.native.named('googlePayLoad').single.arguments
                as Map<Object?, Object?>;
        expect(load['environment'], 'TEST');
        final Map<String, Object?> request =
            jsonDecode(load['request']! as String) as Map<String, Object?>;
        expect(request['merchantInfo'], <String, Object?>{
          'merchantName': 'Shop',
        });
        expect(request['transactionInfo'], <String, Object?>{
          'totalPriceStatus': 'FINAL',
          'totalPrice': '10.50',
          'currencyCode': 'AZN',
          'countryCode': 'AZ',
        });
        // The order was read when the wallet was offered: /pay comes first.
        expect(
          run.backend.requests.map(
            (http.Request r) => '${r.method} ${r.url.path}',
          ),
          <String>[
            'POST /api/v3/client/orders/o1/pay',
            'GET /api/v3/client/orders/o1/status',
            'GET /api/v3/client/orders/o1/status',
          ],
        );
        final http.Request pay = run.backend.to('/pay').single;
        expect(
          pay.body,
          jsonEncode(<String, Object?>{
            'method': 'GOOGLE_PAY',
            'encryptedMessage': testGooglePayToken,
          }),
        );
        expect(pay.headers.containsKey('x-secret-key'), isFalse);
        expect(pay.headers['Content-Type'], startsWith('application/json'));
        expect(pay.headers['X-Idempotency-Key'], hasLength(36));
        expect(pay.headers['X-Client-Secret'], testClientSecret);
        expect(pay.headers['X-Public-Key'], testPublishableKey);
        expect(run.native.named('encryptCard'), isEmpty);
        // CONTRACT §17.11: on tap and right before /pay.
        expect(run.native.named('deviceIntegrity'), hasLength(2));
        expect(run.messages, contains('Google Pay: ok'));
        expect(
          run.messages,
          contains('Google Pay payment finished: success (APPROVED)'),
        );
        run.expectNoSecretLogged();
        expect(Payriff.isPaymentInProgress, isFalse);
      },
    );

    testWidgets('cancel: nothing is sent and the result is null', (
      WidgetTester tester,
    ) async {
      final _Run run = await _start(
        tester,
        FakeClientBackend(),
        config: _googleConfig,
        native: NativeCalls()
          ..googlePayLoadReply = <String, Object?>{'status': 'cancelled'},
      );
      final PayriffResult? result = await pumpUntilDone(
        tester,
        run.pay(WalletKind.googlePay),
      );
      expect(result, isNull);
      expect(run.backend.requests, isEmpty);
      expect(run.messages, contains('Google Pay: cancelled'));
      expect(Payriff.isPaymentInProgress, isFalse);
    });

    testWidgets('error -> WALLET_FAILED "Google Pay failed (status <code>)."', (
      WidgetTester tester,
    ) async {
      final _Run run = await _start(
        tester,
        FakeClientBackend(),
        config: _googleConfig,
        native: NativeCalls()
          ..googlePayLoadReply = <String, Object?>{
            'status': 'error',
            'code': 10,
          },
      );
      final PayriffResult? result = await pumpUntilDone(
        tester,
        run.pay(WalletKind.googlePay),
      );
      _expectWalletFailed(result, 'Google Pay failed (status 10).');
      expect(run.backend.requests, isEmpty);
      expect(run.messages, contains('Google Pay: error 10'));
    });

    testWidgets('a missing or blank token is WALLET_FAILED', (
      WidgetTester tester,
    ) async {
      for (final String? token in <String?>[null, '', '  ']) {
        final _Run run = await _start(
          tester,
          FakeClientBackend(),
          config: _googleConfig,
          native: NativeCalls()
            ..googlePayLoadReply = <String, Object?>{
              'status': 'ok',
              'token': token,
            },
        );
        final PayriffResult? result = await pumpUntilDone(
          tester,
          run.pay(WalletKind.googlePay),
        );
        _expectWalletFailed(result, 'Google Pay returned no payment token.');
        expect(run.backend.requests, isEmpty);
      }
    });

    testWidgets('challenge -> the 3-D Secure sheet, then polling', (
      WidgetTester tester,
    ) async {
      final _Run run = await _start(
        tester,
        FakeClientBackend(
          payPayload: _challenge(),
          statuses: <String>['PENDING', 'APPROVED'],
        ),
        config: _googleConfig,
      );
      final Future<PayriffResult?> future = run.pay(WalletKind.googlePay);
      await settleSheet(tester);
      expect(find.byType(PayriffThreeDsSheet), findsOneWidget);
      expect(Payriff.isPaymentInProgress, isTrue);
      final LoadRequestParams load = web.controller.requests.single;
      expect(load.uri.toString(), 'https://acs.bank.example/challenge');
      expect(load.method, LoadRequestMethod.post);
      expect(utf8.decode(load.body!), 'creq=CREQ-VALUE-42');

      web.delegate
        ..pageStarted(_callback)
        ..urlChanged(_callback)
        ..pageFinished(_callback);
      final PayriffResult? result = await pumpUntilDone(tester, future);
      expect(result, const PayriffResultSuccess(payment: _approved));
      expect(find.byType(PayriffThreeDsSheet), findsNothing);
      run.expectNoSecretLogged();
    });

    testWidgets('a compromised device: refused on tap, before the sheet', (
      WidgetTester tester,
    ) async {
      final _Run run = await _start(
        tester,
        FakeClientBackend(),
        config: _googleConfig,
        native: NativeCalls()..integrityReply = NativeCalls.compromised(),
      );
      final PayriffResult? result = await pumpUntilDone(
        tester,
        run.pay(WalletKind.googlePay),
      );
      expect(result?.error?.code, PayriffErrorCode.deviceCompromised);
      expect(run.native.named('googlePayLoad'), isEmpty);
      expect(run.backend.requests, isEmpty);
      expect(
        run.messages,
        contains(
          'Compromised device (su binary, Frida) at Google Pay tap: Google '
          'Pay payments are refused',
        ),
      );
    });

    testWidgets('a tool that attaches while the sheet is up: refused right '
        'before /pay', (WidgetTester tester) async {
      final NativeCalls native = NativeCalls();
      native.integrityReplies.addAll(<Object?>[
        NativeCalls.clean,
        NativeCalls.compromised(<String>['Frida']),
      ]);
      final _Run run = await _start(
        tester,
        FakeClientBackend(),
        config: _googleConfig,
        native: native,
      );
      final PayriffResult? result = await pumpUntilDone(
        tester,
        run.pay(WalletKind.googlePay),
      );
      expect(result?.error?.code, PayriffErrorCode.deviceCompromised);
      expect(run.native.named('googlePayLoad'), hasLength(1));
      expect(run.backend.to('/pay'), isEmpty);
    });

    testWidgets('429 and no response on /pay: retried with the same token and '
        'idempotency key; the next token gets a new key', (
      WidgetTester tester,
    ) async {
      final FakeClientBackend backend = FakeClientBackend();
      backend.payFailures.addAll(<int>[429, 0]);
      final _Run run = await _start(tester, backend, config: _googleConfig);
      final PayriffResult? result = await pumpUntilDone(
        tester,
        run.pay(WalletKind.googlePay),
      );
      expect(result, isA<PayriffResultSuccess>());
      final List<http.Request> pays = backend.to('/pay');
      expect(pays, hasLength(3));
      expect(
        pays.map((http.Request r) => r.headers['X-Idempotency-Key']).toSet(),
        hasLength(1),
      );
      expect(pays.map((http.Request r) => r.body).toSet(), hasLength(1));

      await pumpUntilDone(tester, run.pay(WalletKind.googlePay));
      expect(
        backend.to('/pay').last.headers['X-Idempotency-Key'],
        isNot(pays.first.headers['X-Idempotency-Key']),
      );
    });

    testWidgets('one payment at a time', (WidgetTester tester) async {
      final Completer<Object?> sheet = Completer<Object?>();
      final _Run run = await _start(
        tester,
        FakeClientBackend(),
        config: _googleConfig,
        native: NativeCalls()..googlePayLoadReply = sheet.future,
      );
      final Future<PayriffResult?> first = run.pay(WalletKind.googlePay);
      await tester.pump();
      expect(Payriff.isPaymentInProgress, isTrue);
      final PayriffResult? second = await run.pay(WalletKind.googlePay);
      expect(second?.error?.code, PayriffErrorCode.paymentInProgress);
      sheet.complete(<String, Object?>{'status': 'cancelled'});
      expect(await pumpUntilDone(tester, first), isNull);
      expect(Payriff.isPaymentInProgress, isFalse);
    });
  });

  group('Apple Pay', () {
    final TargetPlatformVariant ios = TargetPlatformVariant.only(
      TargetPlatform.iOS,
    );

    testWidgets('authorize -> /pay -> final success: the sheet gets .success '
        'once, and the result comes when it is gone', (
      WidgetTester tester,
    ) async {
      final _Run run = await _start(
        tester,
        FakeClientBackend(statuses: <String>['PENDING', 'APPROVED']),
        config: _appleConfig,
      );
      final PayriffResult? result = await pumpUntilDone(
        tester,
        run.pay(WalletKind.applePay),
      );
      expect(result, const PayriffResultSuccess(payment: _approved));
      expect(run.walletCalls, <String>['applePayPresent', 'applePayComplete']);
      expect(run.sheetStatuses, <String>['success']);
      expect(
        run.native.named('applePayPresent').single.arguments,
        <String, Object?>{
          'merchantIdentifier': 'merchant.com.example.shop',
          'countryCode': 'AZ',
          'currencyCode': 'AZN',
          'supportedNetworks': <String>['visa', 'masterCard'],
          'merchantCapabilities': <String>['threeDSecure'],
          'summaryItems': <Object?>[
            <String, Object?>{
              'label': 'Test Merchant',
              'amount': '10.50',
              'type': 'final',
            },
          ],
        },
      );
      final http.Request pay = run.backend.to('/pay').single;
      expect(
        pay.body,
        jsonEncode(<String, Object?>{
          'method': 'APPLE_PAY',
          'encryptedMessage': testApplePayToken,
        }),
      );
      expect(pay.headers.containsKey('x-secret-key'), isFalse);
      expect(run.messages, contains('Apple Pay sheet: success'));
      run.expectNoSecretLogged();
    }, variant: ios);

    final Map<String, (Object, Matcher)> failures = <String, (Object, Matcher)>{
      'final declined': (<String>['DECLINED'], isA<PayriffResultDeclined>()),
      'final CANCELED': (
        <String>['CANCELED'],
        isA<PayriffResultCancelled>().having(
          (PayriffResultCancelled r) => r.reason,
          'reason',
          PayriffCancelReason.canceled,
        ),
      ),
      'final unexpected (REFUNDED)': (
        <String>['REFUNDED'],
        isA<PayriffResultPending>().having(
          (PayriffResultPending r) => r.reason,
          'reason',
          PayriffPendingReason.unexpectedStatus,
        ),
      ),
      'failed from /pay': (
        400,
        isA<PayriffResultFailed>().having(
          (PayriffResultFailed r) => r.error.code,
          'code',
          PayriffErrorCode.orderNotPayable,
        ),
      ),
    };
    failures.forEach((String situation, (Object, Matcher) c) {
      testWidgets('$situation: the sheet gets .failure once, and the result '
          'is returned', (WidgetTester tester) async {
        final (Object input, Matcher matcher) = c;
        final FakeClientBackend backend = input is List<String>
            ? FakeClientBackend(statuses: input)
            : (FakeClientBackend()..payFailures.add(input as int));
        final _Run run = await _start(tester, backend, config: _appleConfig);
        final PayriffResult? result = await pumpUntilDone(
          tester,
          run.pay(WalletKind.applePay),
        );
        expect(result, matcher);
        expect(run.sheetStatuses, <String>['failure']);
        expect(run.messages, contains('Apple Pay sheet: failure'));
      }, variant: ios);
    });

    testWidgets('a compromised device at the authorization: .failure, '
        'DEVICE_COMPROMISED, nothing sent', (WidgetTester tester) async {
      final NativeCalls native = NativeCalls();
      native.integrityReplies.addAll(<Object?>[
        NativeCalls.clean,
        NativeCalls.compromised(<String>['Frida']),
      ]);
      final _Run run = await _start(
        tester,
        FakeClientBackend(),
        config: _appleConfig,
        native: native,
      );
      final PayriffResult? result = await pumpUntilDone(
        tester,
        run.pay(WalletKind.applePay),
      );
      expect(result?.error?.code, PayriffErrorCode.deviceCompromised);
      expect(run.sheetStatuses, <String>['failure']);
      expect(run.backend.requests, isEmpty);
    }, variant: ios);

    for (final String step in <String>['challenge', 'redirect']) {
      testWidgets('$step: .success first, the 3-D Secure sheet only once the '
          'Apple Pay sheet is gone', (WidgetTester tester) async {
        final Completer<void> dismissed = Completer<void>();
        final _Run run = await _start(
          tester,
          FakeClientBackend(
            payPayload: step == 'challenge'
                ? _challenge()
                : <String, Object?>{
                    'nextAction': 'REDIRECT',
                    'redirectUrl': 'https://acs.bank.example/redirect',
                  },
            statuses: <String>['PENDING', 'APPROVED'],
          ),
          config: _appleConfig,
          native: NativeCalls()..applePayDismissed = dismissed,
        );
        final Future<PayriffResult?> future = run.pay(WalletKind.applePay);
        await settleSheet(tester);
        expect(run.sheetStatuses, <String>['success']);
        // PassKit is still dismissing its sheet.
        expect(find.byType(PayriffThreeDsSheet), findsNothing);
        expect(web.controllers, isEmpty);

        dismissed.complete();
        await settleSheet(tester);
        expect(find.byType(PayriffThreeDsSheet), findsOneWidget);
        expect(
          web.controller.requests.single.uri.toString(),
          'https://acs.bank.example/$step',
        );
        web.delegate
          ..pageStarted(_callback)
          ..urlChanged(_callback)
          ..pageFinished(_callback);
        final PayriffResult? result = await pumpUntilDone(tester, future);
        expect(result, const PayriffResultSuccess(payment: _approved));
        // The handler was completed exactly once.
        expect(run.sheetStatuses, <String>['success']);
      }, variant: ios);
    }

    testWidgets('no final status 20 s after the authorization: .success, and '
        'polling goes on to its result', (WidgetTester tester) async {
      // Polling every 2.5 s on fake time: APPROVED at 30 s.
      debugPayriffCardClock = FakeCardClock(realDelays: true);
      final _Run run = await _start(
        tester,
        FakeClientBackend(
          statuses: <String>[...List<String>.filled(12, 'PENDING'), 'APPROVED'],
        ),
        config: _appleConfig,
      );
      PayriffResult? result;
      bool done = false;
      unawaited(
        run.pay(WalletKind.applePay).then((PayriffResult? r) {
          result = r;
          done = true;
        }),
      );
      await tester.pump(const Duration(seconds: 19));
      expect(run.sheetStatuses, isEmpty);
      await tester.pump(const Duration(seconds: 2));
      expect(run.sheetStatuses, <String>['success']);
      expect(done, isFalse);
      expect(
        run.messages,
        contains('Apple Pay: no final status 20 s after the authorization'),
      );
      for (int i = 0; i < 200 && !done; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(done, isTrue);
      expect(result, const PayriffResultSuccess(payment: _approved));
      expect(run.backend.statusChecks, 13);
      expect(run.sheetStatuses, <String>['success']);
    }, variant: ios);

    testWidgets('closed without authorizing: null, nothing sent', (
      WidgetTester tester,
    ) async {
      final _Run run = await _start(
        tester,
        FakeClientBackend(),
        config: _appleConfig,
        native: NativeCalls()
          ..applePayPresentReply = <String, Object?>{'event': 'closed'},
      );
      final PayriffResult? result = await pumpUntilDone(
        tester,
        run.pay(WalletKind.applePay),
      );
      expect(result, isNull);
      expect(run.backend.requests, isEmpty);
      expect(run.native.named('applePayComplete'), isEmpty);
      expect(run.messages, contains('Apple Pay sheet: closed'));
    }, variant: ios);

    testWidgets('a sheet that cannot be shown is WALLET_FAILED', (
      WidgetTester tester,
    ) async {
      for (final Object? reply in <Object?>[
        <String, Object?>{'event': 'notPresented'},
        PlatformException(code: 'x'),
        null,
      ]) {
        final _Run run = await _start(
          tester,
          FakeClientBackend(),
          config: _appleConfig,
          native: NativeCalls()..applePayPresentReply = reply,
        );
        final PayriffResult? result = await pumpUntilDone(
          tester,
          run.pay(WalletKind.applePay),
        );
        _expectWalletFailed(
          result,
          'Apple Pay could not be shown. Check the merchant identifier and '
          'the Apple Pay capability.',
        );
        expect(run.backend.requests, isEmpty);
      }
    }, variant: ios);

    testWidgets('an authorization without payment data: .failure and '
        'WALLET_FAILED', (WidgetTester tester) async {
      final _Run run = await _start(
        tester,
        FakeClientBackend(),
        config: _appleConfig,
        native: NativeCalls()
          ..applePayPresentReply = <String, Object?>{
            'event': 'authorized',
            'paymentData': null,
          },
      );
      final PayriffResult? result = await pumpUntilDone(
        tester,
        run.pay(WalletKind.applePay),
      );
      _expectWalletFailed(result, 'Apple Pay returned no payment data.');
      expect(run.sheetStatuses, <String>['failure']);
      expect(run.backend.requests, isEmpty);
    }, variant: ios);

    testWidgets('configuration and argument errors fail before the sheet', (
      WidgetTester tester,
    ) async {
      final _Run run = await _start(
        tester,
        FakeClientBackend(),
        config: const PayriffConfig(
          publishableKey: testPublishableKey,
          applePay: PayriffApplePayConfig(merchantIdentifier: 'com.shop'),
        ),
      );
      final PayriffResult? invalid = await run.pay(WalletKind.applePay);
      expect(invalid?.error?.code, PayriffErrorCode.invalidConfig);
      final PayriffResult? badSecret = await payWithWallet(
        run.context(),
        kind: WalletKind.googlePay,
        order: _order(WalletKind.googlePay),
        orderId: testOrderId,
        clientSecret: 'secret',
      );
      expect(badSecret?.error?.code, PayriffErrorCode.invalidOrder);
      expect(badSecret?.error?.message, isNot(contains('secret.')));
      expect(run.native.named('applePayPresent'), isEmpty);
      expect(run.native.named('googlePayLoad'), isEmpty);
    }, variant: ios);
  });
}
