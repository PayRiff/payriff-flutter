// CONTRACT §17.9, §17.10, §17.12: the wallet row of PayriffPaymentView and
// the standalone PayriffApplePayButton and PayriffGooglePayButton, with a
// fake Client API, a mocked `payriff/native` channel and fake platform views
// (the native buttons' taps are played on their channels). No network.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payriff/payriff.dart';
import 'package:payriff/src/card/card_form.dart';
import 'package:payriff/src/card/payment_view.dart';
import 'package:payriff/src/internal/card/card_clock.dart';

import 'support/card_support.dart';
import 'support/fake_webview.dart';
import 'support/wallet_support.dart';

const String _googleView = 'payriff/google_pay_button';
const String _appleView = 'payriff/apple_pay_button';

const PayriffConfig _cardOnly = PayriffConfig(
  environment: PayriffEnvironment.sandbox,
  publishableKey: testPublishableKey,
);

const PayriffConfig _google = PayriffConfig(
  environment: PayriffEnvironment.sandbox,
  publishableKey: testPublishableKey,
  enableLogging: true,
  googlePay: PayriffGooglePayConfig(),
);

const PayriffConfig _apple = PayriffConfig(
  environment: PayriffEnvironment.sandbox,
  publishableKey: testPublishableKey,
  enableLogging: true,
  applePay: PayriffApplePayConfig(
    merchantIdentifier: 'merchant.com.example.shop',
  ),
);

FakeClientBackend _walletOrder({
  List<String> methods = const <String>['CARD', 'GOOGLE_PAY', 'APPLE_PAY'],
  List<String>? statuses,
}) => FakeClientBackend(
  paymentMethods: methods,
  googlePay: testGooglePayGateway,
  statuses: statuses,
);

final TargetPlatformVariant _ios = TargetPlatformVariant.only(
  TargetPlatform.iOS,
);

class _Screen {
  _Screen(this.native, this.backend, this.views, this.results, this.logs);

  final NativeCalls native;
  final FakeClientBackend backend;
  final FakePlatformViews views;
  final List<PayriffResult> results;
  final List<String> logs;
}

Future<void> _frames(WidgetTester tester, [int count = 10]) async {
  for (int i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Shows [child] (built with the results' sink) as a page body, then pumps
/// until the order and the wallet decision are in.
Future<_Screen> _show(
  WidgetTester tester,
  FakeClientBackend backend, {
  required PayriffConfig config,
  NativeCalls? native,
  Brightness brightness = Brightness.light,
  required Widget Function(ValueChanged<PayriffResult> onResult) child,
}) async {
  final NativeCalls calls = (native ?? NativeCalls())..install();
  backend.install();
  final FakePlatformViews views = FakePlatformViews()..install();
  final List<String> logs = <String>[];
  final StreamSubscription<PayriffLogEntry> sub = Payriff.logStream.listen(
    (PayriffLogEntry e) => logs.add(e.message),
  );
  addTearDown(sub.cancel);
  Payriff.configure(config);
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final List<PayriffResult> results = <PayriffResult>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(body: child(results.add)),
    ),
  );
  await _frames(tester);
  return _Screen(calls, backend, views, results, logs);
}

Future<_Screen> _showView(
  WidgetTester tester,
  FakeClientBackend backend, {
  required PayriffConfig config,
  NativeCalls? native,
  Brightness brightness = Brightness.light,
  PayriffPaymentViewStyle style = const PayriffPaymentViewStyle(),
}) => _show(
  tester,
  backend,
  config: config,
  native: native,
  brightness: brightness,
  child: (ValueChanged<PayriffResult> onResult) => PayriffPaymentView(
    orderId: testOrderId,
    clientSecret: testClientSecret,
    language: PayriffLanguage.en,
    style: style,
    onResult: onResult,
  ),
);

Offset _formTop(WidgetTester tester) =>
    tester.getTopLeft(find.byType(PayriffCardForm));

double _opacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find.descendant(
        of: find.byKey(paymentViewWalletButtonKey),
        matching: find.byType(Opacity),
      ),
    )
    .opacity;

void _expectNoSecrets(Map<Object?, Object?> params) {
  final String text = jsonEncode(params);
  for (final String secret in <String>[testClientSecret, testPublishableKey]) {
    expect(text, isNot(contains(secret)));
  }
}

