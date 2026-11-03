// CONTRACT §19.2–§19.4 (revision 9, Payriff.js 1.3.1): mada cards and their
// brand mark, Arabic with the right-to-left layout (form, payment view and
// 3-D Secure sheet), the device language in region sa, and mada for Apple
// Pay in region sa. A fake Client API, a fake WebView and a mocked
// `payriff/native` channel. No network.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payriff/payriff.dart';
import 'package:payriff/src/card/card_form.dart';
import 'package:payriff/src/card/payment_view.dart';
import 'package:payriff/src/internal/card/card_clock.dart';
import 'package:payriff/src/internal/language.dart';
import 'package:payriff/src/internal/logger.dart';
import 'package:payriff/src/internal/ui/presenter.dart';
import 'package:payriff/src/internal/ui/sheet.dart';
import 'package:payriff/src/internal/wallet/wallet_payment.dart';
import 'package:payriff/src/internal/wallet/wallet_rules.dart';

import 'support/card_support.dart';
import 'support/fake_webview.dart';

const PayriffConfig _config = PayriffConfig(
  environment: PayriffEnvironment.sandbox,
  publishableKey: testPublishableKey,
);

Future<void> _frames(WidgetTester tester, [int count = 10]) async {
  for (int i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Rect _rect(WidgetTester tester, Key key) => tester.getRect(find.byKey(key));

TextDirection _laidOut(WidgetTester tester, Key key) => tester
    .state<EditableTextState>(
      find.descendant(of: find.byKey(key), matching: find.byType(EditableText)),
    )
    .renderEditable
    .textDirection;

Map<String, Object?> _challenge() => <String, Object?>{
  'orderId': testOrderId,
  'nextAction': 'THREE_DS',
  'channel': 'KAPITAL',
  'accessUrl': 'https://acs.bank.example/challenge',
  'clientRequest': <Object?>[
    <String, Object?>{'key': 'creq', 'value': 'CREQ'},
  ],
};

void main() {
  setUp(Payriff.debugReset);
  tearDown(() {
    debugPayriffCardClock = null;
    Payriff.debugReset();
  });

  group('mada (CONTRACT §19.2)', () {
    testWidgets('a co-badged card shows Visa, then mada once its BIN is '
        'typed; the mark is the mada drawing in the usual badge', (
      WidgetTester tester,
    ) async {
      NativeCalls().install();
      final PayriffCardController controller = PayriffCardController();
      addTearDown(controller.dispose);
      final SemanticsHandle semantics = tester.ensureSemantics();
      await pumpCardApp(tester, controller);
      await tester.enterText(find.byKey(cardNumberFieldKey), '40302');
      await tester.pumpAndSettle();
      expect(controller.brand, PayriffCardBrand.visa);
      expect(find.byKey(const ValueKey<String>('visa')), findsOneWidget);

      await tester.enterText(find.byKey(cardNumberFieldKey), '403024');
      await tester.pumpAndSettle();
      expect(controller.brand, PayriffCardBrand.mada);
      final Finder mark = find.byKey(const ValueKey<String>('mada'));
      expect(mark, findsOneWidget);
      expect(tester.getSize(mark), const Size(36, 24));
      expect(
        (tester
                    .widget<DecoratedBox>(
                      find.descendant(
                        of: mark,
                        matching: find.byType(DecoratedBox),
                      ),
                    )
                    .decoration
                as BoxDecoration)
            .border,
        Border.all(color: const Color(0xFFD1D1D6)),
      );
      expect(tester.getSemantics(find.byKey(cardBrandKey)).label, 'mada');

      await tester.enterText(
        find.byKey(cardNumberFieldKey),
        '4030240000000008',
      );
      await tester.pump();
      expect(controller.brand, PayriffCardBrand.mada);
      semantics.dispose();
    });

    testWidgets('a mada-only BIN being typed is incomplete, not '
        'unsupported', (WidgetTester tester) async {
      NativeCalls().install();
      final PayriffCardController controller = PayriffCardController();
      addTearDown(controller.dispose);
      await pumpCardApp(tester, controller, showHolder: false);
      await tester.enterText(find.byKey(cardNumberFieldKey), '9682');
      // Leave the field: an incomplete number now shows its error.
      await tester.enterText(find.byKey(cardExpiryFieldKey), '12');
      await tester.pump();
      expect(
        tester
            .widget<Text>(find.byKey(cardErrorKey(cardInformationSection)))
            .data,
        'Card number is incomplete',
      );
      await tester.enterText(
        find.byKey(cardNumberFieldKey),
        '5043000000000008',
      );
      await tester.enterText(find.byKey(cardExpiryFieldKey), '1230');
      await tester.enterText(find.byKey(cardCvvFieldKey), '123');
      await tester.pump();
      expect(controller.brand, PayriffCardBrand.mada);
      expect(controller.isComplete, isTrue);
    });

    testWidgets('the payment view\'s badge row stays Mastercard and Visa', (
      WidgetTester tester,
    ) async {
      NativeCalls().install();
      FakeClientBackend().install();
      Payriff.configure(_config);
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
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
      await _frames(tester, 5);
      await tester.enterText(find.byKey(cardNumberFieldKey), '403024');
      await tester.pumpAndSettle();
      expect(find.byKey(paymentViewBadgeKey('mastercard')), findsOneWidget);
      expect(find.byKey(paymentViewBadgeKey('visa')), findsOneWidget);
      expect(find.byKey(paymentViewBadgeKey('mada')), findsNothing);
      expect(PaymentViewAssets.all, hasLength(4));
    });
  });

  group('Arabic and right to left (CONTRACT §19.3)', () {
    test('the device language: ar, and Arabic for other languages in '
        'region sa', () {
      expect(languageForLocaleTag('ar-SA'), PayriffLanguage.ar);
      expect(languageForLocaleTag('tr-TR'), PayriffLanguage.en);
      expect(
        languageForLocaleTag('tr-TR', region: PayriffRegion.sa),
        PayriffLanguage.ar,
      );
      expect(
        languageForLocaleTag('en-US', region: PayriffRegion.sa),
        PayriffLanguage.en,
      );
      expect(PayriffLanguage.ar.value, 'AR');
    });

    testWidgets('a form in Arabic is right to left in a left-to-right app; '
        'the number, expiry and CVC stay left to right with Latin '
        'placeholders', (WidgetTester tester) async {
      NativeCalls().install();
      final PayriffCardController controller = PayriffCardController();
      addTearDown(controller.dispose);
      await pumpCardApp(tester, controller, language: PayriffLanguage.ar);
      expect(
        tester.widget<Text>(find.byKey(cardLabelKey('holder'))).data,
        'اسم حامل البطاقة',
      );
      expect(find.text('1234 1234 1234 1234'), findsOneWidget);
      expect(find.text('MM / YY'), findsOneWidget);
      expect(_laidOut(tester, cardHolderFieldKey), TextDirection.rtl);
      for (final Key key in <Key>[
        cardNumberFieldKey,
        cardExpiryFieldKey,
        cardCvvFieldKey,
      ]) {
        expect(_laidOut(tester, key), TextDirection.ltr, reason: '$key');
      }
      expect(
        _rect(tester, cardBrandKey).right,
        lessThan(_rect(tester, cardNumberFieldKey).left),
      );
      expect(
        _rect(tester, cardCvvFieldKey).right,
        lessThan(_rect(tester, cardExpiryFieldKey).left),
      );
    });

    testWidgets('region sa: a device language the SDK does not have gives '
        'Arabic; region az gives English', (WidgetTester tester) async {
      NativeCalls().install();
      tester.platformDispatcher.localeTestValue = const Locale('tr', 'TR');
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      final PayriffCardController controller = PayriffCardController();
      addTearDown(controller.dispose);
      Payriff.configure(
        const PayriffConfig(
          publishableKey: testPublishableKey,
          region: PayriffRegion.sa,
        ),
      );
      await pumpCardApp(tester, controller, language: null);
      expect(
        tester
            .widget<Text>(find.byKey(cardLabelKey(cardInformationSection)))
            .data,
        'معلومات البطاقة',
      );
      expect(_laidOut(tester, cardHolderFieldKey), TextDirection.rtl);

      Payriff.configure(
        const PayriffConfig(publishableKey: testPublishableKey),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpCardApp(tester, controller, language: null);
      expect(
        tester
            .widget<Text>(find.byKey(cardLabelKey(cardInformationSection)))
            .data,
        'Card information',
      );
      expect(_laidOut(tester, cardHolderFieldKey), TextDirection.ltr);
    });

    testWidgets('the payment view in Arabic: right to left, its copy, and the '
        'logo after "مدعوم من"', (WidgetTester tester) async {
      NativeCalls().install();
      FakeClientBackend().install();
      Payriff.configure(_config);
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PayriffPaymentView(
              orderId: testOrderId,
              clientSecret: testClientSecret,
              language: PayriffLanguage.ar,
              onResult: (_) {},
            ),
          ),
        ),
      );
      await _frames(tester, 5);
      expect(find.text('ادفع 10.50 AZN'), findsOneWidget);
      expect(find.text('دفع آمن وفق PCI DSS'), findsOneWidget);
      expect(
        _rect(tester, paymentViewBadgeKey('mastercard')).left,
        greaterThan(_rect(tester, paymentViewBadgeKey('visa')).right),
      );
      final Text footer = tester.widget<Text>(
        find.descendant(
          of: find.byKey(paymentViewPoweredByKey),
          matching: find.byType(Text),
        ),
      );
      final List<InlineSpan> spans = (footer.textSpan! as TextSpan).children!;
      expect((spans.first as TextSpan).text, 'مدعوم من ');
      expect(spans.last, isA<WidgetSpan>());
    });

    testWidgets('the 3-D Secure sheet in Arabic: its title, and the close '
        'button on the left; the close confirmation is right to left', (
      WidgetTester tester,
    ) async {
      final FakeWebViewPlatform web = installFakeWebView();
      debugPayriffCardClock = FakeCardClock();
      NativeCalls().install();
      FakeClientBackend(
        payPayload: _challenge(),
        statuses: <String>['PENDING', 'APPROVED'],
      ).install();
      Payriff.configure(
        const PayriffConfig(
          environment: PayriffEnvironment.sandbox,
          publishableKey: testPublishableKey,
          language: PayriffLanguage.ar,
        ),
      );
      final PayriffCardController controller = PayriffCardController();
      addTearDown(controller.dispose);
      final BuildContext Function() context = await pumpCardApp(
        tester,
        controller,
        showHolder: false,
      );
      await fillCard(tester);
      final Future<PayriffResult> future = Payriff.confirmCardPayment(
        context(),
        controller,
        orderId: testOrderId,
        clientSecret: testClientSecret,
      );
      await settleSheet(tester);
      expect(find.byType(PayriffThreeDsSheet), findsOneWidget);
      expect(find.text('الدفع'), findsOneWidget);
      final Rect sheet = tester.getRect(find.byType(PayriffThreeDsSheet));
      expect(
        _rect(tester, closeButtonKey).center.dx,
        lessThan(sheet.center.dx),
      );
      expect(web.controller.loads, isNotEmpty);

      await tester.tap(find.byKey(closeButtonKey));
      await settleSheet(tester);
      expect(
        Directionality.of(tester.element(find.byKey(confirmYesKey))),
        TextDirection.rtl,
      );
      await tester.tap(find.byKey(confirmYesKey));
      final PayriffResult result = await pumpUntilDone(tester, future);
      expect(result, isA<PayriffResultPending>());
    });
  });

  group('Apple Pay networks (CONTRACT §19.4)', () {
    for (final (PayriffRegion region, List<String> networks)
        in <(PayriffRegion, List<String>)>[
          (PayriffRegion.az, <String>['visa', 'masterCard']),
          (PayriffRegion.sa, <String>['mada', 'visa', 'masterCard']),
        ]) {
      testWidgets('canMakePayments in region ${region.name}', (
        WidgetTester tester,
      ) async {
        final NativeCalls native = NativeCalls()..install();
        final PayriffConfig config = PayriffConfig(
          publishableKey: testPublishableKey,
          region: region,
          applePay: const PayriffApplePayConfig(
            merchantIdentifier: 'merchant.com.example.shop',
          ),
        );
        final bool offered = await decideWalletOffer(
          kind: WalletKind.applePay,
          order: const PayriffClientOrder(
            orderId: testOrderId,
            amount: 10.5,
            currency: 'SAR',
            status: PayriffPaymentStatus.created,
            rawStatus: 'CREATED',
            paymentMethods: <String>['CARD', 'APPLE_PAY'],
          ),
          config: config,
          logger: SdkLogger.silent,
        );
        expect(offered, isTrue);
        final MethodCall call = native.named('applePayCanMakePayments').single;
        expect((call.arguments as Map<Object?, Object?>)['networks'], networks);
      }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
    }
  });
}
