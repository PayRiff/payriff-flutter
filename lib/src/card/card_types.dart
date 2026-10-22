import 'package:flutter/foundation.dart';

/// A field of the native card form (CONTRACT §16.4).
enum PayriffCardField {
  /// The card number (PAN).
  number('number'),

  /// The expiry date, `MM / YY`.
  expiry('expiry'),

  /// The 3-digit security code.
  cvv('cvv'),

  /// The cardholder name. Shown by default; hidden when
  /// `PayriffCardForm.showHolder` is `false`.
  holder('holder');

  const PayriffCardField(this.value);

  /// The canonical name, for example `number`.
  final String value;
}

/// A card brand the native card form accepts.
enum PayriffCardBrand {
  /// Visa (`4…`).
  visa('visa'),

  /// Mastercard (`51`–`55`, `2221`–`2720`).
  mastercard('mastercard');

  const PayriffCardBrand(this.value);

  /// The canonical name, for example `visa`.
  final String value;
}

/// Why a card field is not valid (CONTRACT §16.4, `card_validation.json`).
enum PayriffCardFieldErrorCode {
  /// The field is empty.
  required('required'),

  /// The customer has not typed enough yet.
  incomplete('incomplete'),

  /// The value can never become valid, for example a failed Luhn check.
  invalid('invalid'),

  /// The card number belongs to a brand the form does not accept.
  unsupported('unsupported'),

  /// The expiry date is in the past.
  expired('expired');

  const PayriffCardFieldErrorCode(this.value);

  /// The canonical name, for example `incomplete`.
  final String value;
}

/// One invalid field of a `VALIDATION_FAILED` error: which field and why.
/// It never contains what the customer typed.
@immutable
final class PayriffCardFieldError {
  /// Creates a field error.
  const PayriffCardFieldError({required this.field, required this.error});

  /// The invalid field.
  final PayriffCardField field;

  /// Why it is invalid.
  final PayriffCardFieldErrorCode error;

  /// `{"field": "number", "error": "invalid"}`.
  Map<String, Object?> toJson() => <String, Object?>{
    'field': field.value,
    'error': error.value,
  };

  @override
  bool operator ==(Object other) =>
      other is PayriffCardFieldError &&
      other.field == field &&
      other.error == error;

  @override
  int get hashCode => Object.hash(field, error);

  @override
  String toString() => 'PayriffCardFieldError(${field.value}: ${error.value})';
}

/// The `change` event of the native card form (CONTRACT §16.4). It never
/// contains the card number, expiry, CVV or holder name.
@immutable
final class PayriffCardFormChange {
  /// Creates a change event.
  const PayriffCardFormChange({
    required this.field,
    required this.valid,
    required this.empty,
    required this.error,
    required this.errorMessage,
    required this.brand,
    required this.complete,
  });

  /// The field that changed.
  final PayriffCardField field;

  /// Whether [field] is valid.
  final bool valid;

  /// Whether [field] is empty.
  final bool empty;

  /// The error the form shows for [field] right now, or `null`. Errors that
  /// more typing can still fix are shown only after the customer leaves the
  /// field or tries to pay.
  final PayriffCardFieldErrorCode? error;

  /// The localized text of [error], or `null`.
  final String? errorMessage;

  /// The detected brand of the card number, or `null` while unknown.
  final PayriffCardBrand? brand;

  /// Whether every field shown in the form is valid.
  final bool complete;

  @override
  bool operator ==(Object other) =>
      other is PayriffCardFormChange &&
      other.field == field &&
      other.valid == valid &&
      other.empty == empty &&
      other.error == error &&
      other.errorMessage == errorMessage &&
      other.brand == brand &&
      other.complete == complete;

  @override
  int get hashCode =>
      Object.hash(field, valid, empty, error, errorMessage, brand, complete);

  @override
  String toString() =>
      'PayriffCardFormChange(field: ${field.value}, valid: $valid, '
      'empty: $empty, error: ${error?.value}, brand: ${brand?.value}, '
      'complete: $complete)';
}
