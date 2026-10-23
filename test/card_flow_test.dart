// CONTRACT §16.7–§16.9: Payriff.confirmCardPayment end to end, with a fake
// Client API, a fake clock, a fake WebView and a mocked `payriff/native`
// channel. No network.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:payriff/payriff.dart';
import 'package:payriff/src/card/card_form.dart';
import 'package:payriff/src/internal/card/card_clock.dart';
import 'package:payriff/src/internal/card/card_crypto.dart';
import 'package:payriff/src/internal/card/card_flow.dart';
import 'package:payriff/src/internal/card/client_api.dart';
import 'package:payriff/src/internal/card/three_ds_website_data.dart';
import 'package:payriff/src/internal/strings.dart';
import 'package:payriff/src/internal/ui/presenter.dart';
import 'package:payriff/src/internal/ui/sheet.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'support/card_support.dart';
import 'support/fake_webview.dart';

const String _callback =
    'https://sb-api.payriff.com/api/v3/gateway/kapital/callback/o1';

const CardPlaintext _testCard = CardPlaintext(
  pan: '4111111111111111',
  cardHolder: 'Unknown',
  expiryYear: '2030',
  expiryMonth: '12',
  cvv: '123',
);

/// A complete main-frame page load (the 3DS sheet has no progress hook).
void _loadPage(FakeNavigationDelegate delegate, String url) {
  delegate
    ..pageStarted(url)
    ..urlChanged(url)
    ..pageFinished(url);
}

Map<String, Object?> _challenge({String creq = 'CREQ-VALUE-42'}) =>
    <String, Object?>{
      'orderId': testOrderId,
      'nextAction': 'THREE_DS',
      'channel': 'KAPITAL',
      'accessUrl': 'https://acs.bank.example/challenge',
      'clientRequest': <Object?>[
        <String, Object?>{'key': 'creq', 'value': creq},
        <String, Object?>{'key': 'threeDSSessionData', 'value': null},
      ],
    };

class _Run {
  _Run(this.context, this.controller, this.native, this.backend);

  final BuildContext Function() context;
  final PayriffCardController controller;
  final NativeCalls native;
  final FakeClientBackend backend;

  Future<PayriffResult> confirm({
    String orderId = testOrderId,
    String clientSecret = testClientSecret,
  }) => Payriff.confirmCardPayment(
    context(),
    controller,
    orderId: orderId,
    clientSecret: clientSecret,
  );

  String text(Key key) =>
      (find.byKey(key).evaluate().single.widget as TextField).controller!.text;
}

Future<_Run> _start(
  WidgetTester tester,
  FakeClientBackend backend, {
  PayriffConfig? config = const PayriffConfig(
    environment: PayriffEnvironment.sandbox,
    publishableKey: testPublishableKey,
  ),
  bool showHolder = false,
}) async {
  final NativeCalls native = NativeCalls()..install();
  backend.install();
  if (config != null) Payriff.configure(config);
  final PayriffCardController controller = PayriffCardController();
  addTearDown(controller.dispose);
  final BuildContext Function() context = await pumpCardApp(
    tester,
    controller,
    showHolder: showHolder,
  );
  return _Run(context, controller, native, backend);
}

