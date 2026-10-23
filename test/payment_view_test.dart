// CONTRACT §16.14: the payment view's order states, images, dark mode and
// text overrides, and its device check (§16.16), with a fake Client API and
// a mocked `payriff/native` channel. No network.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payriff/payriff.dart';
import 'package:payriff/src/card/payment_view.dart';
import 'package:payriff/src/internal/card/card_strings.dart';
import 'package:payriff/src/internal/card/device_integrity.dart';

import 'support/card_support.dart';

/// `view.<key>` of `card_strings.json` in [language].
String _viewString(PayriffLanguage language, String key) {
  final Map<String, Object?> vector =
      jsonDecode(File('test/vectors/card_strings.json').readAsStringSync())
          as Map<String, Object?>;
  final Map<String, Object?> messages =
      vector['messages']! as Map<String, Object?>;
  final Map<String, Object?> table =
      messages[language.value.toLowerCase()]! as Map<String, Object?>;
  return (table['view']! as Map<String, Object?>)[key]! as String;
}

String _notPayable(PayriffLanguage language) =>
    _viewString(language, 'notPayable');

/// The view as a page body. The app is light, and dark when the platform is.
Widget _app({
  PayriffLanguage? language,
  PayriffPaymentViewStyle style = const PayriffPaymentViewStyle(),
  ValueChanged<PayriffResult>? onResult,
}) => MaterialApp(
  darkTheme: ThemeData(brightness: Brightness.dark),
  home: Scaffold(
    body: PayriffPaymentView(
      orderId: testOrderId,
      clientSecret: testClientSecret,
      language: language,
      style: style,
      onResult: onResult ?? (_) {},
    ),
  ),
);

/// Shows the view, then pumps [frames] frames of 100 ms; the order loads in
/// 5.
Future<List<PayriffResult>> _pumpView(
  WidgetTester tester,
  FakeClientBackend backend, {
  PayriffLanguage? language,
  NativeCalls? native,
  PayriffConfig config = const PayriffConfig(
    environment: PayriffEnvironment.sandbox,
    publishableKey: testPublishableKey,
  ),
  PayriffPaymentViewStyle style = const PayriffPaymentViewStyle(),
  int frames = 5,
}) async {
  (native ?? NativeCalls()).install();
  backend.install();
  Payriff.configure(config);
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final List<PayriffResult> results = <PayriffResult>[];
  await tester.pumpWidget(
    _app(language: language, style: style, onResult: results.add),
  );
  await _pumpFrames(tester, frames);
  return results;
}

String? _errorLine(WidgetTester tester) {
  final Finder line = find.byKey(paymentViewErrorKey);
  return line.evaluate().isEmpty ? null : tester.widget<Text>(line).data;
}

/// The image of the footer's logo, a package asset of `payriff`.
String _footerLogo(WidgetTester tester) {
  final Image logo = tester.widget<Image>(
    find.descendant(
      of: find.byKey(paymentViewPoweredByKey),
      matching: find.byType(Image),
    ),
  );
  final AssetImage image = logo.image as AssetImage;
  expect(image.package, PaymentViewAssets.package);
  return image.assetName;
}

/// The size in pixels of the PNG image at [path], from its header.
Size _pngSize(String path) {
  final Uint8List bytes = File(path).readAsBytesSync();
  // The 8-byte signature, then the IHDR chunk: length, type, width, height.
  expect(ascii.decode(bytes.sublist(12, 16)), 'IHDR', reason: path);
  final ByteData data = ByteData.sublistView(bytes);
  return Size(data.getUint32(16).toDouble(), data.getUint32(20).toDouble());
}

