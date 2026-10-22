/// CONTRACT §16.6: the card plaintext and the pinned Payriff RSA key. The
/// encryption itself (AES-256-GCM and RSA-OAEP-SHA-256) runs in native code
/// through `NativeBridge.encryptCard`.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Payriff's RSA public key (DER SubjectPublicKeyInfo, Base64), pinned in
/// the SDK (`card_crypto.json` → `payriffPublicKeySpki`). A unit test checks
/// that the SHA-256 of its DER is [payriffPublicKeySha256]. The backend uses
/// the same key for the sandbox.
const String payriffPublicKeySpkiBase64 =
    'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAxRq5a+44T6Dac60XmVRQ/7cpPyFs'
    'BnamXbJlRVJk8CnES5Re5tVMohyD0hZr3zcQj+bxodYB4zZpQTPlrXvFBC3zz+rXnGlevxBQ'
    '6W2d3QC9q8vWH8p3ZOwTO3qVvDSHH9o+hMMRNbJ7kueq/KZlX/F+bjZ23CZw7iXEGQT3HYVY'
    'nnHsvpaguYDteWBag2sPPLLsVjeB3zhTfQ7OsWp5XTkDuRwLugHPvs6RHLcwGCnodukWyvwU'
    'aEUQR/kMGC+RbMsAIVkcLMP5csfR3Xo7Gi98+i44iLN00f7gE8QvEmvv8xDspyTAjDEL1a5g'
    'K7TijJ3yLG/Bwa1rr1uskYy7lwIDAQAB';

/// The SHA-256 (hex) of the DER of [payriffPublicKeySpkiBase64].
const String payriffPublicKeySha256 =
    '57bea5eb8ac72125dcda83306b98453840a80fc8ef5aac2798789587666024a5';

/// The DER bytes of the pinned key. A fresh copy on every call, so a caller
/// may zero or hand it to native code.
Uint8List payriffPublicKeyDer() => base64Decode(payriffPublicKeySpkiBase64);

/// The card fields that are encrypted. `toString` never shows them.
final class CardPlaintext {
  /// Creates the plaintext fields.
  const CardPlaintext({
    required this.pan,
    required this.cardHolder,
    required this.expiryYear,
    required this.expiryMonth,
    required this.cvv,
  });

  /// Digits only.
  final String pan;

  /// The normalized holder name, or `Unknown` without a holder field.
  final String cardHolder;

  /// Four digits.
  final String expiryYear;

  /// Two digits.
  final String expiryMonth;

  /// Three digits.
  final String cvv;

  @override
  String toString() => 'CardPlaintext(<redacted>)';
}

/// CONTRACT §16.6 step 2: the UTF-8 bytes of JavaScript's
/// `JSON.stringify({pan, cardHolder, expiryYear, expiryMonth, cvv})`: keys in
/// that order, no spaces, non-ASCII kept as UTF-8, `/` not escaped.
///
/// Escaping follows `JSON.stringify` exactly: `"` and `\` get a backslash;
/// `\b`, `\f`, `\n`, `\r` and `\t` their short forms; other code units below
/// U+0020 and lone surrogates become `\u` with four lower-case hex digits.
///
/// The caller zeroes the returned buffer after use. The Dart strings it is
/// built from cannot be wiped (see the README's known limitations).
Uint8List buildCardJsonBytes(CardPlaintext card) {
  final StringBuffer out = StringBuffer('{');
  void field(String key, String value, {bool last = false}) {
    out
      ..write('"')
      ..write(key)
      ..write('":"');
    _writeEscaped(out, value);
    out.write(last ? '"' : '",');
  }

  field('pan', card.pan);
  field('cardHolder', card.cardHolder);
  field('expiryYear', card.expiryYear);
  field('expiryMonth', card.expiryMonth);
  field('cvv', card.cvv, last: true);
  out.write('}');
  return utf8.encode(out.toString());
}

void _writeEscaped(StringBuffer out, String value) {
  final int length = value.length;
  for (int i = 0; i < length; i++) {
    final int unit = value.codeUnitAt(i);
    switch (unit) {
      case 0x22:
        out.write(r'\"');
      case 0x5C:
        out.write(r'\\');
      case 0x08:
        out.write(r'\b');
      case 0x0C:
        out.write(r'\f');
      case 0x0A:
        out.write(r'\n');
      case 0x0D:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      default:
        if (unit < 0x20) {
          _writeUnicodeEscape(out, unit);
        } else if (unit >= 0xD800 && unit <= 0xDBFF) {
          // A high surrogate: kept only when a low surrogate follows.
          final bool paired =
              i + 1 < length &&
              value.codeUnitAt(i + 1) >= 0xDC00 &&
              value.codeUnitAt(i + 1) <= 0xDFFF;
          if (paired) {
            out
              ..writeCharCode(unit)
              ..writeCharCode(value.codeUnitAt(i + 1));
            i++;
          } else {
            _writeUnicodeEscape(out, unit);
          }
        } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
          _writeUnicodeEscape(out, unit);
        } else {
          out.writeCharCode(unit);
        }
    }
  }
}

void _writeUnicodeEscape(StringBuffer out, int unit) =>
    out.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');

/// Overwrites [bytes] with zeros.
void zeroBytes(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);
