/// CONTRACT §16.3: the Client API of the native card flow, authenticated
/// with the publishable key and the order's client secret.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show TlsException;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../config.dart';
import '../../error.dart';
import '../http_log.dart';
import '../logger.dart';
import '../request.dart';
import 'card_clock.dart';
import 'tls_pins.dart';

/// Timeout of a Client API GET.
const Duration clientGetTimeout = Duration(seconds: 15);

/// Timeout of `POST …/pay`.
const Duration clientPostTimeout = Duration(seconds: 30);

/// The waits before the three retries of an HTTP 429.
const List<Duration> rateLimitBackoff = <Duration>[
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
];

/// The wait before the single retry of a `/pay` that got no response.
const Duration payNetworkRetryDelay = Duration(seconds: 1);

/// The largest response body the SDK reads. Payriff's answers are a few
/// kilobytes; anything larger is refused instead of filling memory.
const int maxResponseBytes = 1024 * 1024;

/// The card flow's API host per environment (CONTRACT §16.2). The sandbox
/// host is provisional until Payriff confirms it; it lives only here.
String clientApiBaseUrl(PayriffEnvironment environment) =>
    switch (environment) {
      PayriffEnvironment.production => 'https://api.payriff.com',
      PayriffEnvironment.sandbox => 'https://sb-api.payriff.com',
    };

/// Replaces the HTTP client of new [ClientApi]s (CONTRACT §16.2: "a
/// test-only hook may inject a transport"). For tests only: ignored outside
/// debug builds, so a release build never hands the client secret and the
/// encrypted card to another client. An injected client is not pinned;
/// without one every client is [pinnedHttpClient].
@visibleForTesting
http.Client Function()? debugPayriffClientApiHttpClient;

final RegExp _keyShape = RegExp(r'^[\x21-\x7E]+$');

/// CONTRACT §16.2 (`card_api.json` → `keys`): the trimmed publishable key
/// when it starts with `pr_pk_live_` and is a plain header token; `null`
/// otherwise. A secret key never has that prefix, so it is always refused.
String? usablePublishableKey(String? key) {
  final String? trimmed = trimToNull(key);
  if (trimmed == null ||
      !trimmed.startsWith('pr_pk_live_') ||
      !_keyShape.hasMatch(trimmed)) {
    return null;
  }
  return trimmed;
}

/// `card_api.json` → `clientSecrets`: the trimmed client secret when it
/// starts with `pr_cs_` and is a plain header token; `null` otherwise.
String? usableClientSecret(String? secret) {
  final String? trimmed = trimToNull(secret);
  if (trimmed == null ||
      !trimmed.startsWith('pr_cs_') ||
      !_keyShape.hasMatch(trimmed)) {
    return null;
  }
  return trimmed;
}

/// CONTRACT §16.3: the order path, with the id trimmed and encoded as one
/// path segment. Throws `INVALID_ORDER` for an empty id and for `.` and
/// `..`, which `Uri` would turn into another endpoint.
String clientOrderPath(String orderId, [String suffix = '']) {
  final String id = orderId.trim();
  if (id.isEmpty || id == '.' || id == '..') {
    throw PayriffException(invalidOrder('orderId must be a Payriff order id.'));
  }
  return '/api/v3/client/orders/${encodePathSegment(id)}$suffix';
}

/// A prepared `/pay` request: the exact body bytes and the headers that are
/// resent unchanged on a retry.
final class PayRequest {
  /// Creates a request.
  PayRequest({
    required this.body,
    required this.wrappedKey,
    required this.idempotencyKey,
  });

  /// `{"method":"CARD","encryptedMessage":"…"}` as UTF-8.
  final Uint8List body;

  /// The RSA-wrapped AES key and IV (`x-secret-key`).
  final String wrappedKey;

  /// A new UUID per pay attempt (`X-Idempotency-Key`).
  final String idempotencyKey;

  @override
  String toString() => 'PayRequest(<redacted>)';
}

/// The `/pay` body for [encryptedMessage], byte-exact.
Uint8List payBody(String encryptedMessage) => utf8.encode(
  jsonEncode(<String, Object?>{
    'method': 'CARD',
    'encryptedMessage': encryptedMessage,
  }),
);

