// CONTRACT §17.9, §17.10, §17.12: the wallet row of PayriffPaymentView and
// the standalone PayriffApplePayButton and PayriffGooglePayButton, with a
// fake Client API, a mocked `payriff/native` channel and fake platform views
// (the native buttons' taps are played on their channels). No network.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
/// until the order and the wallet decision are in, unless [settle] is
/// `false`. [textScaler] replaces the device's text scale.
Future<_Screen> _show(
  WidgetTester tester,
  FakeClientBackend backend, {
  required PayriffConfig config,
  NativeCalls? native,
  Brightness brightness = Brightness.light,
  TextScaler? textScaler,
  bool settle = true,
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
      builder: textScaler == null
          ? null
          : (BuildContext context, Widget? page) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: textScaler),
              child: page!,
            ),
      home: Scaffold(body: child(results.add)),
    ),
  );
  if (settle) await _frames(tester);
  return _Screen(calls, backend, views, results, logs);
}

Future<_Screen> _showView(
  WidgetTester tester,
  FakeClientBackend backend, {
  required PayriffConfig config,
  NativeCalls? native,
  Brightness brightness = Brightness.light,
  TextScaler? textScaler,
  PayriffPaymentViewStyle style = const PayriffPaymentViewStyle(),
}) => _show(
  tester,
  backend,
  config: config,
  native: native,
  brightness: brightness,
  textScaler: textScaler,
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

double _height(WidgetTester tester, Key key) =>
    tester.getSize(find.byKey(key)).height;

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
      // CONTRACT §20.3: the device check starts with the view, alongside
      // the integrity check; its answer is not used.
      expect(screen.native.named('googlePayIsReady'), hasLength(1));
      expect(screen.backend.requests, isEmpty);
      expect(
        screen.results.single.error?.code,
        PayriffErrorCode.deviceCompromised,
      );
    });
  });

  group('revision 11: placement, height and reveal (CONTRACT §20)', () {
    // The parts of `wallet.json` → `viewPlacement` in the view.
    final Map<String, Finder> parts = <String, Finder>{
      'walletButton': find.byKey(paymentViewWalletButtonKey),
      'walletDivider': find.byKey(paymentViewWalletDividerKey),
      'form': find.byType(PayriffCardForm),
      'payButton': find.byKey(paymentViewPayButtonKey),
      'error': find.byKey(paymentViewErrorKey),
      'badges': find.byKey(paymentViewBadgesKey),
      'secureNote': find.byKey(paymentViewSecureKey),
    };

    testWidgets('viewPlacement: every case laid out, with its parts in order '
        'and the gaps between them', (WidgetTester tester) async {
      final Map<String, Object?> section =
          walletVectors()['viewPlacement']! as Map<String, Object?>;
      for (final Map<String, Object?> c
          in (section['cases']! as List<Object?>)
              .cast<Map<String, Object?>>()) {
        final Map<String, Object?> style = c['style']! as Map<String, Object?>;
        await tester.pumpWidget(const SizedBox.shrink());
        Payriff.debugReset();
        await _showView(
          tester,
          // An order without CARD shows the error line; the wallet stays.
          _walletOrder(
            methods: c['errorShown'] == true
                ? const <String>['GOOGLE_PAY']
                : const <String>['CARD', 'GOOGLE_PAY'],
          ),
          config: _google,
          // Configured but not offered: the device cannot pay.
          native: NativeCalls()..googlePayReady = c['walletShown']! as bool,
          style: PayriffPaymentViewStyle(
            walletPlacement: PayriffWalletPlacement.values.byName(
              style['walletPlacement']! as String,
            ),
            showWalletDivider: style['showWalletDivider']! as bool,
            showBadges: style['showBadges']! as bool,
            showSecureNote: style['showSecureNote']! as bool,
          ),
        );
        final List<Map<String, Object?>> expected =
            (c['expect']! as List<Object?>).cast<Map<String, Object?>>();
        final Set<String> shown = <String>{
          for (final Map<String, Object?> e in expected) e['part']! as String,
        };
        for (final MapEntry<String, Finder> p in parts.entries) {
          expect(
            p.value,
            shown.contains(p.key) ? findsOneWidget : findsNothing,
            reason: '${c['name']}: ${p.key}',
          );
        }
        // The content starts inside the view's padding of 20.
        double bottom = 20;
        for (final Map<String, Object?> e in expected) {
          final Rect rect = tester.getRect(parts[e['part']! as String]!);
          expect(
            rect.top - bottom,
            moreOrLessEquals((e['gapAbove']! as num).toDouble()),
            reason: '${c['name']}: ${e['part']}',
          );
          bottom = rect.bottom;
        }
      }
    });

    testWidgets('viewWalletHeight: without a style height the wallet button '
        'is as high as Pay at text scale 1 and 3, also with a long title, '
        'which stays one line and is truncated; in both placements', (
      WidgetTester tester,
    ) async {
      const String longTitle =
          'Pay for the whole order now with your bank card, safely and fast';
      for (final PayriffWalletPlacement placement
          in PayriffWalletPlacement.values) {
        for (final double scale in <double>[1, 3]) {
          final Map<String?, double> pays = <String?, double>{};
          for (final String? title in <String?>[null, longTitle]) {
            final String reason =
                '${placement.name}, text scale $scale, '
                '${title == null ? 'the amount' : 'a long title'}';
            await tester.pumpWidget(const SizedBox.shrink());
            Payriff.debugReset();
            await _showView(
              tester,
              _walletOrder(),
              config: _google,
              textScaler: TextScaler.linear(scale),
              style: PayriffPaymentViewStyle(
                walletPlacement: placement,
                payButtonTitle: title,
              ),
            );
            final double pay = _height(tester, paymentViewPayButtonKey);
            expect(
              _height(tester, paymentViewWalletButtonKey),
              pay,
              reason: reason,
            );
            expect(pay, scale == 1 ? 44 : greaterThan(44), reason: reason);
            pays[title] = pay;
            final Finder text = find.descendant(
              of: find.byKey(paymentViewPayButtonKey),
              matching: find.byType(Text),
            );
            expect(tester.widget<Text>(text).maxLines, 1, reason: reason);
            if (title != null) {
              final RenderParagraph paragraph = tester
                  .renderObject<RenderParagraph>(
                    find.descendant(of: text, matching: find.byType(RichText)),
                  );
              expect(paragraph.didExceedMaxLines, isTrue, reason: reason);
            }
          }
          // One line: the long title does not make Pay taller.
          expect(pays[longTitle], pays[null], reason: '$placement, $scale');
        }
      }
    });

    testWidgets('the wallet button follows Pay while Pay shows its spinner', (
      WidgetTester tester,
    ) async {
      final Completer<Object?> sheet = Completer<Object?>();
      final _Screen screen = await _showView(
        tester,
        _walletOrder(),
        config: _google,
        native: NativeCalls()..googlePayLoadReply = sheet.future,
        textScaler: const TextScaler.linear(3),
      );
      final double idle = _height(tester, paymentViewPayButtonKey);
      expect(idle, greaterThan(44));
      expect(_height(tester, paymentViewWalletButtonKey), idle);
      await screen.views.tap(screen.views.live(_googleView).single);
      await tester.pump();
      // Only Pay's spinner is found: the copy under the wallet is offstage.
      expect(find.byKey(paymentViewSpinnerKey), findsOneWidget);
      // The 20-high spinner needs less than the large title.
      expect(_height(tester, paymentViewPayButtonKey), 44);
      expect(_height(tester, paymentViewWalletButtonKey), 44);
      sheet.complete(<String, Object?>{'status': 'cancelled'});
      await _frames(tester);
      expect(find.byKey(paymentViewSpinnerKey), findsNothing);
      expect(_height(tester, paymentViewPayButtonKey), idle);
      expect(_height(tester, paymentViewWalletButtonKey), idle);
    });

    testWidgets('a wallet style height stays fixed at large text, raised to '
        '40', (WidgetTester tester) async {
      for (final (double styleHeight, double expected) in <(double, double)>[
        (56, 56),
        (30, 40),
      ]) {
        await tester.pumpWidget(const SizedBox.shrink());
        Payriff.debugReset();
        await _showView(
          tester,
          _walletOrder(),
          config: _google,
          textScaler: const TextScaler.linear(3),
          style: PayriffPaymentViewStyle(
            walletPlacement: PayriffWalletPlacement.belowPayButton,
            googlePayButton: PayriffGooglePayButtonStyle(height: styleHeight),
          ),
        );
        expect(_height(tester, paymentViewPayButtonKey), greaterThan(56));
        expect(_height(tester, paymentViewWalletButtonKey), expected);
      }
    });

    testWidgets('the copy of Pay under the wallet button is not seen: no '
        'second text, no semantics, no touches', (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      final _Screen screen = await _showView(
        tester,
        _walletOrder(),
        config: _google,
      );
      expect(find.text('Pay 10.50 AZN'), findsOneWidget);
      expect(find.bySemanticsLabel('Pay 10.50 AZN'), findsOneWidget);
      // Paid: the wallet button is disabled and lets touches through, to
      // the copy of Pay's title under it, which takes none.
      await screen.views.tap(screen.views.live(_googleView).single);
      await _frames(tester);
      expect(screen.results.single, isA<PayriffResultSuccess>());
      expect(_opacity(tester), 0.5);
      final HitTestResult hit = tester.hitTestOnBinding(
        tester.getCenter(find.byKey(paymentViewWalletButtonKey)),
      );
      expect(
        hit.path.map((HitTestEntry e) => e.target).whereType<RenderParagraph>(),
        isEmpty,
      );
      expect(find.text('Pay 10.50 AZN'), findsOneWidget);
      expect(find.bySemanticsLabel('Pay 10.50 AZN'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('no AnimatedSize or other implicit animation around the '
        'wallet button', (WidgetTester tester) async {
      bool animated(Widget w) =>
          w is AnimatedSize ||
          w is ImplicitlyAnimatedWidget ||
          w is AnimatedSwitcher ||
          w is AnimatedCrossFade ||
          w is FadeTransition ||
          (w is AnimatedWidget && w is! ListenableBuilder);
      for (final PayriffWalletPlacement placement
          in PayriffWalletPlacement.values) {
        await tester.pumpWidget(const SizedBox.shrink());
        Payriff.debugReset();
        await _showView(
          tester,
          _walletOrder(),
          config: _google,
          style: PayriffPaymentViewStyle(walletPlacement: placement),
        );
        expect(
          find.descendant(
            of: find.byType(PayriffPaymentView),
            matching: find.byType(AnimatedSize),
          ),
          findsNothing,
        );
        // Up to the view. The view's Material follows a theme change of its
        // text style with an AnimatedDefaultTextStyle, for the whole view;
        // it neither moves nor fades anything.
        final List<Type> around = <Type>[];
        tester
            .element(find.byKey(paymentViewWalletButtonKey))
            .visitAncestorElements((Element e) {
              if (e.widget is PayriffPaymentView) return false;
              if (animated(e.widget) && e.widget is! AnimatedDefaultTextStyle) {
                around.add(e.widget.runtimeType);
              }
              return true;
            });
        expect(around, isEmpty, reason: placement.name);
        expect(
          find.descendant(
            of: find.byKey(paymentViewWalletButtonKey),
            matching: find.byWidgetPredicate(animated),
          ),
          findsNothing,
        );
      }
    });

    testWidgets('the order and the wallet appear in the same frame, then '
        'onOrderLoaded; the check was asked before the order answered', (
      WidgetTester tester,
    ) async {
      // The order answers at 500 ms, the device check 300 ms later.
      final FakeClientBackend backend = _walletOrder()
        ..orderDelay = const Duration(milliseconds: 500);
      final List<(bool, bool)> loaded = <(bool, bool)>[];
      bool amount() => find.text('Pay 10.50 AZN').evaluate().isNotEmpty;
      bool wallet() =>
          find.byKey(paymentViewWalletButtonKey).evaluate().isNotEmpty;
      final _Screen screen = await _show(
        tester,
        backend,
        config: _google,
        native: NativeCalls()
          ..deviceCheckDelay = const Duration(milliseconds: 800),
        settle: false,
        child: (ValueChanged<PayriffResult> onResult) => PayriffPaymentView(
          orderId: testOrderId,
          clientSecret: testClientSecret,
          language: PayriffLanguage.en,
          onResult: onResult,
          // Called after the update, before its frame is drawn.
          onOrderLoaded: (_) => loaded.add((amount(), wallet())),
        ),
      );
      expect(screen.native.named('googlePayIsReady'), hasLength(1));
      expect(backend.ordersAnswered, 0);
      final List<(bool, bool)> frames = <(bool, bool)>[];
      for (int i = 0; i < 24; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        frames.add((amount(), wallet()));
      }
      // Frame 16 is drawn at 800 ms: the first with the order, and it has
      // the wallet.
      expect(frames.indexWhere(((bool, bool) f) => f.$1), 15);
      expect(frames.sublist(0, 15), everyElement((false, false)));
      expect(frames.sublist(15), everyElement((true, true)));
      expect(loaded, <(bool, bool)>[(false, false)]);
      expect(screen.views.created, hasLength(1));
    });

    testWidgets('a slow device check: the order shows without the wallet 1 s '
        'after it arrived, and the late answer is ignored', (
      WidgetTester tester,
    ) async {
      final _Screen screen = await _show(
        tester,
        _walletOrder()..orderDelay = const Duration(milliseconds: 500),
        config: _google,
        // Answers 2 s after the order.
        native: NativeCalls()
          ..deviceCheckDelay = const Duration(milliseconds: 2500),
        settle: false,
        child: (ValueChanged<PayriffResult> onResult) => PayriffPaymentView(
          orderId: testOrderId,
          clientSecret: testClientSecret,
          language: PayriffLanguage.en,
          onResult: onResult,
        ),
      );
      await tester.pump(const Duration(milliseconds: 1499));
      expect(find.text('Pay 10.50 AZN'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('Pay 10.50 AZN'), findsOneWidget);
      expect(find.byKey(paymentViewWalletButtonKey), findsNothing);
      expect(
        screen.logs,
        contains(
          'Google Pay offered: false (the device check did not answer in '
          'time)',
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      expect(find.byKey(paymentViewWalletButtonKey), findsNothing);
      expect(find.byKey(paymentViewWalletDividerKey), findsNothing);
      expect(screen.views.created, isEmpty);
      expect(
        screen.logs.where((String l) => l.startsWith('Google Pay offered')),
        hasLength(1),
      );
      // Card payments are unaffected.
      await fillCard(tester, holder: 'ELLEN CARTER');
      await tester.tap(find.byKey(paymentViewPayButtonKey));
      await _frames(tester);
      expect(screen.results.single, isA<PayriffResultSuccess>());
    });

    testWidgets('a failed order read does not wait for the device check', (
      WidgetTester tester,
    ) async {
      final List<PayriffError> failures = <PayriffError>[];
      await _show(
        tester,
        _walletOrder()
          ..orderDelay = const Duration(milliseconds: 500)
          ..orderFails = true,
        config: _google,
        native: NativeCalls()..deviceCheckDelay = null,
        settle: false,
        child: (ValueChanged<PayriffResult> onResult) => PayriffPaymentView(
          orderId: testOrderId,
          clientSecret: testClientSecret,
          language: PayriffLanguage.en,
          onResult: onResult,
          onLoadFailed: failures.add,
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(failures.single.code, PayriffErrorCode.networkError);
      expect(find.byKey(paymentViewErrorKey), findsOneWidget);
      expect(find.byKey(paymentViewWalletButtonKey), findsNothing);
    });

    testWidgets('the form keeps what was typed when the wallet, the divider '
        'and the error line come and go', (WidgetTester tester) async {
      Widget view(String secret) => PayriffPaymentView(
        orderId: testOrderId,
        clientSecret: secret,
        language: PayriffLanguage.en,
        onResult: (_) {},
      );
      String number() => tester
          .widget<TextField>(find.byKey(cardNumberFieldKey))
          .controller!
          .text;
      // An order without CARD: the wallet and the divider above the form,
      // the error line under Pay.
      await _show(
        tester,
        _walletOrder(methods: const <String>['GOOGLE_PAY'])
          ..orderDelay = const Duration(milliseconds: 500),
        config: _google,
        settle: false,
        child: (_) => view(testClientSecret),
      );
      await tester.enterText(
        find.byKey(cardNumberFieldKey),
        '4111111111111111',
      );
      await _frames(tester);
      expect(find.byKey(paymentViewWalletButtonKey), findsOneWidget);
      expect(find.byKey(paymentViewErrorKey), findsOneWidget);
      expect(number(), '4111 1111 1111 1111');
      // A new client secret: the parts go while the order loads again, and
      // come back with it.
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: view('${testClientSecret}2'))),
      );
      expect(find.byKey(paymentViewWalletButtonKey), findsNothing);
      expect(find.byKey(paymentViewErrorKey), findsNothing);
      expect(number(), '4111 1111 1111 1111');
      await _frames(tester);
      expect(find.byKey(paymentViewWalletButtonKey), findsOneWidget);
      expect(number(), '4111 1111 1111 1111');
    });

    testWidgets('a new client secret while the first order waits for the '
        'device check: only the new order shows, once, with its wallet', (
      WidgetTester tester,
    ) async {
      final List<String> loaded = <String>[];
      final NativeCalls native = NativeCalls()
        ..deviceCheckDelay = const Duration(milliseconds: 800);
      Widget view(String secret) => PayriffPaymentView(
        orderId: testOrderId,
        clientSecret: secret,
        language: PayriffLanguage.en,
        onResult: (_) {},
        onOrderLoaded: (_) => loaded.add(secret),
      );
      final _Screen screen = await _show(
        tester,
        _walletOrder()..orderDelay = const Duration(milliseconds: 500),
        config: _google,
        native: native,
        settle: false,
        child: (_) => view(testClientSecret),
      );
      // The first order arrived and waits for the device check.
      await tester.pump(const Duration(milliseconds: 600));
      expect(loaded, isEmpty);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: view('${testClientSecret}2'))),
      );
      await tester.pump(const Duration(seconds: 3));
      expect(loaded, <String>['${testClientSecret}2']);
      expect(find.byKey(paymentViewWalletButtonKey), findsOneWidget);
      expect(screen.views.live(_googleView), hasLength(1));
      // A device check and a decision per read; the first read's decision
      // is dropped.
      expect(native.named('googlePayIsReady'), hasLength(2));
      expect(
        screen.logs.where((String l) => l == 'Google Pay offered: true'),
        hasLength(2),
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
