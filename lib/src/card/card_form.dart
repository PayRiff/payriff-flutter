import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../internal/card/card_crypto.dart';
import '../internal/card/card_strings.dart';
import '../internal/card/format.dart';
import '../internal/card/validation.dart';
import '../internal/language.dart';
import '../internal/native_bridge.dart';
import '../payriff.dart';
import 'brand_mark.dart';
import 'card_form_style.dart';
import 'card_types.dart';

/// Key of the card number field.
const Key cardNumberFieldKey = ValueKey<String>('payriff.card.number');

/// Key of the expiry field.
const Key cardExpiryFieldKey = ValueKey<String>('payriff.card.expiry');

/// Key of the CVV field.
const Key cardCvvFieldKey = ValueKey<String>('payriff.card.cvv');

/// Key of the cardholder name field.
const Key cardHolderFieldKey = ValueKey<String>('payriff.card.holder');

/// Key of the brand mark in the card number field.
const Key cardBrandKey = ValueKey<String>('payriff.card.brand');

/// The section name of the grouped layout's card box.
const String cardInformationSection = 'card';

/// Key of a section's outlined box: [cardInformationSection] or, for the
/// holder and every field of the stacked layout, the field's name.
Key cardBoxKey(String section) => ValueKey<String>('payriff.card.box.$section');

/// Key of the label above a section's box.
Key cardLabelKey(String section) =>
    ValueKey<String>('payriff.card.label.$section');

/// Key of the error line under a section's box.
Key cardErrorKey(String section) =>
    ValueKey<String>('payriff.card.error.$section');

/// Payriff's brand colour (CONTRACT §16.14): the focus outline of the form
/// and the payment view's Pay button.
const Color payriffBrandColor = Color(0xFF4DBDC6);

/// Whether [context] is in dark mode: the Material theme's brightness, or
/// the Cupertino theme's in a `CupertinoApp`. Internal to the SDK.
bool payriffIsDark(BuildContext context) {
  final bool material =
      Localizations.of<MaterialLocalizations>(context, MaterialLocalizations) !=
      null;
  final Brightness brightness = material
      ? Theme.of(context).brightness
      : CupertinoTheme.brightnessOf(context);
  return brightness == Brightness.dark;
}

/// Controls a [PayriffCardForm]. Pass it to `Payriff.confirmCardPayment`.
///
/// It never exposes what the customer typed: only whether the form is
/// complete, the detected brand and whether a payment is running. Listen to
/// it (it is a [ChangeNotifier]) to enable your Pay button or show progress.
class PayriffCardController extends ChangeNotifier {
  /// Creates a controller for one [PayriffCardForm].
  PayriffCardController();

  _PayriffCardFormState? _form;
  bool _processing = false;
  bool _disposed = false;

  /// Whether a [PayriffCardForm] currently uses this controller.
  bool get isAttached => _form != null;

  /// Whether every field shown in the form is valid.
  bool get isComplete => _form?._isComplete ?? false;

  /// The detected brand of the card number, or `null` while unknown.
  PayriffCardBrand? get brand => _form?._brand;

  /// Whether `Payriff.confirmCardPayment` is running for this form. The
  /// form is locked meanwhile; show progress on your Pay button.
  bool get isProcessing => _processing;

  /// Clears every field and the shown errors.
  void clear() => _form?._clearValues();

