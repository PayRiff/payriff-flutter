import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../wallet/wallet_button_style.dart';
import 'card_form_style.dart';

/// Where `PayriffPaymentView` shows the Apple Pay or Google Pay button
/// (CONTRACT §20.1). Without a wallet the view looks the same with either.
enum PayriffWalletPlacement {
  /// Above the card form, the default: the wallet button, the "Or pay by
  /// card" divider 16 below it (unless `showWalletDivider` is `false`), then
  /// the card form 16 below.
  top,

  /// Under the Pay button: the card form and Pay first, then the wallet
  /// button 12 below Pay. The error line, the badges and the secure line
  /// follow below the wallet button. There is no divider, so
  /// `showWalletDivider` and `walletDividerText` have no effect.
  belowPayButton,
}

/// The look of `PayriffPaymentView` (CONTRACT §16.14, §17.9, §18, §20).
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
///     payButtonLabel: 'Pay now', // "Pay now 1.00 AZN"
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
    this.payButtonLabel,
    this.payButtonTitle,
    this.cornerSmoothing = 0,
    this.buttonDisabledColor,
    this.buttonDisabledTextColor,
    this.badgeBorderColor,
    this.secondaryTextColor,
    this.showBadges = true,
    this.showSecureNote = true,
    this.secureNoteText,
    this.showPoweredBy = true,
    this.formStyle = const PayriffCardFormStyle(),
    this.applePayButton = const PayriffApplePayButtonStyle(),
    this.googlePayButton = const PayriffGooglePayButtonStyle(),
    this.walletDividerText,
    this.showWalletDivider = true,
    this.walletPlacement = PayriffWalletPlacement.top,
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

  /// The height of the Pay button; it grows with large text. Its title stays
  /// one line, and a long one is truncated. Defaults to 44.
  final double buttonHeight;

  /// The radius of the Pay button's corners. Defaults to 16.
  final double buttonCornerRadius;

  /// The word on the Pay button, in place of "Pay". It is shown as it is in
  /// every language, without white space around it. The amount and the
  /// currency still follow it ("Pay now 1.00 AZN"), and it shows alone while
  /// the amount is unknown. `null`: "Pay" in the view's language.
  final String? payButtonLabel;

  /// The whole text of the Pay button, in every state and every language,
  /// without white space around it (CONTRACT §18.1). No amount or currency
  /// is added, also while the amount is unknown; the spinner still replaces
  /// it while paying. It wins over [payButtonLabel]. `null` or blank: the
  /// usual title with the amount.
  ///
  /// The Apple Pay and Google Pay sheets and the bank's 3-D Secure page still
  /// show the order's real amount and currency. With this title, showing the
  /// customer what will be charged is up to you.
  final String? payButtonTitle;

  /// How smooth the corners of the Pay button and the card badges are, from
  /// 0 (circular corners, the default) to 1 (CONTRACT §18.2): Figma's corner
  /// smoothing, as in iOS-style continuous corners. Values outside 0…1 are
  /// clamped. It is also the card form's when [formStyle] sets no
  /// `cornerSmoothing`. The wallet buttons keep their own shape.
  final double cornerSmoothing;

  /// The fill of the disabled Pay button (CONTRACT §18.3). When it or
  /// [buttonDisabledTextColor] is set, the disabled button is drawn in these
  /// colours at full opacity: this fill, else [buttonColor]. `null` with
  /// [buttonDisabledTextColor] also `null`: the enabled colours at 50%
  /// opacity.
  final Color? buttonDisabledColor;

  /// The text and spinner colour of the disabled Pay button (CONTRACT
  /// §18.3), else the enabled text colour. See [buttonDisabledColor].
  final Color? buttonDisabledTextColor;

  /// The border of the Mastercard and Visa badges under the Pay button
  /// (CONTRACT §18.4). In the view it also colours the border of the brand
  /// mark in the card number field, unless `formStyle.brandMarkBorderColor`
  /// is set. `null`: `#ECEEF0`.
  final Color? badgeBorderColor;

  /// The colour of the secure line and the "Powered by" footer. `null`:
  /// `#76787F`.
  final Color? secondaryTextColor;

  /// Whether to show the Mastercard and Visa badges under the Pay button.
  /// Defaults to `true`.
  final bool showBadges;

  /// Whether to show the lock and the "Proceed securely by PCI DSS" line.
  /// Defaults to `true`.
  final bool showSecureNote;

  /// The text next to the lock, in place of "Proceed securely by PCI DSS".
  /// It is shown as it is in every language. `null`: the text in the view's
  /// language.
  final String? secureNoteText;

  /// Whether to show the "Powered by Payriff" footer at the bottom.
  /// Defaults to `true`. In dark mode the logo's wordmark is light
  /// (`#E1E4E8`).
  final bool showPoweredBy;

  /// The look of the card form inside the view. Its error colour and error
  /// text style are also used for the view's error line, and its border
  /// colour for the lines of the wallet divider.
  final PayriffCardFormStyle formStyle;

  /// The Apple Pay button of the view (see [walletPlacement]), on iOS when
  /// `PayriffConfig.applePay` is set and Apple Pay is offered for the order.
  /// Its `height` defaults to the Pay button's height as laid out, at every
  /// text size (CONTRACT §20.2), and its `cornerRadius` to
  /// [buttonCornerRadius].
  final PayriffApplePayButtonStyle applePayButton;

  /// The Google Pay button of the view (see [walletPlacement]), on Android
  /// when `PayriffConfig.googlePay` is set and Google Pay is offered for the
  /// order. Its `height` defaults to the Pay button's height as laid out, at
  /// every text size (CONTRACT §20.2), and its `cornerRadius` to
  /// [buttonCornerRadius].
  final PayriffGooglePayButtonStyle googlePayButton;

  /// The text of the divider between the wallet button and the card form,
  /// in place of "Or pay by card". It is shown as it is in every language,
  /// without white space around it. `null` or blank: "Or pay by card" in the
  /// view's language. Only with [PayriffWalletPlacement.top].
  final String? walletDividerText;

  /// Whether to show the divider ("Or pay by card", with a line on each
  /// side) between the wallet button and the card form. Defaults to `true`.
  /// Without it the form follows the wallet button 16 below. Only with
  /// [PayriffWalletPlacement.top].
  final bool showWalletDivider;

  /// Where the Apple Pay or Google Pay button goes (CONTRACT §20.1):
  /// [PayriffWalletPlacement.top], the default, above the card form with
  /// the divider, or [PayriffWalletPlacement.belowPayButton], 12 below the
  /// Pay button and without the divider.
  final PayriffWalletPlacement walletPlacement;

  /// A copy with the given properties replaced.
  PayriffPaymentViewStyle copyWith({
    Color? backgroundColor,
    EdgeInsets? padding,
    Color? buttonColor,
    TextStyle? buttonTextStyle,
    double? buttonHeight,
    double? buttonCornerRadius,
    String? payButtonLabel,
    String? payButtonTitle,
    double? cornerSmoothing,
    Color? buttonDisabledColor,
    Color? buttonDisabledTextColor,
    Color? badgeBorderColor,
    Color? secondaryTextColor,
    bool? showBadges,
    bool? showSecureNote,
    String? secureNoteText,
    bool? showPoweredBy,
    PayriffCardFormStyle? formStyle,
    PayriffApplePayButtonStyle? applePayButton,
    PayriffGooglePayButtonStyle? googlePayButton,
    String? walletDividerText,
    bool? showWalletDivider,
    PayriffWalletPlacement? walletPlacement,
  }) => PayriffPaymentViewStyle(
    backgroundColor: backgroundColor ?? this.backgroundColor,
    padding: padding ?? this.padding,
    buttonColor: buttonColor ?? this.buttonColor,
    buttonTextStyle: buttonTextStyle ?? this.buttonTextStyle,
    buttonHeight: buttonHeight ?? this.buttonHeight,
    buttonCornerRadius: buttonCornerRadius ?? this.buttonCornerRadius,
    payButtonLabel: payButtonLabel ?? this.payButtonLabel,
    payButtonTitle: payButtonTitle ?? this.payButtonTitle,
    cornerSmoothing: cornerSmoothing ?? this.cornerSmoothing,
    buttonDisabledColor: buttonDisabledColor ?? this.buttonDisabledColor,
    buttonDisabledTextColor:
        buttonDisabledTextColor ?? this.buttonDisabledTextColor,
    badgeBorderColor: badgeBorderColor ?? this.badgeBorderColor,
    secondaryTextColor: secondaryTextColor ?? this.secondaryTextColor,
    showBadges: showBadges ?? this.showBadges,
    showSecureNote: showSecureNote ?? this.showSecureNote,
    secureNoteText: secureNoteText ?? this.secureNoteText,
    showPoweredBy: showPoweredBy ?? this.showPoweredBy,
    formStyle: formStyle ?? this.formStyle,
    applePayButton: applePayButton ?? this.applePayButton,
    googlePayButton: googlePayButton ?? this.googlePayButton,
    walletDividerText: walletDividerText ?? this.walletDividerText,
    showWalletDivider: showWalletDivider ?? this.showWalletDivider,
    walletPlacement: walletPlacement ?? this.walletPlacement,
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
      other.payButtonLabel == payButtonLabel &&
      other.payButtonTitle == payButtonTitle &&
      other.cornerSmoothing == cornerSmoothing &&
      other.buttonDisabledColor == buttonDisabledColor &&
      other.buttonDisabledTextColor == buttonDisabledTextColor &&
      other.badgeBorderColor == badgeBorderColor &&
      other.secondaryTextColor == secondaryTextColor &&
      other.showBadges == showBadges &&
      other.showSecureNote == showSecureNote &&
      other.secureNoteText == secureNoteText &&
      other.showPoweredBy == showPoweredBy &&
      other.formStyle == formStyle &&
      other.applePayButton == applePayButton &&
      other.googlePayButton == googlePayButton &&
      other.walletDividerText == walletDividerText &&
      other.showWalletDivider == showWalletDivider &&
      other.walletPlacement == walletPlacement;

  @override
  int get hashCode => Object.hashAll(<Object?>[
    backgroundColor,
    padding,
    buttonColor,
    buttonTextStyle,
    buttonHeight,
    buttonCornerRadius,
    payButtonLabel,
    payButtonTitle,
    cornerSmoothing,
    buttonDisabledColor,
    buttonDisabledTextColor,
    badgeBorderColor,
    secondaryTextColor,
    showBadges,
    showSecureNote,
    secureNoteText,
    showPoweredBy,
    formStyle,
    applePayButton,
    googlePayButton,
    walletDividerText,
    showWalletDivider,
    walletPlacement,
  ]);
}
