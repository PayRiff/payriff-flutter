// CONTRACT §16.4 and §16.5: the native card form.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payriff/payriff.dart';
import 'package:payriff/src/card/card_form.dart';

import 'support/card_support.dart';

TextField _field(WidgetTester tester, Key key) =>
    tester.widget<TextField>(find.byKey(key));

String? _text(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).data;

/// The error line under [section], or `null` when it has none.
String? _errorLine(WidgetTester tester, String section) {
  final Finder line = find.byKey(cardErrorKey(section));
  return line.evaluate().isEmpty ? null : tester.widget<Text>(line).data;
}

BoxDecoration _box(WidgetTester tester, String section) =>
    tester.widget<DecoratedBox>(find.byKey(cardBoxKey(section))).decoration
        as BoxDecoration;

Color _outline(WidgetTester tester, String section) =>
    (_box(tester, section).border! as Border).top.color;

Rect _rect(WidgetTester tester, Key key) => tester.getRect(find.byKey(key));

const String _card = cardInformationSection;
const Color _idle = Color(0xFFECEEF0);
const Color _brand = Color(0xFF4DBDC6);
const Color _red = Color(0xFFEC4D3D);

void main() {
  setUp(Payriff.debugReset);
  tearDown(Payriff.debugReset);

  testWidgets('input security: no copy, masked CVV, autofill hints, no '
      'keyboard learning (§16.5)', (WidgetTester tester) async {
    NativeCalls().install();
    final PayriffCardController controller = PayriffCardController();
    addTearDown(controller.dispose);
    await pumpCardApp(tester, controller);

    final TextField number = _field(tester, cardNumberFieldKey);
    final TextField expiry = _field(tester, cardExpiryFieldKey);
    final TextField cvv = _field(tester, cardCvvFieldKey);
    final TextField holder = _field(tester, cardHolderFieldKey);
    for (final TextField f in <TextField>[number, expiry, cvv, holder]) {
      expect(f.autocorrect, isFalse);
      expect(f.enableSuggestions, isFalse);
      expect(f.enableIMEPersonalizedLearning, isFalse);
      expect(f.smartDashesType, SmartDashesType.disabled);
      expect(f.smartQuotesType, SmartQuotesType.disabled);
    }
    expect(number.enableInteractiveSelection, isFalse);
    expect(cvv.enableInteractiveSelection, isFalse);
    expect(cvv.obscureText, isTrue);
    expect(number.obscureText, isFalse);
    expect(number.keyboardType, TextInputType.number);
    expect(expiry.keyboardType, TextInputType.number);
    expect(cvv.keyboardType, TextInputType.number);
    expect(number.autofillHints, <String>[AutofillHints.creditCardNumber]);
    expect(expiry.autofillHints, <String>[
      AutofillHints.creditCardExpirationDate,
    ]);
    expect(holder.autofillHints, <String>[AutofillHints.creditCardName]);
    expect(cvv.autofillHints, isNull);
    expect(
      tester.widget<AutofillGroup>(find.byType(AutofillGroup)).onDisposeAction,
      AutofillContextAction.cancel,
    );
  });

  testWidgets('keyboard copy and cut do nothing on the number', (
    WidgetTester tester,
  ) async {
    NativeCalls().install();
    final List<MethodCall> clipboard = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method.startsWith('Clipboard.')) clipboard.add(call);
        return null;
      },
    );
    final PayriffCardController controller = PayriffCardController();
    addTearDown(controller.dispose);
    await pumpCardApp(tester, controller);
    await tester.enterText(find.byKey(cardNumberFieldKey), '4111111111111111');
    final TextEditingController text = _field(
      tester,
      cardNumberFieldKey,
    ).controller!;
    text.selection = TextSelection(
      baseOffset: 0,
      extentOffset: text.text.length,
    );
    await tester.pump();
    for (final LogicalKeyboardKey key in <LogicalKeyboardKey>[
      LogicalKeyboardKey.keyC,
      LogicalKeyboardKey.keyX,
    ]) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    }
    await tester.pump();
    expect(
      clipboard.where((MethodCall c) => c.method == 'Clipboard.setData'),
      isEmpty,
    );
    expect(text.text, '4111 1111 1111 1111');
  });

  testWidgets('a cleared card cannot come back through undo or redo (§16.5)', (
    WidgetTester tester,
  ) async {
    NativeCalls().install();
    final PayriffCardController controller = PayriffCardController();
    addTearDown(controller.dispose);
    await pumpCardApp(tester, controller);
    final Map<Key, List<String>> typing = <Key, List<String>>{
      cardNumberFieldKey: <String>['4111', '41111111', '4111111111111111'],
      cardExpiryFieldKey: <String>['1', '12', '1230'],
      cardCvvFieldKey: <String>['1', '12', '123'],
      cardHolderFieldKey: <String>['JO', 'JOHN', 'JOHN DOE'],
    };
    for (final MapEntry<Key, List<String>> field in typing.entries) {
      for (final String text in field.value) {
        await tester.enterText(find.byKey(field.key), text);
        // Longer than the undo history's 500 ms grouping: every step is kept.
        await tester.pump(const Duration(milliseconds: 600));
      }
    }

    controller.clear();
    await tester.pump();
    for (final Key key in typing.keys) {
      // Focusing the empty field records it in the undo history.
      await tester.tap(find.byKey(key));
      await tester.pump(const Duration(milliseconds: 600));
      for (final LogicalKeyboardKey shortcut in <LogicalKeyboardKey>[
        LogicalKeyboardKey.keyZ, // undo
        LogicalKeyboardKey.keyZ,
        LogicalKeyboardKey.keyY, // redo
      ]) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
        await tester.sendKeyEvent(shortcut);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
        await tester.pump();
        expect(_field(tester, key).controller!.text, isEmpty, reason: '$key');
      }
    }
    expect(controller.isComplete, isFalse);
  });

  testWidgets('formats while typing and auto-advances to the next field', (
    WidgetTester tester,
  ) async {
    NativeCalls().install();
    final PayriffCardController controller = PayriffCardController();
    addTearDown(controller.dispose);
    await pumpCardApp(tester, controller, showHolder: false);

    await tester.showKeyboard(find.byKey(cardNumberFieldKey));
    await tester.enterText(find.byKey(cardNumberFieldKey), '5555555555554444');
    await tester.pump();
    expect(
      _field(tester, cardNumberFieldKey).controller!.text,
      '5555 5555 5555 4444',
    );
    expect(controller.brand, PayriffCardBrand.mastercard);
    expect(tester.getSemantics(find.byKey(cardBrandKey)).label, 'Mastercard');
    // Valid with the caret at the end: the focus moves on.
    expect(_field(tester, cardExpiryFieldKey).focusNode!.hasFocus, isTrue);

    await tester.enterText(find.byKey(cardExpiryFieldKey), '4');
    await tester.pump();
    expect(_field(tester, cardExpiryFieldKey).controller!.text, '04 / ');
    await tester.enterText(find.byKey(cardExpiryFieldKey), '04 / 30');
    await tester.pump();
    expect(_field(tester, cardCvvFieldKey).focusNode!.hasFocus, isTrue);

    await tester.enterText(find.byKey(cardCvvFieldKey), '12a34');
    await tester.pump();
    expect(_field(tester, cardCvvFieldKey).controller!.text, '123');
    expect(controller.isComplete, isTrue);
  });

  testWidgets('autoAdvance can be turned off', (WidgetTester tester) async {
    NativeCalls().install();
    final PayriffCardController controller = PayriffCardController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PayriffCardForm(
            controller: controller,
            autoAdvance: false,
            language: PayriffLanguage.en,
          ),
        ),
      ),
    );
    await tester.showKeyboard(find.byKey(cardNumberFieldKey));
    await tester.enterText(find.byKey(cardNumberFieldKey), '4111111111111111');
    await tester.pump();
    expect(_field(tester, cardNumberFieldKey).focusNode!.hasFocus, isTrue);
  });

  testWidgets('errors show at the right time (visibleError), each under its '
      'field when stacked', (WidgetTester tester) async {
    NativeCalls().install();
    final List<PayriffCardFormChange> changes = <PayriffCardFormChange>[];
    final PayriffCardController controller = PayriffCardController();
    addTearDown(controller.dispose);
    await pumpCardApp(
      tester,
      controller,
      onChanged: changes.add,
      style: const PayriffCardFormStyle(layout: PayriffCardFormLayout.stacked),
    );

    await tester.showKeyboard(find.byKey(cardNumberFieldKey));
    await tester.enterText(find.byKey(cardNumberFieldKey), '4111');
    await tester.pump();
    // Incomplete while typing: not shown.
    expect(find.text('Card number is incomplete'), findsNothing);
    // Leaving the field shows it.
    await tester.showKeyboard(find.byKey(cardCvvFieldKey));
    await tester.pump();
    expect(find.text('Card number is incomplete'), findsOneWidget);
    // A definite error shows at once, even while typing.
    await tester.enterText(find.byKey(cardCvvFieldKey), '1');
    await tester.showKeyboard(find.byKey(cardExpiryFieldKey));
    await tester.enterText(find.byKey(cardExpiryFieldKey), '1320');
    await tester.pump();
    expect(find.text('Expiry date is invalid'), findsOneWidget);
    // An empty field that was only tabbed through shows nothing.
    expect(find.text('Enter the CVV'), findsNothing);

    final PayriffCardFormChange last = changes.lastWhere(
      (PayriffCardFormChange c) => c.field == PayriffCardField.number,
    );
    expect(last.valid, isFalse);
    expect(last.error, PayriffCardFieldErrorCode.incomplete);
    expect(last.errorMessage, 'Card number is incomplete');
    expect(last.brand, PayriffCardBrand.visa);
    expect(last.complete, isFalse);
    for (final PayriffCardFormChange c in changes) {
      expect(c.toString(), isNot(contains('4111')));
    }
  });

  testWidgets('copy follows the language; the holder is normalized', (
    WidgetTester tester,
  ) async {
    NativeCalls().install();
    final PayriffCardController controller = PayriffCardController();
    addTearDown(controller.dispose);
    await pumpCardApp(tester, controller, language: PayriffLanguage.az);
    expect(_text(tester, cardLabelKey('holder')), 'Kart sahibinin adı');
    expect(_text(tester, cardLabelKey(_card)), 'Kart məlumatları');
    expect(
      tester.getSemantics(find.byKey(cardNumberFieldKey)).label,
      startsWith('Kart nömrəsi'),
    );
    await fillCard(tester, holder: '  Ellen   Carter ');
    final CardFormCheck check = checkCardForm(controller)!;
    expect(check.errors, isEmpty);
    // CONTRACT §16.4: normalized and always upper case.
    expect(check.card!.cardHolder, 'ELLEN CARTER');
    expect(check.card!.pan, '4111111111111111');
    expect(check.card!.expiryMonth, '12');
    expect(check.card!.expiryYear, '2030');
  });

  testWidgets('screen protection while mounted; locked while processing; '
      'clear() empties every field', (WidgetTester tester) async {
    final NativeCalls native = NativeCalls()..install();
    final PayriffCardController controller = PayriffCardController();
    addTearDown(controller.dispose);
    await pumpCardApp(tester, controller, showHolder: false);
    expect(native.secureCount, 1);
    expect(controller.isAttached, isTrue);

    await fillCard(tester);
    setCardFormProcessing(controller, true);
    await tester.pump();
    expect(_field(tester, cardNumberFieldKey).enabled, isFalse);
    expect(controller.isProcessing, isTrue);
    setCardFormProcessing(controller, false);
    await tester.pump();
    expect(_field(tester, cardNumberFieldKey).enabled, isTrue);

    controller.clear();
    await tester.pump();
    expect(_field(tester, cardNumberFieldKey).controller!.text, isEmpty);
    expect(_field(tester, cardCvvFieldKey).controller!.text, isEmpty);
    expect(controller.isComplete, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(native.secureCount, 0);
    expect(controller.isAttached, isFalse);
  });

  group('layout and appearance (§16.4)', () {
    testWidgets('the default form shows the holder, like pay.payriff.com: '
        '"Card holder", then the "Card information" box', (
      WidgetTester tester,
    ) async {
      NativeCalls().install();
      final PayriffCardController controller = PayriffCardController();
      addTearDown(controller.dispose);
      // No showHolder argument: the form's own default.
      final PayriffCardForm form = PayriffCardForm(
        controller: controller,
        language: PayriffLanguage.en,
      );
      expect(form.showHolder, isTrue);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: form)));

      expect(_text(tester, cardLabelKey('holder')), 'Card holder');
      expect(
        find.descendant(
          of: find.byKey(cardBoxKey('holder')),
          matching: find.byKey(cardHolderFieldKey),
        ),
        findsOneWidget,
      );
      expect(_text(tester, cardLabelKey(_card)), 'Card information');
      expect(
        _rect(tester, cardBoxKey('holder')).bottom,
        lessThan(_rect(tester, cardLabelKey(_card)).top),
      );

      // The holder is required, and the typed name is sent, not `Unknown`.
      await fillCard(tester);
      expect(controller.isComplete, isFalse);
      expect(checkCardForm(controller)!.errors, const <PayriffCardFieldError>[
        PayriffCardFieldError(
          field: PayriffCardField.holder,
          error: PayriffCardFieldErrorCode.required,
        ),
      ]);
      await tester.enterText(find.byKey(cardHolderFieldKey), 'Ellen Carter');
      await tester.pump();
      expect(controller.isComplete, isTrue);
      expect(checkCardForm(controller)!.card!.cardHolder, 'ELLEN CARTER');
    });

    testWidgets('grouped by default, like pay.payriff.com: the holder, then '
        'one card box with the number above expiry | CVC', (
      WidgetTester tester,
    ) async {
      NativeCalls().install();
      final PayriffCardController controller = PayriffCardController();
      addTearDown(controller.dispose);
      await pumpCardApp(tester, controller);

      // Two labels; the fields' own labels are only accessibility labels.
      expect(_text(tester, cardLabelKey('holder')), 'Card holder');
      expect(_text(tester, cardLabelKey(_card)), 'Card information');
      for (final String label in <String>[
        'Card number',
        'Expiry date',
        'Security code',
      ]) {
        expect(find.text(label), findsNothing);
      }
      expect(find.text('1234 1234 1234 1234'), findsOneWidget);
      expect(find.text('MM / YY'), findsOneWidget);
      expect(find.text('CVC'), findsOneWidget);
      // The holder's label and its placeholder.
      expect(find.text('Card holder'), findsNWidgets(2));

      final Finder holderBox = find.byKey(cardBoxKey('holder'));
      final Finder cardBox = find.byKey(cardBoxKey(_card));
      expect(
        find.descendant(
          of: holderBox,
          matching: find.byKey(cardHolderFieldKey),
        ),
        findsOneWidget,
      );
      for (final Key key in <Key>[
        cardNumberFieldKey,
        cardExpiryFieldKey,
        cardCvvFieldKey,
        cardBrandKey,
      ]) {
        expect(
          find.descendant(of: cardBox, matching: find.byKey(key)),
          findsOneWidget,
        );
      }

      // Holder label, holder box, card label, card box: 10 between a label
      // and its box, 16 between the sections (§16.14).
      final Rect holderLabel = _rect(tester, cardLabelKey('holder'));
      final Rect holder = tester.getRect(holderBox);
      final Rect cardLabel = _rect(tester, cardLabelKey(_card));
      final Rect box = tester.getRect(cardBox);
      expect(holder.top - holderLabel.bottom, 10);
      expect(cardLabel.top - holder.bottom, 16);
      expect(box.top - cardLabel.bottom, 10);

      // A 46-high holder field; two 40-high rows that share their 1-wide
      // divider; expiry and CVC split the second row in half (§16.14).
      expect(holder.height, 46);
      expect(box.height, 40 + 40 - 1);
      final Rect number = _rect(tester, cardNumberFieldKey);
      final Rect expiry = _rect(tester, cardExpiryFieldKey);
      final Rect cvv = _rect(tester, cardCvvFieldKey);
      expect(number.center.dy, closeTo(box.top + 20, 1));
      expect(expiry.center.dy, closeTo(box.top + 40 - 1 + 20, 1));
      expect(cvv.center.dy, expiry.center.dy);
      expect(expiry.left - box.left, 1 + 14);
      expect(box.right - cvv.right, 1 + 14);
      expect(expiry.width, closeTo(cvv.width, 0.001));
      expect(cvv.left - expiry.right, 14 + 1 + 14);
      // The brand mark trails the number.
      final Rect brand = _rect(tester, cardBrandKey);
      expect(brand.left, greaterThan(number.right));
      expect(box.right - brand.right, 1 + 14);
      expect(brand.center.dy, number.center.dy);

      final BoxDecoration decoration = _box(tester, _card);
      // Transparent: the field shows the page background (§16.14).
      expect(decoration.color, const Color(0x00000000));
      expect(decoration.borderRadius, BorderRadius.circular(12));
      expect(decoration.border, Border.all(color: _idle));
      // The lines between the rows and cells use the border colour.
      expect(
        find.descendant(
          of: cardBox,
          matching: find.byWidgetPredicate(
            (Widget w) => w is ColoredBox && w.color == _idle,
          ),
        ),
        findsNWidgets(2),
      );

      // The keyboard's next button follows the order shown.
      expect(
        _field(tester, cardHolderFieldKey).textInputAction,
        TextInputAction.next,
      );
      expect(
        _field(tester, cardCvvFieldKey).textInputAction,
        TextInputAction.done,
      );
      await tester.showKeyboard(find.byKey(cardHolderFieldKey));
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();
      expect(_field(tester, cardNumberFieldKey).focusNode!.hasFocus, isTrue);

      // A tap anywhere in a row focuses its field, not only on the text.
      await tester.tapAt(holder.topLeft + const Offset(40, 4));
      await tester.pump();
      expect(_field(tester, cardHolderFieldKey).focusNode!.hasFocus, isTrue);
      await tester.tapAt(Offset(cvv.center.dx, box.bottom - 4));
      await tester.pump();
      expect(_field(tester, cardCvvFieldKey).focusNode!.hasFocus, isTrue);
    });

    testWidgets('grouped: the labels from card_strings.json are the '
        "fields' accessibility labels", (WidgetTester tester) async {
      NativeCalls().install();
      final PayriffCardController controller = PayriffCardController();
      addTearDown(controller.dispose);
      await pumpCardApp(tester, controller);
      for (final (Key key, String label) in <(Key, String)>[
        (cardNumberFieldKey, 'Card number'),
        (cardExpiryFieldKey, 'Expiry date'),
        (cardCvvFieldKey, 'Security code'),
        (cardHolderFieldKey, 'Card holder'),
      ]) {
        expect(tester.getSemantics(find.byKey(key)).label, startsWith(label));
      }
      expect(
        tester.getSemantics(find.byKey(cardLabelKey(_card))),
        isSemantics(label: 'Card information', isHeader: true),
      );
    });

    testWidgets('grouped: one error line per section; the card box shows the '
        'first visible error of number, expiry and CVC', (
      WidgetTester tester,
    ) async {
      NativeCalls().install();
      final PayriffCardController controller = PayriffCardController();
      addTearDown(controller.dispose);
      await pumpCardApp(tester, controller);
      expect(_errorLine(tester, 'holder'), isNull);
      expect(_errorLine(tester, _card), isNull);

      // Paying with an empty form: every field has an error, each section
      // shows one.
      expect(checkCardForm(controller)!.errors, hasLength(4));
      await tester.pump();
      expect(_errorLine(tester, 'holder'), 'Enter the cardholder name');
      expect(_errorLine(tester, _card), 'Enter your card number');
      expect(find.text('Enter the expiry date'), findsNothing);
      expect(find.text('Enter the CVV'), findsNothing);

      await tester.enterText(
        find.byKey(cardNumberFieldKey),
        '4111111111111111',
      );
      await tester.pump();
      expect(_errorLine(tester, _card), 'Enter the expiry date');
      await tester.enterText(find.byKey(cardExpiryFieldKey), '1320');
      await tester.pump();
      expect(_errorLine(tester, _card), 'Expiry date is invalid');
      await tester.enterText(find.byKey(cardExpiryFieldKey), '1230');
      await tester.pump();
      expect(_errorLine(tester, _card), 'Enter the CVV');
      await tester.enterText(find.byKey(cardCvvFieldKey), '123');
      await tester.pump();
      expect(_errorLine(tester, _card), isNull);
      expect(_errorLine(tester, 'holder'), 'Enter the cardholder name');
      await tester.enterText(find.byKey(cardHolderFieldKey), 'Ellen Carter');
      await tester.pump();
      expect(_errorLine(tester, 'holder'), isNull);
      expect(controller.isComplete, isTrue);

      // Before any payment attempt the number's error waits for the
      // customer to leave the field; a definite expiry error shows at once.
      controller.clear();
      await tester.pump();
      await tester.enterText(find.byKey(cardNumberFieldKey), '4111');
      await tester.pump();
      expect(_errorLine(tester, _card), isNull);
      await tester.enterText(find.byKey(cardExpiryFieldKey), '1320');
      await tester.pump();
      expect(_errorLine(tester, _card), 'Card number is incomplete');
      await tester.enterText(
        find.byKey(cardNumberFieldKey),
        '4111111111111111',
      );
      await tester.pump();
      expect(_errorLine(tester, _card), 'Expiry date is invalid');
    });

    testWidgets('grouped: the outline shows the focus colour while a field '
        'of the section has the focus, and the error colour over it', (
      WidgetTester tester,
    ) async {
      NativeCalls().install();
      final PayriffCardController controller = PayriffCardController();
      addTearDown(controller.dispose);
      await pumpCardApp(tester, controller);
      expect(_outline(tester, 'holder'), _idle);
      expect(_outline(tester, _card), _idle);

      for (final Key key in <Key>[
        cardNumberFieldKey,
        cardExpiryFieldKey,
        cardCvvFieldKey,
      ]) {
        await tester.showKeyboard(find.byKey(key));
        await tester.pump();
        // The focus colour is Payriff's brand teal (§16.14).
        expect(_outline(tester, _card), _brand, reason: '$key');
        expect(_outline(tester, 'holder'), _idle, reason: '$key');
      }
      expect(_field(tester, cardCvvFieldKey).cursorColor, _brand);
      await tester.showKeyboard(find.byKey(cardHolderFieldKey));
      await tester.pump();
      expect(_outline(tester, 'holder'), _brand);
      expect(_outline(tester, _card), _idle);

      // A section that shows an error is red, focused or not.
      checkCardForm(controller);
      await tester.pump();
      expect(_field(tester, cardHolderFieldKey).focusNode!.hasFocus, isTrue);
      expect(_outline(tester, 'holder'), _red);
      expect(_outline(tester, _card), _red);
      // Only the outline: the lines inside keep the border colour.
      expect(
        find.descendant(
          of: find.byKey(cardBoxKey(_card)),
          matching: find.byWidgetPredicate(
            (Widget w) => w is ColoredBox && w.color == _idle,
          ),
        ),
        findsNWidgets(2),
      );
      await fillCard(tester, holder: 'ELLEN CARTER');
      expect(_outline(tester, 'holder'), _brand);
      expect(_outline(tester, _card), _idle);
    });

    testWidgets("the app's InputDecorationTheme does not change the form", (
      WidgetTester tester,
    ) async {
      NativeCalls().install();
      final PayriffCardController controller = PayriffCardController();
      addTearDown(controller.dispose);
      await pumpCardApp(
        tester,
        controller,
        theme: ThemeData(
          inputDecorationTheme: const InputDecorationThemeData(
            filled: true,
            fillColor: Color(0xFFFF0000),
            contentPadding: EdgeInsets.all(30),
            enabledBorder: OutlineInputBorder(),
            focusedBorder: OutlineInputBorder(),
            constraints: BoxConstraints(minHeight: 80),
          ),
        ),
      );
      // Two 40-high rows that share their 1-wide divider (§16.14).
      expect(_rect(tester, cardBoxKey(_card)).height, 40 + 40 - 1);
      final InputDecorator decorator = tester.widget<InputDecorator>(
        find.descendant(
          of: find.byKey(cardNumberFieldKey),
          matching: find.byType(InputDecorator),
        ),
      );
      expect(decorator.decoration.filled, isFalse);
      expect(decorator.decoration.enabledBorder, InputBorder.none);
      expect(decorator.decoration.contentPadding, EdgeInsets.zero);
    });

    testWidgets('dark mode defaults', (WidgetTester tester) async {
      NativeCalls().install();
      final PayriffCardController controller = PayriffCardController();
      addTearDown(controller.dispose);
      await pumpCardApp(
        tester,
        controller,
        theme: ThemeData(brightness: Brightness.dark),
      );
      final BoxDecoration decoration = _box(tester, _card);
      // Transparent: the field shows the page background (§16.14).
      expect(decoration.color, const Color(0x00000000));
      expect(decoration.border, Border.all(color: const Color(0xFF3F4145)));
      expect(
        _field(tester, cardNumberFieldKey).style!.color,
        const Color(0xFF8E8E93),
      );
      expect(
        tester.widget<Text>(find.byKey(cardLabelKey(_card))).style!.color,
        const Color(0xFFE1E4E8),
      );
    });

    testWidgets('a custom PayriffCardFormStyle changes the look', (
      WidgetTester tester,
    ) async {
      NativeCalls().install();
      final PayriffCardController controller = PayriffCardController();
      addTearDown(controller.dispose);
      const Color border = Color(0xFF00897B);
      const Color focus = Color(0xFF6A1B9A);
      const Color error = Color(0xFFFF6F00);
      const Color fill = Color(0xFFF1F8E9);
      const Color placeholder = Color(0xFF9E9E9E);
      const Color label = Color(0xFF004D40);
      await pumpCardApp(
        tester,
        controller,
        style: const PayriffCardFormStyle(
          labelTextStyle: TextStyle(fontSize: 12, color: label),
          inputTextStyle: TextStyle(fontSize: 18),
          placeholderColor: placeholder,
          errorTextStyle: TextStyle(fontStyle: FontStyle.italic),
          holderLabel: 'Name on card',
          cardLabel: 'Card details',
          fieldBackgroundColor: fill,
          borderColor: border,
          focusedBorderColor: focus,
          errorColor: error,
          borderWidth: 2,
          cornerRadius: 20,
          holderHeight: 56,
          rowHeight: 56,
          horizontalPadding: 20,
          labelSpacing: 4,
          sectionSpacing: 32,
        ),
      );

      final BoxDecoration decoration = _box(tester, _card);
      expect(decoration.color, fill);
      expect(decoration.borderRadius, BorderRadius.circular(20));
      expect(decoration.border, Border.all(color: border, width: 2));
      final Rect box = _rect(tester, cardBoxKey(_card));
      expect(box.height, 56 + 56 - 2);
      expect(_rect(tester, cardBoxKey('holder')).height, 56);
      expect(_rect(tester, cardExpiryFieldKey).left - box.left, 2 + 20);
      expect(box.top - _rect(tester, cardLabelKey(_card)).bottom, 4);
      expect(
        _rect(tester, cardLabelKey(_card)).top -
            _rect(tester, cardBoxKey('holder')).bottom,
        32,
      );

      // Text styles are merged over the defaults.
      final Text holderLabel = tester.widget<Text>(
        find.byKey(cardLabelKey('holder')),
      );
      expect(holderLabel.data, 'Name on card');
      expect(holderLabel.style!.fontSize, 12);
      expect(holderLabel.style!.color, label);
      expect(holderLabel.style!.fontWeight, FontWeight.w600);
      expect(_text(tester, cardLabelKey(_card)), 'Card details');
      expect(
        tester.getSemantics(find.byKey(cardHolderFieldKey)).label,
        startsWith('Name on card'),
      );
      final TextField number = _field(tester, cardNumberFieldKey);
      expect(number.style!.fontSize, 18);
      expect(number.style!.color, const Color(0xFF4D4F54));
      expect(number.decoration!.hintStyle!.color, placeholder);
      expect(number.cursorColor, focus);

      await tester.showKeyboard(find.byKey(cardNumberFieldKey));
      await tester.pump();
      expect(_outline(tester, _card), focus);
      expect(_outline(tester, 'holder'), border);
      checkCardForm(controller);
      await tester.pump();
      expect(_outline(tester, _card), error);
      final Text line = tester.widget<Text>(find.byKey(cardErrorKey(_card)));
      expect(line.style!.color, error);
      expect(line.style!.fontStyle, FontStyle.italic);
      expect(line.style!.fontSize, 13);
    });

    testWidgets('showLabels: false hides the labels but keeps the '
        'accessibility labels', (WidgetTester tester) async {
      NativeCalls().install();
      final PayriffCardController controller = PayriffCardController();
      addTearDown(controller.dispose);
      await pumpCardApp(
        tester,
        controller,
        style: const PayriffCardFormStyle(showLabels: false),
      );
      expect(find.byKey(cardLabelKey('holder')), findsNothing);
      expect(find.byKey(cardLabelKey(_card)), findsNothing);
      expect(find.text('Card information'), findsNothing);
      expect(
        tester.getSemantics(find.byKey(cardHolderFieldKey)).label,
        startsWith('Card holder'),
      );
      expect(
        tester.getSemantics(find.byKey(cardNumberFieldKey)).label,
        startsWith('Card number'),
      );
    });

    testWidgets('stacked: every field on its own, labelled, with its own '
        'outline and error', (WidgetTester tester) async {
      NativeCalls().install();
      final PayriffCardController controller = PayriffCardController();
      addTearDown(controller.dispose);
      await pumpCardApp(
        tester,
        controller,
        style: const PayriffCardFormStyle(
          layout: PayriffCardFormLayout.stacked,
        ),
      );
      expect(find.byKey(cardBoxKey(_card)), findsNothing);
      for (final (Key key, String section, String label)
          in <(Key, String, String)>[
            (cardNumberFieldKey, 'number', 'Card number'),
            (cardExpiryFieldKey, 'expiry', 'Expiry date'),
            (cardCvvFieldKey, 'cvv', 'Security code'),
            (cardHolderFieldKey, 'holder', 'Card holder'),
          ]) {
        expect(
          find.descendant(
            of: find.byKey(cardBoxKey(section)),
            matching: find.byKey(key),
          ),
          findsOneWidget,
        );
        expect(_text(tester, cardLabelKey(section)), label);
        expect(tester.getSemantics(find.byKey(key)).label, startsWith(label));
        expect(
          _rect(tester, cardBoxKey(section)).height,
          section == 'holder' ? 46 : 40,
        );
      }
      // The number, expiry | CVC, then the holder.
      final Rect number = _rect(tester, cardBoxKey('number'));
      final Rect expiry = _rect(tester, cardBoxKey('expiry'));
      final Rect cvv = _rect(tester, cardBoxKey('cvv'));
      final Rect holder = _rect(tester, cardBoxKey('holder'));
      expect(number.bottom, lessThan(expiry.top));
      expect(expiry.top, cvv.top);
      expect(cvv.left - expiry.right, 16);
      expect(cvv.bottom, lessThan(holder.top));
      expect(
        _field(tester, cardCvvFieldKey).textInputAction,
        TextInputAction.next,
      );
      expect(
        _field(tester, cardHolderFieldKey).textInputAction,
        TextInputAction.done,
      );

      await tester.showKeyboard(find.byKey(cardExpiryFieldKey));
      await tester.pump();
      expect(_outline(tester, 'expiry'), _brand);
      expect(_outline(tester, 'number'), _idle);
      expect(_outline(tester, 'cvv'), _idle);

      checkCardForm(controller);
      await tester.pump();
      expect(_errorLine(tester, 'number'), 'Enter your card number');
      expect(_errorLine(tester, 'expiry'), 'Enter the expiry date');
      expect(_errorLine(tester, 'cvv'), 'Enter the CVV');
      expect(_errorLine(tester, 'holder'), 'Enter the cardholder name');
      for (final String section in <String>[
        'number',
        'expiry',
        'cvv',
        'holder',
      ]) {
        expect(_outline(tester, section), _red, reason: section);
      }
      await fillCard(tester, holder: 'ELLEN CARTER');
      expect(controller.isComplete, isTrue);
      expect(_errorLine(tester, 'cvv'), isNull);
    });
  });

  testWidgets('works inside a CupertinoApp', (WidgetTester tester) async {
    NativeCalls().install();
    final PayriffCardController controller = PayriffCardController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(CupertinoAppHost(controller: controller));
    expect(find.byKey(cardNumberFieldKey), findsOneWidget);
    // The default form, so with the holder.
    await fillCard(tester, holder: 'ELLEN CARTER');
    expect(controller.isComplete, isTrue);
  });
}

class CupertinoAppHost extends StatelessWidget {
  const CupertinoAppHost({super.key, required this.controller});

  final PayriffCardController controller;

  @override
  Widget build(BuildContext context) => CupertinoApp(
    home: CupertinoPageScaffold(
      child: SafeArea(
        child: PayriffCardForm(
          controller: controller,
          language: PayriffLanguage.en,
        ),
      ),
    ),
  );
}