  /// Moves the keyboard focus to [field], when the form shows it.
  void focus(PayriffCardField field) => _form?._focusField(field);

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// What `confirmCardPayment` gets from a form: the invalid fields, or the
/// card to encrypt when there are none.
typedef CardFormCheck = ({
  List<PayriffCardFieldError> errors,
  CardPlaintext? card,
});

/// CONTRACT §16.7 step 1: validates the form of [controller] and shows every
/// error, as after a payment attempt. `null` when no form is attached.
/// Internal to the SDK.
CardFormCheck? checkCardForm(PayriffCardController controller) =>
    controller._form?._check();

/// Locks or unlocks the form of [controller] while a payment runs. Internal
/// to the SDK.
void setCardFormProcessing(PayriffCardController controller, bool value) {
  if (controller._processing == value) return;
  controller._processing = value;
  controller._form?._onProcessingChanged();
  controller._changed();
}

/// CONTRACT §16.5: clears the card values after a final result. Internal to
/// the SDK.
void clearCardForm(PayriffCardController controller) =>
    controller._form?._clearValues();

/// The native card form (CONTRACT §16.4): card number, expiry, CVV and the
/// cardholder name, which [showHolder] can hide.
///
/// By default it looks like the card form of Payriff's hosted payment page
/// (pay.payriff.com): the cardholder name first, then one "Card information"
/// box with the number on top and the expiry and the CVC side by side below
/// it. Change the look, or switch to the stacked layout, with [style].
///
/// For a ready-made payment screen (the form, a Pay button with the amount,
/// the card badges and the Payriff footer) use `PayriffPaymentView`, which
/// is built on this form.
///
/// The form validates and formats as the customer types, shows the card
/// brand, and moves on to the next field when one becomes valid
/// ([autoAdvance]). Card values never leave the SDK except encrypted:
/// `Payriff.confirmCardPayment` reads them through the [controller].
///
/// While it is shown, screenshots and app-switcher snapshots are blocked
/// (Android `FLAG_SECURE`, an iOS cover while the app is inactive). Copy and
/// cut are off for the number and the CVV, the CVV is masked and never
/// offered to autofill, and the keyboard neither corrects, suggests nor
/// learns. The values are cleared after a final payment result and when the
/// form is disposed.
///
/// ```dart
/// final controller = PayriffCardController();
/// PayriffCardForm(controller: controller);
/// final result = await Payriff.confirmCardPayment(
///   context,
///   controller,
///   orderId: orderId,
///   clientSecret: clientSecret,
/// );
/// ```
class PayriffCardForm extends StatefulWidget {
  /// Creates a card form controlled by [controller].
  const PayriffCardForm({
    super.key,
    required this.controller,
    this.showHolder = true,
    this.autoAdvance = true,
    this.language,
    this.style = const PayriffCardFormStyle(),
    this.onChanged,
  });

  /// Connects the form to `Payriff.confirmCardPayment`.
  final PayriffCardController controller;

  /// Whether to show the cardholder name field. Defaults to `true`, as on
  /// Payriff's hosted payment page. Set it to `false` to hide the field; the
  /// name is then sent as `Unknown`.
  final bool showHolder;

  /// Whether a field that becomes valid while typing at its end moves the
  /// focus on: number → expiry → CVV. Defaults to `true`.
  final bool autoAdvance;

  /// The language of the labels, placeholders and errors. `null` uses
  /// `PayriffConfig.language`, then the device language.
  final PayriffLanguage? language;

  /// The layout, colours, text styles, sizes and labels. The default looks
  /// like Payriff's hosted payment page and follows light and dark mode.
  final PayriffCardFormStyle style;

  /// Called when a field's state changes. The event never contains what the
  /// customer typed.
  final ValueChanged<PayriffCardFormChange>? onChanged;

