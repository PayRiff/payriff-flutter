import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payriff/payriff.dart';
import 'package:payriff_example/main.dart';
import 'package:payriff_example/src/home_page.dart';
import 'package:payriff_example/src/settings.dart';

void main() {
  setUp(Payriff.debugReset);

  Future<void> pumpApp(
    WidgetTester tester, {
    String publishableKey = 'pr_pk_live_TEST',
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // The plugin's native half (app id, screen protection, device checks)
    // is not there in widget tests. Without a device check reply the SDK
    // fails closed and refuses card payments, so this one is clean.
    const MethodChannel native = MethodChannel('payriff/native');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      native,
      (MethodCall call) async => switch (call.method) {
        'appId' => 'com.payriff.example.flutter',
        'deviceIntegrity' => <String, Object?>{
          'compromised': false,
          'signals': <String>[],
        },
        _ => null,
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        native,
        null,
      ),
    );
    await tester.pumpWidget(
      PayriffExampleApp(
        home: HomePage(
          settings: ExampleSettings(
            environment: PayriffEnvironment.sandbox,
            publishableKey: publishableKey,
          ),
        ),
      ),
    );
  }

  Future<void> enterOrder(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const ValueKey<String>('order-id')),
      'o1',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('client-secret')),
      'pr_cs_TEST',
    );
    await tester.pump();
  }

  FilledButton button(WidgetTester tester, String name) =>
      tester.widget<FilledButton>(find.byKey(ValueKey<String>('pay-$name')));

  test('parseOrder reads the order JSON or two values', () {
    expect(parseOrder('{"orderId": " o1 ", "clientSecret": "pr_cs_abc"}'), (
      orderId: 'o1',
      clientSecret: 'pr_cs_abc',
    ));
    expect(parseOrder('  o2\n pr_cs_def '), (
      orderId: 'o2',
      clientSecret: 'pr_cs_def',
    ));
    for (final String text in <String>[
      '',
      'o3',
      'a b c',
      '{"orderId":"o4"}',
      '{"orderId":1,"clientSecret":"pr_cs_x"}',
      '["o5","pr_cs_x"]',
    ]) {
      expect(parseOrder(text), isNull, reason: text);
    }
  });

  testWidgets(
    'one screen: orderId, clientSecret and three pay buttons that wait for both',
    (WidgetTester tester) async {
      await pumpApp(tester);
      expect(
        find.byKey(const ValueKey<String>('no-publishable-key')),
        findsNothing,
      );
      for (final String name in <String>['page', 'bottomSheet', 'popup']) {
        expect(button(tester, name).onPressed, isNull, reason: name);
      }
      await enterOrder(tester);
      for (final String name in <String>['page', 'bottomSheet', 'popup']) {
        expect(button(tester, name).onPressed, isNotNull, reason: name);
      }
      // No secret key, callback URL or order creation anywhere.
      expect(find.textContaining('ecret key'), findsNothing);
    },
  );

  testWidgets('without a publishable key it says how to add one', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester, publishableKey: '');
    expect(
      find.byKey(const ValueKey<String>('no-publishable-key')),
      findsOneWidget,
    );
    await enterOrder(tester);
    expect(button(tester, 'page').onPressed, isNull);
  });

  testWidgets('Paste fills both fields from the order JSON', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async => call.method == 'Clipboard.getData'
          ? <String, Object?>{
              'text': '{"orderId":"o1","clientSecret":"pr_cs_TEST"}',
            }
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('paste-order')));
    await tester.pumpAndSettle();
    expect(find.text('o1'), findsOneWidget);
    expect(find.text('pr_cs_TEST'), findsOneWidget);
    expect(button(tester, 'popup').onPressed, isNotNull);
  });

  testWidgets('Pay in page pushes a screen with only the payment view', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);
    await enterOrder(tester);
    await tester.tap(find.byKey(const ValueKey<String>('pay-page')));
    await tester.pumpAndSettle();
    final PayriffPaymentView view = tester.widget<PayriffPaymentView>(
      find.byType(PayriffPaymentView),
    );
    expect(view.orderId, 'o1');
    expect(view.clientSecret, 'pr_cs_TEST');
    expect(find.text('Card information'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('order-id')), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('o1'), findsOneWidget);
  });

  testWidgets('Pay in bottom sheet shows the payment view in a modal sheet', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);
    await enterOrder(tester);
    await tester.tap(find.byKey(const ValueKey<String>('pay-bottomSheet')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(PayriffPaymentView),
      ),
      findsOneWidget,
    );
    expect(find.text('Card information'), findsOneWidget);
  });

  testWidgets('Pay in popup shows the payment view in a dialog that closes', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);
    await enterOrder(tester);
    await tester.tap(find.byKey(const ValueKey<String>('pay-popup')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(PayriffPaymentView),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey<String>('popup-close')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('o1'), findsOneWidget);
  });
}
