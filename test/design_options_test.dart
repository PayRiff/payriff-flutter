// CONTRACT §18 (revision 8): the design-system options. Every case of
// corner_smoothing.json and strings_override.json, and the options through
// the payment view, the card form and the 3-D Secure sheet, with a fake
// Client API, a fake WebView and a mocked `payriff/native` channel. No
// network.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:payriff/payriff.dart';
import 'package:payriff/src/card/brand_mark.dart';
import 'package:payriff/src/card/card_form.dart';
import 'package:payriff/src/card/payment_view.dart';
import 'package:payriff/src/internal/card/card_clock.dart';
import 'package:payriff/src/internal/card/card_strings.dart';
import 'package:payriff/src/internal/card/client_api.dart';
import 'package:payriff/src/internal/strings.dart';
import 'package:payriff/src/internal/ui/sheet.dart';
import 'package:payriff/src/internal/ui/smooth_rect.dart';

import 'support/card_support.dart';
import 'support/fake_webview.dart';
import 'support/wallet_support.dart';

Map<String, Object?> _load(String name) =>
    jsonDecode(File('test/vectors/$name').readAsStringSync())
        as Map<String, Object?>;

List<Map<String, Object?>> _list(Object? value) =>
    (value! as List<Object?>).cast<Map<String, Object?>>();

double _num(Object? value) => (value! as num).toDouble();

Offset _point(Object? value) {
  final List<Object?> xy = value! as List<Object?>;
  return Offset(_num(xy[0]), _num(xy[1]));
}

void _expectPoint(Offset actual, Object? expected, String reason) {
  final Offset e = _point(expected);
  expect(actual.dx, closeTo(e.dx, 0.001), reason: '$reason x');
  expect(actual.dy, closeTo(e.dy, 0.001), reason: '$reason y');
}

/// One [PayriffStrings] field set to a value, by its name in
/// `strings_override.json` → `fields`.
final Map<String, PayriffStrings Function(String)> _fieldSetters =
    <String, PayriffStrings Function(String)>{
      'holderLabel': (String v) => PayriffStrings(holderLabel: v),
      'cardInformationLabel': (String v) =>
          PayriffStrings(cardInformationLabel: v),
      'numberAccessibilityLabel': (String v) =>
          PayriffStrings(numberAccessibilityLabel: v),
      'expiryAccessibilityLabel': (String v) =>
          PayriffStrings(expiryAccessibilityLabel: v),
      'cvcAccessibilityLabel': (String v) =>
          PayriffStrings(cvcAccessibilityLabel: v),
      'holderPlaceholder': (String v) => PayriffStrings(holderPlaceholder: v),
      'numberPlaceholder': (String v) => PayriffStrings(numberPlaceholder: v),
      'expiryPlaceholder': (String v) => PayriffStrings(expiryPlaceholder: v),
      'cvcPlaceholder': (String v) => PayriffStrings(cvcPlaceholder: v),
      'numberRequired': (String v) => PayriffStrings(numberRequired: v),
      'numberIncomplete': (String v) => PayriffStrings(numberIncomplete: v),
      'numberInvalid': (String v) => PayriffStrings(numberInvalid: v),
      'numberUnsupported': (String v) => PayriffStrings(numberUnsupported: v),
      'expiryRequired': (String v) => PayriffStrings(expiryRequired: v),
      'expiryIncomplete': (String v) => PayriffStrings(expiryIncomplete: v),
      'expiryInvalid': (String v) => PayriffStrings(expiryInvalid: v),
      'expiryExpired': (String v) => PayriffStrings(expiryExpired: v),
      'cvcRequired': (String v) => PayriffStrings(cvcRequired: v),
      'cvcIncomplete': (String v) => PayriffStrings(cvcIncomplete: v),
      'cvcInvalid': (String v) => PayriffStrings(cvcInvalid: v),
      'holderRequired': (String v) => PayriffStrings(holderRequired: v),
      'holderInvalid': (String v) => PayriffStrings(holderInvalid: v),
      'pay': (String v) => PayriffStrings(pay: v),
      'secureNote': (String v) => PayriffStrings(secureNote: v),
      'poweredBy': (String v) => PayriffStrings(poweredBy: v),
      'orPayByCard': (String v) => PayriffStrings(orPayByCard: v),
      'notPayable': (String v) => PayriffStrings(notPayable: v),
      'deviceNotSupported': (String v) => PayriffStrings(deviceNotSupported: v),
      'sheetTitle': (String v) => PayriffStrings(sheetTitle: v),
      'verifying': (String v) => PayriffStrings(verifying: v),
      'close': (String v) => PayriffStrings(close: v),
      'retry': (String v) => PayriffStrings(retry: v),
      'closeConfirmTitle': (String v) => PayriffStrings(closeConfirmTitle: v),
      'closeConfirmMessage': (String v) =>
          PayriffStrings(closeConfirmMessage: v),
      'closeConfirmClose': (String v) => PayriffStrings(closeConfirmClose: v),
      'closeConfirmContinue': (String v) =>
          PayriffStrings(closeConfirmContinue: v),
      'pageLoadError': (String v) => PayriffStrings(pageLoadError: v),
      'dialogOk': (String v) => PayriffStrings(dialogOk: v),
      'dialogCancel': (String v) => PayriffStrings(dialogCancel: v),
    };

/// The strings of a vector case: `{}` or one field.
PayriffStrings _strings(Object? value) {
  final Map<String, Object?> fields = value! as Map<String, Object?>;
  expect(fields.length, lessThanOrEqualTo(1));
  if (fields.isEmpty) return const PayriffStrings();
  final MapEntry<String, Object?> field = fields.entries.single;
  return _fieldSetters[field.key]!(field.value! as String);
}

PayriffLanguage _language(Object? code) => PayriffLanguage.values.firstWhere(
  (PayriffLanguage l) => l.value.toLowerCase() == (code as String? ?? 'en'),
);

PayriffCardField _cardField(String name) =>
    PayriffCardField.values.firstWhere((PayriffCardField f) => f.value == name);

/// The `card_strings.json` text `<section>.<key>` through the SDK's lookup.
String _cardText(PayriffCardStrings strings, String key) {
  final List<String> parts = key.split('.');
  final String section = parts[0];
  final String name = parts[1];
  switch (section) {
    case 'label':
      return strings.label(_cardField(name));
    case 'placeholder':
      return strings.placeholder(_cardField(name));
    case 'group':
      return strings.cardInformation;
    case 'view':
      return switch (name) {
        'pay' => strings.pay,
        'secure' => strings.secure,
        'poweredBy' => strings.poweredBy,
        'orPayByCard' => strings.orPayByCard,
        'notPayable' => strings.notPayable,
        'deviceNotSupported' => strings.deviceNotSupported,
        _ => throw StateError('unknown view key $name'),
      };
  }
  return strings.error(
    _cardField(section),
    PayriffCardFieldErrorCode.values.firstWhere(
      (PayriffCardFieldErrorCode c) => c.value == name,
    ),
  );
}

/// The `strings.json` text [key] through the SDK's lookup.
String _sheetText(PayriffSheetStrings strings, String key) =>
    strings[PayriffStringKey.values.firstWhere(
      (PayriffStringKey k) => k.id == key,
    )];