  @override
  State<PayriffCardForm> createState() => _PayriffCardFormState();
}

const List<PayriffCardField> _advanceOrder = <PayriffCardField>[
  PayriffCardField.number,
  PayriffCardField.expiry,
  PayriffCardField.cvv,
];

// Copy and cut through a hardware keyboard, for the number and the CVV.
final Map<ShortcutActivator, Intent> _noCopyShortcuts =
    <ShortcutActivator, Intent>{
      for (final LogicalKeyboardKey key in <LogicalKeyboardKey>[
        LogicalKeyboardKey.keyC,
        LogicalKeyboardKey.keyX,
      ]) ...<ShortcutActivator, Intent>{
        SingleActivator(key, control: true):
            const DoNothingAndStopPropagationTextIntent(),
        SingleActivator(key, meta: true):
            const DoNothingAndStopPropagationTextIntent(),
      },
      const SingleActivator(LogicalKeyboardKey.copy):
          const DoNothingAndStopPropagationTextIntent(),
      const SingleActivator(LogicalKeyboardKey.cut):
          const DoNothingAndStopPropagationTextIntent(),
    };

class _PayriffCardFormState extends State<PayriffCardForm> {
  final Map<PayriffCardField, TextEditingController> _text =
      <PayriffCardField, TextEditingController>{
        for (final PayriffCardField f in PayriffCardField.values)
          f: TextEditingController(),
      };
  final Map<PayriffCardField, FocusNode> _focus = <PayriffCardField, FocusNode>{
    for (final PayriffCardField f in PayriffCardField.values)
      f: FocusNode(debugLabel: 'payriff.card.${f.value}'),
  };
  final Set<PayriffCardField> _touched = <PayriffCardField>{};
  final Map<PayriffCardField, String> _lastText = <PayriffCardField, String>{};
  final Map<PayriffCardField, PayriffCardFormChange> _lastChange =
      <PayriffCardField, PayriffCardFormChange>{};
  bool _submitted = false;

  /// Bumped whenever the values are cleared. It keys every field's subtree,
  /// so the field's undo history, which still holds what was typed, is
  /// thrown away with it (CONTRACT §16.5).
  int _generation = 0;

  List<PayriffCardField> get _fields => <PayriffCardField>[
    PayriffCardField.number,
    PayriffCardField.expiry,
    PayriffCardField.cvv,
    if (widget.showHolder) PayriffCardField.holder,
  ];

  /// The fields in the order the layout shows them, which the keyboard's
  /// next button follows. The grouped layout puts the holder first.
  List<PayriffCardField> get _shownOrder => switch (widget.style.layout) {
    PayriffCardFormLayout.grouped => <PayriffCardField>[
      if (widget.showHolder) PayriffCardField.holder,
      PayriffCardField.number,
      PayriffCardField.expiry,
      PayriffCardField.cvv,
    ],
    PayriffCardFormLayout.stacked => _fields,
  };

  PayriffLanguage get _language =>
      widget.language ?? Payriff.config?.language ?? deviceLanguage();

  PayriffCardStrings get _strings => PayriffCardStrings(_language);

  ({bool valid, bool empty, PayriffCardFieldErrorCode? error}) _validate(
    PayriffCardField field,
  ) {
    final String text = _text[field]!.text;
    switch (field) {
      case PayriffCardField.number:
        final CardFieldValidation v = validateNumber(text);
        return (valid: v.valid, empty: v.empty, error: v.errorCode);
      case PayriffCardField.expiry:
        final ExpiryValidation v = validateExpiry(text, DateTime.now());
        return (valid: v.valid, empty: v.empty, error: v.errorCode);
      case PayriffCardField.cvv:
        final CardFieldValidation v = validateCvv(text);
        return (valid: v.valid, empty: v.empty, error: v.errorCode);
      case PayriffCardField.holder:
        final CardFieldValidation v = validateHolder(text);
        return (valid: v.valid, empty: v.empty, error: v.errorCode);
    }
  }

  bool get _isComplete =>
      _fields.every((PayriffCardField f) => _validate(f).valid);

  PayriffCardBrand? get _brand =>
      validateNumber(_text[PayriffCardField.number]!.text).brand;

  PayriffCardFieldErrorCode? _visibleError(PayriffCardField field) =>
      visibleError(
        _validate(field).error,
        focused: _focus[field]!.hasFocus,
        touched: _touched.contains(field),
        submitted: _submitted,
      );

  @override
  void initState() {
    super.initState();
    // CONTRACT §16.0 item 4: no screenshots or app-switcher snapshots of the
    // card while the form exists.
    unawaited(NativeBridge.setSecure(true));
    _attach(widget.controller);
    for (final PayriffCardField field in PayriffCardField.values) {
      _focus[field]!.addListener(() => _onFocusChanged(field));
    }
  }

