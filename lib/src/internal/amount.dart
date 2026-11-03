/// Amounts as the customer sees them: on the payment view's Pay button and
/// in the Apple Pay and Google Pay sheets (CONTRACT §16.14, §17.4).
library;

// A non-negative number as Dart prints it: digits, an optional fraction and
// an optional exponent (`10.5`, `1e-7`, `1.5e+21`).
final RegExp _decimal = RegExp(r'^(\d+)(?:\.(\d*))?(?:[eE]([+-]?\d+))?$');

/// [amount] with exactly 2 decimals and `.` as the separator, for example
/// `10.5` → `10.50` (`wallet.json` → `amounts`). `null` when [amount] is
/// `null`, infinite or NaN.
///
/// Decimal arithmetic: the number is read from its shortest decimal form
/// (the digits the API sent), then rounded half up to cents, so a binary
/// value such as `1.005` → `1.0049999…` still gives `1.01`.
String? formatAmount2(num? amount) {
  if (amount == null || !amount.isFinite) return null;
  final RegExpMatch? match = _decimal.firstMatch(amount.abs().toString());
  if (match == null) return null;
  final String fraction = match[2] ?? '';
  final BigInt digits = BigInt.parse('${match[1]}$fraction');
  // amount = digits × 10^(exponent − fraction digits); cents = amount × 100.
  final int shift = int.parse(match[3] ?? '0') - fraction.length + 2;
  BigInt cents;
  if (shift >= 0) {
    cents = digits * BigInt.from(10).pow(shift);
  } else {
    final BigInt unit = BigInt.from(10).pow(-shift);
    cents = digits ~/ unit;
    if ((digits % unit) * BigInt.two >= unit) cents += BigInt.one;
  }
  final String text = cents.toString().padLeft(3, '0');
  final String formatted =
      '${text.substring(0, text.length - 2)}.'
      '${text.substring(text.length - 2)}';
  return amount < 0 && cents != BigInt.zero ? '-$formatted' : formatted;
}