/// The text of a vector field in [language] with [overrides].
String _text(
  Map<String, Object?> field,
  PayriffLanguage language,
  List<PayriffStrings> overrides,
) => field['source'] == 'card_strings'
    ? _cardText(
        PayriffCardStrings(language, overrides: overrides),
        field['key']! as String,
      )
    : _sheetText(
        PayriffSheetStrings(language, overrides: overrides),
        field['key']! as String,
      );

/// A canvas that records the paths drawn on it.
class _RecordingCanvas extends Fake implements Canvas {
  final List<(Path, Paint)> paths = <(Path, Paint)>[];

  @override
  void drawPath(Path path, Paint paint) => paths.add((path, paint));
}

double _length(Path path) => path.computeMetrics().fold(
  0,
  (double total, ui.PathMetric m) => total + m.length,
);

const PayriffConfig _config = PayriffConfig(
  environment: PayriffEnvironment.sandbox,
  publishableKey: testPublishableKey,
);

Future<void> _frames(WidgetTester tester, [int count = 10]) async {
  for (int i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// What the view reported, in order.
class _Events {
  final List<String> log = <String>[];
  final List<PayriffResult> results = <PayriffResult>[];
  final List<PayriffError> loadFailures = <PayriffError>[];

  /// Runs at onPaymentStarted, before the event is logged.
  void Function(PayriffPaymentMethod method)? onStarted;
}

/// Shows a payment view as a page body and waits until the order is in.
Future<_Events> _pumpView(
  WidgetTester tester, {
  FakeClientBackend? backend,
  NativeCalls? native,
  PayriffConfig config = _config,
  PayriffPaymentViewStyle style = const PayriffPaymentViewStyle(),
  PayriffStrings? strings,
  PayriffLanguage? language = PayriffLanguage.en,
  String clientSecret = testClientSecret,
  _Events? events,
  int frames = 5,
}) async {
  (native ?? NativeCalls()).install();
  (backend ?? FakeClientBackend()).install();
  Payriff.configure(config);
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final _Events e = events ?? _Events();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PayriffPaymentView(
          orderId: testOrderId,
          clientSecret: clientSecret,
          language: language,
          style: style,
          strings: strings,
          onResult: (PayriffResult r) {
            e.results.add(r);
            e.log.add('result ${r.type}');
          },
          onPaymentStarted: (PayriffPaymentMethod m) {
            e.onStarted?.call(m);
            e.log.add('started ${m.name}');
          },
          onOrderLoaded: (PayriffClientOrder o) =>
              e.log.add('loaded ${o.orderId}'),
          onLoadFailed: (PayriffError error) {
            e.loadFailures.add(error);
            e.log.add('loadFailed ${error.code.value}');
          },
        ),
      ),
    ),
  );
  await _frames(tester, frames);
  return e;
}

Finder _inPay(Type type) => find.descendant(
  of: find.byKey(paymentViewPayButtonKey),
  matching: find.byType(type),
);

Decoration _decorationOf(WidgetTester tester, Finder finder) =>
    tester.widget<DecoratedBox>(finder).decoration;

String? _errorLine(WidgetTester tester) {
  final Finder line = find.byKey(paymentViewErrorKey);
  return line.evaluate().isEmpty ? null : tester.widget<Text>(line).data;
}

/// A Client API that answers every request with HTTP [status].
void _installFailingApi(int status) {
  debugPayriffClientApiHttpClient = () => MockClient(
    (http.Request request) async =>
        http.Response('{"code":"01000","message":"Order not found"}', status),
  );
  addTearDown(() => debugPayriffClientApiHttpClient = null);
}

const String _callback =
    'https://sb-api.payriff.com/api/v3/gateway/kapital/callback/o1';

Map<String, Object?> _challenge() => <String, Object?>{
  'orderId': testOrderId,
  'nextAction': 'THREE_DS',
  'channel': 'KAPITAL',
  'accessUrl': 'https://acs.bank.example/challenge',
  'clientRequest': <Object?>[
    <String, Object?>{'key': 'creq', 'value': 'CREQ'},
  ],
};

void _loadPage(FakeNavigationDelegate delegate, String url) {
  delegate
    ..pageStarted(url)
    ..urlChanged(url)
    ..pageFinished(url);
}