  @override
  void didUpdateWidget(PayriffCardForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _detach(oldWidget.controller);
      _attach(widget.controller);
    }
    if (oldWidget.showHolder && !widget.showHolder) {
      _text[PayriffCardField.holder]!.clear();
    }
  }

  void _attach(PayriffCardController controller) {
    assert(
      controller._form == null || identical(controller._form, this),
      'A PayriffCardController can drive only one PayriffCardForm at a time.',
    );
    controller._form = this;
    _notifyAfterFrame(controller);
  }

  void _detach(PayriffCardController controller) {
    if (identical(controller._form, this)) {
      controller._form = null;
      _notifyAfterFrame(controller);
    }
  }

  // Attaching and detaching run while the tree builds (initState,
  // didUpdateWidget, dispose); listeners may only rebuild after that frame.
  static void _notifyAfterFrame(PayriffCardController controller) {
    WidgetsBinding.instance.addPostFrameCallback((_) => controller._changed());
  }

  @override
  void dispose() {
    _clearText();
    _detach(widget.controller);
    for (final TextEditingController c in _text.values) {
      c.dispose();
    }
    for (final FocusNode n in _focus.values) {
      n.dispose();
    }
    unawaited(NativeBridge.setSecure(false));
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Controller hooks

  CardFormCheck _check() {
    _submitted = true;
    if (mounted) setState(() {});
    final List<PayriffCardFieldError> errors = <PayriffCardFieldError>[
      for (final PayriffCardField field in _fields)
        if (_validate(field).error case final PayriffCardFieldErrorCode error)
          PayriffCardFieldError(field: field, error: error),
    ];
    for (final PayriffCardField field in _fields) {
      _emit(field);
    }
    if (errors.isNotEmpty) return (errors: errors, card: null);
    final ExpiryValidation expiry = validateExpiry(
      _text[PayriffCardField.expiry]!.text,
      DateTime.now(),
    );
    return (
      errors: errors,
      card: CardPlaintext(
        pan: validateNumber(_text[PayriffCardField.number]!.text).value,
        cardHolder: widget.showHolder
            ? validateHolder(_text[PayriffCardField.holder]!.text).value
            : 'Unknown',
        expiryYear: expiry.expiryYear!,
        expiryMonth: expiry.expiryMonth!,
        cvv: validateCvv(_text[PayriffCardField.cvv]!.text).value,
      ),
    );
  }

  void _onProcessingChanged() {
    if (!mounted) return;
    if (widget.controller.isProcessing) FocusScope.of(context).unfocus();
    setState(() {});
  }

  void _clearText() {
    for (final TextEditingController c in _text.values) {
      c.value = TextEditingValue.empty;
    }
    _lastText.clear();
    // Without this, undo (Ctrl/Cmd+Z, iOS shake or three-finger swipe)
    // would bring the cleared number and CVV back.
    _generation++;
  }

  void _clearValues() {
    _clearText();
    _touched.clear();
    _submitted = false;
    _lastChange.clear();
    if (mounted) setState(() {});
    widget.controller._changed();
  }

  void _focusField(PayriffCardField field) {
    if (_fields.contains(field)) _focus[field]!.requestFocus();
  }

  // ---------------------------------------------------------------------
  // Field events

  void _onFocusChanged(PayriffCardField field) {
    if (!mounted) return;
    if (!_focus[field]!.hasFocus) _touched.add(field);
    setState(() {});
    if (_fields.contains(field)) _emit(field);
  }

  void _onChanged(PayriffCardField field, String text) {
    final String previous = _lastText[field] ?? '';
    _lastText[field] = text;
    setState(() {});
    _emit(field);
    widget.controller._changed();
    if (!widget.autoAdvance || text.length <= previous.length) return;
    final int index = _advanceOrder.indexOf(field);
    if (index < 0 || index + 1 >= _advanceOrder.length) return;
    final TextSelection selection = _text[field]!.selection;
    final bool caretAtEnd =
        selection.isCollapsed && selection.baseOffset == text.length;
    if (caretAtEnd && _validate(field).valid) {
      _focus[_advanceOrder[index + 1]]!.requestFocus();
    }
  }

  void _emit(PayriffCardField field) {
    final ValueChanged<PayriffCardFormChange>? onChanged = widget.onChanged;
    if (onChanged == null) return;
    final ({bool valid, bool empty, PayriffCardFieldErrorCode? error}) v =
        _validate(field);
    final PayriffCardFieldErrorCode? shown = _visibleError(field);
    final PayriffCardFormChange change = PayriffCardFormChange(
      field: field,
      valid: v.valid,
      empty: v.empty,
      error: shown,
      errorMessage: shown == null ? null : _strings.error(field, shown),
      brand: field == PayriffCardField.number ? _brand : null,
      complete: _isComplete,
    );
    if (_lastChange[field] == change) return;
    _lastChange[field] = change;
    onChanged(change);
  }

  // ---------------------------------------------------------------------
  // Build

  @override
  Widget build(BuildContext context) {
    Widget form = _buildForm(context);
    // TextField needs Material localizations and a Material ancestor; a
    // CupertinoApp has neither.
    if (Localizations.of<MaterialLocalizations>(
          context,
          MaterialLocalizations,
        ) ==
        null) {
      form = Localizations.override(
        context: context,
        delegates: const <LocalizationsDelegate<Object?>>[
          DefaultMaterialLocalizations.delegate,
        ],
        child: form,
      );
    }
    return Material(type: MaterialType.transparency, child: form);
  }

  Widget _buildForm(BuildContext context) {
    final CardFormLook look = CardFormLook(
      widget.style,
      dark: payriffIsDark(context),
    );
    return AutofillGroup(
      // Never offer to save the card when the form goes away.
      onDisposeAction: AutofillContextAction.cancel,
      child: switch (widget.style.layout) {
        PayriffCardFormLayout.grouped => _grouped(look),
        PayriffCardFormLayout.stacked => _stacked(look),
      },
    );
  }

  /// CONTRACT §16.4 `grouped`, as on pay.payriff.com: the holder, then one
  /// box with the number row above the expiry and CVC cells.
  Widget _grouped(CardFormLook look) {
    final PayriffCardFormStyle style = widget.style;
    const PayriffCardField holder = PayriffCardField.holder;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.showHolder) ...<Widget>[
          _section(
            look,
            section: holder.value,
            label: _label(holder),
            fields: const <PayriffCardField>[holder],
            child: _cell(holder, look),
          ),
          SizedBox(height: style.sectionSpacing),
        ],
        _section(
          look,
          section: cardInformationSection,
          label: style.cardLabel ?? _strings.cardInformation,
          // It names the group; the fields carry their own labels.
          header: true,
          fields: const <PayriffCardField>[
            PayriffCardField.number,
            PayriffCardField.expiry,
            PayriffCardField.cvv,
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _cell(PayriffCardField.number, look),
              ColoredBox(
                color: look.border,
                child: SizedBox(height: style.borderWidth),
              ),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(child: _cell(PayriffCardField.expiry, look)),
                    ColoredBox(
                      color: look.border,
                      child: SizedBox(width: style.borderWidth),
                    ),
                    Expanded(child: _cell(PayriffCardField.cvv, look)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// CONTRACT §16.4 `stacked`: every field on its own, with its label above
  /// it and its error below it.
  Widget _stacked(CardFormLook look) {
    final PayriffCardFormStyle style = widget.style;
    final double gap = style.sectionSpacing;
    Widget field(PayriffCardField f) => _section(
      look,
      section: f.value,
      label: _label(f),
      fields: <PayriffCardField>[f],
      child: _cell(f, look),
    );
    Widget label(PayriffCardField f) => _sectionLabel(look, f.value, _label(f));
    Widget box(PayriffCardField f) =>
        _sectionBox(look, f.value, <PayriffCardField>[f], _cell(f, look));
    Widget? error(PayriffCardField f) =>
        _sectionError(look, f.value, <PayriffCardField>[f]);
    // Expiry and CVC side by side: their labels, boxes and errors each on
    // one row, so the boxes line up even when one label wraps.
    Widget pair(
      Widget? expiry,
      Widget? cvv, {
      CrossAxisAlignment align = CrossAxisAlignment.start,
    }) => Row(
      crossAxisAlignment: align,
      children: <Widget>[
        Expanded(child: expiry ?? const SizedBox.shrink()),
        SizedBox(width: gap),
        Expanded(child: cvv ?? const SizedBox.shrink()),
      ],
    );
    final Widget? expiryError = error(PayriffCardField.expiry);
    final Widget? cvvError = error(PayriffCardField.cvv);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        field(PayriffCardField.number),
        SizedBox(height: gap),
        if (style.showLabels) ...<Widget>[
          pair(
            label(PayriffCardField.expiry),
            label(PayriffCardField.cvv),
            align: CrossAxisAlignment.end,
          ),
          SizedBox(height: style.labelSpacing),
        ],
        pair(box(PayriffCardField.expiry), box(PayriffCardField.cvv)),
        if (expiryError != null || cvvError != null)
          pair(expiryError, cvvError),
        if (widget.showHolder) ...<Widget>[
          SizedBox(height: gap),
          field(PayriffCardField.holder),
        ],
      ],
    );
  }

  /// The field's label: shown above it in the stacked layout (the holder's
  /// in both), and always its accessibility label.
  String _label(PayriffCardField field) =>
      (field == PayriffCardField.holder ? widget.style.holderLabel : null) ??
      _strings.label(field);

  /// A section (CONTRACT §16.4): its label, one outlined box holding [child]
  /// and at most one error line, for the first visible error of [fields].
  Widget _section(
    CardFormLook look, {
    required String section,
    required String label,
    required List<PayriffCardField> fields,
    required Widget child,
    bool header = false,
  }) {
    final Widget? error = _sectionError(look, section, fields);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.style.showLabels) ...<Widget>[
          _sectionLabel(look, section, label, header: header),
          SizedBox(height: widget.style.labelSpacing),
        ],
        _sectionBox(look, section, fields, child),
        ?error,
      ],
    );
  }

  /// The label above a section's box. A field's label is already the
  /// field's accessibility label, so only a group's label is read out, as a
  /// heading.
  Widget _sectionLabel(
    CardFormLook look,
    String section,
    String label, {
    bool header = false,
  }) {
    final Widget text = Text(
      label,
      key: cardLabelKey(section),
      style: look.label,
    );
    return header
        ? Semantics(header: true, child: text)
        : ExcludeSemantics(child: text);
  }

  /// A section's outlined box. The outline shows the error colour while the
  /// section shows an error, else the focus colour while one of [fields] has
  /// the focus.
  Widget _sectionBox(
    CardFormLook look,
    String section,
    List<PayriffCardField> fields,
    Widget child,
  ) {
    final PayriffCardFormStyle style = widget.style;
    final bool error = _errorLine(fields) != null;
    final bool focused = fields.any(
      (PayriffCardField f) => _focus[f]!.hasFocus,
    );
    return DecoratedBox(
      key: cardBoxKey(section),
      decoration: BoxDecoration(
        color: look.fill,
        border: Border.all(
          color: look.outline(error: error, focused: focused),
          width: style.borderWidth,
        ),
        borderRadius: BorderRadius.circular(style.cornerRadius),
      ),
      child: Padding(
        padding: EdgeInsets.all(style.borderWidth),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(
            math.max(0, style.cornerRadius - style.borderWidth),
          ),
          child: child,
        ),
      ),
    );
  }

  /// The error line under a section's box, or `null` while it has none.
  Widget? _sectionError(
    CardFormLook look,
    String section,
    List<PayriffCardField> fields,
  ) {
    final String? error = _errorLine(fields);
    if (error == null) return null;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Text(error, key: cardErrorKey(section), style: look.errorText),
      ),
    );
  }

  /// The text of the first visible error of [fields], in order.
  String? _errorLine(List<PayriffCardField> fields) {
    for (final PayriffCardField field in fields) {
      if (_visibleError(field) case final PayriffCardFieldErrorCode code) {
        return _strings.error(field, code);
      }
    }
    return null;
  }

  /// One row or cell of a box: [field] across all of it, as high as
  /// `holderHeight` (the holder) or `rowHeight` (the others) less the
  /// outline, with the brand mark after the number.
  Widget _cell(PayriffCardField field, CardFormLook look) {
    final PayriffCardFormStyle style = widget.style;
    // CONTRACT §16.14: the heights include the outline (and, in the card
    // box, the line between the rows).
    final double height = field == PayriffCardField.holder
        ? style.holderHeight
        : style.rowHeight;
    return GestureDetector(
      // A tap above or below the text line focuses the field too.
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: widget.controller.isProcessing
          ? null
          : () => _focus[field]!.requestFocus(),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: math.max(0, height - 2 * style.borderWidth),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: style.horizontalPadding),
          child: Row(
            children: <Widget>[
              Expanded(child: _input(field, look)),
              if (field == PayriffCardField.number) ...<Widget>[
                const SizedBox(width: 8),
                _BrandMark(brand: _brand, look: look),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The text field of [field], bare: its section draws the outline, the
  /// fill and the error.
  Widget _input(PayriffCardField field, CardFormLook look) {
    final List<PayriffCardField> order = _shownOrder;
    final bool last = field == order.last;
    final bool secret =
        field == PayriffCardField.number || field == PayriffCardField.cvv;
    Widget input = TextField(
      key: switch (field) {
        PayriffCardField.number => cardNumberFieldKey,
        PayriffCardField.expiry => cardExpiryFieldKey,
        PayriffCardField.cvv => cardCvvFieldKey,
        PayriffCardField.holder => cardHolderFieldKey,
      },
      controller: _text[field],
      focusNode: _focus[field],
      enabled: !widget.controller.isProcessing,
      onChanged: (String text) => _onChanged(field, text),
      onSubmitted: last ? null : (_) => _focusNext(field),
      textInputAction: last ? TextInputAction.done : TextInputAction.next,
      keyboardType: field == PayriffCardField.holder
          ? TextInputType.name
          : TextInputType.number,
      textCapitalization: field == PayriffCardField.holder
          ? TextCapitalization.characters
          : TextCapitalization.none,
      inputFormatters: switch (field) {
        PayriffCardField.number => <TextInputFormatter>[
          CardInputFormatter(CardFormatKind.number),
        ],
        PayriffCardField.expiry => <TextInputFormatter>[
          CardInputFormatter(CardFormatKind.expiry),
        ],
        PayriffCardField.cvv => <TextInputFormatter>[
          CardInputFormatter(CardFormatKind.cvv),
        ],
        // CONTRACT §16.4: always upper case, capped after upper-casing.
        PayriffCardField.holder => <TextInputFormatter>[
          const HolderInputFormatter(),
          LengthLimitingTextInputFormatter(maxHolderLength),
        ],
      },
      // CONTRACT §16.5: autofill for number, expiry and holder only.
      autofillHints: switch (field) {
        PayriffCardField.number => const <String>[
          AutofillHints.creditCardNumber,
        ],
        PayriffCardField.expiry => const <String>[
          AutofillHints.creditCardExpirationDate,
        ],
        PayriffCardField.holder => const <String>[AutofillHints.creditCardName],
        PayriffCardField.cvv => null,
      },
      obscureText: field == PayriffCardField.cvv,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
      // No selection handles or menu: no copy or cut of the number or CVV.
      enableInteractiveSelection: !secret,
      style: look.input,
      cursorColor: look.focus,
      // Set explicitly, so the app's InputDecorationTheme cannot change the
      // form's size, padding, fill or borders.
      decoration: InputDecoration(
        isCollapsed: true,
        isDense: true,
        filled: false,
        contentPadding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        visualDensity: VisualDensity.standard,
        hintText: _strings.placeholder(field),
        hintStyle: TextStyle(color: look.placeholder),
        hintMaxLines: 1,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
      ),
    );
    // CONTRACT §16.4: the label strings are the fields' accessibility labels.
    input = Semantics(label: _label(field), child: input);
    if (secret) input = Shortcuts(shortcuts: _noCopyShortcuts, child: input);
    return KeyedSubtree(key: ValueKey<int>(_generation), child: input);
  }

  void _focusNext(PayriffCardField field) {
    final List<PayriffCardField> fields = _shownOrder;
    final int index = fields.indexOf(field);
    if (index >= 0 && index + 1 < fields.length) {
      _focus[fields[index + 1]]!.requestFocus();
    }
  }
}

/// The [PayriffCardFormStyle] with every default filled in for light or
/// dark mode (CONTRACT §16.4, with the page values of §16.14). Internal to
/// the SDK; `PayriffPaymentView` uses it for its error line.
final class CardFormLook {
  /// Resolves [style] for dark mode when [dark] is true.
  CardFormLook(this.style, {required bool dark})
    : labelColor = dark ? const Color(0xFFE1E4E8) : const Color(0xFF34363A),
      inputColor = dark ? const Color(0xFF8E8E93) : const Color(0xFF4D4F54),
      fill = style.fieldBackgroundColor ?? const Color(0x00000000),
      border =
          style.borderColor ??
          (dark ? const Color(0xFF3F4145) : const Color(0xFFECEEF0)),
      focus = style.focusedBorderColor ?? payriffBrandColor,
      error =
          style.errorColor ??
          (dark ? const Color(0xFFEC5545) : const Color(0xFFEC4D3D)),
      placeholder =
          style.placeholderColor ??
          (dark ? const Color(0xFF5F6167) : const Color(0xFF76787F));

  /// The style being resolved.
  final PayriffCardFormStyle style;

  /// The colour of the labels.
  final Color labelColor;

  /// The colour of what the customer types.
  final Color inputColor;

  /// The fill of the fields.
  final Color fill;

  /// The outlines and the lines inside the card box.
  final Color border;

  /// The outline of the focused section, and the text cursor.
  final Color focus;

  /// The outline of a section with an error, and the error lines.
  final Color error;

  /// The colour of the placeholders.
  final Color placeholder;

  /// The labels: 14 semibold.
  TextStyle get label => TextStyle(
    color: labelColor,
    fontSize: 14,
    fontWeight: FontWeight.w600,
  ).merge(style.labelTextStyle);

  /// What the customer types, and the placeholders: 14 regular.
  TextStyle get input => TextStyle(
    color: inputColor,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  ).merge(style.inputTextStyle);

  /// The error lines: 13 regular.
  TextStyle get errorText => TextStyle(
    color: error,
    fontSize: 13,
    fontWeight: FontWeight.w400,
  ).merge(style.errorTextStyle);

  /// The outline colour of a section.
  Color outline({required bool error, required bool focused}) =>
      error ? this.error : (focused ? focus : border);
}

/// The brand of the card number as a small mark.
class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.brand, required this.look});

  final PayriffCardBrand? brand;
  final CardFormLook look;

  @override
  Widget build(BuildContext context) => Semantics(
    key: cardBrandKey,
    container: true,
    label: switch (brand) {
      PayriffCardBrand.visa => 'Visa',
      PayriffCardBrand.mastercard => 'Mastercard',
      null => null,
    },
    child: CardBrandMark(brand: brand, outline: look.placeholder),
  );
}
