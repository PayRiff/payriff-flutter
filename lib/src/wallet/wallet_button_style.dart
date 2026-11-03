import 'package:flutter/foundation.dart';

/// The words on the Apple Pay button (CONTRACT §17.10): the
/// `PKPaymentButtonType` of the same name.
enum PayriffApplePayButtonType {
  /// The Apple Pay mark alone. The default.
  plain,

  /// "Buy with Apple Pay".
  buy,

  /// "Check out with Apple Pay".
  checkout,

  /// "Book with Apple Pay".
  book,

  /// "Donate with Apple Pay".
  donate,

  /// "Order with Apple Pay". Needs iOS 14; earlier versions show [plain].
  order,

  /// "Subscribe with Apple Pay".
  subscribe,
}

/// The colours of the Apple Pay button (CONTRACT §17.10): the
/// `PKPaymentButtonStyle` of the same name.
enum PayriffApplePayButtonTheme {
  /// Follows the page: [black] on a light page, [white] on a dark one,
  /// from the theme's brightness (`Theme`, or `CupertinoTheme` in a
  /// `CupertinoApp`). The default.
  automatic,

  /// A black button with a white mark.
  black,

  /// A white button with a black mark.
  white,

  /// A white button with a black mark and a thin black outline.
  whiteOutline,
}

/// The look of the Apple Pay button (CONTRACT §17.10).
///
/// The button is Apple's own `PKPaymentButton`: Apple's rules allow no other
/// way to draw the Apple Pay mark, so only these options exist.
///
/// ```dart
/// const PayriffApplePayButtonStyle(
///   type: PayriffApplePayButtonType.buy,
///   theme: PayriffApplePayButtonTheme.whiteOutline,
///   cornerRadius: 8,
/// )
/// ```
@immutable
final class PayriffApplePayButtonStyle {
  /// Creates a style. Leave a property out to keep its default.
  const PayriffApplePayButtonStyle({
    this.type = PayriffApplePayButtonType.plain,
    this.theme = PayriffApplePayButtonTheme.automatic,
    this.cornerRadius,
    this.height,
  });

  /// The words on the button. Defaults to [PayriffApplePayButtonType.plain].
  final PayriffApplePayButtonType type;

  /// The colours. Defaults to [PayriffApplePayButtonTheme.automatic].
  final PayriffApplePayButtonTheme theme;

  /// The radius of the corners. `null`: the payment view's
  /// `buttonCornerRadius` (16) in `PayriffPaymentView`, 16 in a standalone
  /// `PayriffApplePayButton`. A negative radius counts as 0.
  final double? cornerRadius;

  /// The height. `null`: the payment view's `buttonHeight` (44) in
  /// `PayriffPaymentView`, 44 in a standalone `PayriffApplePayButton`. A
  /// height below 40 is raised to 40.
  final double? height;

  /// A copy with the given properties replaced.
  PayriffApplePayButtonStyle copyWith({
    PayriffApplePayButtonType? type,
    PayriffApplePayButtonTheme? theme,
    double? cornerRadius,
    double? height,
  }) => PayriffApplePayButtonStyle(
    type: type ?? this.type,
    theme: theme ?? this.theme,
    cornerRadius: cornerRadius ?? this.cornerRadius,
    height: height ?? this.height,
  );

  @override
  bool operator ==(Object other) =>
      other is PayriffApplePayButtonStyle &&
      other.type == type &&
      other.theme == theme &&
      other.cornerRadius == cornerRadius &&
      other.height == height;

  @override
  int get hashCode => Object.hash(type, theme, cornerRadius, height);
}

/// The words on the Google Pay button (CONTRACT §17.10): the
/// `ButtonConstants.ButtonType` of the same name.
enum PayriffGooglePayButtonType {
  /// The Google Pay mark alone. The default.
  plain,

  /// "Buy with Google Pay".
  buy,

  /// "Pay with Google Pay".
  pay,

  /// "Check out with Google Pay".
  checkout,

  /// "Book with Google Pay".
  book,

  /// "Donate with Google Pay".
  donate,

  /// "Order with Google Pay".
  order,

  /// "Subscribe with Google Pay".
  subscribe,
}

/// The colours of the Google Pay button (CONTRACT §17.10): the
/// `ButtonConstants.ButtonTheme` of the same name.
enum PayriffGooglePayButtonTheme {
  /// Follows the page: [dark] on a light page, [light] on a dark one, from
  /// the theme's brightness (`Theme`, or `CupertinoTheme` in a
  /// `CupertinoApp`). The default.
  automatic,

  /// A dark button.
  dark,

  /// A light button.
  light,
}

/// The look of the Google Pay button (CONTRACT §17.10).
///
/// The button is Google's own `PayButton`: Google's brand rules allow no
/// other way to draw the Google Pay mark, so only these options exist.
///
/// ```dart
/// const PayriffGooglePayButtonStyle(
///   type: PayriffGooglePayButtonType.pay,
///   theme: PayriffGooglePayButtonTheme.light,
///   cornerRadius: 8,
/// )
/// ```
@immutable
final class PayriffGooglePayButtonStyle {
  /// Creates a style. Leave a property out to keep its default.
  const PayriffGooglePayButtonStyle({
    this.type = PayriffGooglePayButtonType.plain,
    this.theme = PayriffGooglePayButtonTheme.automatic,
    this.cornerRadius,
    this.height,
  });

  /// The words on the button. Defaults to [PayriffGooglePayButtonType.plain].
  final PayriffGooglePayButtonType type;

  /// The colours. Defaults to [PayriffGooglePayButtonTheme.automatic].
  final PayriffGooglePayButtonTheme theme;

  /// The radius of the corners. `null`: the payment view's
  /// `buttonCornerRadius` (16) in `PayriffPaymentView`, 16 in a standalone
  /// `PayriffGooglePayButton`. A negative radius counts as 0.
  final double? cornerRadius;

  /// The height. `null`: the payment view's `buttonHeight` (44) in
  /// `PayriffPaymentView`, 44 in a standalone `PayriffGooglePayButton`. A
  /// height below 40 is raised to 40.
  final double? height;

  /// A copy with the given properties replaced.
  PayriffGooglePayButtonStyle copyWith({
    PayriffGooglePayButtonType? type,
    PayriffGooglePayButtonTheme? theme,
    double? cornerRadius,
    double? height,
  }) => PayriffGooglePayButtonStyle(
    type: type ?? this.type,
    theme: theme ?? this.theme,
    cornerRadius: cornerRadius ?? this.cornerRadius,
    height: height ?? this.height,
  );

  @override
  bool operator ==(Object other) =>
      other is PayriffGooglePayButtonStyle &&
      other.type == type &&
      other.theme == theme &&
      other.cornerRadius == cornerRadius &&
      other.height == height;

  @override
  int get hashCode => Object.hash(type, theme, cornerRadius, height);
}
