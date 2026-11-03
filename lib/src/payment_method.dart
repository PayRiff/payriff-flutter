/// How the customer pays in `PayriffPaymentView` (CONTRACT §18.5), as
/// `onPaymentStarted` reports it.
enum PayriffPaymentMethod {
  /// The card form and its Pay button.
  card('CARD'),

  /// The Apple Pay button, on iOS.
  applePay('APPLE_PAY'),

  /// The Google Pay button, on Android.
  googlePay('GOOGLE_PAY');

  const PayriffPaymentMethod(this.value);

  /// The Client API's name of the method, for example `APPLE_PAY`.
  final String value;
}