void main() {
  setUp(Payriff.debugReset);
  tearDown(() {
    debugPayriffCardClock = null;
    Payriff.debugReset();
  });

  group('corner_smoothing.json (CONTRACT §18.2)', () {
    final Map<String, Object?> v = _load('corner_smoothing.json');
    final List<Map<String, Object?>> cases = _list(v['cases']);
    test('has cases', () => expect(cases, isNotEmpty));
    for (final Map<String, Object?> c in cases) {
      test(c['name']! as String, () {
        final double width = _num(c['width']);
        final double height = _num(c['height']);
        final SmoothCorner corner = SmoothCorner.of(
          width: width,
          height: height,
          radius: _num(c['radius']),
          smoothing: _num(c['smoothing']),
        );
        final Map<String, Object?> e = c['expect']! as Map<String, Object?>;
        for (final (String name, double value) in <(String, double)>[
          ('radius', corner.radius),
          ('smoothing', corner.smoothing),
          ('p', corner.p),
          ('a', corner.a),
          ('b', corner.b),
          ('c', corner.c),
          ('d', corner.d),
          ('arcSectionLength', corner.arcSectionLength),
          ('arcMeasure', corner.arcMeasure),
        ]) {
          expect(value, closeTo(_num(e[name]), 0.001), reason: name);
        }
        final SmoothCornerPath topRight = smoothCornerPath(
          Offset.zero & Size(width, height),
          corner,
          0,
        );
        final Map<String, Object?> t = e['topRight']! as Map<String, Object?>;
        _expectPoint(topRight.start, t['start'], 'start');
        final List<Object?> cubic1 = t['cubic1']! as List<Object?>;
        final List<Object?> cubic2 = t['cubic2']! as List<Object?>;
        for (int i = 0; i < 3; i++) {
          _expectPoint(topRight.cubic1[i], cubic1[i], 'cubic1[$i]');
          _expectPoint(topRight.cubic2[i], cubic2[i], 'cubic2[$i]');
        }
        final Map<String, Object?> arc = t['arc']! as Map<String, Object?>;
        _expectPoint(topRight.center, arc['center'], 'arc center');
        expect(topRight.radius, closeTo(_num(arc['radius']), 0.001));
        expect(topRight.startAngle, closeTo(_num(arc['startAngle']), 0.001));
        expect(topRight.endAngle, closeTo(_num(arc['endAngle']), 0.001));
      });
    }

    test('the other corners are the top-right one mirrored, and the outline '
        'fills the rectangle', () {
      const Rect rect = Rect.fromLTWH(10, 20, 300, 48);
      final SmoothCorner corner = SmoothCorner.of(
        width: rect.width,
        height: rect.height,
        radius: 12,
        smoothing: 0.6,
      );
      final SmoothCornerPath topRight = smoothCornerPath(rect, corner, 0);
      final SmoothCornerPath bottomLeft = smoothCornerPath(rect, corner, 2);
      // A half turn about the centre maps one onto the other.
      Offset turn(Offset p) => rect.center * 2 - p;
      expect(bottomLeft.start, _closeTo(turn(topRight.start)));
      expect(bottomLeft.center, _closeTo(turn(topRight.center)));
      expect(bottomLeft.cubic2.last, _closeTo(turn(topRight.cubic2.last)));
      expect(bottomLeft.startAngle - topRight.startAngle, 180);
      final Rect bounds = smoothRectPath(rect, 12, 0.6).getBounds();
      expect(bounds.left, closeTo(rect.left, 0.01));
      expect(bounds.top, closeTo(rect.top, 0.01));
      expect(bounds.right, closeTo(rect.right, 0.01));
      expect(bounds.bottom, closeTo(rect.bottom, 0.01));
    });

    test('smoothing 0 is the circular rounded rectangle', () {
      for (final (Size size, double radius) in <(Size, double)>[
        (const Size(300, 48), 12),
        (const Size(300, 44), 16),
        (const Size(42, 28), 4),
        (const Size(48, 48), 24),
        (const Size(100, 40), 30),
      ]) {
        final Rect rect = Offset.zero & size;
        final Path smooth = smoothRectPath(rect, radius, 0);
        final Path circular = Path()
          ..addRRect(
            RRect.fromRectAndRadius(
              rect,
              Radius.circular(radius.clamp(0, size.shortestSide / 2)),
            ),
          );
        expect(_length(smooth), closeTo(_length(circular), 0.01));
        for (double x = 0.25; x < size.width; x += 0.5) {
          for (double y = 0.25; y < size.height; y += 0.5) {
            final Offset p = Offset(x, y);
            expect(smooth.contains(p), circular.contains(p), reason: '$p');
          }
        }
      }
    });

    test('a border is stroked inset by half its width, with the radius less '
        'half the width', () {
      const Rect rect = Rect.fromLTWH(0, 0, 42, 28);
      for (final double smoothing in <double>[0, 0.6]) {
        final _RecordingCanvas canvas = _RecordingCanvas();
        SmoothRectangleBorder(
          side: const BorderSide(color: Color(0xFFECEEF0), width: 2),
          radius: 4,
          smoothing: smoothing,
        ).paint(canvas, rect);
        final (Path path, Paint paint) = canvas.paths.single;
        expect(paint.strokeWidth, 2);
        expect(paint.style, PaintingStyle.stroke);
        expect(paint.color.toARGB32(), 0xFFECEEF0);
        final Rect bounds = path.getBounds();
        expect(bounds.left, closeTo(1, 0.01));
        expect(bounds.right, closeTo(41, 0.01));
        expect(
          _length(path),
          closeTo(_length(smoothRectPath(rect.deflate(1), 3, smoothing)), 0.01),
        );
      }
    });

    test('the decoration is the plain BoxDecoration at smoothing 0, as '
        'before, and the smooth shape otherwise; smoothing is clamped', () {
      const BorderSide side = BorderSide(color: Color(0xFFECEEF0));
      for (final double smoothing in <double>[0, -0.2, double.nan]) {
        expect(
          roundedRectDecoration(
            color: const Color(0x00000000),
            side: side,
            radius: 12,
            smoothing: smoothing,
          ),
          BoxDecoration(
            color: const Color(0x00000000),
            border: Border.all(color: const Color(0xFFECEEF0)),
            borderRadius: BorderRadius.circular(12),
          ),
        );
      }
      expect(
        roundedRectDecoration(radius: 16, smoothing: 0),
        BoxDecoration(borderRadius: BorderRadius.circular(16)),
      );
      expect(
        roundedRectDecoration(side: side, radius: 12, smoothing: 0.6),
        const ShapeDecoration(
          shape: SmoothRectangleBorder(side: side, radius: 12, smoothing: 0.6),
        ),
      );
      expect(clampSmoothing(1.5), 1);
      expect(clampSmoothing(-1), 0);
    });
  });

  group('strings_override.json (CONTRACT §18.6)', () {
    final Map<String, Object?> v = _load('strings_override.json');
    final List<Map<String, Object?>> fields = _list(v['fields']);

    test('the fields are exactly PayriffStrings\' text fields', () {
      expect(
        fields.map((Map<String, Object?> f) => f['field']).toSet(),
        _fieldSetters.keys.toSet(),
      );
      expect(fields, hasLength(_fieldSetters.length));
    });

    for (final Map<String, Object?> field in fields) {
      test('${field['field']} replaces ${field['source']} '
          '${field['key']} in every language, and nothing else', () {
        const String value = 'Ø override';
        final PayriffStrings strings = _fieldSetters[field['field']]!(value);
        for (final PayriffLanguage language in PayriffLanguage.values) {
          expect(_text(field, language, <PayriffStrings>[strings]), value);
          for (final Map<String, Object?> other in fields) {
            if (identical(other, field) ||
                (other['source'] == field['source'] &&
                    other['key'] == field['key'])) {
              continue;
            }
            expect(
              _text(other, language, <PayriffStrings>[strings]),
              _text(other, language, const <PayriffStrings>[]),
              reason: '${other['field']}',
            );
          }
        }
      });
    }

    for (final Map<String, Object?> c in _list(v['resolution'])) {
      test('resolution: ${c['name']}', () {
        final String name = c['field']! as String;
        final Map<String, Object?> field = fields.firstWhere(
          (Map<String, Object?> f) => f['field'] == name,
        );
        expect(
          _text(field, _language(c['language']), <PayriffStrings>[
            _strings(c['view']),
            _strings(c['config']),
          ]),
          c['expect'],
        );
      });
    }

    for (final Map<String, Object?> c in _list(v['payButton'])) {
      test('payButton: ${c['name']}', () {
        final Map<String, Object?> style = c['style']! as Map<String, Object?>;
        final Object? amount = c['amount'];
        expect(
          paymentViewPayTitle(
            PayriffCardStrings(
              _language(c['language']),
              overrides: <PayriffStrings>[_strings(c['strings'])],
            ),
            PayriffClientOrder(
              orderId: testOrderId,
              amount: amount as num?,
              currency: c['currency'] as String?,
            ),
            label: style['payButtonLabel'] as String?,
            title: style['payButtonTitle'] as String?,
          ),
          c['expect'],
        );
      });
    }

    for (final Map<String, Object?> c in _list(v['poweredBy'])) {
      test('poweredBy: "${c['text']}"', () {
        final ({String before, String after}) parts = poweredByPartsOf(
          c['text']! as String,
        );
        final Map<String, Object?> e = c['expect']! as Map<String, Object?>;
        expect(parts.before, e['before']);
        expect(parts.after, e['after']);
      });
    }

    test('PayriffStrings compares by value', () {
      const PayriffStrings a = PayriffStrings(
        pay: 'Ödə',
        errorMessages: <PayriffErrorCode, String>{
          PayriffErrorCode.networkError: 'Offline',
        },
      );
      final PayriffStrings b = PayriffStrings(
        pay: 'Ödə',
        errorMessages: <PayriffErrorCode, String>{
          PayriffErrorCode.networkError: 'Offline',
        },
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const PayriffStrings(pay: 'Ödə')));
      expect(const PayriffStrings().errorMessages, isEmpty);
    });

    testWidgets('errorMessages: the error line shows the app\'s text; the '
        'result and onLoadFailed keep PayriffError.message', (
      WidgetTester tester,
    ) async {
      NativeCalls().install();
      _installFailingApi(404);
      Payriff.configure(
        const PayriffConfig(
          environment: PayriffEnvironment.sandbox,
          publishableKey: testPublishableKey,
          strings: PayriffStrings(
            errorMessages: <PayriffErrorCode, String>{
              PayriffErrorCode.sessionExpired: 'Config: expired',
              PayriffErrorCode.networkError: 'Config: offline',
            },
          ),
        ),
      );
      final List<PayriffResult> results = <PayriffResult>[];
      final List<PayriffError> failures = <PayriffError>[];
      Widget view(PayriffStrings? strings) => MaterialApp(
        home: Scaffold(
          body: PayriffPaymentView(
            orderId: testOrderId,
            clientSecret: testClientSecret,
            language: PayriffLanguage.en,
            strings: strings,
            onResult: results.add,
            onLoadFailed: failures.add,
          ),
        ),
      );
      await tester.pumpWidget(view(null));
      await _frames(tester, 5);
      expect(_errorLine(tester), 'Config: expired');
      expect(results.single.error?.code, PayriffErrorCode.sessionExpired);
      expect(results.single.error?.message, 'Order not found');
      expect(failures.single.message, 'Order not found');

      // The view's text wins; a blank one keeps the config's.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        view(
          const PayriffStrings(
            errorMessages: <PayriffErrorCode, String>{
              PayriffErrorCode.sessionExpired: 'View: expired',
            },
          ),
        ),
      );
      await _frames(tester, 5);
      expect(_errorLine(tester), 'View: expired');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        view(
          const PayriffStrings(
            errorMessages: <PayriffErrorCode, String>{
              PayriffErrorCode.sessionExpired: '  ',
            },
          ),
        ),
      );
      await _frames(tester, 5);
      expect(_errorLine(tester), 'Config: expired');

      // Without an entry for the code: the message, as before.
      Payriff.configure(_config);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(view(null));
      await _frames(tester, 5);
      expect(_errorLine(tester), 'Order not found');
    });

    testWidgets('the view\'s strings win over the config\'s field by field, '
        'in the form and the view', (WidgetTester tester) async {
      await _pumpView(
        tester,
        config: const PayriffConfig(
          environment: PayriffEnvironment.sandbox,
          publishableKey: testPublishableKey,
          strings: PayriffStrings(
            pay: 'Config pay',
            holderLabel: 'Config holder',
            secureNote: 'Config secure',
          ),
        ),
        strings: const PayriffStrings(
          pay: 'View pay',
          cardInformationLabel: 'View card',
          poweredBy: 'Güvenli ödeme',
        ),
      );
      expect(find.text('View pay 10.50 AZN'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(cardLabelKey('holder'))).data,
        'Config holder',
      );
      expect(
        tester.widget<Text>(find.byKey(cardLabelKey('card'))).data,
        'View card',
      );
      expect(find.text('Config secure'), findsOneWidget);
      // A footer without "Payriff" is followed by a space and the logo.
      final Text footer = tester.widget<Text>(
        find.descendant(
          of: find.byKey(paymentViewPoweredByKey),
          matching: find.byType(Text),
        ),
      );
      final List<InlineSpan> spans = (footer.textSpan! as TextSpan).children!;
      expect((spans.first as TextSpan).text, 'Güvenli ödeme ');
      expect(spans.last, isA<WidgetSpan>());
      expect(
        tester.getSemantics(find.byKey(paymentViewPoweredByKey)).label,
        'Güvenli ödeme Payriff',
      );
    });

    testWidgets('the style overrides still win over PayriffStrings', (
      WidgetTester tester,
    ) async {
      await _pumpView(
        tester,
        strings: const PayriffStrings(
          pay: 'Strings pay',
          secureNote: 'Strings secure',
          holderLabel: 'Strings holder',
          cardInformationLabel: 'Strings card',
        ),
        style: const PayriffPaymentViewStyle(
          payButtonLabel: 'Style pay',
          secureNoteText: 'Style secure',
          formStyle: PayriffCardFormStyle(
            holderLabel: 'Style holder',
            cardLabel: 'Style card',
          ),
        ),
      );
      expect(find.text('Style pay 10.50 AZN'), findsOneWidget);
      expect(find.text('Style secure'), findsOneWidget);
      expect(find.text('Style holder'), findsOneWidget);
      expect(find.text('Style card'), findsOneWidget);
      expect(find.textContaining('Strings'), findsNothing);
    });

    testWidgets('the 3-D Secure sheet of confirmCardPayment shows '
        'PayriffConfig.strings; the payment view\'s sheet its own', (
      WidgetTester tester,
    ) async {
      final FakeWebViewPlatform web = installFakeWebView();
      debugPayriffCardClock = FakeCardClock();
      const PayriffConfig config = PayriffConfig(
        environment: PayriffEnvironment.sandbox,
        publishableKey: testPublishableKey,
        strings: PayriffStrings(sheetTitle: 'Config sheet', close: 'Shut'),
      );
      await _pumpView(
        tester,
        backend: FakeClientBackend(payPayload: _challenge()),
        config: config,
        strings: const PayriffStrings(sheetTitle: 'View sheet'),
      );
      await fillCard(tester, holder: 'ELLEN CARTER');
      await tester.tap(find.byKey(paymentViewPayButtonKey));
      await settleSheet(tester);
      expect(find.byType(PayriffThreeDsSheet), findsOneWidget);
      expect(find.text('View sheet'), findsOneWidget);
      expect(find.text('Config sheet'), findsNothing);
      // A field the view does not set comes from the config.
      expect(
        tester.getSemantics(find.byKey(closeButtonKey)).label,
        contains('Shut'),
      );
      _loadPage(web.delegate, _callback);
      await _frames(tester, 20);
      expect(find.byType(PayriffThreeDsSheet), findsNothing);
    });

    test('errorMessages for the lines with their own field: the field '
        'first, then errorMessages, then the built-in text', () {
      const PayriffStrings messages = PayriffStrings(
        errorMessages: <PayriffErrorCode, String>{
          PayriffErrorCode.deviceCompromised: 'Map: device',
          PayriffErrorCode.orderNotPayable: 'Map: not payable',
          PayriffErrorCode.networkError: 'Map: network',
        },
      );
      const PayriffStrings fields = PayriffStrings(
        deviceNotSupported: 'Field: device',
        notPayable: 'Field: not payable',
        pageLoadError: 'Field: page',
      );
      for (final PayriffLanguage language in PayriffLanguage.values) {
        final PayriffCardStrings builtIn = PayriffCardStrings(language);
        final PayriffSheetStrings sheetBuiltIn = PayriffSheetStrings(language);
        // errorMessages without the field.
        PayriffCardStrings card = PayriffCardStrings(
          language,
          overrides: const <PayriffStrings>[messages],
        );
        PayriffSheetStrings sheet = PayriffSheetStrings(
          language,
          overrides: const <PayriffStrings>[messages],
        );
        expect(card.deviceNotSupported, 'Map: device');
        expect(card.notPayable, 'Map: not payable');
        expect(sheet[PayriffStringKey.pageLoadError], 'Map: network');
        // Only those lines: every other text stays.
        expect(card.pay, builtIn.pay);
        expect(card.secure, builtIn.secure);
        for (final PayriffStringKey key in PayriffStringKey.values) {
          if (key == PayriffStringKey.pageLoadError) continue;
          expect(sheet[key], sheetBuiltIn[key], reason: key.id);
        }
        // The field wins, also from a later layer (the config's field over
        // the view's errorMessages).
        card = PayriffCardStrings(
          language,
          overrides: const <PayriffStrings>[messages, fields],
        );
        sheet = PayriffSheetStrings(
          language,
          overrides: const <PayriffStrings>[messages, fields],
        );
        expect(card.deviceNotSupported, 'Field: device');
        expect(card.notPayable, 'Field: not payable');
        expect(sheet[PayriffStringKey.pageLoadError], 'Field: page');
        // A blank field and a blank entry count as not set.
        card = PayriffCardStrings(
          language,
          overrides: const <PayriffStrings>[
            PayriffStrings(
              notPayable: ' ',
              errorMessages: <PayriffErrorCode, String>{
                PayriffErrorCode.deviceCompromised: '  ',
              },
            ),
            messages,
          ],
        );
        expect(card.notPayable, 'Map: not payable');
        expect(card.deviceNotSupported, 'Map: device');
        // Nothing set: the built-in text.
        expect(
          PayriffCardStrings(
            language,
            overrides: const <PayriffStrings>[PayriffStrings()],
          ).notPayable,
          builtIn.notPayable,
        );
        expect(
          PayriffSheetStrings(
            language,
            overrides: const <PayriffStrings>[PayriffStrings()],
          )[PayriffStringKey.pageLoadError],
          sheetBuiltIn[PayriffStringKey.pageLoadError],
        );
      }
    });

    testWidgets('errorMessages on the view\'s not-payable and device lines; '
        'the result keeps its English message', (WidgetTester tester) async {
      const PayriffConfig config = PayriffConfig(
        environment: PayriffEnvironment.sandbox,
        publishableKey: testPublishableKey,
        strings: PayriffStrings(
          errorMessages: <PayriffErrorCode, String>{
            PayriffErrorCode.orderNotPayable: 'Map: not payable',
            PayriffErrorCode.deviceCompromised: 'Map: device',
          },
        ),
      );
      await _pumpView(
        tester,
        backend: FakeClientBackend(orderStatus: 'APPROVED'),
        config: config,
      );
      expect(_errorLine(tester), 'Map: not payable');

      // The view's own field wins over the config's errorMessages.
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpView(
        tester,
        backend: FakeClientBackend(orderStatus: 'APPROVED'),
        config: config,
        strings: const PayriffStrings(notPayable: 'Field: not payable'),
      );
      expect(_errorLine(tester), 'Field: not payable');

      await tester.pumpWidget(const SizedBox.shrink());
      final _Events events = await _pumpView(
        tester,
        native: NativeCalls()..integrityReply = NativeCalls.compromised(),
        config: config,
      );
      expect(_errorLine(tester), 'Map: device');
      expect(
        events.results.single.error?.message,
        'Card payments are not available on this device.',
      );
    });

    testWidgets('errorMessages[NETWORK_ERROR] on the 3-D Secure page-load '
        'error, unless pageLoadError is set', (WidgetTester tester) async {
      for (final (PayriffStrings strings, String expected)
          in <(PayriffStrings, String)>[
            (
              const PayriffStrings(
                errorMessages: <PayriffErrorCode, String>{
                  PayriffErrorCode.networkError: 'Map: network',
                },
              ),
              'Map: network',
            ),
            (
              const PayriffStrings(
                pageLoadError: 'Field: page',
                errorMessages: <PayriffErrorCode, String>{
                  PayriffErrorCode.networkError: 'Map: network',
                },
              ),
              'Field: page',
            ),
          ]) {
        final FakeWebViewPlatform web = installFakeWebView();
        debugPayriffCardClock = FakeCardClock();
        NativeCalls().install();
        FakeClientBackend(
          payPayload: _challenge(),
          statuses: <String>['APPROVED'],
        ).install();
        Payriff.configure(
          PayriffConfig(
            environment: PayriffEnvironment.sandbox,
            publishableKey: testPublishableKey,
            strings: strings,
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
        web.delegate.error(
          code: -1009,
          url: 'https://acs.bank.example/challenge',
        );
        await tester.pump();
        expect(find.text(expected), findsOneWidget);
        expect(
          find.text(
            "The page couldn't be loaded. Check your internet connection.",
          ),
          findsNothing,
        );
        await tester.tap(find.byKey(retryButtonKey));
        await settleSheet(tester);
        _loadPage(web.delegate, _callback);
        expect(
          await pumpUntilDone(tester, future),
          isA<PayriffResultSuccess>(),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        Payriff.debugReset();
      }
    });
  });

  group('Pay button (CONTRACT §18.1, §18.3)', () {
    testWidgets('payButtonTitle is the whole text while loading and after, '
        'without the amount', (WidgetTester tester) async {
      await _pumpView(
        tester,
        style: const PayriffPaymentViewStyle(
          payButtonTitle: '  Ödə €12 ',
          payButtonLabel: 'Buy',
        ),
        strings: const PayriffStrings(pay: 'Öde'),
        frames: 0,
      );
      expect(find.text('Ödə €12'), findsOneWidget);
      await _frames(tester, 5);
      expect(find.text('Ödə €12'), findsOneWidget);
      expect(find.textContaining('10.50'), findsNothing);
      expect(
        tester.getSemantics(find.byKey(paymentViewPayButtonKey)).label,
        'Ödə €12',
      );
    });

    testWidgets('without disabled colours a disabled Pay is the enabled one '
        'at 50% opacity', (WidgetTester tester) async {
      await _pumpView(tester);
      expect(tester.widget<Opacity>(_inPay(Opacity)).opacity, 0.5);
      expect(
        (_decorationOf(tester, _inPay(DecoratedBox)) as BoxDecoration).color,
        payriffBrandColor,
      );
      await fillCard(tester, holder: 'ELLEN CARTER');
      expect(tester.widget<Opacity>(_inPay(Opacity)).opacity, 1);
    });

    testWidgets('disabled colours: full opacity, the disabled fill and text; '
        'enabled is unchanged', (WidgetTester tester) async {
      const Color fill = Color(0xFFE0E0E0);
      const Color text = Color(0xFF616161);
      await _pumpView(
        tester,
        style: const PayriffPaymentViewStyle(
          buttonColor: Color(0xFF6D28D9),
          buttonDisabledColor: fill,
          buttonDisabledTextColor: text,
        ),
      );
      expect(tester.widget<Opacity>(_inPay(Opacity)).opacity, 1);
      expect(
        (_decorationOf(tester, _inPay(DecoratedBox)) as BoxDecoration).color,
        fill,
      );
      expect(tester.widget<Text>(_inPay(Text)).style!.color, text);

      await fillCard(tester, holder: 'ELLEN CARTER');
      expect(tester.widget<Opacity>(_inPay(Opacity)).opacity, 1);
      expect(
        (_decorationOf(tester, _inPay(DecoratedBox)) as BoxDecoration).color,
        const Color(0xFF6D28D9),
      );
      expect(
        tester.widget<Text>(_inPay(Text)).style!.color,
        const Color(0xFFFFFFFF),
      );
    });

    testWidgets('one disabled colour: the other comes from the enabled look', (
      WidgetTester tester,
    ) async {
      await _pumpView(
        tester,
        style: const PayriffPaymentViewStyle(
          buttonDisabledTextColor: Color(0xFF9E9E9E),
        ),
      );
      expect(tester.widget<Opacity>(_inPay(Opacity)).opacity, 1);
      expect(
        (_decorationOf(tester, _inPay(DecoratedBox)) as BoxDecoration).color,
        payriffBrandColor,
      );
      expect(
        tester.widget<Text>(_inPay(Text)).style!.color,
        const Color(0xFF9E9E9E),
      );
    });
  });

  group('badges and the brand mark (CONTRACT §18.4)', () {
    BoxDecoration badge(WidgetTester tester, String brand) =>
        _decorationOf(tester, find.byKey(paymentViewBadgeKey(brand)))
            as BoxDecoration;

    Decoration brandMark(WidgetTester tester) => _decorationOf(
      tester,
      find.descendant(
        of: find.byKey(cardBrandKey),
        matching: find.byType(DecoratedBox),
      ),
    );

    testWidgets('the badges are the frameless marks in a frame drawn in '
        'code: 1 wide, outer radius 4, #ECEEF0, no fill', (
      WidgetTester tester,
    ) async {
      await _pumpView(tester);
      for (final (String brand, String mark, double width)
          in <(String, String, double)>[
            ('mastercard', PaymentViewAssets.mastercardMark, 43),
            ('visa', PaymentViewAssets.visaMark, 42),
          ]) {
        expect(
          badge(tester, brand),
          BoxDecoration(
            border: Border.all(color: const Color(0xFFECEEF0)),
            borderRadius: BorderRadius.circular(4),
          ),
        );
        expect(
          tester.getSize(find.byKey(paymentViewBadgeKey(brand))),
          Size(width, 28),
        );
        final Image image = tester.widget<Image>(
          find.descendant(
            of: find.byKey(paymentViewBadgeKey(brand)),
            matching: find.byType(Image),
          ),
        );
        expect((image.image as AssetImage).assetName, mark);
      }
      // The badges' gap and order are as before.
      final Rect mastercard = tester.getRect(
        find.byKey(paymentViewBadgeKey('mastercard')),
      );
      final Rect visa = tester.getRect(find.byKey(paymentViewBadgeKey('visa')));
      expect(visa.left - mastercard.right, 8);
      // The brand mark keeps its #D1D1D6 border.
      await tester.enterText(find.byKey(cardNumberFieldKey), '4111');
      await tester.pumpAndSettle();
      expect(
        (brandMark(tester) as BoxDecoration).border,
        Border.all(color: const Color(0xFFD1D1D6)),
      );
    });

    testWidgets('badgeBorderColor colours the frames and, in the view, the '
        'brand mark; brandMarkBorderColor wins for the mark', (
      WidgetTester tester,
    ) async {
      const Color badges = Color(0xFF00897B);
      await _pumpView(
        tester,
        style: const PayriffPaymentViewStyle(badgeBorderColor: badges),
      );
      expect(badge(tester, 'visa').border, Border.all(color: badges));
      expect(badge(tester, 'mastercard').border, Border.all(color: badges));
      await tester.enterText(find.byKey(cardNumberFieldKey), '5555');
      await tester.pumpAndSettle();
      expect(
        (brandMark(tester) as BoxDecoration).border,
        Border.all(color: badges),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpView(
        tester,
        style: const PayriffPaymentViewStyle(
          badgeBorderColor: badges,
          formStyle: PayriffCardFormStyle(
            brandMarkBorderColor: Color(0xFF6A1B9A),
          ),
        ),
      );
      await tester.enterText(find.byKey(cardNumberFieldKey), '5555');
      await tester.pumpAndSettle();
      expect(
        (brandMark(tester) as BoxDecoration).border,
        Border.all(color: const Color(0xFF6A1B9A)),
      );
      expect(badge(tester, 'visa').border, Border.all(color: badges));
    });

    testWidgets('a form outside the view: brandMarkBorderColor, else '
        '#D1D1D6', (WidgetTester tester) async {
      NativeCalls().install();
      final PayriffCardController controller = PayriffCardController();
      addTearDown(controller.dispose);
      await pumpCardApp(
        tester,
        controller,
        style: const PayriffCardFormStyle(
          brandMarkBorderColor: Color(0xFF123456),
        ),
      );
      await tester.enterText(find.byKey(cardNumberFieldKey), '4111');
      await tester.pumpAndSettle();
      expect(
        (brandMark(tester) as BoxDecoration).border,
        Border.all(color: const Color(0xFF123456)),
      );
      expect(cardBrandMarkBorderColor, const Color(0xFFD1D1D6));
    });
  });

  group('corner smoothing in the widgets (CONTRACT §18.2)', () {
    testWidgets('the view\'s smoothing reaches the card box, the holder, the '
        'brand mark, the Pay button and the badges', (
      WidgetTester tester,
    ) async {
      await _pumpView(
        tester,
        style: const PayriffPaymentViewStyle(cornerSmoothing: 0.6),
      );
      ShapeDecoration shape(Finder finder) =>
          _decorationOf(tester, finder) as ShapeDecoration;
      expect(
        shape(find.byKey(cardBoxKey(cardInformationSection))).shape,
        const SmoothRectangleBorder(
          side: BorderSide(color: Color(0xFFECEEF0)),
          radius: 12,
          smoothing: 0.6,
        ),
      );
      expect(
        shape(find.byKey(cardBoxKey('holder'))).shape,
        isA<SmoothRectangleBorder>(),
      );
      // The rows are clipped to the inner outline.
      expect(
        find.descendant(
          of: find.byKey(cardBoxKey(cardInformationSection)),
          matching: find.byType(ClipPath),
        ),
        findsOneWidget,
      );
      expect(
        shape(_inPay(DecoratedBox)),
        const ShapeDecoration(
          color: payriffBrandColor,
          shape: SmoothRectangleBorder(radius: 16, smoothing: 0.6),
        ),
      );
      expect(
        shape(find.byKey(paymentViewBadgeKey('visa'))).shape,
        const SmoothRectangleBorder(
          side: BorderSide(color: Color(0xFFECEEF0)),
          radius: 4,
          smoothing: 0.6,
        ),
      );
      await tester.enterText(find.byKey(cardNumberFieldKey), '4111');
      await tester.pumpAndSettle();
      expect(
        shape(
          find.descendant(
            of: find.byKey(cardBrandKey),
            matching: find.byType(DecoratedBox),
          ),
        ).shape,
        const SmoothRectangleBorder(
          side: BorderSide(color: Color(0xFFD1D1D6)),
          radius: 4,
          smoothing: 0.6,
        ),
      );
    });

    testWidgets('the form\'s own smoothing wins over the view\'s', (
      WidgetTester tester,
    ) async {
      await _pumpView(
        tester,
        style: const PayriffPaymentViewStyle(
          cornerSmoothing: 0.6,
          formStyle: PayriffCardFormStyle(cornerSmoothing: 0),
        ),
      );
      expect(
        _decorationOf(tester, find.byKey(cardBoxKey(cardInformationSection))),
        isA<BoxDecoration>(),
      );
      expect(
        _decorationOf(tester, _inPay(DecoratedBox)),
        isA<ShapeDecoration>(),
      );
    });

    testWidgets('a smooth form outside the view', (WidgetTester tester) async {
      NativeCalls().install();
      final PayriffCardController controller = PayriffCardController();
      addTearDown(controller.dispose);
      await pumpCardApp(
        tester,
        controller,
        style: const PayriffCardFormStyle(
          cornerSmoothing: 1,
          layout: PayriffCardFormLayout.stacked,
        ),
      );
      for (final String section in <String>['number', 'expiry', 'cvv']) {
        expect(
          (_decorationOf(tester, find.byKey(cardBoxKey(section)))
                  as ShapeDecoration)
              .shape,
          const SmoothRectangleBorder(
            side: BorderSide(color: Color(0xFFECEEF0)),
            radius: 12,
            smoothing: 1,
          ),
        );
      }
    });

    test('the styles default to no smoothing and take part in ==, hashCode '
        'and copyWith', () {
      const PayriffPaymentViewStyle view = PayriffPaymentViewStyle();
      expect(view.cornerSmoothing, 0);
      expect(view.payButtonTitle, isNull);
      expect(view.buttonDisabledColor, isNull);
      expect(view.buttonDisabledTextColor, isNull);
      expect(view.badgeBorderColor, isNull);
      const PayriffCardFormStyle form = PayriffCardFormStyle();
      expect(form.cornerSmoothing, isNull);
      expect(form.brandMarkBorderColor, isNull);
      const PayriffPaymentViewStyle set = PayriffPaymentViewStyle(
        payButtonTitle: 'Pay',
        cornerSmoothing: 0.6,
        buttonDisabledColor: Color(0xFF111111),
        buttonDisabledTextColor: Color(0xFF222222),
        badgeBorderColor: Color(0xFF333333),
        formStyle: PayriffCardFormStyle(
          cornerSmoothing: 0.4,
          brandMarkBorderColor: Color(0xFF444444),
        ),
      );
      final PayriffPaymentViewStyle copy = view.copyWith(
        payButtonTitle: 'Pay',
        cornerSmoothing: 0.6,
        buttonDisabledColor: const Color(0xFF111111),
        buttonDisabledTextColor: const Color(0xFF222222),
        badgeBorderColor: const Color(0xFF333333),
        formStyle: form.copyWith(
          cornerSmoothing: 0.4,
          brandMarkBorderColor: const Color(0xFF444444),
        ),
      );
      expect(copy, set);
      expect(copy.hashCode, set.hashCode);
      expect(set, isNot(view.copyWith(cornerSmoothing: 0.6)));
      expect(
        form.copyWith(cornerSmoothing: 0.4),
        isNot(form.copyWith(cornerSmoothing: 0.5)),
      );
    });
  });

  group('callbacks (CONTRACT §18.5)', () {
    testWidgets('card: onOrderLoaded once per read, onPaymentStarted once per '
        'attempt before anything is sent, then onResult', (
      WidgetTester tester,
    ) async {
      debugPayriffCardClock = FakeCardClock();
      final NativeCalls native = NativeCalls();
      final FakeClientBackend backend = FakeClientBackend();
      // The first attempt fails without ending the order.
      backend.payFailures.add(500);
      int attempts = 0;
      final _Events events = _Events()
        ..onStarted = (PayriffPaymentMethod method) {
          expect(method, PayriffPaymentMethod.card);
          // Nothing of this attempt was encrypted or sent yet.
          expect(backend.to('/pay'), hasLength(attempts));
          expect(native.named('encryptCard'), hasLength(attempts));
          attempts++;
        };
      await _pumpView(tester, backend: backend, native: native, events: events);
      expect(events.log, <String>['loaded $testOrderId']);

      // Pay is disabled while the form is incomplete: no attempt.
      await tester.tap(find.byKey(paymentViewPayButtonKey));
      await tester.pump();
      expect(events.log, <String>['loaded $testOrderId']);

      await fillCard(tester, holder: 'ELLEN CARTER');
      await tester.tap(find.byKey(paymentViewPayButtonKey));
      await _frames(tester, 20);
      expect(events.log, <String>[
        'loaded $testOrderId',
        'started card',
        'result failed',
      ]);
      expect(events.results.single.error?.code, PayriffErrorCode.paymentFailed);

      await fillCard(tester, holder: 'ELLEN CARTER');
      await tester.tap(find.byKey(paymentViewPayButtonKey));
      await _frames(tester, 20);
      expect(events.log, <String>[
        'loaded $testOrderId',
        'started card',
        'result failed',
        'started card',
        'result success',
      ]);
      expect(events.loadFailures, isEmpty);
    });

    testWidgets('onOrderLoaded also for an order that cannot be paid by card, '
        'and again for a new client secret', (WidgetTester tester) async {
      final _Events events = _Events();
      final FakeClientBackend backend = FakeClientBackend(
        orderStatus: 'APPROVED',
      );
      await _pumpView(tester, backend: backend, events: events);
      expect(events.log, <String>['loaded $testOrderId']);
      expect(_errorLine(tester), 'This order cannot be paid by card');
      await _pumpView(
        tester,
        backend: backend,
        events: events,
        clientSecret: '${testClientSecret}2',
      );
      expect(events.log, <String>[
        'loaded $testOrderId',
        'loaded $testOrderId',
      ]);
    });

    testWidgets('onLoadFailed: an order that cannot be read, and a fatal one '
        'also once to onResult', (WidgetTester tester) async {
      NativeCalls().install();
      _installFailingApi(404);
      final _Events failing = _Events();
      Payriff.configure(_config);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PayriffPaymentView(
              orderId: testOrderId,
              clientSecret: testClientSecret,
              onResult: failing.results.add,
              onOrderLoaded: (_) => failing.log.add('loaded'),
              onLoadFailed: failing.loadFailures.add,
            ),
          ),
        ),
      );
      await _frames(tester, 5);
      expect(failing.log, isEmpty);
      expect(failing.loadFailures.single.code, PayriffErrorCode.sessionExpired);
      expect(failing.results.single.error, failing.loadFailures.single);

      // Not fatal (no response): onLoadFailed only.
      await tester.pumpWidget(const SizedBox.shrink());
      debugPayriffClientApiHttpClient = () => MockClient(
        (http.Request request) async => throw http.ClientException('offline'),
      );
      final _Events offline = _Events();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PayriffPaymentView(
              orderId: testOrderId,
              clientSecret: testClientSecret,
              onResult: offline.results.add,
              onLoadFailed: offline.loadFailures.add,
            ),
          ),
        ),
      );
      await _frames(tester, 5);
      expect(offline.loadFailures.single.code, PayriffErrorCode.networkError);
      expect(offline.results, isEmpty);
    });

    testWidgets('onLoadFailed: a compromised device, without reading the '
        'order', (WidgetTester tester) async {
      final FakeClientBackend backend = FakeClientBackend();
      final _Events events = _Events();
      await _pumpView(
        tester,
        backend: backend,
        native: NativeCalls()..integrityReply = NativeCalls.compromised(),
        events: events,
      );
      expect(events.log, <String>[
        'loadFailed DEVICE_COMPROMISED',
        'result failed',
      ]);
      expect(backend.requests, isEmpty);
    });

    testWidgets('Google Pay: onPaymentStarted before its sheet opens', (
      WidgetTester tester,
    ) async {
      debugPayriffCardClock = FakeCardClock();
      final FakePlatformViews views = FakePlatformViews()..install();
      final NativeCalls native = NativeCalls();
      final _Events events = _Events()
        ..onStarted = (PayriffPaymentMethod method) {
          expect(method, PayriffPaymentMethod.googlePay);
          expect(native.named('googlePayLoad'), isEmpty);
        };
      await _pumpView(
        tester,
        backend: FakeClientBackend(
          paymentMethods: const <String>['CARD', 'GOOGLE_PAY'],
          googlePay: testGooglePayGateway,
        ),
        native: native,
        config: const PayriffConfig(
          environment: PayriffEnvironment.sandbox,
          publishableKey: testPublishableKey,
          googlePay: PayriffGooglePayConfig(),
        ),
        events: events,
        frames: 10,
      );
      await views.tap(views.live('payriff/google_pay_button').single);
      await _frames(tester, 20);
      expect(events.log, <String>[
        'loaded $testOrderId',
        'started googlePay',
        'result success',
      ]);
      expect(native.named('googlePayLoad'), hasLength(1));
      expect(PayriffPaymentMethod.googlePay.value, 'GOOGLE_PAY');
      expect(PayriffPaymentMethod.card.value, 'CARD');
      expect(PayriffPaymentMethod.applePay.value, 'APPLE_PAY');
    });
  });

  group('layout direction (CONTRACT §18.7)', () {
    Future<void> pumpRtlForm(WidgetTester tester) async {
      NativeCalls().install();
      final PayriffCardController controller = PayriffCardController();
      addTearDown(controller.dispose);
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  PayriffCardForm(
                    controller: controller,
                    language: PayriffLanguage.en,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    TextField field(WidgetTester tester, Key key) =>
        tester.widget<TextField>(find.byKey(key));

    TextDirection editable(WidgetTester tester, Key key) => tester
        .state<EditableTextState>(
          find.descendant(
            of: find.byKey(key),
            matching: find.byType(EditableText),
          ),
        )
        .renderEditable
        .textDirection;

    testWidgets('right to left: the rows mirror, the number, expiry and CVC '
        'stay left to right, the holder follows', (WidgetTester tester) async {
      await pumpRtlForm(tester);
      for (final Key key in <Key>[
        cardNumberFieldKey,
        cardExpiryFieldKey,
        cardCvvFieldKey,
      ]) {
        final TextField input = field(tester, key);
        expect(input.textDirection, TextDirection.ltr, reason: '$key');
        expect(input.textAlign, TextAlign.left, reason: '$key');
        expect(input.decoration!.hintTextDirection, TextDirection.ltr);
        expect(editable(tester, key), TextDirection.ltr);
      }
      expect(field(tester, cardHolderFieldKey).textDirection, isNull);
      expect(editable(tester, cardHolderFieldKey), TextDirection.rtl);

      final Rect number = tester.getRect(find.byKey(cardNumberFieldKey));
      final Rect brand = tester.getRect(find.byKey(cardBrandKey));
      final Rect expiry = tester.getRect(find.byKey(cardExpiryFieldKey));
      final Rect cvv = tester.getRect(find.byKey(cardCvvFieldKey));
      final Rect box = tester.getRect(
        find.byKey(cardBoxKey(cardInformationSection)),
      );
      // The brand mark is on the trailing (left) side, the CVC left of the
      // expiry.
      expect(brand.right, lessThan(number.left));
      expect(box.left + 1 + 14, brand.left);
      expect(cvv.right, lessThan(expiry.left));
      // Labels and errors align to the leading (right) edge.
      final Rect label = tester.getRect(
        find.byKey(cardLabelKey(cardInformationSection)),
      );
      expect(label.right, closeTo(box.right, 0.5));
      final PayriffCardController controller = PayriffCardController();
      addTearDown(controller.dispose);
    });

    testWidgets('left to right by default: the inputs are left to right too, '
        'and the holder follows the layout', (WidgetTester tester) async {
      NativeCalls().install();
      final PayriffCardController controller = PayriffCardController();
      addTearDown(controller.dispose);
      await pumpCardApp(tester, controller);
      expect(editable(tester, cardNumberFieldKey), TextDirection.ltr);
      expect(editable(tester, cardHolderFieldKey), TextDirection.ltr);
      final Rect number = tester.getRect(find.byKey(cardNumberFieldKey));
      final Rect brand = tester.getRect(find.byKey(cardBrandKey));
      expect(brand.left, greaterThan(number.right));
    });

    testWidgets('the payment view follows a right-to-left host', (
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
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: PayriffPaymentView(
                orderId: testOrderId,
                clientSecret: testClientSecret,
                language: PayriffLanguage.en,
                onResult: (_) {},
              ),
            ),
          ),
        ),
      );
      await _frames(tester, 5);
      // The badge row mirrors: Mastercard is on the right.
      expect(
        tester.getRect(find.byKey(paymentViewBadgeKey('mastercard'))).left,
        greaterThan(
          tester.getRect(find.byKey(paymentViewBadgeKey('visa'))).right,
        ),
      );
      expect(
        tester.widget<TextField>(find.byKey(cardNumberFieldKey)).textDirection,
        TextDirection.ltr,
      );
    });
  });

  group('Payriff.isSupported (CONTRACT §18.8)', () {
    void answer(Object? Function() reply) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('payriff/native'), (
            MethodCall call,
          ) async {
            if (call.method == 'isSupported') {
              final Object? value = reply();
              if (value is Exception) throw value;
              return value;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('payriff/native'),
              null,
            ),
      );
    }

    testWidgets('Android and iOS ask the plugin for the OS version', (
      WidgetTester tester,
    ) async {
      answer(() => true);
      expect(await Payriff.isSupported(), isTrue);
      answer(() => false);
      expect(await Payriff.isSupported(), isFalse);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('iOS', (WidgetTester tester) async {
      answer(() => true);
      expect(await Payriff.isSupported(), isTrue);
      answer(() => false);
      expect(await Payriff.isSupported(), isFalse);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('a failure or no plugin is false', (WidgetTester tester) async {
      answer(() => PlatformException(code: 'error'));
      expect(await Payriff.isSupported(), isFalse);
      answer(() => null);
      expect(await Payriff.isSupported(), isFalse);
      answer(MissingPluginException.new);
      expect(await Payriff.isSupported(), isFalse);
    });

    testWidgets('other platforms are false without asking', (
      WidgetTester tester,
    ) async {
      bool asked = false;
      answer(() {
        asked = true;
        return true;
      });
      expect(await Payriff.isSupported(), isFalse);
      expect(asked, isFalse);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  });
}

Matcher _closeTo(Offset expected) => predicate<Offset>(
  (Offset actual) => (actual - expected).distance < 0.001,
  'within 0.001 of $expected',
);
