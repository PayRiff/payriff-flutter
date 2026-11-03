import 'package:flutter/foundation.dart';

import 'error.dart';

/// Texts of your own for the SDK's screens (CONTRACT §18.6), for example
/// from your app's localization, or for a language the SDK does not have.
///
/// Every field is optional. Together they cover every visible text of the
/// card form, the payment view and the 3-D Secure sheet. A field that is
/// `null` or blank after trimming keeps the SDK's own text in the effective
/// language (Azerbaijani, English or Russian); any other value is shown
/// exactly as given, in every language.
///
/// Set them app-wide with `PayriffConfig.strings`, which also reaches the
/// 3-D Secure sheet that `Payriff.confirmCardPayment` opens, or for one
/// payment view with `PayriffPaymentView.strings`, which wins over the
/// config's field by field there and in the sheets the view opens.
///
/// The text options of the styles still win over these fields:
/// `PayriffPaymentViewStyle.payButtonTitle` and `payButtonLabel` over [pay],
/// `secureNoteText` over [secureNote], `walletDividerText` over
/// [orPayByCard], and `PayriffCardFormStyle.holderLabel` and `cardLabel`
/// over [holderLabel] and [cardInformationLabel].
///
/// ```dart
/// Payriff.configure(PayriffConfig(
///   publishableKey: 'pr_pk_live_…',
///   strings: PayriffStrings(
///     pay: l10n.pay,
///     holderLabel: l10n.cardHolder,
///     sheetTitle: l10n.payment,
///     errorMessages: <PayriffErrorCode, String>{
///       PayriffErrorCode.networkError: l10n.noConnection,
///     },
///   ),
/// ));
/// ```
@immutable
final class PayriffStrings {
  /// Creates a set of texts. Leave a field out to keep the SDK's text.
  const PayriffStrings({
    this.holderLabel,
    this.cardInformationLabel,
    this.numberAccessibilityLabel,
    this.expiryAccessibilityLabel,
    this.cvcAccessibilityLabel,
    this.holderPlaceholder,
    this.numberPlaceholder,
    this.expiryPlaceholder,
    this.cvcPlaceholder,
    this.numberRequired,
    this.numberIncomplete,
    this.numberInvalid,
    this.numberUnsupported,
    this.expiryRequired,
    this.expiryIncomplete,
    this.expiryInvalid,
    this.expiryExpired,
    this.cvcRequired,
    this.cvcIncomplete,
    this.cvcInvalid,
    this.holderRequired,
    this.holderInvalid,
    this.pay,
    this.secureNote,
    this.poweredBy,
    this.orPayByCard,
    this.notPayable,
    this.deviceNotSupported,
    this.sheetTitle,
    this.verifying,
    this.close,
    this.retry,
    this.closeConfirmTitle,
    this.closeConfirmMessage,
    this.closeConfirmClose,
    this.closeConfirmContinue,
    this.pageLoadError,
    this.dialogOk,
    this.dialogCancel,
    this.errorMessages = const <PayriffErrorCode, String>{},
  });

  // Card form ---------------------------------------------------------------

  /// The label above the cardholder name, and its accessibility label:
  /// "Card holder".
  final String? holderLabel;

  /// The label above the card box of the grouped layout: "Card
  /// information".
  final String? cardInformationLabel;

  /// The card number field's accessibility label, and its label in the
  /// stacked layout: "Card number".
  final String? numberAccessibilityLabel;

  /// The expiry field's accessibility label, and its label in the stacked
  /// layout: "Expiry date".
  final String? expiryAccessibilityLabel;

  /// The CVC field's accessibility label, and its label in the stacked
  /// layout: "Security code".
  final String? cvcAccessibilityLabel;

  /// The cardholder name's placeholder: "Card holder".
  final String? holderPlaceholder;

  /// The card number's placeholder: "1234 1234 1234 1234".
  final String? numberPlaceholder;

  /// The expiry's placeholder: "MM / YY".
  final String? expiryPlaceholder;