void main() {
  late FakeWebViewPlatform web;
  late FakeCardClock clock;

  setUp(() {
    Payriff.debugReset();
    web = installFakeWebView();
    clock = FakeCardClock();
    debugPayriffCardClock = clock;
  });

  tearDown(() {
    debugPayriffCardClock = null;
    Payriff.debugReset();
  });

  group('confirmCardPayment', () {
    testWidgets('CHECK_STATUS: encrypts natively, pays and polls to success', (
      WidgetTester tester,
    ) async {
      final _Run run = await _start(
        tester,
        FakeClientBackend(statuses: <String>['PENDING', 'APPROVED']),
      );
      expect(run.native.secureCount, 1, reason: 'the form protects the screen');
      await fillCard(tester);
      expect(run.controller.isComplete, isTrue);
      expect(run.controller.brand, PayriffCardBrand.visa);

      final PayriffResult result = await pumpUntilDone(tester, run.confirm());

      expect(
        result,
        const PayriffResultSuccess(
          payment: PayriffPayment(
            orderId: testOrderId,
            status: PayriffPaymentStatus.approved,
            rawStatus: 'APPROVED',
            amount: 10.5,
            currency: 'AZN',
          ),
        ),
      );
      // The card JSON is built byte-exact in Dart and encrypted natively
      // with the pinned key.
      final Map<Object?, Object?> args =
          run.native.named('encryptCard').single.arguments
              as Map<Object?, Object?>;
      expect(
        utf8.decode(args['card']! as List<int>),
        '{"pan":"4111111111111111","cardHolder":"Unknown","expiryYear":'
        '"2030","expiryMonth":"12","cvv":"123"}',
      );
      expect(args['spki'], payriffPublicKeyDer());

      final List<http.Request> requests = run.backend.requests;
      expect(
        requests.map((http.Request r) => '${r.method} ${r.url.path}'),
        <String>[
          'GET /api/v3/client/orders/o1',
          'POST /api/v3/client/orders/o1/pay',
          'GET /api/v3/client/orders/o1/status',
          'GET /api/v3/client/orders/o1/status',
        ],
      );
      final http.Request pay = requests[1];
      expect(pay.url.host, 'sb-api.payriff.com');
      expect(pay.body, '{"method":"CARD","encryptedMessage":"ENCRYPTED+/="}');
      expect(pay.headers['x-secret-key'], 'WRAPPED+/=');
      expect(pay.headers['X-Idempotency-Key'], hasLength(36));
      for (final http.Request r in requests) {
        expect(r.headers['X-Public-Key'], testPublishableKey);
        expect(r.headers['X-Client-Secret'], testClientSecret);
        expect(r.headers['X-Client-App-Id'], testAppId);
        expect(r.headers.containsKey('Authorization'), isFalse);
        expect(r.headers.containsKey('Origin'), isFalse);
      }
      expect(clock.sleeps, <Duration>[const Duration(milliseconds: 2500)]);
      // CONTRACT §9.1a: no WebView was shown, so no website data is removed.
      expect(run.native.named('clearWebsiteData'), isEmpty);
      // CONTRACT §16.5: the values are cleared after a final result.
      expect(run.text(cardNumberFieldKey), isEmpty);
      expect(run.text(cardCvvFieldKey), isEmpty);
      expect(run.controller.isProcessing, isFalse);
      expect(Payriff.isPaymentInProgress, isFalse);
    });

    testWidgets('an invalid form fails with VALIDATION_FAILED and no request', (
      WidgetTester tester,
    ) async {
      final _Run run = await _start(tester, FakeClientBackend());
      await tester.enterText(
        find.byKey(cardNumberFieldKey),
        '4242424242424241',
      );
      await tester.pump();
      final PayriffResult result = await pumpUntilDone(tester, run.confirm());
      expect(result.error?.code, PayriffErrorCode.validationFailed);
      expect(result.error?.fields, const <PayriffCardFieldError>[
        PayriffCardFieldError(
          field: PayriffCardField.number,
          error: PayriffCardFieldErrorCode.invalid,
        ),
        PayriffCardFieldError(
          field: PayriffCardField.expiry,
          error: PayriffCardFieldErrorCode.required,
        ),
        PayriffCardFieldError(
          field: PayriffCardField.cvv,
          error: PayriffCardFieldErrorCode.required,
        ),
      ]);
      expect(result.error.toString(), isNot(contains('4242')));
      expect(run.backend.requests, isEmpty);
      expect(run.native.named('encryptCard'), isEmpty);
      // Submitting shows the errors, and the typed value stays. The grouped
      // card box has one error line: the first of number, expiry and CVC.
      expect(find.text('Card number is invalid'), findsOneWidget);
      expect(find.text('Enter the expiry date'), findsNothing);
      expect(find.text('Enter the CVV'), findsNothing);
      expect(run.text(cardNumberFieldKey), '4242 4242 4242 4241');
    });

    testWidgets(
      'an order that is not payable by card fails before encrypting',
      (WidgetTester tester) async {
        final _Run run = await _start(
          tester,
          FakeClientBackend(orderStatus: 'APPROVED'),
        );
        await fillCard(tester);
        PayriffResult result = await pumpUntilDone(tester, run.confirm());
        expect(result.error?.code, PayriffErrorCode.orderNotPayable);
        expect(run.native.named('encryptCard'), isEmpty);
        expect(run.backend.requests, hasLength(1));

        run.backend
          ..orderStatus = 'CREATED'
          ..paymentMethods = <String>['GOOGLE_PAY'];
        await fillCard(tester);
        result = await pumpUntilDone(tester, run.confirm());
        expect(result.error?.code, PayriffErrorCode.orderNotPayable);
        expect(run.native.named('encryptCard'), isEmpty);
      },
    );

    testWidgets('429 on /pay: three retries with the same bytes and key, then '
        'RATE_LIMITED (fatal)', (WidgetTester tester) async {
      final FakeClientBackend backend = FakeClientBackend();
      backend.payFailures.addAll(<int>[429, 429, 429, 429]);
      final _Run run = await _start(tester, backend);
      await fillCard(tester);
      final PayriffResult result = await pumpUntilDone(tester, run.confirm());
      expect(result.error?.code, PayriffErrorCode.rateLimited);
      expect(result.error?.isFatal, isTrue);
      final List<http.Request> pays = backend.to('/pay');
      expect(pays, hasLength(4));
      expect(
        pays.map((http.Request r) => r.headers['X-Idempotency-Key']).toSet(),
        hasLength(1),
      );
      expect(pays.map((http.Request r) => r.body).toSet(), hasLength(1));
      expect(clock.sleeps, const <Duration>[
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 4),
      ]);
      // The card was sent: the values are gone.
      expect(run.text(cardNumberFieldKey), isEmpty);
    });

    testWidgets('/pay without a response is resent once, unchanged', (
      WidgetTester tester,
    ) async {
      final FakeClientBackend backend = FakeClientBackend();
      backend.payFailures.add(0);
      final _Run run = await _start(tester, backend);
      await fillCard(tester);
      final PayriffResult result = await pumpUntilDone(tester, run.confirm());
      expect(result, isA<PayriffResultSuccess>());
      final List<http.Request> pays = backend.to('/pay');
      expect(pays, hasLength(2));
      expect(pays[0].body, pays[1].body);
      expect(
        pays[0].headers['X-Idempotency-Key'],
        pays[1].headers['X-Idempotency-Key'],
      );
      expect(clock.sleeps.first, const Duration(seconds: 1));
    });

    testWidgets('a failed encryption sends nothing and keeps the form', (
      WidgetTester tester,
    ) async {
      final _Run run = await _start(tester, FakeClientBackend());
      run.native.encryptReply = null;
      await fillCard(tester);
      final PayriffResult result = await pumpUntilDone(tester, run.confirm());
      expect(result.error?.code, PayriffErrorCode.unknown);
      expect(run.backend.to('/pay'), isEmpty);
      expect(run.text(cardNumberFieldKey), '4111 1111 1111 1111');
    });

    testWidgets('status polling ends after 120 s with pending(notFinal)', (
      WidgetTester tester,
    ) async {
      final _Run run = await _start(
        tester,
        FakeClientBackend(statuses: <String>['PENDING']),
      );
      await fillCard(tester);
      final PayriffResult result = await pumpUntilDone(tester, run.confirm());
      expect(result, isA<PayriffResultPending>());
      expect(
        (result as PayriffResultPending).reason,
        PayriffPendingReason.notFinal,
      );
      expect(result.payment.status, PayriffPaymentStatus.pending);
      expect(run.backend.statusChecks, 49);
      expect(clock.sleeps, hasLength(48));
    });

    testWidgets('a status the SDK cannot verify any more is pending', (
      WidgetTester tester,
    ) async {
      final _Run run = await _start(
        tester,
        FakeClientBackend(statuses: <String>['!404']),
      );
      await fillCard(tester);
      final PayriffResult result = await pumpUntilDone(tester, run.confirm());
      expect(
        (result as PayriffResultPending).reason,
        PayriffPendingReason.verificationFailed,
      );
    });

    testWidgets('network errors while polling keep polling', (
      WidgetTester tester,
    ) async {
      final _Run run = await _start(
        tester,
        FakeClientBackend(statuses: <String>['!fail', '!fail', 'DECLINED']),
      );
      await fillCard(tester);
      final PayriffResult result = await pumpUntilDone(tester, run.confirm());
      expect(result, isA<PayriffResultDeclined>());
      expect(run.backend.statusChecks, 3);
    });

    testWidgets('an unknown next step: one status check, else '
        'UNEXPECTED_RESPONSE', (WidgetTester tester) async {
      final _Run run = await _start(
        tester,
        FakeClientBackend(
          payPayload: <String, Object?>{'nextAction': 'FOO'},
          statuses: <String>['PENDING'],
        ),
      );
      await fillCard(tester);
      PayriffResult result = await pumpUntilDone(tester, run.confirm());
      expect(result.error?.code, PayriffErrorCode.unexpectedResponse);
      expect(run.backend.statusChecks, 1);

      run.backend.statuses
        ..clear()
        ..add('CANCELED');
      await fillCard(tester);
      result = await pumpUntilDone(tester, run.confirm());
      expect(
        (result as PayriffResultCancelled).reason,
        PayriffCancelReason.canceled,
      );
    });

    testWidgets('configuration and argument errors fail before any request', (
      WidgetTester tester,
    ) async {
      final _Run run = await _start(tester, FakeClientBackend(), config: null);
      await fillCard(tester);
      Future<PayriffErrorCode?> code({
        String clientSecret = testClientSecret,
        String orderId = testOrderId,
      }) async => (await pumpUntilDone(
        tester,
        run.confirm(clientSecret: clientSecret, orderId: orderId),
      )).error?.code;

      expect(await code(), PayriffErrorCode.notConfigured);
      Payriff.configure(const PayriffConfig());
      expect(await code(), PayriffErrorCode.invalidConfig);
      Payriff.configure(
        const PayriffConfig(publishableKey: '0123456789ABCDEF0123456789ABCDEF'),
      );
      expect(await code(), PayriffErrorCode.invalidConfig);
      Payriff.configure(
        const PayriffConfig(publishableKey: ' $testPublishableKey '),
      );
      final PayriffResult bad = await pumpUntilDone(
        tester,
        run.confirm(clientSecret: 'cs_secret_value'),
      );
      expect(bad.error?.code, PayriffErrorCode.invalidOrder);
      expect(bad.error.toString(), isNot(contains('cs_secret_value')));
      expect(await code(orderId: '..'), PayriffErrorCode.invalidOrder);
      expect(await code(orderId: '  '), PayriffErrorCode.invalidOrder);
      expect(run.backend.requests, isEmpty);
      expect(run.native.named('encryptCard'), isEmpty);
      // The card is still there for a corrected call.
      expect(run.text(cardNumberFieldKey), '4111 1111 1111 1111');
    });
  });

  group('3-D Secure sheet', () {
    testWidgets('challenge: native POST, callback, parallel polling closes '
        'the sheet; nothing secret is logged', (WidgetTester tester) async {
      final List<PayriffLogEntry> logs = <PayriffLogEntry>[];
      final StreamSubscription<PayriffLogEntry> sub = Payriff.logStream.listen(
        logs.add,
      );
      addTearDown(sub.cancel);
      final _Run run = await _start(
        tester,
        FakeClientBackend(
          payPayload: _challenge(),
          statuses: <String>['PENDING', 'APPROVED'],
        ),
        config: const PayriffConfig(
          environment: PayriffEnvironment.sandbox,
          publishableKey: testPublishableKey,
          enableLogging: true,
        ),
      );
      await fillCard(tester);
      final Future<PayriffResult> future = run.confirm();
      await settleSheet(tester);

      expect(find.byType(PayriffThreeDsSheet), findsOneWidget);
      expect(run.native.secureCount, 2, reason: 'form + 3DS sheet');
      expect(Payriff.isPaymentInProgress, isTrue);
      expect(run.controller.isProcessing, isTrue);
      final FakeWebViewController page = web.controller;
      final LoadRequestParams load = page.requests.single;
      expect(load.uri.toString(), 'https://acs.bank.example/challenge');
      expect(load.method, LoadRequestMethod.post);
      expect(load.headers['Content-Type'], 'application/x-www-form-urlencoded');
      expect(utf8.decode(load.body!), 'creq=CREQ-VALUE-42&threeDSSessionData=');
      expect(page.javaScriptMode, JavaScriptMode.unrestricted);
      expect(page.zoomEnabled, isFalse);

      final FakeNavigationDelegate delegate = web.delegate;
      expect(
        await delegate.navigate('https://acs.bank.example/next'),
        NavigationDecision.navigate,
      );
      expect(
        await delegate.navigate('http://insecure.example/'),
        NavigationDecision.prevent,
      );
      // A plain-http page that bypassed the navigation request (an Android
      // form POST) is stopped and never stays on screen.
      final int loadsBefore = page.requests.length;
      delegate.pageStarted('http://insecure.example/form');
      await tester.pump();
      expect(page.requests.length, loadsBefore + 1);
      expect(page.requests.last.uri.toString(), 'about:blank');
      expect(
        find.text(
          "The page couldn't be loaded. Check your internet connection.",
        ),
        findsOneWidget,
      );
      // The gateway callback carries the bank's answer: it loads.
      expect(await delegate.navigate(_callback), NavigationDecision.navigate);
      expect(run.backend.statusChecks, 0);
      _loadPage(delegate, _callback);
      final PayriffResult result = await pumpUntilDone(tester, future);

      expect(result, isA<PayriffResultSuccess>());
      expect(run.backend.statusChecks, 2);
      expect(find.byType(PayriffThreeDsSheet), findsNothing);
      expect(run.native.secureCount, 1);
      for (final PayriffLogEntry entry in logs) {
        for (final String secret in <String>[
          testClientSecret,
          '4111',
          'ENCRYPTED',
          'WRAPPED',
          'CREQ-VALUE-42',
        ]) {
          expect(entry.message, isNot(contains(secret)), reason: entry.message);
        }
        // CONTRACT §11: bank pages reach the log by scheme and host only.
        for (final String path in <String>['/challenge', '/next', '/form']) {
          expect(entry.message, isNot(contains(path)), reason: entry.message);
        }
      }
      final List<String> messages = logs
          .map((PayriffLogEntry e) => e.message)
          .toList();
      expect(
        messages,
        containsAll(<String>[
          '3-D Secure page: ThreeDsRequest(POST https://acs.bank.example)',
          '3DS navigation https://acs.bank.example: allow',
          'Blocked 3-D Secure page http://insecure.example',
          // Payriff's own callback keeps its path.
          '3DS navigation $_callback: allowCallback',
        ]),
      );
    });

    testWidgets('the first navigation after the callback ends the step', (
      WidgetTester tester,
    ) async {
      final _Run run = await _start(
        tester,
        FakeClientBackend(
          payPayload: _challenge(),
          statuses: <String>['DECLINED'],
        ),
      );
      await fillCard(tester);
      final Future<PayriffResult> future = run.confirm();
      await settleSheet(tester);
      final FakeNavigationDelegate delegate = web.delegate;
      // Android: the POST to the callback is seen only as a page start.
      delegate.pageStarted(_callback);
      expect(
        await delegate.navigate('about:blank'),
        NavigationDecision.navigate,
      );
      expect(
        await delegate.navigate('https://merchant.example/return?ok=1'),
        NavigationDecision.prevent,
      );
      final PayriffResult result = await pumpUntilDone(tester, future);
      expect(result, isA<PayriffResultDeclined>());
      expect(find.byType(PayriffThreeDsSheet), findsNothing);
    });

    testWidgets('a bank app link before the callback goes to the native '
        'launcher', (WidgetTester tester) async {
      final _Run run = await _start(
        tester,
        FakeClientBackend(
          payPayload: _challenge(),
          statuses: <String>['APPROVED'],
        ),
      );
      await fillCard(tester);
      final Future<PayriffResult> future = run.confirm();
      await settleSheet(tester);
      expect(
        await web.delegate.navigate('birbank://confirm?id=1'),
        NavigationDecision.prevent,
      );
      await tester.pump();
      expect(
        run.native
            .named('openExternal')
            .map<Object?>((MethodCall c) => (c.arguments as Map)['url']),
        <String>['birbank://confirm?id=1'],
      );
      expect(
        await web.delegate.navigate('javascript:alert(1)'),
        NavigationDecision.prevent,
      );
      expect(run.native.named('openExternal'), hasLength(1));
      _loadPage(web.delegate, _callback);
      expect(await pumpUntilDone(tester, future), isA<PayriffResultSuccess>());
    });

    testWidgets(
      'closing the sheet: confirmation, one check, pending(notFinal)',
      (WidgetTester tester) async {
        final _Run run = await _start(
          tester,
          FakeClientBackend(
            payPayload: _challenge(),
            statuses: <String>['PENDING'],
          ),
        );
        await fillCard(tester);
        final Future<PayriffResult> future = run.confirm();
        await settleSheet(tester);
        _loadPage(web.delegate, 'https://acs.bank.example/challenge');
        await tester.pump();

        await tester.tap(find.byKey(closeButtonKey));
        await settleSheet(tester);
        expect(find.byKey(confirmYesKey), findsOneWidget);
        await tester.tap(find.byKey(confirmYesKey));
        final PayriffResult result = await pumpUntilDone(tester, future);

        expect(
          (result as PayriffResultPending).reason,
          PayriffPendingReason.notFinal,
        );
        expect(run.backend.statusChecks, 1);
        expect(find.byType(PayriffThreeDsSheet), findsNothing);
        expect(run.native.secureCount, 1);
        // A close ends the payment too: the bank page's data goes.
        expect(
          (run.native.named('clearWebsiteData').single.arguments
              as Map<Object?, Object?>)['hosts'],
          <String>['acs.bank.example'],
        );
        // Never cancelled(userClosed) once the card was sent; the form is
        // cleared.
        expect(run.text(cardNumberFieldKey), isEmpty);
      },
    );

    testWidgets('a WebView without the navigation rules never loads the bank '
        'page; closing checks the status', (WidgetTester tester) async {
      web.failNavigationDelegates = true;
      final _Run run = await _start(
        tester,
        FakeClientBackend(
          payPayload: _challenge(),
          statuses: <String>['PENDING'],
        ),
      );
      await fillCard(tester);
      final Future<PayriffResult> future = run.confirm();
      await settleSheet(tester);

      expect(find.byType(PayriffThreeDsSheet), findsOneWidget);
      expect(web.controller.requests, isEmpty);
      expect(
        find.text(
          "The page couldn't be loaded. Check your internet connection.",
        ),
        findsOneWidget,
      );
      // "Try again" still loads nothing.
      await tester.tap(find.byKey(retryButtonKey));
      await settleSheet(tester);
      expect(web.controller.requests, isEmpty);

      await tester.tap(find.byKey(closeButtonKey));
      await settleSheet(tester);
      await tester.tap(find.byKey(confirmYesKey));
      final PayriffResult result = await pumpUntilDone(tester, future);
      expect(
        (result as PayriffResultPending).reason,
        PayriffPendingReason.notFinal,
      );
      expect(run.backend.statusChecks, 1);
      // The sheet showed, but its WebView loaded nothing.
      expect(run.native.named('clearWebsiteData'), isEmpty);
    });

    testWidgets('a page-load error offers "Try again" (resends the POST)', (
      WidgetTester tester,
    ) async {
      final _Run run = await _start(
        tester,
        FakeClientBackend(
          payPayload: _challenge(),
          statuses: <String>['APPROVED'],
        ),
      );
      await fillCard(tester);
      final Future<PayriffResult> future = run.confirm();
      await settleSheet(tester);
      web.delegate.error(
        code: -1009,
        url: 'https://acs.bank.example/challenge',
      );
      await tester.pump();
      expect(
        find.text(
          "The page couldn't be loaded. Check your internet connection.",
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(retryButtonKey));
      await settleSheet(tester);
      expect(web.controller.requests, hasLength(2));
      expect(web.controller.requests.last.method, LoadRequestMethod.post);
      _loadPage(web.delegate, _callback);
      expect(await pumpUntilDone(tester, future), isA<PayriffResultSuccess>());
    });

    testWidgets('3DS Method: hidden WebViews POST behind the loader, then '
        '/three-ds and status polling', (WidgetTester tester) async {
      debugPayriffCardClock = clock = FakeCardClock(realDelays: true);
      final _Run run = await _start(
        tester,
        FakeClientBackend(
          payPayload: <String, Object?>{
            'nextAction': 'THREE_DS',
            'channel': 'ATB',
            'clientRequest': <Object?>[
              <String, Object?>{
                'key': 'threeDSMethodUrl',
                'value': 'https://acs.bank.example/method',
              },
              <String, Object?>{
                'key': 'threeDSMethodData',
                'value': 'METHOD-DATA-1',
              },
              <String, Object?>{
                'key': 'threeDSMethodUrlServer',
                'value': 'https://sb-api.payriff.com/api/v3/gateway/atb/method',
              },
            ],
          },
          threeDs: <Object>[
            <String, Object?>{'nextAction': 'WAIT'},
            <String, Object?>{'nextAction': 'CHECK_STATUS'},
          ],
          statuses: <String>['APPROVED'],
        ),
      );
      await fillCard(tester);
      final Future<PayriffResult> future = run.confirm();
      await settleSheet(tester);

      expect(find.byType(PayriffThreeDsSheet), findsOneWidget);
      expect(find.text('Checking payment…'), findsOneWidget);
      final List<LoadRequestParams> loads = <LoadRequestParams>[
        for (final FakeWebViewController c in web.controllers) ...c.requests,
      ];
      expect(loads, hasLength(2));
      expect(loads[0].uri.toString(), 'https://acs.bank.example/method');
      expect(loads[0].method, LoadRequestMethod.post);
      expect(utf8.decode(loads[0].body!), 'threeDSMethodData=METHOD-DATA-1');
      expect(
        loads[1].uri.toString(),
        'https://sb-api.payriff.com/api/v3/gateway/atb/method',
      );
      expect(loads[1].body, isEmpty);
      // Hidden WebViews answer dialogs themselves and never open apps.
      final FakeWebViewController hidden = web.controllers[1];
      expect(hidden.alertHandlerSet, isTrue);
      expect(
        await web.delegates[1].navigate('bank://x'),
        NavigationDecision.prevent,
      );

      // A redirect inside a hidden WebView is a site of the payment too.
      web.delegates[1].pageStarted('https://acs2.bank.example/method/next');

      final PayriffResult result = await pumpUntilDone(tester, future);
      expect(result, isA<PayriffResultSuccess>());
      expect(run.backend.to('/three-ds'), hasLength(2));
      expect(find.byType(PayriffThreeDsSheet), findsNothing);
      expect(
        (run.native.named('clearWebsiteData').single.arguments
            as Map<Object?, Object?>)['hosts'],
        <String>['acs.bank.example', 'sb-api.payriff.com', 'acs2.bank.example'],
      );
    });

    testWidgets('iOS: bank-page dialogs use dialog_ok and dialog_cancel, '
        'name the page host and stop after maxDialogsPerPage (CONTRACT §10)', (
      WidgetTester tester,
    ) async {
      final _Run run = await _start(
        tester,
        FakeClientBackend(
          payPayload: _challenge(),
          statuses: <String>['APPROVED'],
        ),
      );
      await fillCard(tester);
      final Future<PayriffResult> future = run.confirm();
      await settleSheet(tester);
      final FakeWebViewController page = web.controller;
      const String bank = 'https://ACS.Bank.example/challenge?session=1';
      Future<void> pumpDialog() =>
          tester.pump(const Duration(milliseconds: 400));

      final Future<void> alert = page.onAlert!(
        const JavaScriptAlertDialogRequest(message: 'Hi', url: bank),
      );
      await pumpDialog();
      expect(find.text('Hi'), findsOneWidget);
      // The host is the title, without the query.
      expect(find.text('acs.bank.example'), findsOneWidget);
      expect(find.textContaining('session=1'), findsNothing);
      expect(find.text('OK'), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
      await tester.tap(find.byKey(jsDialogOkKey));
      await pumpDialog();
      await alert;

      final Future<bool> confirm = page.onConfirm!(
        const JavaScriptConfirmDialogRequest(message: 'Leave?', url: bank),
      );
      await pumpDialog();
      expect(find.text('Cancel'), findsOneWidget);
      await tester.tap(find.byKey(jsDialogCancelKey));
      await pumpDialog();
      expect(await confirm, isFalse);

      final Future<String> prompt = page.onPrompt!(
        const JavaScriptTextInputDialogRequest(
          message: 'Code?',
          url: bank,
          defaultText: '12',
        ),
      );
      await pumpDialog();
      expect(find.text('12'), findsOneWidget);
      await tester.tap(find.byKey(jsDialogOkKey));
      await pumpDialog();
      expect(await prompt, '12');

      // Later dialogs are answered without showing: OK for alert, Cancel for
      // confirm and prompt.
      expect(maxDialogsPerPage, 3);
      await page.onAlert!(
        const JavaScriptAlertDialogRequest(message: 'Loop', url: bank),
      );
      expect(
        await page.onConfirm!(
          const JavaScriptConfirmDialogRequest(message: 'Loop', url: bank),
        ),
        isFalse,
      );
      expect(
        await page.onPrompt!(
          const JavaScriptTextInputDialogRequest(
            message: 'Loop',
            url: bank,
            defaultText: 'x',
          ),
        ),
        '',
      );
      await pumpDialog();
      expect(find.text('Loop'), findsNothing);

      _loadPage(web.delegate, _callback);
      expect(await pumpUntilDone(tester, future), isA<PayriffResultSuccess>());
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('Android keeps the WebView default dialogs on the bank page', (
      WidgetTester tester,
    ) async {
      final _Run run = await _start(
        tester,
        FakeClientBackend(
          payPayload: _challenge(),
          statuses: <String>['APPROVED'],
        ),
      );
      await fillCard(tester);
      final Future<PayriffResult> future = run.confirm();
      await settleSheet(tester);
      expect(web.controller.onAlert, isNull);
      expect(web.controller.onConfirm, isNull);
      expect(web.controller.onPrompt, isNull);
      _loadPage(web.delegate, _callback);
      expect(await pumpUntilDone(tester, future), isA<PayriffResultSuccess>());
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    test('dialogOrigin is the lower-case host of an http(s) frame', () {
      expect(
        dialogOrigin('https://ACS.Bank.example/x?y=1#z'),
        'acs.bank.example',
      );
      expect(dialogOrigin('http://localhost:8080/x'), 'localhost');
      expect(dialogOrigin('about:blank'), isNull);
      expect(dialogOrigin('data:text/html,hi'), isNull);
      expect(dialogOrigin(''), isNull);
    });

    testWidgets('REDIRECT opens the page with a GET', (
      WidgetTester tester,
    ) async {
      final _Run run = await _start(
        tester,
        FakeClientBackend(
          payPayload: <String, Object?>{
            'nextAction': 'REDIRECT',
            'redirectUrl': 'https://bank.example/frictionless?x=1',
          },
          statuses: <String>['APPROVED'],
        ),
      );
      await fillCard(tester);
      final Future<PayriffResult> future = run.confirm();
      await settleSheet(tester);
      final LoadRequestParams load = web.controller.requests.single;
      expect(load.method, LoadRequestMethod.get);
      expect(load.uri.toString(), 'https://bank.example/frictionless?x=1');
      _loadPage(web.delegate, _callback);
      expect(await pumpUntilDone(tester, future), isA<PayriffResultSuccess>());
    });

    testWidgets('another payment while one runs is PAYMENT_IN_PROGRESS', (
      WidgetTester tester,
    ) async {
      final _Run run = await _start(
        tester,
        FakeClientBackend(
          payPayload: _challenge(),
          statuses: <String>['APPROVED'],
        ),
      );
      await fillCard(tester);
      final Future<PayriffResult> future = run.confirm();
      // A second tap in the same frame is refused too.
      expect(
        (await run.confirm()).error?.code,
        PayriffErrorCode.paymentInProgress,
      );
      await settleSheet(tester);
      final PayriffResult second = await run.confirm();
      expect(second.error?.code, PayriffErrorCode.paymentInProgress);
      _loadPage(web.delegate, _callback);
      expect(await pumpUntilDone(tester, future), isA<PayriffResultSuccess>());
    });
  });

  group('3-D Secure website data (CONTRACT §9.1a)', () {
    test('records the host, origin and URL of http(s) pages only', () {
      final ThreeDsWebsiteData data = ThreeDsWebsiteData();
      expect(data.isEmpty, isTrue);
      for (final String url in <String>[
        'https://ACS.Bank.example/challenge?creq=1#top',
        'https://acs.bank.example/challenge',
        'https://user:pw@acs.bank.example:8443/a/b?c=d',
        'http://plain.example',
        'https://acs.bank.example./x',
        'about:blank',
        'data:text/html,hi',
        'birbank://confirm?id=1',
        'javascript:alert(1)',
        'https:///no-host',
        'not a url',
        '',
      ]) {
        data.record(url);
      }
      expect(data.isEmpty, isFalse);
      expect(data.hosts, <String>['acs.bank.example', 'plain.example']);
      expect(data.origins, <String>[
        'https://acs.bank.example',
        'https://acs.bank.example:8443',
        'http://plain.example',
        'https://acs.bank.example.',
      ]);
      // No user info, query or fragment.
      expect(data.urls, <String>[
        'https://acs.bank.example/challenge',
        'https://acs.bank.example:8443/a/b',
        'http://plain.example/',
        'https://acs.bank.example./x',
      ]);
    });

    test('keeps the first maxEntries sites', () {
      final ThreeDsWebsiteData data = ThreeDsWebsiteData();
      for (int i = 0; i < ThreeDsWebsiteData.maxEntries + 10; i++) {
        data.record('https://site$i.example/page');
      }
      expect(data.hosts, hasLength(ThreeDsWebsiteData.maxEntries));
      expect(data.origins, hasLength(ThreeDsWebsiteData.maxEntries));
      expect(data.urls, hasLength(ThreeDsWebsiteData.maxEntries));
      expect(data.hosts.first, 'site0.example');
      expect(
        data.hosts.last,
        'site${ThreeDsWebsiteData.maxEntries - 1}.example',
      );
    });

    test('the sheet records the pages it allows or starts, never a '
        'navigation it cancels', () {
      final ThreeDsSession session = ThreeDsSession(
        apiBaseUrl: 'https://sb-api.payriff.com',
        strings: const PayriffStrings(PayriffLanguage.en),
        openExternal: (String url) async => true,
      );
      addTearDown(session.dispose);
      session.showPage(
        ThreeDsRequest.get(Uri.parse('https://acs.bank.example/challenge')),
      );
      expect(session.websiteData.isEmpty, isTrue, reason: 'nothing loaded');
      expect(
        session.decideNavigation(
          'https://acs.bank.example/next?step=2',
          isMainFrame: true,
        ),
        NavigationDecision.navigate,
      );
      expect(
        session.decideNavigation(
          'https://frames.example/f',
          isMainFrame: false,
        ),
        NavigationDecision.navigate,
      );
      expect(
        session.decideNavigation('http://plain.example/', isMainFrame: true),
        NavigationDecision.prevent,
      );
      expect(
        session.decideNavigation('birbank://confirm', isMainFrame: true),
        NavigationDecision.prevent,
      );
      // Android: the bank's POST to the callback shows only as a page start.
      session.onMainFrameUrl(_callback);
      // The navigation that ends the flow is cancelled before it is sent.
      expect(
        session.decideNavigation(
          'https://merchant.example/return',
          isMainFrame: true,
        ),
        NavigationDecision.prevent,
      );
      expect(session.websiteData.hosts, <String>[
        'acs.bank.example',
        'frames.example',
        'sb-api.payriff.com',
      ]);
    });

    testWidgets('a 3-D Secure payment ends with one clearWebsiteData call for '
        'the sites its WebViews loaded', (WidgetTester tester) async {
      final _Run run = await _start(
        tester,
        FakeClientBackend(
          payPayload: _challenge(),
          statuses: <String>['PENDING', 'APPROVED'],
        ),
      );
      await fillCard(tester);
      final Future<PayriffResult> future = run.confirm();
      await settleSheet(tester);
      final FakeNavigationDelegate delegate = web.delegate;
      _loadPage(delegate, 'https://acs.bank.example/challenge');
      expect(
        await delegate.navigate('https://ACS.bank.example/next?session=1#top'),
        NavigationDecision.navigate,
      );
      expect(
        await delegate.navigate(
          'https://fp.bank-cdn.example:8443/frame?id=2',
          isMainFrame: false,
        ),
        NavigationDecision.navigate,
      );
      // Cancelled navigations never reach a server.
      expect(
        await delegate.navigate('http://plain.example/'),
        NavigationDecision.prevent,
      );
      expect(
        await delegate.navigate('birbank://confirm?id=1'),
        NavigationDecision.prevent,
      );
      expect(run.native.named('clearWebsiteData'), isEmpty);
      expect(await delegate.navigate(_callback), NavigationDecision.navigate);
      _loadPage(delegate, _callback);
      final PayriffResult result = await pumpUntilDone(tester, future);

      expect(result, isA<PayriffResultSuccess>());
      final List<MethodCall> calls = run.native.named('clearWebsiteData');
      expect(calls, hasLength(1));
      expect(calls.single.arguments, <String, Object?>{
        'hosts': <String>[
          'acs.bank.example',
          'fp.bank-cdn.example',
          'sb-api.payriff.com',
        ],
        'origins': <String>[
          'https://acs.bank.example',
          'https://fp.bank-cdn.example:8443',
          'https://sb-api.payriff.com',
        ],
        'urls': <String>[
          'https://acs.bank.example/challenge',
          'https://acs.bank.example/next',
          'https://fp.bank-cdn.example:8443/frame',
          'https://sb-api.payriff.com/api/v3/gateway/kapital/callback/o1',
        ],
      });
    });

    testWidgets('a failing clearWebsiteData leaves the result alone and is '
        'logged at debug level', (WidgetTester tester) async {
      final List<PayriffLogEntry> logs = <PayriffLogEntry>[];
      final StreamSubscription<PayriffLogEntry> sub = Payriff.logStream.listen(
        logs.add,
      );
      addTearDown(sub.cancel);
      final _Run run = await _start(
        tester,
        FakeClientBackend(
          payPayload: _challenge(),
          statuses: <String>['APPROVED'],
        ),
        config: const PayriffConfig(
          environment: PayriffEnvironment.sandbox,
          publishableKey: testPublishableKey,
          enableLogging: true,
        ),
      );
      run.native.clearWebsiteDataFails = true;
      await fillCard(tester);
      final Future<PayriffResult> future = run.confirm();
      await settleSheet(tester);
      _loadPage(web.delegate, _callback);
      final PayriffResult result = await pumpUntilDone(tester, future);

      expect(result, isA<PayriffResultSuccess>());
      expect(run.native.named('clearWebsiteData'), hasLength(1));
      expect(Payriff.isPaymentInProgress, isFalse);
      final List<PayriffLogEntry> failures = logs
          .where(
            (PayriffLogEntry e) => e.message.startsWith(
              'Could not remove the 3-D Secure website data',
            ),
          )
          .toList();
      expect(failures, hasLength(1));
      expect(failures.single.level, PayriffLogLevel.debug);
    });
  });

  group('retrieveOrder', () {
    testWidgets('reads the order with the client headers', (
      WidgetTester tester,
    ) async {
      final _Run run = await _start(tester, FakeClientBackend());
      final PayriffClientOrder order = await Payriff.retrieveOrder(
        orderId: ' o1 ',
        clientSecret: testClientSecret,
      );
      expect(order.orderId, 'o1');
      expect(order.amount, 10.5);
      expect(order.merchantName, 'Test Merchant');
      expect(order.isPayableByCard, isTrue);
      expect(run.backend.requests.single.headers['X-Client-App-Id'], testAppId);
    });

    testWidgets('X-Client-App-Id is omitted when the app id is unknown', (
      WidgetTester tester,
    ) async {
      final _Run run = await _start(tester, FakeClientBackend());
      run.native.appId = null;
      await Payriff.retrieveOrder(
        orderId: 'o1',
        clientSecret: testClientSecret,
      );
      expect(
        run.backend.requests.single.headers.containsKey('X-Client-App-Id'),
        isFalse,
      );
    });

    testWidgets('refuses a missing publishable key and a bad client secret', (
      WidgetTester tester,
    ) async {
      final _Run run = await _start(
        tester,
        FakeClientBackend(),
        config: const PayriffConfig(),
      );
      await expectLater(
        Payriff.retrieveOrder(orderId: 'o1', clientSecret: testClientSecret),
        throwsA(
          isA<PayriffException>().having(
            (PayriffException e) => e.error.code,
            'code',
            PayriffErrorCode.invalidConfig,
          ),
        ),
      );
      Payriff.configure(
        const PayriffConfig(publishableKey: testPublishableKey),
      );
      await expectLater(
        Payriff.retrieveOrder(orderId: 'o1', clientSecret: 'secret'),
        throwsA(
          isA<PayriffException>().having(
            (PayriffException e) => e.error.code,
            'code',
            PayriffErrorCode.invalidOrder,
          ),
        ),
      );
      expect(run.backend.requests, isEmpty);
    });
  });

  testWidgets('an unexpected error after /pay is never a failure: one status '
      'check, else pending', (WidgetTester tester) async {
    NativeCalls().install();
    final FakeClientBackend backend = FakeClientBackend(
      payPayload: _challenge(),
      statuses: <String>['PENDING'],
    )..install();
    final ClientApi api = testClientApi(clock);
    addTearDown(api.close);
    final PayriffResult result = await CardPayment(
      api: api,
      orderId: testOrderId,
      clock: clock,
      strings: const PayriffStrings(PayriffLanguage.en),
      // A bug while opening the 3DS sheet, after the card was sent.
      openSheet: (ThreeDsSession session) => throw StateError('broken'),
    ).run(_testCard);

    expect(
      (result as PayriffResultPending).reason,
      PayriffPendingReason.notFinal,
    );
    expect(backend.to('/pay'), hasLength(1));
    expect(backend.statusChecks, 1);
  });
}
