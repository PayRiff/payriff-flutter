/// Card field validation, ported 1:1 from the web SDK (`fields/validation.js`,
/// Payriff.js 1.2.4, and mada from 1.3.1). Pure functions;
/// `card_validation.json` is the test.
library;

import 'dart:math' as math;

import '../../card/card_types.dart';

/// A brand's accepted prefix ranges and lengths.
typedef CardBrandRule = ({
  PayriffCardBrand brand,
  List<(String, String)> ranges,
  List<int> lengths,
});

/// The BINs of mada (CONTRACT §19.2, `card_validation.json` → `madaBins`):
/// the 113 entries of Payriff.js `MADA_BINS`, each an exact 6- or 8-digit
/// prefix.
const List<String> madaBins = <String>[
  '22337902',
  '22337986',
  '22402030',
  '40177800',
  '403024',
  '40545400',
  '406136',
  '406996',
  '40719700',
  '40739500',
  '407520',
  '409201',
  '410621',
  '410685',
  '410834',
  '412565',
  '417633',
  '419593',
  '420132',
  '421141',
  '42222200',
  '422817',
  '422818',
  '422819',
  '428331',
  '428671',
  '428672',
  '428673',
  '431361',
  '432328',
  '434107',
  '439954',
  '440533',
  '440647',
  '440795',
  '442463',
  '445564',
  '446393',
  '446404',
  '446672',
  '45488707',
  '45488713',
  '455036',
  '455708',
  '457865',
  '457997',
  '458456',
  '462220',
  '468540',
  '468541',
  '468542',
  '468543',
  '474491',
  '483010',
  '483011',
  '483012',
  '484783',
  '486094',
  '486095',
  '486096',
  '489317',
  '489318',
  '489319',
  '49098000',
  '49098001',
  '492464',
  '504300',
  '513213',
  '515079',
  '516138',
  '520058',
  '521076',
  '524130',
  '524514',
  '524940',
  '529415',
  '529741',
  '530060',
  '530906',
  '531095',
  '531196',
  '532013',
  '535825',
  '535989',
  '536023',
  '537767',
  '539931',
  '543085',
  '543357',
  '549760',
  '554180',
  '555610',
  '558563',
  '588845',
  '588848',
  '588850',
  '588982',
  '588983',
  '589005',
  '589206',
  '604906',
  '605141',
  '636120',
  '968201',
  '968202',
  '968203',
  '968204',
  '968205',
  '968206',
  '968207',
  '968208',
  '968209',
  '968211',
];

/// Prefix ranges compare as equal-length digit strings, so a partial number
/// can still "become" a brand (for example `22` for the Mastercard 2-series).
/// mada comes first: a brand is detected only once its whole prefix is
/// typed, so a card that is also Visa or Mastercard shows that brand until
/// its 6- or 8-digit mada BIN is complete (CONTRACT §19.2).
final List<CardBrandRule> cardBrandRules = <CardBrandRule>[
  (
    brand: PayriffCardBrand.mada,
    ranges: <(String, String)>[for (final String bin in madaBins) (bin, bin)],
    lengths: <int>[16],
  ),
  (
    brand: PayriffCardBrand.visa,
    ranges: <(String, String)>[('4', '4')],
    // CONTRACT §16.4: at most 16 digits (the web SDK also allows 19).
    lengths: <int>[16],
  ),
  (
    brand: PayriffCardBrand.mastercard,
    ranges: <(String, String)>[('51', '55'), ('2221', '2720')],
    lengths: <int>[16],
  ),
];

/// The most digits a card number may have (CONTRACT §16.4).
const int maxPanDigits = 16;

/// The longest cardholder name.
const int maxHolderLength = 50;

/// The CVV length.
const int cvvLength = 3;

/// The result of one validator: `value` is the normalized value.
typedef CardFieldValidation = ({
  bool valid,
  bool empty,
  PayriffCardFieldErrorCode? errorCode,
  PayriffCardBrand? brand,
  String value,
});