  /// The CVC's placeholder: "CVC".
  final String? cvcPlaceholder;

  /// The error of an empty card number, after Pay: "Enter your card
  /// number".
  final String? numberRequired;

  /// The error of a card number that is too short: "Card number is
  /// incomplete".
  final String? numberIncomplete;

  /// The error of a card number that fails the check: "Card number is
  /// invalid".
  final String? numberInvalid;

  /// The error of a card brand other than Visa and Mastercard: "This card
  /// type is not supported".
  final String? numberUnsupported;

  /// The error of an empty expiry, after Pay: "Enter the expiry date".
  final String? expiryRequired;

  /// The error of an expiry that is too short: "Expiry date is incomplete".
  final String? expiryIncomplete;

  /// The error of an expiry that is not a date, or too far ahead: "Expiry
  /// date is invalid".
  final String? expiryInvalid;

  /// The error of an expiry in the past: "This card has expired".
  final String? expiryExpired;

  /// The error of an empty CVC, after Pay: "Enter the CVV".
  final String? cvcRequired;

  /// The error of a CVC that is too short: "CVV is incomplete".
  final String? cvcIncomplete;

  /// The error of a CVC that cannot be valid: "CVV is invalid".
  final String? cvcInvalid;

  /// The error of an empty cardholder name, after Pay: "Enter the
  /// cardholder name".
  final String? holderRequired;

  /// The error of a cardholder name that is too long or has characters it
  /// may not have: "Cardholder name is invalid".
  final String? holderInvalid;

  // Payment view ------------------------------------------------------------

  /// The word on the Pay button, followed by the amount and the currency:
  /// "Pay" ("Pay 1.00 AZN").
  final String? pay;

  /// The text next to the lock: "Proceed securely by PCI DSS".
  final String? secureNote;

  /// The footer, "Powered by Payriff". The Payriff logo replaces the first
  /// "Payriff" in it; a text without "Payriff" is followed by a space and the
  /// logo.
  final String? poweredBy;

  /// The divider between the Apple Pay or Google Pay button and the card
  /// form: "Or pay by card".
  final String? orPayByCard;

  /// The error line of an order that cannot be paid by card: "This order
  /// cannot be paid by card".
  final String? notPayable;

  /// The error line on a device where card payments are refused: "Card
  /// payments aren't available on this device for security reasons".
  final String? deviceNotSupported;

  // 3-D Secure sheet --------------------------------------------------------

  /// The title of the 3-D Secure sheet: "Payment".
  final String? sheetTitle;

  /// The text under the loader while the payment is checked: "Checking
  /// payment…".
  final String? verifying;

  /// The close button's accessibility label, and the "Close" button of the
  /// page-load error.
  final String? close;

  /// The "Try again" button of the page-load error.
  final String? retry;

  /// The title of the close confirmation: "Close this window?".
  final String? closeConfirmTitle;

  /// The message of the close confirmation: "The payment isn't finished
  /// yet. If you close this window, we'll check its status.".
  final String? closeConfirmMessage;

  /// The close confirmation's button that closes the sheet: "Close".
  final String? closeConfirmClose;

  /// The close confirmation's button that keeps the sheet: "Continue
  /// payment".
  final String? closeConfirmContinue;

  /// The text when the bank page cannot be loaded: "The page couldn't be
  /// loaded. Check your internet connection.".
  final String? pageLoadError;

  /// The OK button of the bank page's JavaScript dialogs, which the SDK
  /// shows itself on iOS: "OK".
  final String? dialogOk;

  /// The Cancel button of the bank page's JavaScript dialogs on iOS:
  /// "Cancel".
  final String? dialogCancel;

