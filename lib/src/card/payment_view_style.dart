import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'card_form_style.dart';

/// The look of `PayriffPaymentView` (CONTRACT §16.14).
///
/// Every property is optional. The defaults reproduce the card part of
/// Payriff's hosted payment page (pay.payriff.com) in the system font, and
/// follow light and dark mode. A colour you set is used in both modes.
///
/// ```dart
/// PayriffPaymentView(
///   orderId: order.orderId,
///   clientSecret: order.clientSecret,
///   onResult: handleResult,
///   style: const PayriffPaymentViewStyle(
///     buttonColor: Color(0xFF0B57D0),
///     buttonCornerRadius: 8,
///     showPoweredBy: false,
///     formStyle: PayriffCardFormStyle(cornerRadius: 8),
///   ),
/// )
/// ```
@immutable
final class PayriffPaymentViewStyle {
  /// Creates a style. Leave a property out to keep its default.
  const PayriffPaymentViewStyle({
    this.backgroundColor,
    this.padding = const EdgeInsets.all(20),
    this.buttonColor,
    this.buttonTextStyle,
    this.buttonHeight = 44,
    this.buttonCornerRadius = 16,
    this.secondaryTextColor,
    this.showBadges = true,
    this.showSecureNote = true,
    this.showPoweredBy = true,
    this.formStyle = const PayriffCardFormStyle(),
  }) : assert(buttonHeight >= 0),
       assert(buttonCornerRadius >= 0);

  /// The background of the whole view. `null`: `#FCFCFD`, `#222224` in dark
  /// mode.
  final Color? backgroundColor;

  /// The space around the content. The view adds the safe area and, when
  /// its parent does not make room for the keyboard, the keyboard's height.
  /// Defaults to 20 on every side.
  final EdgeInsets padding;

  /// The fill of the Pay button. `null`: Payriff's brand colour `#4DBDC6`.
  final Color? buttonColor;

  /// The Pay button's title, merged over the default: 16 semibold, white.
  /// The spinner shown while paying uses its colour.
  final TextStyle? buttonTextStyle;

  /// The height of the Pay button; it grows with large text. Defaults to 44.
  final double buttonHeight;

  /// The radius of the Pay button's corners. Defaults to 16.
  final double buttonCornerRadius;

  /// The colour of the secure line and the "Powered by" footer. `null`:
  /// `#76787F`.
  final Color? secondaryTextColor;

  /// Whether to show the Mastercard and Visa badges under the Pay button.
  /// Defaults to `true`.
  final bool showBadges;

  /// Whether to show the lock and the "Proceed securely by PCI DSS" line.
  /// Defaults to `true`.
  final bool showSecureNote;

  /// Whether to show the "Powered by Payriff" footer at the bottom.
  /// Defaults to `true`.
  final bool showPoweredBy;

  /// The look of the card form inside the view. Its error colour and error
  /// text style are also used for the view's error line.
  final PayriffCardFormStyle formStyle;

  /// A copy with the given properties replaced.
  PayriffPaymentViewStyle copyWith({
    Color? backgroundColor,
    EdgeInsets? padding,
    Color? buttonColor,
    TextStyle? buttonTextStyle,
    double? buttonHeight,
    double? buttonCornerRadius,
    Color? secondaryTextColor,
    bool? showBadges,
    bool? showSecureNote,
    bool? showPoweredBy,
    PayriffCardFormStyle? formStyle,
  }) => PayriffPaymentViewStyle(
    backgroundColor: backgroundColor ?? this.backgroundColor,
    padding: padding ?? this.padding,
    buttonColor: buttonColor ?? this.buttonColor,
    buttonTextStyle: buttonTextStyle ?? this.buttonTextStyle,
    buttonHeight: buttonHeight ?? this.buttonHeight,
    buttonCornerRadius: buttonCornerRadius ?? this.buttonCornerRadius,
    secondaryTextColor: secondaryTextColor ?? this.secondaryTextColor,
    showBadges: showBadges ?? this.showBadges,
    showSecureNote: showSecureNote ?? this.showSecureNote,
    showPoweredBy: showPoweredBy ?? this.showPoweredBy,
    formStyle: formStyle ?? this.formStyle,
  );

  @override
  bool operator ==(Object other) =>
      other is PayriffPaymentViewStyle &&
      other.backgroundColor == backgroundColor &&
      other.padding == padding &&
      other.buttonColor == buttonColor &&
      other.buttonTextStyle == buttonTextStyle &&
      other.buttonHeight == buttonHeight &&
      other.buttonCornerRadius == buttonCornerRadius &&
      other.secondaryTextColor == secondaryTextColor &&
      other.showBadges == showBadges &&
      other.showSecureNote == showSecureNote &&
      other.showPoweredBy == showPoweredBy &&
      other.formStyle == formStyle;

  @override
  int get hashCode => Object.hash(
    backgroundColor,
    padding,
    buttonColor,
    buttonTextStyle,
    buttonHeight,
    buttonCornerRadius,
    secondaryTextColor,
    showBadges,
    showSecureNote,
    showPoweredBy,
    formStyle,
  );
}
