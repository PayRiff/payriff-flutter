/// Request and response logging for the SDK's API calls (CONTRACT §11): one
/// pretty-printed JSON object per request and per response, with headers and
/// body, at `debug` level, in debug builds only, with every secret redacted.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'logger.dart';

/// Whether request and response details are logged. Debug builds only, so a
/// release build never writes order data to the device log.
const bool httpDetailsLogged = kDebugMode;

/// Headers whose values never reach the logs.
const Set<String> _secretHeaders = <String>{
  'authorization',
  'x-client-secret',
  'x-secret-key',
};

/// JSON fields whose values never reach the logs.
const Set<String> _secretFields = <String>{
  'appkey',
  'app_key',
  'cardholder',
  'card_holder',
  'clientsecret',
  'client_secret',
  'creq',
  'cvc',
  'cvv',
  'encryptedmessage',
  'expirymonth',
  'expiryyear',
  'password',
  'secretkey',
  'secret_key',
  'threedsmethoddata',
  'threedssessiondata',
};

/// Card-number fields: only the last four digits are logged.
const Set<String> _panFields = <String>{'pan', 'cardnumber', 'card_number'};

/// A body whose redacted JSON is longer than this is not logged in full.
const int maxLoggedBodyChars = 16000;

const JsonEncoder _pretty = JsonEncoder.withIndent('  ');

/// The request as pretty-printed JSON: `method`, `url`, `headers`, `body`.
String describeRequest(
  String method,
  Uri url,
  Map<String, String> headers,
  String? body,
) => _pretty.convert(<String, Object?>{
  'method': method,
  'url': redactUrl(url.toString()),
  'headers': redactHeaders(headers),
  'body': redactBody(body),
});

/// The response as pretty-printed JSON: `status`, `method`, `url`,
/// `headers`, `body`.
String describeResponse(
  int status,
  String method,
  Uri url,
  Map<String, String> headers,
  String? body,
) => _pretty.convert(<String, Object?>{
  'status': status,
  'method': method,
  'url': redactUrl(url.toString()),
  'headers': redactHeaders(headers),
  'body': redactBody(body),
});

/// [headers] sorted by name, with secret headers as `***(<length>)` and the
/// publishable key reduced to its prefix.
Map<String, String> redactHeaders(Map<String, String> headers) {
  final List<String> names = headers.keys.toList()
    ..sort((String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return <String, String>{
    for (final String name in names)
      name: _headerValue(name.toLowerCase(), headers[name]!),
  };
}

String _headerValue(String lowerName, String value) {
  if (_secretHeaders.contains(lowerName)) return redactSecret(value);
  if (lowerName == 'x-public-key') {
    const String prefix = 'pr_pk_live_';
    return value.startsWith(prefix)
        ? '$prefix***(${value.length})'
        : redactSecret(value);
  }
  return value;
}

/// A JSON [body] with secrets redacted, card numbers masked and URL queries
/// stripped. `null` when empty; a short description when it is not JSON or
/// too long.
Object? redactBody(String? body) {
  if (body == null || body.isEmpty) return null;
  final Object? json;
  try {
    json = jsonDecode(body);
  } on FormatException {
    return '(${utf8.encode(body).length} bytes, not JSON)';
  }
  final Object? redacted = _redact(json, null);
  final int length = jsonEncode(redacted).length;
  return length <= maxLoggedBodyChars
      ? redacted
      : '($length characters of JSON, too long to log)';
}

Object? _redact(Object? value, String? key) {
  final String? lower = key?.toLowerCase();
  if (value is Map && value['key'] is String && value.containsKey('value')) {
    // A form field for the bank (`clientRequest`: creq, session data): the
    // name is shown, never the value.
    return <String, Object?>{
      for (final MapEntry<Object?, Object?> e in value.entries)
        '${e.key}': e.key == 'value'
            ? (e.value == null ? null : redactSecret('${e.value}'))
            : _redact(e.value, '${e.key}'),
    };
  }
  if (value is Map) {
    return <String, Object?>{
      for (final MapEntry<Object?, Object?> e in value.entries)
        '${e.key}': _redact(e.value, '${e.key}'),
    };
  }
  if (value is List) {
    return <Object?>[for (final Object? v in value) _redact(v, key)];
  }
  if (value == null) return null;
  if (lower != null && _secretFields.contains(lower)) {
    return redactSecret('$value');
  }
  if (lower != null && _panFields.contains(lower)) return _maskPan('$value');
  if (value is String && _httpUrl.hasMatch(value)) return redactUrl(value);
  return value;
}

final RegExp _httpUrl = RegExp(r'^https?://', caseSensitive: false);
final RegExp _nonDigit = RegExp(r'\D');

String _maskPan(String pan) {
  if (pan.contains('*')) return pan;
  final String digits = pan.replaceAll(_nonDigit, '');
  return digits.length <= 4
      ? redactSecret(pan)
      : '****${digits.substring(digits.length - 4)}';
}
