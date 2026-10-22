/// Display formatting of the card fields, ported 1:1 from the web SDK
/// (`fields/format.js`); `card_format.json` is the test. Formatting never
/// changes the validated value: the validators strip non-digits themselves.
library;

import 'dart:math' as math;

import 'package:flutter/services.dart';

import 'validation.dart';

final RegExp _groupsOfFour = RegExp(r'(\d{4})(?=\d)');
final RegExp _digit = RegExp(r'\d');

/// `4242 4242 4242 4242`, capped at the brand's longest length.
String formatNumber(String raw) {
  final String d = digitsOnly(raw);
  final String digits = d.substring(0, math.min(d.length, maxPanLength(d)));
  return digits.replaceAllMapped(_groupsOfFour, (Match m) => '${m[1]} ');
}

/// `MM / YY`. [inserting] is `true` while typing and `false` while deleting,
/// so that backspace can remove the ` / `.
String formatExpiry(String raw, {required bool inserting}) {
  final String all = digitsOnly(raw);
  final String d = all.substring(0, math.min(all.length, 4));
  if (d.length == 1 && d.compareTo('1') > 0 && inserting) return '0$d / ';
  if (d.length == 2 && inserting) return '$d / ';
  if (d.length > 2) return '${d.substring(0, 2)} / ${d.substring(2)}';
  return d;
}

/// At most three digits.
String formatCvv(String raw) {
  final String d = digitsOnly(raw);
  return d.substring(0, math.min(d.length, cvvLength));
}

/// The cardholder name in upper case, like on the card (CONTRACT §16.4).
/// Dart's mapping is locale-independent, so `i` becomes `I`, never `İ`.
String formatHolder(String raw) => raw.toUpperCase();

/// Applies [formatted] to an edit, keeping the caret after the same number
/// of digits (or at the end when it was at the end), like the web SDK's
/// `reformat`.
TextEditingValue reformatValue(TextEditingValue value, String formatted) {
  if (formatted == value.text) return value;
  final String text = value.text;
  final int caret = value.selection.isValid
      ? value.selection.baseOffset.clamp(0, text.length)
      : text.length;
  final bool atEnd = caret >= text.length;
  int pos = formatted.length;
  if (!atEnd) {
    final int digitsBefore = digitsOnly(text.substring(0, caret)).length;
    pos = 0;
    for (int seen = 0; pos < formatted.length && seen < digitsBefore; pos++) {
      if (_digit.hasMatch(formatted[pos])) seen++;
    }
  }
  return TextEditingValue(
    text: formatted,
    selection: TextSelection.collapsed(offset: pos),
  );
}

/// Which card field a [CardInputFormatter] formats.
enum CardFormatKind {
  /// The card number.
  number,

  /// The expiry date.
  expiry,

  /// The CVV.
  cvv,
}

/// Formats a card field while the customer types.
final class CardInputFormatter extends TextInputFormatter {
  /// Creates a formatter for [kind].
  CardInputFormatter(this.kind);

  /// The field it formats.
  final CardFormatKind kind;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final String formatted = switch (kind) {
      CardFormatKind.number => formatNumber(newValue.text),
      CardFormatKind.expiry => formatExpiry(
        newValue.text,
        inserting: newValue.text.length >= oldValue.text.length,
      ),
      CardFormatKind.cvv => formatCvv(newValue.text),
    };
    return reformatValue(newValue, formatted);
  }
}

/// Upper-cases the cardholder name while the customer types. The caret and
/// any composing region stay put; when upper-casing changes the length
/// (`ß` → `SS`) the caret goes to the end.
final class HolderInputFormatter extends TextInputFormatter {
  /// Creates the holder formatter.
  const HolderInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final String upper = formatHolder(newValue.text);
    if (upper == newValue.text) return newValue;
    if (upper.length != newValue.text.length) {
      return TextEditingValue(
        text: upper,
        selection: TextSelection.collapsed(offset: upper.length),
      );
    }
    return newValue.copyWith(text: upper);
  }
}
