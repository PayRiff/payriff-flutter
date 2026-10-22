// Transport hardening of the Client API's own HTTP client (audit FLT-12),
// played against a local HttpServer on the loopback interface. No Payriff
// API and no external network is involved. This file has no widget tests,
// so the flutter_test binding's HTTP mock is not installed; the tests still
// run inside an HttpOverrides zone that creates real clients.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:payriff/payriff.dart';
import 'package:payriff/src/internal/card/card_clock.dart';
import 'package:payriff/src/internal/card/client_api.dart';

const String _okOrder =
    '{"code":"00000","payload":{"orderId":"o1","status":"CREATED"}}';

/// HttpOverrides that create real clients.
final class _RealHttp extends HttpOverrides {}

/// A loopback server; [handle] answers each request.
Future<HttpServer> _serve(
  List<String> paths,
  Future<void> Function(HttpRequest request) handle,
) async {
  final HttpServer server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  server.listen((HttpRequest request) async {
    paths.add(request.uri.path);
    await request.drain<void>();
    await handle(request);
    await request.response.close();
  });
  return server;
}

ClientApi _api(String baseUrl) => ClientApi(
  baseUrl: baseUrl,
  publishableKey: 'pr_pk_live_TEST',
  clientSecret: 'pr_cs_TEST',
  appId: 'com.payriff.example.flutter',
  clock: const SystemCardClock(),
);

String _base(HttpServer server) => 'http://127.0.0.1:${server.port}';

Future<T> _withRealHttp<T>(Future<T> Function() body) =>
    HttpOverrides.runWithHttpOverrides(body, _RealHttp());

Future<PayriffError> _errorOf(Future<Object?> call) async {
  try {
    await call;
  } on PayriffException catch (e) {
    return e.error;
  }
  fail('expected a PayriffException');
}

void main() {
  test('the Client API never sends through a zone client from '
      'http.runWithClient, which could log the client secret', () async {
    final List<String> paths = <String>[];
    final List<http.Request> zoneRequests = <http.Request>[];
    await _withRealHttp(() async {
      final HttpServer server = await _serve(paths, (
        HttpRequest request,
      ) async {
        expect(request.headers.value('x-client-secret'), 'pr_cs_TEST');
        request.response
          ..headers.contentType = ContentType.json
          ..write(_okOrder);
      });
      addTearDown(server.close);
      await http.runWithClient(
        () async {
          final ClientApi api = _api(_base(server));
          try {
            expect((await api.retrieveOrder('o1'))['orderId'], 'o1');
          } finally {
            api.close();
          }
        },
        () => MockClient((http.Request request) async {
          zoneRequests.add(request);
          return http.Response('{}', 500);
        }),
      );
    });
    expect(zoneRequests, isEmpty);
    expect(paths, <String>['/api/v3/client/orders/o1']);
  });

  test('a redirect is returned as the answer, never followed', () async {
    final List<String> paths = <String>[];
    await _withRealHttp(() async {
      final HttpServer server = await _serve(paths, (
        HttpRequest request,
      ) async {
        if (request.uri.path == '/elsewhere') {
          request.response.write(_okOrder);
          return;
        }
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(HttpHeaders.locationHeader, '/elsewhere');
      });
      addTearDown(server.close);
      final ClientApi api = _api(_base(server));
      addTearDown(api.close);
      final PayriffError error = await _errorOf(api.retrieveOrder('o1'));
      expect(error.code, PayriffErrorCode.paymentFailed);
      expect(error.httpStatus, HttpStatus.found);
    });
    expect(paths, <String>['/api/v3/client/orders/o1']);
  });

  test('a body over $maxResponseBytes bytes is refused, declared or '
      'streamed', () async {
    final List<String> paths = <String>[];
    await _withRealHttp(() async {
      final HttpServer server = await _serve(paths, (
        HttpRequest request,
      ) async {
        final List<int> big = List<int>.filled(maxResponseBytes + 1, 0x20);
        if (request.uri.path.endsWith('declared')) {
          request.response
            ..statusCode = 503
            ..contentLength = big.length
            ..add(big);
        } else {
          // Chunked, without a Content-Length.
          request.response.bufferOutput = false;
          for (int i = 0; i < big.length; i += 64 * 1024) {
            request.response.add(
              big.sublist(i, (i + 64 * 1024).clamp(0, big.length)),
            );
            await request.response.flush();
          }
        }
      });
      addTearDown(server.close);
      final ClientApi api = _api(_base(server));
      addTearDown(api.close);
      final PayriffError declared = await _errorOf(
        api.retrieveOrder('declared'),
      );
      expect(declared.code, PayriffErrorCode.paymentFailed);
      expect(declared.httpStatus, 503);
      final PayriffError streamed = await _errorOf(
        api.retrieveOrder('streamed'),
      );
      expect(streamed.code, PayriffErrorCode.paymentFailed);
      expect(streamed.httpStatus, 200);
    });
  });

  test('a body of exactly the limit is still read', () async {
    final String padded = _okOrder.padRight(maxResponseBytes);
    expect(utf8.encode(padded), hasLength(maxResponseBytes));
    debugPayriffClientApiHttpClient = () =>
        MockClient((http.Request request) async => http.Response(padded, 200));
    addTearDown(() => debugPayriffClientApiHttpClient = null);
    final ClientApi api = _api('https://x.test');
    addTearDown(api.close);
    expect((await api.retrieveOrder('o1'))['orderId'], 'o1');
  });
}
