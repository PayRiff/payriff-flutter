// CONTRACT §16.14: the payment view's order states, with a fake Client API
// and a mocked `payriff/native` channel. No network.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payriff/payriff.dart';
import 'package:payriff/src/card/payment_view.dart';

import 'support/card_support.dart';

/// `view.notPayable` of `card_strings.json` in [language].
String _notPayable(PayriffLanguage language) {
  final Map<String, Object?> vector =
      jsonDecode(File('test/vectors/card_strings.json').readAsStringSync())
          as Map<String, Object?>;
  final Map<String, Object?> messages =
      vector['messages']! as Map<String, Object?>;
  final Map<String, Object?> table =
      messages[language.value.toLowerCase()]! as Map<String, Object?>;
  return (table['view']! as Map<String, Object?>)['notPayable']! as String;
}

Future<List<PayriffResult>> _pumpView(
  WidgetTester tester,
  FakeClientBackend backend, {
  PayriffLanguage? language,
}) async {
  NativeCalls().install();
  backend.install();
  Payriff.configure(
    const PayriffConfig(
      environment: PayriffEnvironment.sandbox,
      publishableKey: testPublishableKey,
    ),
  );
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final List<PayriffResult> results = <PayriffResult>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PayriffPaymentView(
          orderId: testOrderId,
          clientSecret: testClientSecret,
          language: language,
          onResult: results.add,
        ),
      ),
    ),
  );
  for (int i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return results;
}

String? _errorLine(WidgetTester tester) {
  final Finder line = find.byKey(paymentViewErrorKey);
  return line.evaluate().isEmpty ? null : tester.widget<Text>(line).data;
}

void main() {
  setUp(Payriff.debugReset);
  tearDown(Payriff.debugReset);

  for (final PayriffLanguage language in PayriffLanguage.values) {
    testWidgets('an order that cannot be paid by card shows view.notPayable '
        'in the view language (${language.value})', (
      WidgetTester tester,
    ) async {
      final FakeClientBackend backend = FakeClientBackend(
        orderStatus: 'APPROVED',
      );
      final List<PayriffResult> results = await _pumpView(
        tester,
        backend,
        language: language,
      );
      expect(_errorLine(tester), _notPayable(language));
      // The Pay button stays disabled: a full card pays nothing.
      await fillCard(tester, holder: 'ELLEN CARTER');
      await tester.tap(find.byKey(paymentViewPayButtonKey));
      await tester.pump();
      expect(backend.to('/pay'), isEmpty);
      expect(results, isEmpty);
    });
  }

  testWidgets('an order without CARD shows the line too; a payable order '
      'shows none', (WidgetTester tester) async {
    await _pumpView(
      tester,
      FakeClientBackend(paymentMethods: const <String>['GOOGLE_PAY']),
      language: PayriffLanguage.ru,
    );
    expect(_errorLine(tester), 'Этот заказ нельзя оплатить картой');

    await tester.pumpWidget(const SizedBox.shrink());
    Payriff.debugReset();
    await _pumpView(tester, FakeClientBackend(), language: PayriffLanguage.en);
    expect(_errorLine(tester), isNull);
    expect(find.text('Pay 10.50 AZN'), findsOneWidget);
  });
}