/// The result of [validateExpiry]; month and year are set when valid.
typedef ExpiryValidation = ({
  bool valid,
  bool empty,
  PayriffCardFieldErrorCode? errorCode,
  String? expiryMonth,
  String? expiryYear,
});

final RegExp _nonDigits = RegExp(r'\D+');
final RegExp _whitespace = RegExp(r'\s+');
final RegExp _edgeWhitespace = RegExp(r'^\s+|\s+$');
final RegExp _forbiddenHolder = RegExp(r'[\u0000-\u001f<>]');

/// JavaScript's `String(s).replace(/\D+/g, '')`.
String digitsOnly(String s) => s.replaceAll(_nonDigits, '');

/// The Luhn check; an empty string is not valid.
bool luhn(String digits) {
  int sum = 0;
  bool double = false;
  for (int i = digits.length - 1; i >= 0; i--) {
    int d = digits.codeUnitAt(i) - 48;
    if (double) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
    double = !double;
  }
  return digits.isNotEmpty && sum % 10 == 0;
}

bool _prefixMatch(String digits, String lo, String hi, {required bool full}) {
  if (full && digits.length < lo.length) return false;
  final int n = math.min(digits.length, lo.length);
  final String p = digits.substring(0, n);
  return p.compareTo(lo.substring(0, n)) >= 0 &&
      p.compareTo(hi.substring(0, n)) <= 0;
}

bool _matches(CardBrandRule rule, String digits, {required bool full}) =>
    rule.ranges.any(
      ((String, String) range) =>
          _prefixMatch(digits, range.$1, range.$2, full: full),
    );

/// The brand once enough digits are typed to be certain, else `null`.
PayriffCardBrand? detectBrand(String digits) {
  for (final CardBrandRule rule in cardBrandRules) {
    if (_matches(rule, digits, full: true)) return rule.brand;
  }
  return null;
}

List<CardBrandRule> _candidates(String digits) => <CardBrandRule>[
  for (final CardBrandRule rule in cardBrandRules)
    if (_matches(rule, digits, full: false)) rule,
];

/// The most digits [digits] may still grow to.
int maxPanLength(String digits) {
  final List<CardBrandRule> candidates = _candidates(digits);
  if (candidates.isEmpty) return maxPanDigits;
  return candidates.expand((CardBrandRule r) => r.lengths).reduce(math.max);
}

/// Validates a card number.
CardFieldValidation validateNumber(String raw) {
  final String digits = digitsOnly(raw);
  if (digits.isEmpty) {
    return (
      valid: false,
      empty: true,
      errorCode: PayriffCardFieldErrorCode.required,
      brand: null,
      value: '',
    );
  }
  final PayriffCardBrand? brand = detectBrand(digits);
  final List<CardBrandRule> candidates = _candidates(digits);
  if (candidates.isEmpty) {
    return (
      valid: false,
      empty: false,
      errorCode: PayriffCardFieldErrorCode.unsupported,
      brand: null,
      value: digits,
    );
  }
  final List<int> lengths = brand != null
      ? cardBrandRules.firstWhere((CardBrandRule r) => r.brand == brand).lengths
      : <int>[for (final CardBrandRule r in candidates) ...r.lengths];
  final int max = lengths.reduce(math.max);
  PayriffCardFieldErrorCode? error;
  if (digits.length > max) {
    error = PayriffCardFieldErrorCode.invalid;
  } else if (brand == null || !lengths.contains(digits.length)) {
    error = PayriffCardFieldErrorCode.incomplete;
  } else if (!luhn(digits)) {
    error = PayriffCardFieldErrorCode.invalid;
  }
  return (
    valid: error == null,
    empty: false,
    errorCode: error,
    brand: brand,
    value: digits,
  );
}

