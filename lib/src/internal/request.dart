import 'dart:convert';

import '../error.dart';

/// Creates an `INVALID_ORDER` error naming the offending argument.
PayriffError invalidOrder(String message) =>
    PayriffError(code: PayriffErrorCode.invalidOrder, message: message);

/// Creates an `INVALID_CONFIG` error.
PayriffError invalidConfig(String message) =>
    PayriffError(code: PayriffErrorCode.invalidConfig, message: message);

/// Creates a `NOT_CONFIGURED` error.
PayriffError notConfigured(String message) =>
    PayriffError(code: PayriffErrorCode.notConfigured, message: message);

/// [value] without surrounding whitespace, or `null` when it is `null` or
/// blank.
String? trimToNull(String? value) {
  final String? trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// CONTRACT §16.3: percent-encodes the UTF-8 bytes of [value] as one path
/// segment. Only ALPHA, DIGIT, `-`, `_` and `~` stay; everything else,
/// including `.`, becomes `%XX` with upper-case hex.
String encodePathSegment(String value) {
  final StringBuffer out = StringBuffer();
  for (final int byte in utf8.encode(value)) {
    final bool keep =
        (byte >= 0x41 && byte <= 0x5A) || // A-Z
        (byte >= 0x61 && byte <= 0x7A) || // a-z
        (byte >= 0x30 && byte <= 0x39) || // 0-9
        byte == 0x2D || // -
        byte == 0x5F || // _
        byte == 0x7E; // ~
    if (keep) {
      out.writeCharCode(byte);
    } else {
      out
        ..write('%')
        ..write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
    }
  }
  return out.toString();
}
