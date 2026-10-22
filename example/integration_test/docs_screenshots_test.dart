// Takes the screenshots of the Payriff Flutter docs on a simulator or device.
//
// It never reaches Payriff: a fake HTTP client answers the order lookup with a
// sample order, and nothing is paid.
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/docs_screenshots_test.dart \
//     [--dart-define=DOCS_SUFFIX=-dark] -d <device>
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:payriff/payriff.dart';
// The SDK's debug-only test hook for its HTTP client.
// ignore: implementation_imports
import 'package:payriff/src/internal/card/client_api.dart'
    show debugPayriffClientApiHttpClient;
import 'package:payriff_example/main.dart';
import 'package:payriff_example/src/home_page.dart';
import 'package:payriff_example/src/settings.dart';

const String _suffix = String.fromEnvironment('DOCS_SUFFIX');

// The docs' sample order. Not real: only the fake client below knows it.
const String _orderId = '7c9e6679-7425-40de-944b-e07fc1f90ae7';
const String _clientSecret = 'pr_cs_v1_DocsScreenshotSampleOnly0000000000000';

/// Answers `GET /api/v3/client/orders/{id}` with a payable 1.00 AZN order.
http.Client _fakePayriff() => MockClient((http.Request request) async {
  final bool order =
      request.method == 'GET' &&
      request.url.path == '/api/v3/client/orders/$_orderId';
  if (!order) return http.Response('{"code": "15404"}', 404);
  return http.Response(
    jsonEncode(<String, Object?>{
      'code': '00000',
      'message': 'OK',
      'payload': <String, Object?>{
        'orderId': _orderId,
        'amount': 1.0,
        'currency': 'AZN',
        'description': 'Order #1042',
        'merchantName': 'Payriff Docs',
        'status': 'CREATED',
        'language': 'EN',
        'paymentMethods': <String>['CARD'],
      },
    }),
    200,
    headers: <String, String>{'content-type': 'application/json'},
  );
});

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  debugPayriffClientApiHttpClient = _fakePayriff;

  Future<void> wait(WidgetTester tester, [int ms = 600]) async {
    await Future<void>.delayed(Duration(milliseconds: ms));
    await tester.pump();
  }

  Future<void> shot(WidgetTester tester, String name) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await wait(tester, 900);
    await binding.takeScreenshot('$name$_suffix');
  }

  /// Waits until the payment view has read the order (its Pay title shows
  /// the amount).
  Future<void> waitForOrder(WidgetTester tester) async {
    for (int i = 0; i < 60; i++) {
      await wait(tester, 250);
      if (find.textContaining('AZN').evaluate().isNotEmpty) return;
    }
    fail('The sample order did not load.');
  }

  Future<void> type(WidgetTester tester, String key, String text) async {
    await tester.enterText(find.byKey(ValueKey<String>(key)), text);
    await wait(tester, 200);
  }

  Future<void> fillCard(WidgetTester tester, {required String number}) async {
    await type(tester, 'payriff.card.holder', 'AYSEL MAMMADOVA');
    await type(tester, 'payriff.card.number', number);
    await type(tester, 'payriff.card.expiry', '1230');
    await type(tester, 'payriff.card.cvv', '123');
  }

  Future<void> close(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await wait(tester, 800);
  }

  testWidgets('docs screenshots', (WidgetTester tester) async {
    await tester.pumpWidget(
      PayriffExampleApp(
        home: HomePage(
          settings: ExampleSettings(
            environment: PayriffEnvironment.production,
            publishableKey: 'pr_pk_live_DocsScreenshotSampleOnly000000000',
          ),
        ),
      ),
    );
    await wait(tester, 1500);
    await type(tester, 'order-id', _orderId);
    await type(tester, 'client-secret', _clientSecret);
    await shot(tester, '01-home');

    // Pay in page: empty, filled (Visa), then a typing error.
    await tester.tap(find.byKey(const ValueKey<String>('pay-page')));
    await waitForOrder(tester);
    await shot(tester, '02-page');
    await fillCard(tester, number: '4111111111111111');
    await shot(tester, '03-page-filled');
    await type(tester, 'payriff.card.number', '4111111111111112');
    await type(tester, 'payriff.card.holder', 'AYSEL MAMMADOVA');
    await shot(tester, '04-page-error');
    await close(tester);

    // Pay in bottom sheet, filled with a Mastercard.
    await tester.tap(find.byKey(const ValueKey<String>('pay-bottomSheet')));
    await waitForOrder(tester);
    await shot(tester, '05-sheet');
    await fillCard(tester, number: '5555555555554444');
    await shot(tester, '06-sheet-filled');
    await close(tester);

    // Pay in popup.
    await tester.tap(find.byKey(const ValueKey<String>('pay-popup')));
    await waitForOrder(tester);
    await shot(tester, '07-popup');
    await close(tester);

    // Appearance: the same view restyled through PayriffPaymentViewStyle.
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: PayriffPaymentView(
            orderId: _orderId,
            clientSecret: _clientSecret,
            onResult: (_) {},
            style: const PayriffPaymentViewStyle(
              backgroundColor: Color(0xFFF5F3FF),
              buttonColor: Color(0xFF6D28D9),
              buttonCornerRadius: 26,
              buttonHeight: 52,
              showPoweredBy: false,
              formStyle: PayriffCardFormStyle(
                layout: PayriffCardFormLayout.stacked,
                labelTextStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: Color(0xFF6D28D9),
                ),
                inputTextStyle: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                fieldBackgroundColor: Color(0xFFFFFFFF),
                borderColor: Color(0xFFDDD6FE),
                focusedBorderColor: Color(0xFF6D28D9),
                cornerRadius: 14,
                holderHeight: 52,
                rowHeight: 52,
              ),
            ),
          ),
        ),
      ),
    );
    await waitForOrder(tester);
    await shot(tester, '08-custom');

    // Localisation: the default view in Azerbaijani.
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: PayriffPaymentView(
            orderId: _orderId,
            clientSecret: _clientSecret,
            language: PayriffLanguage.az,
            onResult: (_) {},
          ),
        ),
      ),
    );
    await waitForOrder(tester);
    await shot(tester, '09-az');
  });
}