/// Validates `MM/YY` (separator optional) against [now]'s month. A card is
/// valid through the last day of its expiry month and at most 20 years
/// ahead.
ExpiryValidation validateExpiry(String raw, DateTime now) {
  final String digits = digitsOnly(raw);
  ExpiryValidation failed(
    PayriffCardFieldErrorCode code, {
    bool empty = false,
  }) => (
    valid: false,
    empty: empty,
    errorCode: code,
    expiryMonth: null,
    expiryYear: null,
  );
  if (digits.isEmpty) {
    return failed(PayriffCardFieldErrorCode.required, empty: true);
  }
  if (digits.length < 4) return failed(PayriffCardFieldErrorCode.incomplete);
  if (digits.length > 4) return failed(PayriffCardFieldErrorCode.invalid);
  final int month = int.parse(digits.substring(0, 2));
  final int year = 2000 + int.parse(digits.substring(2, 4));
  if (month < 1 || month > 12) return failed(PayriffCardFieldErrorCode.invalid);
  final int nowIndex = now.year * 12 + (now.month - 1);
  final int expIndex = year * 12 + (month - 1);
  if (expIndex < nowIndex) return failed(PayriffCardFieldErrorCode.expired);
  if (expIndex > nowIndex + 20 * 12) {
    return failed(PayriffCardFieldErrorCode.invalid);
  }
  return (
    valid: true,
    empty: false,
    errorCode: null,
    expiryMonth: month.toString().padLeft(2, '0'),
    expiryYear: '$year',
  );
}

/// Validates a 3-digit CVV.
CardFieldValidation validateCvv(String raw) {
  final String digits = digitsOnly(raw);
  final PayriffCardFieldErrorCode? error = digits.isEmpty
      ? PayriffCardFieldErrorCode.required
      : digits.length < cvvLength
      ? PayriffCardFieldErrorCode.incomplete
      : digits.length > cvvLength
      ? PayriffCardFieldErrorCode.invalid
      : null;
  return (
    valid: error == null,
    empty: digits.isEmpty,
    errorCode: error,
    brand: null,
    value: digits,
  );
}

/// JavaScript's `String(raw).trim().replace(/\s+/g, ' ')`.
String normalizeHolder(String raw) =>
    raw.replaceAll(_edgeWhitespace, '').replaceAll(_whitespace, ' ');

/// Validates a cardholder name: at most 50 UTF-16 code units, no control
/// characters, `<` or `>`.
CardFieldValidation validateHolder(String raw) {
  final String name = normalizeHolder(raw);
  final PayriffCardFieldErrorCode? error = name.isEmpty
      ? PayriffCardFieldErrorCode.required
      : name.length > maxHolderLength || _forbiddenHolder.hasMatch(name)
      ? PayriffCardFieldErrorCode.invalid
      : null;
  return (
    valid: error == null,
    empty: name.isEmpty,
    errorCode: error,
    brand: null,
    value: name,
  );
}

/// The error the customer should see right now (a UX timing decision; the
/// validator always knows the error).
///
/// * `invalid`, `unsupported` and `expired` show immediately: more typing
///   cannot fix them.
/// * `incomplete` shows once the field was left ([touched]) or a payment was
///   attempted ([submitted]), never while typing in it.
/// * `required` shows only after a payment attempt.
PayriffCardFieldErrorCode? visibleError(
  PayriffCardFieldErrorCode? code, {
  required bool focused,
  required bool touched,
  required bool submitted,
}) {
  if (code == null) return null;
  switch (code) {
    case PayriffCardFieldErrorCode.invalid:
    case PayriffCardFieldErrorCode.unsupported:
    case PayriffCardFieldErrorCode.expired:
      return code;
    case PayriffCardFieldErrorCode.required:
    case PayriffCardFieldErrorCode.incomplete:
      break;
  }
  if (focused && !submitted) return null;
  if (code == PayriffCardFieldErrorCode.required) {
    return submitted ? code : null;
  }
  return touched || submitted ? code : null;
}