  /// Texts for the SDK's on-screen error lines, by error code (CONTRACT
  /// §18.6):
  ///
  /// * the error line of `PayriffPaymentView` when the order did not load or
  ///   a payment ended the order (for example
  ///   [PayriffErrorCode.networkError] or [PayriffErrorCode.sessionExpired]),
  ///   in place of `PayriffError.message`, which is a developer-facing
  ///   English text;
  /// * the lines that have their own field, when that field is not set:
  ///   [PayriffErrorCode.deviceCompromised] for [deviceNotSupported],
  ///   [PayriffErrorCode.orderNotPayable] for [notPayable], and
  ///   [PayriffErrorCode.networkError] for [pageLoadError] in the 3-D Secure
  ///   sheet.
  ///
  /// Only the screen changes: the `PayriffError` in the result keeps its
  /// English `message`.
  final Map<PayriffErrorCode, String> errorMessages;

  @override
  bool operator ==(Object other) =>
      other is PayriffStrings &&
      other.holderLabel == holderLabel &&
      other.cardInformationLabel == cardInformationLabel &&
      other.numberAccessibilityLabel == numberAccessibilityLabel &&
      other.expiryAccessibilityLabel == expiryAccessibilityLabel &&
      other.cvcAccessibilityLabel == cvcAccessibilityLabel &&
      other.holderPlaceholder == holderPlaceholder &&
      other.numberPlaceholder == numberPlaceholder &&
      other.expiryPlaceholder == expiryPlaceholder &&
      other.cvcPlaceholder == cvcPlaceholder &&
      other.numberRequired == numberRequired &&
      other.numberIncomplete == numberIncomplete &&
      other.numberInvalid == numberInvalid &&
      other.numberUnsupported == numberUnsupported &&
      other.expiryRequired == expiryRequired &&
      other.expiryIncomplete == expiryIncomplete &&
      other.expiryInvalid == expiryInvalid &&
      other.expiryExpired == expiryExpired &&
      other.cvcRequired == cvcRequired &&
      other.cvcIncomplete == cvcIncomplete &&
      other.cvcInvalid == cvcInvalid &&
      other.holderRequired == holderRequired &&
      other.holderInvalid == holderInvalid &&
      other.pay == pay &&
      other.secureNote == secureNote &&
      other.poweredBy == poweredBy &&
      other.orPayByCard == orPayByCard &&
      other.notPayable == notPayable &&
      other.deviceNotSupported == deviceNotSupported &&
      other.sheetTitle == sheetTitle &&
      other.verifying == verifying &&
      other.close == close &&
      other.retry == retry &&
      other.closeConfirmTitle == closeConfirmTitle &&
      other.closeConfirmMessage == closeConfirmMessage &&
      other.closeConfirmClose == closeConfirmClose &&
      other.closeConfirmContinue == closeConfirmContinue &&
      other.pageLoadError == pageLoadError &&
      other.dialogOk == dialogOk &&
      other.dialogCancel == dialogCancel &&
      mapEquals(other.errorMessages, errorMessages);

  @override
  int get hashCode => Object.hashAll(<Object?>[
    holderLabel,
    cardInformationLabel,
    numberAccessibilityLabel,
    expiryAccessibilityLabel,
    cvcAccessibilityLabel,
    holderPlaceholder,
    numberPlaceholder,
    expiryPlaceholder,
    cvcPlaceholder,
    numberRequired,
    numberIncomplete,
    numberInvalid,
    numberUnsupported,
    expiryRequired,
    expiryIncomplete,
    expiryInvalid,
    expiryExpired,
    cvcRequired,
    cvcIncomplete,
    cvcInvalid,
    holderRequired,
    holderInvalid,
    pay,
    secureNote,
    poweredBy,
    orPayByCard,
    notPayable,
    deviceNotSupported,
    sheetTitle,
    verifying,
    close,
    retry,
    closeConfirmTitle,
    closeConfirmMessage,
    closeConfirmClose,
    closeConfirmContinue,
    pageLoadError,
    dialogOk,
    dialogCancel,
    Object.hashAllUnordered(<Object>[
      for (final MapEntry<PayriffErrorCode, String> e in errorMessages.entries)
        Object.hash(e.key, e.value),
    ]),
  ]);
}
