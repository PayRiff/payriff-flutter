import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// How `PayriffCardForm` arranges its fields (CONTRACT §16.4).
enum PayriffCardFormLayout {
  /// The default, like the card form of Payriff's hosted payment page
  /// (pay.payriff.com): the cardholder name first, when shown, then one
  /// "Card information" box with the card number on top and the expiry and
  /// the CVC side by side below it. Each of the two sections has one error
  /// line.
  grouped,

  /// Every field on its own, with its label above it and its error below
  /// it: the card number, the expiry and the CVC side by side, then the
  /// cardholder name, when shown.
  stacked,
}

/// The look of `PayriffCardForm` (CONTRACT §16.4 and §16.14).
///
/// Every property is optional. The defaults reproduce the card form of
/// Payriff's hosted payment page (pay.payriff.com): its colours, sizes and
/// spacing, in the system font. They follow light and dark mode. A colour
/// you set is used in both modes.
///
/// ```dart
/// PayriffCardForm(
///   controller: card,
///   style: const PayriffCardFormStyle(
///     cornerRadius: 16,
///     focusedBorderColor: Color(0xFF00A3A3),
///     labelTextStyle: TextStyle(fontSize: 13),
///   ),
/// )
/// ```
///
/// `PayriffPaymentView` takes one through `PayriffPaymentViewStyle.formStyle`.
@immutable
final class PayriffCardFormStyle {
  /// Creates a style. Leave a property out to keep its default.
  const PayriffCardFormStyle({
    this.layout = PayriffCardFormLayout.grouped,
    this.labelTextStyle,
    this.inputTextStyle,
    this.placeholderColor,
    this.errorTextStyle,
    this.showLabels = true,
    this.holderLabel,
    this.cardLabel,
    this.fieldBackgroundColor,
    this.borderColor,
    this.focusedBorderColor,
    this.errorColor,
    this.borderWidth = 1,
    this.cornerRadius = 12,
    this.holderHeight = 46,
    this.rowHeight = 40,
    this.horizontalPadding = 14,
    this.labelSpacing = 10,
    this.sectionSpacing = 16,
  }) : assert(borderWidth >= 0),
       assert(cornerRadius >= 0),
       assert(holderHeight >= 0),
       assert(rowHeight >= 0),
       assert(horizontalPadding >= 0),
       assert(labelSpacing >= 0),
       assert(sectionSpacing >= 0);

  /// How the fields are arranged. Defaults to
  /// [PayriffCardFormLayout.grouped].
  final PayriffCardFormLayout layout;

  /// The labels above the sections or fields, merged over the default:
  /// 14 semibold in `#34363A` (`#E1E4E8` in dark mode). Set only what you
  /// want to change.
  final TextStyle? labelTextStyle;

  /// What the customer types, merged over the default: 14 regular in
  /// `#4D4F54` (`#8E8E93` in dark mode). The placeholders use it too, in
  /// [placeholderColor].
  final TextStyle? inputTextStyle;

  /// The colour of the placeholders. `null`: `#76787F`, `#5F6167` in dark
  /// mode.
  final Color? placeholderColor;

  /// The error lines, merged over the default: 13 regular in [errorColor].
  final TextStyle? errorTextStyle;

  /// Whether to show the labels above the sections or fields. The fields
  /// keep their accessibility labels either way. Defaults to `true`.
  final bool showLabels;

  /// The label above the cardholder name field. `null`: "Card holder" in
  /// the form's language.
  final String? holderLabel;

  /// The label above the card box of the grouped layout. `null`: "Card
  /// information" in the form's language. The stacked layout labels each
  /// field instead.
  final String? cardLabel;

  /// The fill of the fields. `null`: transparent, so the fields show the
  /// background behind the form.
  final Color? fieldBackgroundColor;

  /// The outlines, and the lines between the rows and cells of the card
  /// box. `null`: `#ECEEF0`, `#3F4145` in dark mode.
  final Color? borderColor;

  /// The outline of the section (grouped) or field (stacked) that has the
  /// focus, and the text cursor. `null`: Payriff's brand colour `#4DBDC6`.
  final Color? focusedBorderColor;

  /// The outline of a section or field that shows an error, and the colour
  /// of the error lines. `null`: `#EC4D3D`, `#EC5545` in dark mode.
  final Color? errorColor;