void main() {
  setUp(() {
    Payriff.debugReset();
    installFakeWebView();
    debugPayriffCardClock = FakeCardClock();
  });

  tearDown(() {
    debugPayriffCardClock = null;
    Payriff.debugReset();
  });

  group('PayriffPaymentView (CONTRACT §17.9)', () {
    testWidgets('without a wallet the §16.14 layout is unchanged; the button '
        'and the divider appear only when the wallet is offered', (
      WidgetTester tester,
    ) async {
      // No wallet configured.
      _Screen screen = await _showView(
        tester,
        _walletOrder(),
        config: _cardOnly,
      );
      final Offset cardOnly = _formTop(tester);
      expect(find.byKey(paymentViewWalletButtonKey), findsNothing);
      expect(find.byKey(paymentViewWalletDividerKey), findsNothing);
      expect(find.text('Or pay by card'), findsNothing);
      expect(screen.views.created, isEmpty);
      expect(find.text('Pay 10.50 AZN'), findsOneWidget);

      // Configured, but not offered: no gateway merchant id on the order or
      // in the configuration (CONTRACT revision 10: paymentMethods is not
      // checked), or Google Pay is not ready on the device.
      for (final (FakeClientBackend backend, NativeCalls native, String line)
          in <(FakeClientBackend, NativeCalls, String)>[
            (
              FakeClientBackend(),
              NativeCalls(),
              'Google Pay offered: false (no gatewayMerchantId)',
            ),
            (
              _walletOrder(),
              NativeCalls()..googlePayReady = false,
              'Google Pay offered: false (Google Pay is not ready on this '
                  'device)',
            ),
          ]) {
        await tester.pumpWidget(const SizedBox.shrink());
        Payriff.debugReset();
        screen = await _showView(
          tester,
          backend,
          config: _google,
          native: native,
        );
        expect(_formTop(tester), cardOnly);
        expect(find.byKey(paymentViewWalletButtonKey), findsNothing);
        expect(find.byKey(paymentViewWalletDividerKey), findsNothing);
        expect(screen.views.created, isEmpty);
        expect(screen.logs.where((String l) => l == line), hasLength(1));
      }

      // Offered.
      await tester.pumpWidget(const SizedBox.shrink());
      Payriff.debugReset();
      screen = await _showView(tester, _walletOrder(), config: _google);
      expect(screen.logs, contains('Google Pay offered: true'));
      expect(find.byKey(paymentViewWalletButtonKey), findsOneWidget);
      expect(find.byKey(paymentViewWalletDividerKey), findsOneWidget);
      expect(find.text('Or pay by card'), findsOneWidget);
      final Rect button = tester.getRect(
        find.byKey(paymentViewWalletButtonKey),
      );
      final Rect divider = tester.getRect(
        find.byKey(paymentViewWalletDividerKey),
      );
      expect(button.top, cardOnly.dy);
      expect(button.height, 44);
      // Full width: the padding of 20 on each side of the 390-wide page.
      expect(button.width, 390 - 40);
      expect(divider.top - button.bottom, 16);
      expect(_formTop(tester).dy - divider.bottom, 16);
      expect(_opacity(tester), 1);

      final CreatedPlatformView view = screen.views.live(_googleView).single;
      expect(view.params['type'], 'PLAIN');
      expect(view.params['theme'], 'DARK');
      expect(view.params['cornerRadius'], 16.0);
      expect(
        jsonDecode(view.params['allowedPaymentMethods']! as String),
        <Object?>[
          <String, Object?>{
            'type': 'CARD',
            'parameters': <String, Object?>{
              'allowedAuthMethods': <String>['PAN_ONLY', 'CRYPTOGRAM_3DS'],
              'allowedCardNetworks': <String>['VISA', 'MASTERCARD'],
            },
            'tokenizationSpecification': <String, Object?>{
              'type': 'PAYMENT_GATEWAY',
              'parameters': testGooglePayGateway,
            },
          },
        ],
      );
      _expectNoSecrets(view.params);
      // CONTRACT §17.3 item 4 asked the device once.
      expect(screen.native.named('googlePayIsReady'), hasLength(1));
    });

    testWidgets('Apple Pay on iOS: PKPaymentButton, black on a light page, '
        'white on a dark one', (WidgetTester tester) async {
      final _Screen screen = await _showView(
        tester,
        _walletOrder(),
        config: _apple,
      );
      expect(screen.logs, contains('Apple Pay offered: true'));
      expect(
        screen.native.named('applePayCanMakePayments').single.arguments,
        <String, Object?>{
          'networks': <String>['visa', 'masterCard'],
          'capabilities': <String>['threeDSecure'],
        },
      );
      CreatedPlatformView view = screen.views.live(_appleView).single;
      expect(view.params, <String, Object?>{
        'type': 'plain',
        'theme': 'black',
        'cornerRadius': 16.0,
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Scaffold(
            body: PayriffPaymentView(
              orderId: testOrderId,
              clientSecret: testClientSecret,
              language: PayriffLanguage.en,
              onResult: (_) {},
            ),
          ),
        ),
      );
      await _frames(tester);
      view = screen.views.live(_appleView).single;
      expect(view.params['theme'], 'white');
      // Google Pay does not exist on iOS.
      expect(screen.views.live(_googleView), isEmpty);
    }, variant: _ios);

    testWidgets('a tap pays with the wallet: the form is locked, Pay shows '
        'its spinner and the button is dimmed; the result goes to onResult', (
      WidgetTester tester,
    ) async {
      final Completer<Object?> sheet = Completer<Object?>();
      final _Screen screen = await _showView(
        tester,
        _walletOrder(statuses: <String>['APPROVED']),
        config: _google,
        native: NativeCalls()..googlePayLoadReply = sheet.future,
      );
      await screen.views.tap(screen.views.live(_googleView).single);
      await tester.pump();
      expect(find.byKey(paymentViewSpinnerKey), findsOneWidget);
      expect(_opacity(tester), 0.5);
      // The form is locked: its fields do not take input.
      final TextField number = tester.widget<TextField>(
        find.byKey(cardNumberFieldKey),
      );
      expect(number.enabled ?? true, isFalse);
      // A second tap while paying does nothing.
      await screen.views.tap(screen.views.live(_googleView).single);
      await tester.pump();
      expect(screen.native.named('googlePayLoad'), hasLength(1));

      sheet.complete(<String, Object?>{
        'status': 'ok',
        'token': testGooglePayToken,
      });
      await _frames(tester);
      expect(screen.results, hasLength(1));
      expect(screen.results.single, isA<PayriffResultSuccess>());
      expect(screen.backend.to('/pay'), hasLength(1));
      // A payment that reached a status is not paid again from the view.
      expect(find.byKey(paymentViewSpinnerKey), findsNothing);
      expect(_opacity(tester), 0.5);
    });

    testWidgets('closing the wallet sheet reports nothing and the view stays '
        'usable', (WidgetTester tester) async {
      final _Screen screen = await _showView(
        tester,
        _walletOrder(),
        config: _google,
        native: NativeCalls()
          ..googlePayLoadReply = <String, Object?>{'status': 'cancelled'},
      );
      await screen.views.tap(screen.views.live(_googleView).single);
      await _frames(tester);
      expect(screen.results, isEmpty);
      expect(screen.backend.to('/pay'), isEmpty);
      expect(_opacity(tester), 1);
      expect(find.byKey(paymentViewSpinnerKey), findsNothing);
      // Card payments still work.
      await fillCard(tester, holder: 'ELLEN CARTER');
      await tester.tap(find.byKey(paymentViewPayButtonKey));
      await _frames(tester);
      expect(screen.results.single, isA<PayriffResultSuccess>());
    });

    testWidgets('WALLET_FAILED goes to onResult and keeps the order payable', (
      WidgetTester tester,
    ) async {
      final _Screen screen = await _showView(
        tester,
        _walletOrder(),
        config: _google,
        native: NativeCalls()
          ..googlePayLoadReply = <String, Object?>{
            'status': 'error',
            'code': 8,
          },
      );
      await screen.views.tap(screen.views.live(_googleView).single);
      await _frames(tester);
      expect(screen.results.single.error?.code, PayriffErrorCode.walletFailed);
      expect(_opacity(tester), 1);
    });

    testWidgets('an order without CARD says so under Pay, and the wallet '
        'button stays usable', (WidgetTester tester) async {
      final _Screen screen = await _showView(
        tester,
        _walletOrder(methods: const <String>['GOOGLE_PAY']),
        config: _google,
      );
      expect(
        tester.widget<Text>(find.byKey(paymentViewErrorKey)).data,
        'This order cannot be paid by card',
      );
      expect(find.byKey(paymentViewWalletButtonKey), findsOneWidget);
      expect(_opacity(tester), 1);
      await screen.views.tap(screen.views.live(_googleView).single);
      await _frames(tester);
      expect(screen.results.single, isA<PayriffResultSuccess>());
    });

    testWidgets('the style: divider text, no divider, the wallet button\'s '
        'height and corners', (WidgetTester tester) async {
      _Screen screen = await _showView(
        tester,
        _walletOrder(),
        config: _google,
        style: const PayriffPaymentViewStyle(
          walletDividerText: '  or with a card ',
          googlePayButton: PayriffGooglePayButtonStyle(
            type: PayriffGooglePayButtonType.pay,
            theme: PayriffGooglePayButtonTheme.light,
            height: 52,
            cornerRadius: 4,
          ),
        ),
      );
      expect(find.text('or with a card'), findsOneWidget);
      expect(tester.getSize(find.byKey(paymentViewWalletButtonKey)).height, 52);
      CreatedPlatformView view = screen.views.live(_googleView).single;
      expect(view.params['type'], 'PAY');
      expect(view.params['theme'], 'LIGHT');
      expect(view.params['cornerRadius'], 4.0);

      // A blank text is the localized one; the view's button metrics are
      // the fallback, and a height below 40 is raised to 40.
      await tester.pumpWidget(const SizedBox.shrink());
      Payriff.debugReset();
      screen = await _showView(
        tester,
        _walletOrder(),
        config: _google,
        style: const PayriffPaymentViewStyle(
          walletDividerText: '  ',
          buttonHeight: 36,
          buttonCornerRadius: 10,
        ),
      );
      expect(find.text('Or pay by card'), findsOneWidget);
      expect(tester.getSize(find.byKey(paymentViewWalletButtonKey)).height, 40);
      view = screen.views.live(_googleView).single;
      expect(view.params['cornerRadius'], 10.0);

      // Without the divider the form follows 16 below the button.
      await tester.pumpWidget(const SizedBox.shrink());
      Payriff.debugReset();
      await _showView(
        tester,
        _walletOrder(),
        config: _google,
        style: const PayriffPaymentViewStyle(showWalletDivider: false),
      );
      expect(find.byKey(paymentViewWalletDividerKey), findsNothing);
      expect(
        _formTop(tester).dy -
            tester.getRect(find.byKey(paymentViewWalletButtonKey)).bottom,
        16,
      );
    });

    testWidgets('the divider in every language', (WidgetTester tester) async {
      for (final (PayriffLanguage language, String text)
          in <(PayriffLanguage, String)>[
            (PayriffLanguage.az, 'Və ya kartla ödəyin'),
            (PayriffLanguage.en, 'Or pay by card'),
            (PayriffLanguage.ru, 'Или оплатите картой'),
          ]) {
        await _show(
          tester,
          _walletOrder(),
          config: _google,
          child: (ValueChanged<PayriffResult> onResult) => PayriffPaymentView(
            orderId: testOrderId,
            clientSecret: testClientSecret,
            language: language,
            onResult: onResult,
          ),
        );
        expect(find.text(text), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        Payriff.debugReset();
      }
    });

    testWidgets('a compromised device offers no wallet', (
      WidgetTester tester,
    ) async {
      final _Screen screen = await _showView(
        tester,
        _walletOrder(),
        config: _google,
        native: NativeCalls()..integrityReply = NativeCalls.compromised(),
      );
      expect(find.byKey(paymentViewWalletButtonKey), findsNothing);
      expect(screen.views.created, isEmpty);
      expect(screen.native.named('googlePayIsReady'), isEmpty);
      expect(
        screen.results.single.error?.code,
        PayriffErrorCode.deviceCompromised,
      );
    });
  });

  group('revision 10: the configuration decides, on its own platform', () {
    testWidgets('a card-only order without googlePay offers Google Pay with '
        'the configuration\'s gatewayMerchantId', (WidgetTester tester) async {
      final _Screen screen = await _showView(
        tester,
        FakeClientBackend(),
        config: const PayriffConfig(
          environment: PayriffEnvironment.sandbox,
          publishableKey: testPublishableKey,
          enableLogging: true,
          googlePay: PayriffGooglePayConfig(gatewayMerchantId: ' PRF0001 '),
        ),
      );
      expect(screen.logs, contains('Google Pay offered: true'));
      expect(find.byKey(paymentViewWalletButtonKey), findsOneWidget);
      final CreatedPlatformView view = screen.views.live(_googleView).single;
      expect(
        jsonDecode(view.params['allowedPaymentMethods']! as String),
        <Object?>[
          <String, Object?>{
            'type': 'CARD',
            'parameters': <String, Object?>{
              'allowedAuthMethods': <String>['PAN_ONLY', 'CRYPTOGRAM_3DS'],
              'allowedCardNetworks': <String>['VISA', 'MASTERCARD'],
            },
            'tokenizationSpecification': <String, Object?>{
              'type': 'PAYMENT_GATEWAY',
              'parameters': <String, Object?>{
                'gateway': 'payriff',
                'gatewayMerchantId': 'PRF0001',
              },
            },
          },
        ],
      );
      await screen.views.tap(view);
      await _frames(tester);
      expect(screen.results.single, isA<PayriffResultSuccess>());
      final Map<String, Object?> request =
          jsonDecode(
                (screen.native.named('googlePayLoad').single.arguments
                        as Map<Object?, Object?>)['request']!
                    as String,
              )
              as Map<String, Object?>;
      expect(
        ((request['allowedPaymentMethods']! as List<Object?>).single
            as Map<String, Object?>)['tokenizationSpecification'],
        <String, Object?>{
          'type': 'PAYMENT_GATEWAY',
          'parameters': <String, Object?>{
            'gateway': 'payriff',
            'gatewayMerchantId': 'PRF0001',
          },
        },
      );
    });

    testWidgets('Android: a configured Apple Pay never appears', (
      WidgetTester tester,
    ) async {
      final List<bool> availability = <bool>[];
      _Screen screen = await _showView(tester, _walletOrder(), config: _apple);
      expect(find.byKey(paymentViewWalletButtonKey), findsNothing);
      expect(find.byKey(paymentViewWalletDividerKey), findsNothing);
      expect(screen.views.created, isEmpty);
      expect(screen.native.named('applePayCanMakePayments'), isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      Payriff.debugReset();
      screen = await _show(
        tester,
        _walletOrder(),
        config: _apple,
        child: (ValueChanged<PayriffResult> onResult) => PayriffApplePayButton(
          key: const ValueKey<String>('apple'),
          orderId: testOrderId,
          clientSecret: testClientSecret,
          onAvailabilityChange: availability.add,
          onResult: onResult,
        ),
      );
      expect(availability, <bool>[false]);
      expect(
        tester.getSize(find.byKey(const ValueKey<String>('apple'))),
        Size.zero,
      );
      expect(screen.views.created, isEmpty);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('iOS: a configured Google Pay never appears', (
      WidgetTester tester,
    ) async {
      final List<bool> availability = <bool>[];
      _Screen screen = await _showView(tester, _walletOrder(), config: _google);
      expect(find.byKey(paymentViewWalletButtonKey), findsNothing);
      expect(screen.views.created, isEmpty);
      expect(screen.native.named('googlePayIsReady'), isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      Payriff.debugReset();
      screen = await _show(
        tester,
        _walletOrder(),
        config: _google,
        child: (ValueChanged<PayriffResult> onResult) => PayriffGooglePayButton(
          key: const ValueKey<String>('google'),
          orderId: testOrderId,
          clientSecret: testClientSecret,
          onAvailabilityChange: availability.add,
          onResult: onResult,
        ),
      );
      expect(availability, <bool>[false]);
      expect(
        tester.getSize(find.byKey(const ValueKey<String>('google'))),
        Size.zero,
      );
      expect(screen.views.created, isEmpty);
    }, variant: _ios);
  });

  group('standalone buttons (CONTRACT §17.10)', () {
    Widget google(
      ValueChanged<PayriffResult> onResult,
      List<bool> availability, {
      PayriffGooglePayButtonStyle style = const PayriffGooglePayButtonStyle(),
    }) => Column(
      children: <Widget>[
        PayriffGooglePayButton(
          key: const ValueKey<String>('google'),
          orderId: testOrderId,
          clientSecret: testClientSecret,
          style: style,
          onAvailabilityChange: availability.add,
          onResult: onResult,
        ),
        PayriffApplePayButton(
          key: const ValueKey<String>('apple'),
          orderId: testOrderId,
          clientSecret: testClientSecret,
          onResult: onResult,
        ),
      ],
    );

    testWidgets('PayriffGooglePayButton: offered, it appears 44 high; a tap '
        'pays and reports the result. Apple Pay renders nothing on Android', (
      WidgetTester tester,
    ) async {
      final List<bool> availability = <bool>[];
      final _Screen screen = await _show(
        tester,
        _walletOrder(),
        config: _google,
        child: (ValueChanged<PayriffResult> onResult) =>
            google(onResult, availability),
      );
      expect(availability, <bool>[true]);
      expect(
        tester.getSize(find.byKey(const ValueKey<String>('google'))),
        const Size(390, 44),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey<String>('apple'))),
        Size.zero,
      );
      final CreatedPlatformView view = screen.views.live(_googleView).single;
      expect(view.params['cornerRadius'], 16.0);
      _expectNoSecrets(view.params);
      expect(screen.views.live(_appleView), isEmpty);

      await screen.views.tap(view);
      await _frames(tester);
      expect(screen.results.single, isA<PayriffResultSuccess>());
      expect(screen.backend.to('/pay'), hasLength(1));
    });

    testWidgets('not offered: zero size and onAvailabilityChange(false)', (
      WidgetTester tester,
    ) async {
      final List<bool> availability = <bool>[];
      // No gateway merchant id on the order or in the configuration
      // (CONTRACT revision 10).
      final _Screen screen = await _show(
        tester,
        FakeClientBackend(),
        config: _google,
        child: (ValueChanged<PayriffResult> onResult) =>
            google(onResult, availability),
      );
      expect(availability, <bool>[false]);
      expect(
        tester.getSize(find.byKey(const ValueKey<String>('google'))),
        Size.zero,
      );
      expect(screen.views.created, isEmpty);
    });

    testWidgets('closing the sheet: cancelled(userClosed) with the order id '
        'and an unknown status', (WidgetTester tester) async {
      final List<bool> availability = <bool>[];
      final _Screen screen = await _show(
        tester,
        _walletOrder(),
        config: _google,
        native: NativeCalls()
          ..googlePayLoadReply = <String, Object?>{'status': 'cancelled'},
        child: (ValueChanged<PayriffResult> onResult) =>
            google(onResult, availability),
      );
      await screen.views.tap(screen.views.live(_googleView).single);
      await _frames(tester);
      expect(
        screen.results.single,
        const PayriffResultCancelled(
          reason: PayriffCancelReason.userClosed,
          payment: PayriffPayment(orderId: testOrderId),
        ),
      );
      expect(
        screen.results.single.payment?.status,
        PayriffPaymentStatus.unknown,
      );
    });

    testWidgets('a device refused on tap makes the button unavailable', (
      WidgetTester tester,
    ) async {
      final List<bool> availability = <bool>[];
      final NativeCalls native = NativeCalls();
      final _Screen screen = await _show(
        tester,
        _walletOrder(),
        config: _google,
        native: native,
        child: (ValueChanged<PayriffResult> onResult) =>
            google(onResult, availability),
      );
      native.integrityReply = NativeCalls.compromised(<String>['Frida']);
      await screen.views.tap(screen.views.live(_googleView).single);
      await _frames(tester);
      expect(
        screen.results.single.error?.code,
        PayriffErrorCode.deviceCompromised,
      );
      expect(availability, <bool>[true, false]);
      expect(
        tester.getSize(find.byKey(const ValueKey<String>('google'))),
        Size.zero,
      );
    });

    testWidgets('PayriffApplePayButton on iOS: offered and paid; Google Pay '
        'renders nothing there', (WidgetTester tester) async {
      final List<bool> availability = <bool>[];
      final _Screen screen = await _show(
        tester,
        _walletOrder(),
        config: _apple,
        child: (ValueChanged<PayriffResult> onResult) => Column(
          children: <Widget>[
            PayriffApplePayButton(
              key: const ValueKey<String>('apple'),
              orderId: testOrderId,
              clientSecret: testClientSecret,
              style: const PayriffApplePayButtonStyle(
                type: PayriffApplePayButtonType.buy,
                height: 50,
              ),
              onAvailabilityChange: availability.add,
              onResult: onResult,
            ),
            PayriffGooglePayButton(
              key: const ValueKey<String>('google'),
              orderId: testOrderId,
              clientSecret: testClientSecret,
              onAvailabilityChange: availability.add,
              onResult: onResult,
            ),
          ],
        ),
      );
      expect(availability, unorderedEquals(<bool>[true, false]));
      expect(
        tester.getSize(find.byKey(const ValueKey<String>('apple'))).height,
        50,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey<String>('google'))),
        Size.zero,
      );
      final CreatedPlatformView view = screen.views.live(_appleView).single;
      expect(view.params, <String, Object?>{
        'type': 'buy',
        'theme': 'black',
        'cornerRadius': 16.0,
      });
      await screen.views.tap(view);
      await _frames(tester);
      expect(screen.results.single, isA<PayriffResultSuccess>());
      expect(
        screen.native
            .named('applePayComplete')
            .map<Object?>(
              (MethodCall c) =>
                  (c.arguments as Map<Object?, Object?>)['status'],
            ),
        <Object?>['success'],
      );
    }, variant: _ios);
  });
}