Future<void> _pumpFrames(WidgetTester tester, [int count = 10]) async {
  for (int i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void _expectDeviceRefused(PayriffResult result) {
  expect(result, isA<PayriffResultFailed>());
  expect(result.error?.code, PayriffErrorCode.deviceCompromised);
  expect(
    result.error?.message,
    'Card payments are not available on this device.',
  );
  expect(result.error?.isFatal, isFalse);
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

  group('images and dark mode (CONTRACT §16.14)', () {
    test('every image ships at 1x, 2.0x and 3.0x in its size, and the '
        'folder holds no other image', () {
      const Map<String, Size> sizes = <String, Size>{
        PaymentViewAssets.mastercard: Size(43, 28),
        PaymentViewAssets.visa: Size(42, 28),
        PaymentViewAssets.logo: Size(82, 16),
        PaymentViewAssets.logoDark: Size(82, 16),
      };
      expect(PaymentViewAssets.all, unorderedEquals(sizes.keys));
      final Set<String> shipped = <String>{};
      for (final String asset in PaymentViewAssets.all) {
        final int slash = asset.lastIndexOf('/');
        for (final int scale in <int>[1, 2, 3]) {
          final String path = scale == 1
              ? asset
              : '${asset.substring(0, slash)}/$scale.0x'
                    '${asset.substring(slash)}';
          shipped.add(path);
          expect(_pngSize(path), sizes[asset]! * scale.toDouble());
        }
      }
      // pubspec.yaml ships the whole folder; pub leaves out dot files.
      expect(
        Directory('assets/payment_view')
            .listSync(recursive: true)
            .whereType<File>()
            .where((File file) => !file.uri.pathSegments.last.startsWith('.'))
            .map((File file) => file.path)
            .toSet(),
        shipped,
      );
      // The dark logo is an image of its own (the wordmark in #E1E4E8).
      expect(
        File(PaymentViewAssets.logoDark).readAsBytesSync(),
        isNot(File(PaymentViewAssets.logo).readAsBytesSync()),
      );
      expect(PaymentViewAssets.footerLogo(dark: false), PaymentViewAssets.logo);
      expect(
        PaymentViewAssets.footerLogo(dark: true),
        PaymentViewAssets.logoDark,
      );
    });

    testWidgets('the footer shows payriff-logo in light mode and '
        'payriff-logo-dark in dark mode, and follows a switch', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      for (final PayriffLanguage language in PayriffLanguage.values) {
        tester.platformDispatcher.platformBrightnessTestValue =
            Brightness.light;
        await _pumpView(tester, FakeClientBackend(), language: language);
        expect(_footerLogo(tester), PaymentViewAssets.logo);

        tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
        await tester.pumpAndSettle();
        expect(_footerLogo(tester), PaymentViewAssets.logoDark);

        tester.platformDispatcher.platformBrightnessTestValue =
            Brightness.light;
        await tester.pumpAndSettle();
        expect(_footerLogo(tester), PaymentViewAssets.logo);
        await tester.pumpWidget(const SizedBox.shrink());
        Payriff.debugReset();
      }
    });

    testWidgets('in a CupertinoApp the logo follows the Cupertino theme', (
      WidgetTester tester,
    ) async {
      NativeCalls().install();
      FakeClientBackend().install();
      Payriff.configure(
        const PayriffConfig(
          environment: PayriffEnvironment.sandbox,
          publishableKey: testPublishableKey,
        ),
      );
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      Widget app(Brightness brightness) => CupertinoApp(
        theme: CupertinoThemeData(brightness: brightness),
        home: CupertinoPageScaffold(
          child: PayriffPaymentView(
            orderId: testOrderId,
            clientSecret: testClientSecret,
            language: PayriffLanguage.en,
            onResult: (_) {},
          ),
        ),
      );
      await tester.pumpWidget(app(Brightness.dark));
      await _pumpFrames(tester, 5);
      expect(find.text('Pay 10.50 AZN'), findsOneWidget);
      expect(_footerLogo(tester), PaymentViewAssets.logoDark);

      await tester.pumpWidget(app(Brightness.light));
      await tester.pumpAndSettle();
      expect(_footerLogo(tester), PaymentViewAssets.logo);
    });
  });

  group('text overrides (CONTRACT §16.14)', () {
    const PayriffClientOrder order = PayriffClientOrder(
      orderId: testOrderId,
      amount: 1.02,
      currency: 'AZN',
    );

    test('payButtonLabel replaces view.pay in every language; the amount '
        'and currency still follow it, and it shows alone without one', () {
      for (final PayriffLanguage language in PayriffLanguage.values) {
        final PayriffCardStrings strings = PayriffCardStrings(language);
        final String pay = _viewString(language, 'pay');
        // null keeps view.pay.
        expect(paymentViewPayTitle(strings, order), '$pay 1.02 AZN');
        expect(paymentViewPayTitle(strings, null), pay);
        expect(
          paymentViewPayTitle(strings, order, label: 'Pay now'),
          'Pay now 1.02 AZN',
        );
        // While the order loads, and for an order without an amount.
        expect(paymentViewPayTitle(strings, null, label: 'Pay now'), 'Pay now');
        expect(
          paymentViewPayTitle(
            strings,
            const PayriffClientOrder(orderId: testOrderId, currency: 'AZN'),
            label: 'Pay now',
          ),
          'Pay now',
        );
      }
      final PayriffCardStrings strings = PayriffCardStrings(PayriffLanguage.en);
      // White space around the label is dropped; a blank label counts as none
      // (CONTRACT §16.14).
      expect(
        paymentViewPayTitle(strings, order, label: '  Buy \n'),
        'Buy 1.02 AZN',
      );
      expect(paymentViewPayTitle(strings, order, label: ''), 'Pay 1.02 AZN');
      expect(paymentViewPayTitle(strings, order, label: '  '), 'Pay 1.02 AZN');
    });

    test('the overrides default to null and take part in ==, hashCode and '
        'copyWith', () {
      const PayriffPaymentViewStyle plain = PayriffPaymentViewStyle();
      expect(plain.payButtonLabel, isNull);
      expect(plain.secureNoteText, isNull);
      const PayriffPaymentViewStyle texts = PayriffPaymentViewStyle(
        payButtonLabel: 'Pay now',
        secureNoteText: 'Secured by Payriff',
      );
      final PayriffPaymentViewStyle copy = plain.copyWith(
        payButtonLabel: 'Pay now',
        secureNoteText: 'Secured by Payriff',
      );
      expect(copy, texts);
      expect(copy.hashCode, texts.hashCode);
      expect(texts, isNot(plain.copyWith(payButtonLabel: 'Pay now')));
      expect(
        texts,
        isNot(plain.copyWith(secureNoteText: 'Secured by Payriff')),
      );
      final PayriffPaymentViewStyle taller = texts.copyWith(buttonHeight: 52);
      expect(taller.payButtonLabel, 'Pay now');
      expect(taller.secureNoteText, 'Secured by Payriff');
    });

    testWidgets('the view shows them in place of the localized texts; null '
        'brings those back', (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      const PayriffPaymentViewStyle style = PayriffPaymentViewStyle(
        payButtonLabel: 'Pay now',
        secureNoteText: 'Your card is encrypted on this device',
      );
      const PayriffLanguage language = PayriffLanguage.az;
      await _pumpView(
        tester,
        FakeClientBackend(),
        language: language,
        style: style,
        frames: 0,
      );
      // While the order loads: the label alone.
      expect(find.text('Pay now'), findsOneWidget);

      await _pumpFrames(tester, 5);
      expect(find.text('Pay now 10.50 AZN'), findsOneWidget);
      expect(find.bySemanticsLabel('Pay now 10.50 AZN'), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(paymentViewSecureKey),
                matching: find.byType(Text),
              ),
            )
            .data,
        'Your card is encrypted on this device',
      );
      expect(find.text(_viewString(language, 'pay')), findsNothing);
      expect(find.text(_viewString(language, 'secure')), findsNothing);

      // The default style: the localized texts, and the order is kept.
      await tester.pumpWidget(_app(language: language));
      await tester.pump();
      expect(
        find.text('${_viewString(language, 'pay')} 10.50 AZN'),
        findsOneWidget,
      );
      expect(find.text(_viewString(language, 'secure')), findsOneWidget);
      expect(find.text('Your card is encrypted on this device'), findsNothing);
      semantics.dispose();
    });
  });

  group('device integrity (CONTRACT §16.16)', () {
    for (final PayriffLanguage language in PayriffLanguage.values) {
      testWidgets('a compromised device shows view.deviceNotSupported, does '
          'not read the order and reports once (${language.value})', (
        WidgetTester tester,
      ) async {
        final FakeClientBackend backend = FakeClientBackend();
        final NativeCalls native = NativeCalls()
          ..integrityReply = NativeCalls.compromised();
        final List<PayriffResult> results = await _pumpView(
          tester,
          backend,
          language: language,
          native: native,
        );
        expect(_errorLine(tester), _viewString(language, 'deviceNotSupported'));
        expect(backend.requests, isEmpty);
        expect(results, hasLength(1));
        _expectDeviceRefused(results.single);
        // The Pay button stays disabled: a full card pays nothing, and
        // nothing is reported again.
        await fillCard(tester, holder: 'ELLEN CARTER');
        await tester.tap(find.byKey(paymentViewPayButtonKey));
        await _pumpFrames(tester);
        expect(backend.requests, isEmpty);
        expect(native.named('encryptCard'), isEmpty);
        expect(native.named('deviceIntegrity'), hasLength(1));
        expect(results, hasLength(1));
        expect(find.text(_viewString(language, 'pay')), findsOneWidget);
      });
    }

    testWidgets('a check that cannot complete counts as a compromised '
        'device', (WidgetTester tester) async {
      final FakeClientBackend backend = FakeClientBackend();
      // A reply without the `compromised` flag.
      final List<PayriffResult> results = await _pumpView(
        tester,
        backend,
        language: PayriffLanguage.en,
        native: NativeCalls()..integrityReply = null,
      );
      expect(
        _errorLine(tester),
        "Card payments aren't available on this device for security reasons",
      );
      expect(backend.requests, isEmpty);
      expect(results, hasLength(1));
      _expectDeviceRefused(results.single);
    });

    testWidgets('allowCompromisedDevices reads the order and only logs a '
        'warning', (WidgetTester tester) async {
      final List<String> warnings = <String>[];
      final StreamSubscription<PayriffLogEntry> logs = Payriff.logStream.listen(
        (PayriffLogEntry entry) {
          if (entry.level == PayriffLogLevel.warning) {
            warnings.add(entry.message);
          }
        },
      );
      addTearDown(logs.cancel);
      final List<PayriffResult> results = await _pumpView(
        tester,
        FakeClientBackend(),
        language: PayriffLanguage.en,
        native: NativeCalls()
          ..integrityReply = NativeCalls.compromised(<String>['Xposed']),
        config: const PayriffConfig(
          environment: PayriffEnvironment.sandbox,
          publishableKey: testPublishableKey,
          enableLogging: true,
          allowCompromisedDevices: true,
        ),
      );
      expect(_errorLine(tester), isNull);
      expect(find.text('Pay 10.50 AZN'), findsOneWidget);
      expect(results, isEmpty);
      expect(warnings, <String>[
        'Compromised device (Xposed) at payment view: allowed by '
            'PayriffConfig.allowCompromisedDevices',
      ]);
    });

    testWidgets('outside debug builds allowCompromisedDevices is ignored: '
        'the view refuses the device and does not read the order', (
      WidgetTester tester,
    ) async {
      // What a profile or release build does.
      debugPayriffDevelopmentBuild = false;
      addTearDown(() => debugPayriffDevelopmentBuild = null);
      final List<String> warnings = <String>[];
      final StreamSubscription<PayriffLogEntry> logs = Payriff.logStream.listen(
        (PayriffLogEntry entry) {
          if (entry.level == PayriffLogLevel.warning) {
            warnings.add(entry.message);
          }
        },
      );
      addTearDown(logs.cancel);
      final FakeClientBackend backend = FakeClientBackend();
      final List<PayriffResult> results = await _pumpView(
        tester,
        backend,
        language: PayriffLanguage.en,
        native: NativeCalls()
          ..integrityReply = NativeCalls.compromised(<String>['Xposed']),
        config: const PayriffConfig(
          environment: PayriffEnvironment.sandbox,
          publishableKey: testPublishableKey,
          enableLogging: true,
          allowCompromisedDevices: true,
        ),
      );
      expect(
        _errorLine(tester),
        "Card payments aren't available on this device for security reasons",
      );
      expect(backend.requests, isEmpty);
      expect(results, hasLength(1));
      _expectDeviceRefused(results.single);
      expect(warnings, <String>[
        'PayriffConfig.allowCompromisedDevices is ignored outside debug '
            'builds: card payments are refused on compromised devices.',
        'Compromised device (Xposed) at payment view: card payments are '
            'refused (PayriffConfig.allowCompromisedDevices is ignored '
            'outside debug builds)',
      ]);
    });

    testWidgets('a tool that attaches after the view appeared stops Pay', (
      WidgetTester tester,
    ) async {
      final FakeClientBackend backend = FakeClientBackend();
      final NativeCalls native = NativeCalls();
      final List<PayriffResult> results = await _pumpView(
        tester,
        backend,
        language: PayriffLanguage.en,
        native: native,
      );
      expect(find.text('Pay 10.50 AZN'), findsOneWidget);
      native.integrityReply = NativeCalls.compromised(<String>['Frida']);

      await fillCard(tester, holder: 'ELLEN CARTER');
      await tester.tap(find.byKey(paymentViewPayButtonKey));
      await _pumpFrames(tester);

      expect(results, hasLength(1));
      _expectDeviceRefused(results.single);
      expect(
        _errorLine(tester),
        "Card payments aren't available on this device for security reasons",
      );
      expect(backend.to('/pay'), isEmpty);
      expect(native.named('encryptCard'), isEmpty);
      // Pay stays disabled.
      await fillCard(tester, holder: 'ELLEN CARTER');
      await tester.tap(find.byKey(paymentViewPayButtonKey));
      await _pumpFrames(tester);
      expect(results, hasLength(1));
      expect(native.named('deviceIntegrity'), hasLength(2));
    });
  });
}