  /// The width of the outlines and of the lines between the rows and cells.
  /// Defaults to 1.
  final double borderWidth;

  /// The radius of the outer corners. Defaults to 12.
  final double cornerRadius;

  /// The height of the cardholder name field, its outline included; it
  /// grows with large text. Defaults to 46.
  final double holderHeight;

  /// The height of a row of the card box, its outline and the line it
  /// shares with the other row included (so the default box is
  /// `40 + 40 - 1` high); in the stacked layout, the height of the number,
  /// expiry and CVC fields, outline included. Rows grow with large text.
  /// Defaults to 40.
  final double rowHeight;

  /// The space between a row's sides and its text or the brand mark.
  /// Defaults to 14.
  final double horizontalPadding;

  /// The space between a label and its field. Defaults to 10.
  final double labelSpacing;

  /// The space between the cardholder name and the card box; in the stacked
  /// layout, between the fields. Defaults to 16.
  final double sectionSpacing;

  /// A copy with the given properties replaced.
  PayriffCardFormStyle copyWith({
    PayriffCardFormLayout? layout,
    TextStyle? labelTextStyle,
    TextStyle? inputTextStyle,
    Color? placeholderColor,
    TextStyle? errorTextStyle,
    bool? showLabels,
    String? holderLabel,
    String? cardLabel,
    Color? fieldBackgroundColor,
    Color? borderColor,
    Color? focusedBorderColor,
    Color? errorColor,
    double? borderWidth,
    double? cornerRadius,
    double? holderHeight,
    double? rowHeight,
    double? horizontalPadding,
    double? labelSpacing,
    double? sectionSpacing,
  }) => PayriffCardFormStyle(
    layout: layout ?? this.layout,
    labelTextStyle: labelTextStyle ?? this.labelTextStyle,
    inputTextStyle: inputTextStyle ?? this.inputTextStyle,
    placeholderColor: placeholderColor ?? this.placeholderColor,
    errorTextStyle: errorTextStyle ?? this.errorTextStyle,
    showLabels: showLabels ?? this.showLabels,
    holderLabel: holderLabel ?? this.holderLabel,
    cardLabel: cardLabel ?? this.cardLabel,
    fieldBackgroundColor: fieldBackgroundColor ?? this.fieldBackgroundColor,
    borderColor: borderColor ?? this.borderColor,
    focusedBorderColor: focusedBorderColor ?? this.focusedBorderColor,
    errorColor: errorColor ?? this.errorColor,
    borderWidth: borderWidth ?? this.borderWidth,
    cornerRadius: cornerRadius ?? this.cornerRadius,
    holderHeight: holderHeight ?? this.holderHeight,
    rowHeight: rowHeight ?? this.rowHeight,
    horizontalPadding: horizontalPadding ?? this.horizontalPadding,
    labelSpacing: labelSpacing ?? this.labelSpacing,
    sectionSpacing: sectionSpacing ?? this.sectionSpacing,
  );

  @override
  bool operator ==(Object other) =>
      other is PayriffCardFormStyle &&
      other.layout == layout &&
      other.labelTextStyle == labelTextStyle &&
      other.inputTextStyle == inputTextStyle &&
      other.placeholderColor == placeholderColor &&
      other.errorTextStyle == errorTextStyle &&
      other.showLabels == showLabels &&
      other.holderLabel == holderLabel &&
      other.cardLabel == cardLabel &&
      other.fieldBackgroundColor == fieldBackgroundColor &&
      other.borderColor == borderColor &&
      other.focusedBorderColor == focusedBorderColor &&
      other.errorColor == errorColor &&
      other.borderWidth == borderWidth &&
      other.cornerRadius == cornerRadius &&
      other.holderHeight == holderHeight &&
      other.rowHeight == rowHeight &&
      other.horizontalPadding == horizontalPadding &&
      other.labelSpacing == labelSpacing &&
      other.sectionSpacing == sectionSpacing;

  @override
  int get hashCode => Object.hash(
    layout,
    labelTextStyle,
    inputTextStyle,
    placeholderColor,
    errorTextStyle,
    showLabels,
    holderLabel,
    cardLabel,
    fieldBackgroundColor,
    borderColor,
    focusedBorderColor,
    errorColor,
    borderWidth,
    cornerRadius,
    holderHeight,
    rowHeight,
    horizontalPadding,
    labelSpacing,
    sectionSpacing,
  );
}