/// A random version-4 UUID from the platform CSPRNG.
String newIdempotencyKey([math.Random? random]) {
  final math.Random rng = random ?? math.Random.secure();
  final List<int> b = List<int>.generate(16, (_) => rng.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final String h = b.map((int x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

/// One Client API session: the publishable key, one order's client secret
/// and the app id.
///
/// Every call returns the envelope's `payload` (an empty map when it has
/// none) or throws a [PayriffException] mapped as in CONTRACT §16.3.
final class ClientApi {
  /// Creates a client. It owns a pinned `dart:io` client
  /// ([pinnedHttpClient], CONTRACT §16.15; never `http.Client()`, so a zone
  /// client from `http.runWithClient` never sees the client secret) and
  /// closes it in [close].
  ClientApi({
    required this.baseUrl,
    required String publishableKey,
    required String clientSecret,
    required String? appId,
    required CardClock clock,
    SdkLogger? logger,
  }) : _publishableKey = publishableKey,
       _clientSecret = clientSecret,
       _appId = appId,
       _clock = clock,
       _logger = logger ?? SdkLogger.silent,
       _client =
           (kDebugMode ? debugPayriffClientApiHttpClient?.call() : null) ??
           IOClient(pinnedHttpClient());

  /// The API base URL without a trailing slash.
  final String baseUrl;

  final String _publishableKey;
  final String _clientSecret;
  final String? _appId;
  final CardClock _clock;
  final SdkLogger _logger;
  final http.Client _client;

  /// `GET /api/v3/client/orders/{orderId}`.
  Future<Map<String, Object?>> retrieveOrder(String orderId) =>
      _call('GET', clientOrderPath(orderId), timeout: clientGetTimeout);

  /// `GET /api/v3/client/orders/{orderId}/three-ds`.
  Future<Map<String, Object?>> threeDs(String orderId) => _call(
    'GET',
    clientOrderPath(orderId, '/three-ds'),
    timeout: clientGetTimeout,
  );

  /// `GET /api/v3/client/orders/{orderId}/status`.
  Future<Map<String, Object?>> status(String orderId) => _call(
    'GET',
    clientOrderPath(orderId, '/status'),
    timeout: clientGetTimeout,
  );

  /// `POST /api/v3/client/orders/{orderId}/pay` with [request]. A 429 is
  /// retried with the same bytes and idempotency key, and so is one request
  /// that got no response.
  Future<Map<String, Object?>> pay(String orderId, PayRequest request) => _call(
    'POST',
    clientOrderPath(orderId, '/pay'),
    body: request.body,
    extraHeaders: <String, String>{
      'Content-Type': 'application/json',
      'x-secret-key': request.wrappedKey,
      'X-Idempotency-Key': request.idempotencyKey,
    },
    timeout: clientPostTimeout,
    retryNoResponseOnce: true,
  );

  /// Closes the HTTP client.
  void close() => _client.close();

  Future<Map<String, Object?>> _call(
    String method,
    String path, {
    Uint8List? body,
    Map<String, String> extraHeaders = const <String, String>{},
    required Duration timeout,
    bool retryNoResponseOnce = false,
  }) async {
    final Uri url = Uri.parse('$baseUrl$path');
    int rateLimitRetries = 0;
    bool retriedNoResponse = false;
    while (true) {
      final (int, String) response;
      try {
        response = await _send(method, url, body, extraHeaders, timeout);
      } on PayriffException catch (e) {
        // A pinning failure is not retried: nothing was sent, and the
        // same server would be refused again.
        if (retryNoResponseOnce &&
            !retriedNoResponse &&
            e.error.code == PayriffErrorCode.networkError &&
            e.error.isRetryable) {
          retriedNoResponse = true;
          _logger.info('$method ${url.path}: no response, retrying once');
          await _clock.sleep(payNetworkRetryDelay);
          continue;
        }
        rethrow;
      }
      final (int status, String text) = response;
      if (status == 429 && rateLimitRetries < rateLimitBackoff.length) {
        final Duration wait = rateLimitBackoff[rateLimitRetries++];
        _logger.info(
          '$method ${url.path}: HTTP 429, retry $rateLimitRetries in '
          '${wait.inSeconds} s',
        );
        await _clock.sleep(wait);
        continue;
      }
      return parseClientResponse(status, text);
    }
  }

  Future<(int, String)> _send(
    String method,
    Uri url,
    Uint8List? body,
    Map<String, String> extraHeaders,
    Duration timeout,
  ) async {
    final http.Request request = http.Request(method, url)
      // The API does not redirect; a redirect would carry the client secret
      // somewhere else, so it is taken as the (unsuccessful) answer.
      ..followRedirects = false
      ..headers['Accept'] = 'application/json'
      ..headers['X-Public-Key'] = _publishableKey
      ..headers['X-Client-Secret'] = _clientSecret
      ..headers.addAll(extraHeaders);
    final String? appId = _appId;
    if (appId != null) request.headers['X-Client-App-Id'] = appId;
    if (body != null) request.bodyBytes = body;
    _logger.debug('$method ${url.path}');
    if (httpDetailsLogged) {
      _logger.debug(
        'HTTP request\n'
        '${describeRequest(method, url, request.headers, body == null ? null : utf8.decode(body, allowMalformed: true))}',
      );
    }
    try {
      final http.StreamedResponse streamed = await _client
          .send(request)
          .timeout(timeout);
      final (int status, Uint8List bytes) = await _readCapped(
        streamed,
      ).timeout(timeout);
      final String text = utf8.decode(bytes, allowMalformed: true);
      _logger.debug('$method ${url.path} -> HTTP $status');
      if (httpDetailsLogged) {
        _logger.debug(
          'HTTP response\n'
          '${describeResponse(status, method, url, streamed.headers, text)}',
        );
      }
      return (status, text);
    } on _TooLarge catch (e) {
      _logger.warning('$method ${url.path}: the response is too large');
      return (e.status, '');
    } on TimeoutException {
      _logger.warning('$method ${url.path} timed out');
      throw PayriffException(
        PayriffError(
          code: PayriffErrorCode.networkError,
          message: 'The request timed out after ${timeout.inSeconds} s.',
          isRetryable: true,
        ),
      );
    } on TlsException {
      // CONTRACT §16.15: the server's certificate failed the pinned
      // validation (a HandshakeException or CertificateException), so the
      // TLS handshake ended before the request was sent.
      _logger.warning(
        '$method ${url.path}: the server certificate could not be verified',
      );
      throw const PayriffException(pinningFailure);
    } on Object {
      // The exception text is not kept: an HTTP client may quote headers.
      _logger.warning('$method ${url.path} failed: no response');
      throw const PayriffException(
        PayriffError(
          code: PayriffErrorCode.networkError,
          message: 'The request failed before a response arrived.',
          isRetryable: true,
        ),
      );
    }
  }

  static Future<(int, Uint8List)> _readCapped(
    http.StreamedResponse response,
  ) async {
    final int status = response.statusCode;
    final int? declared = response.contentLength;
    if (declared != null && declared > maxResponseBytes) {
      unawaited(response.stream.listen(null).cancel());
      throw _TooLarge(status);
    }
    final BytesBuilder bytes = BytesBuilder(copy: false);
    await for (final List<int> chunk in response.stream) {
      bytes.add(chunk);
      if (bytes.length > maxResponseBytes) throw _TooLarge(status);
    }
    return (status, bytes.takeBytes());
  }
}

final class _TooLarge implements Exception {
  const _TooLarge(this.status);

  final int status;
}

/// CONTRACT §16.3: the envelope `payload` of a successful answer (HTTP 2xx
/// and `code` `00000`), or a [PayriffException] with the mapped error.
Map<String, Object?> parseClientResponse(int httpStatus, String body) {
  Map<String, Object?>? envelope;
  if (body.trim().isNotEmpty) {
    try {
      final Object? decoded = jsonDecode(body);
      if (decoded is Map<String, Object?>) envelope = decoded;
    } on FormatException {
      envelope = null;
    }
  }
  final Object? rawCode = envelope?['code'];
  final String? code = rawCode is String ? rawCode : null;
  if (httpStatus >= 200 && httpStatus < 300 && code == '00000') {
    final Object? payload = envelope!['payload'];
    return payload is Map<String, Object?> ? payload : <String, Object?>{};
  }
  throw PayriffException(
    mapClientError(httpStatus, code, envelope?['message']),
  );
}

/// Splits a Payriff message at its first newline: the trimmed first line and
/// the digits after `Support ticket:` in the rest, when present.
(String?, String?) splitPayriffMessage(Object? raw) {
  if (raw is! String) return (null, null);
  final int newline = raw.indexOf('\n');
  final String head = (newline < 0 ? raw : raw.substring(0, newline)).trim();
  final String rest = newline < 0 ? '' : raw.substring(newline + 1);
  final String? ticket = RegExp(
    r'Support ticket:\s*(\d+)',
  ).firstMatch(rest)?.group(1);
  return (head.isEmpty ? null : head, ticket);
}

/// CONTRACT §16.3 (`card_api.json` → `errors`): the error for an
/// unsuccessful answer. [message] is the envelope's `message`.
PayriffError mapClientError(int httpStatus, String? code, Object? message) {
  final (String? text, String? ticket) = splitPayriffMessage(message);
  PayriffError error(
    PayriffErrorCode kind,
    String fallback, {
    bool fatal = false,
    bool retryable = false,
  }) => PayriffError(
    code: kind,
    message: text ?? fallback,
    isRetryable: retryable,
    httpStatus: httpStatus,
    payriffCode: code,
    supportTicket: ticket,
    isFatal: fatal,
  );
  if (httpStatus == 401) {
    return error(
      PayriffErrorCode.unauthorized,
      'Payriff rejected the publishable key or this app (HTTP 401).',
      fatal: true,
    );
  }
  if (httpStatus == 404) {
    return error(
      PayriffErrorCode.sessionExpired,
      'The order was not found or its client secret expired.',
      fatal: true,
    );
  }
  if (httpStatus == 429) {
    return error(
      PayriffErrorCode.rateLimited,
      'Too many requests (HTTP 429).',
      fatal: true,
    );
  }
  if (httpStatus == 400 && code == '15400') {
    return error(
      PayriffErrorCode.invalidRequest,
      'Payriff rejected the request format.',
    );
  }
  if (httpStatus == 400) {
    return error(PayriffErrorCode.orderNotPayable, 'The order cannot be paid.');
  }
  return error(
    PayriffErrorCode.paymentFailed,
    'The payment failed (HTTP $httpStatus).',
    retryable: true,
  );
}
