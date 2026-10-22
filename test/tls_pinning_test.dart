// CONTRACT §16.15: certificate pinning of the SDK's own HTTP client. Every
// section of test/vectors/tls_pins.json is asserted here: the hosts and the
// trust anchors are the vector's, the anchors are the pinned roots, the
// current chain of api.payriff.com passes and an interception proxy's chain
// does not (pure checks on the parsed certificates, without validity dates).
// The pinned client then refuses a real TLS server on the loopback interface
// whose throwaway TEST certificate it does not trust. No Payriff API and no
// external network is involved; this file has no widget tests, so the
// flutter_test binding's HTTP mock is not installed.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:payriff/payriff.dart';
import 'package:payriff/src/internal/card/card_clock.dart';
import 'package:payriff/src/internal/card/client_api.dart';
import 'package:payriff/src/internal/card/tls_pins.dart';

import 'support/card_support.dart';
import 'support/test_certificates.dart';
import 'support/x509.dart';

final Map<String, Object?> _vector =
    jsonDecode(File('test/vectors/tls_pins.json').readAsStringSync())
        as Map<String, Object?>;

List<Map<String, Object?>> _list(String key) =>
    (_vector[key]! as List<Object?>).cast<Map<String, Object?>>();

List<Certificate> _chain(String key) =>
    ((_vector[key]! as Map<String, Object?>)['pems']! as List<Object?>)
        .cast<String>()
        .map(Certificate.fromPem)
        .toList();

final List<Certificate> _anchors = payriffTrustAnchors
    .map((({String name, String pem}) a) => Certificate.fromPem(a.pem))
    .toList();

final Set<String> _pins = _list(
  'pins',
).map((Map<String, Object?> p) => p['spkiSha256']! as String).toSet();

/// HttpOverrides that create real clients.
final class _RealHttp extends HttpOverrides {}

/// An app-wide override that accepts every certificate, as some apps set
/// for a debugging proxy.
final class _AcceptAnyCertificate extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..badCertificateCallback = (X509Certificate c, String h, int p) => true;
}

Future<PayriffError> _errorOf(Future<Object?> call) async {
  try {
    await call;
  } on PayriffException catch (e) {
    return e.error;
  }
  fail('expected a PayriffException');
}

void _expectPinningFailure(PayriffError error) {
  expect(error.code, PayriffErrorCode.networkError);
  expect(error.isRetryable, isFalse);
  expect(error.isFatal, isFalse);
  expect(error.message, "Payriff's server certificate could not be verified.");
  expect(error.httpStatus, isNull);
}

void main() {
  group('tls_pins.json', () {
    test('the hosts and the trust anchors are the vector, in order', () {
      expect(payriffPinnedHosts, _vector['hosts']);
      expect(<String>[
        for (final PayriffEnvironment e in PayriffEnvironment.values)
          Uri.parse(clientApiBaseUrl(e)).host,
      ], payriffPinnedHosts);
      expect(
        payriffTrustAnchors
            .map(
              (({String name, String pem}) a) => <String, Object?>{
                'name': a.name,
                'pem': a.pem,
              },
            )
            .toList(),
        _list('trustAnchors'),
      );
    });

    test('every anchor is a pinned, self-signed root, and every pinned root '
        'has an anchor', () {
      expect(_pins, hasLength(_list('pins').length), reason: 'no duplicates');
      for (int i = 0; i < _anchors.length; i++) {
        final Certificate anchor = _anchors[i];
        final String name = payriffTrustAnchors[i].name;
        expect(anchor.isSelfIssued, isTrue, reason: name);
        expect(_pins, contains(anchor.pin), reason: name);
        final Map<String, Object?> pin = _list(
          'pins',
        ).firstWhere((Map<String, Object?> p) => p['spkiSha256'] == anchor.pin);
        expect(pin['name'], name);
      }
      // The pins that are not anchors are intermediates, which chain to one.
      final Set<String> anchorPins = _anchors
          .map((Certificate a) => a.pin)
          .toSet();
      expect(anchorPins, hasLength(_anchors.length));
      for (final Map<String, Object?> pin in _list('pins')) {
        if (anchorPins.contains(pin['spkiSha256'])) continue;
        expect(pin['role'], contains('intermediate'), reason: '${pin['name']}');
      }
    });

    test('the anchors contain the issuer of the current chain, by subject '
        'and key', () {
      final List<Certificate> chain = _chain('currentChain');
      final Certificate leaf = chain[0];
      final Certificate intermediate = chain[1];
      expect(leaf.isIssuedBy(intermediate), isTrue);
      // The intermediate (Sectigo DV R36) is pinned and issued by Root R46,
      // an anchor; the chain also carries R46 cross-signed by USERTrust RSA,
      // with R46's subject and key.
      expect(_pins, contains(intermediate.pin));
      final Certificate r46 = _anchors.singleWhere(
        (Certificate a) => listEquals(a.subject, intermediate.issuer),
      );
      expect(intermediate.isIssuedBy(r46), isTrue);
      expect(chain.where((Certificate c) => c.sameCa(r46)), hasLength(1));
      // The last certificate is USERTrust RSA itself, also an anchor.
      expect(
        _anchors.where((Certificate a) => a.sameCa(chain.last)),
        hasLength(1),
      );
    });

    test('the pin check accepts the current chain', () {
      final List<Certificate> chain = _chain('currentChain');
      // CONTRACT §16.15: a certificate of the chain has a pinned key ...
      expect(chain.where((Certificate c) => _pins.contains(c.pin)), isNotEmpty);
      // ... and Flutter's anchors end the path from the leaf.
      expect(chainEndsAtAnchor(chain, _anchors), isTrue);
      // Without the anchors that it chains to, it fails.
      expect(
        chainEndsAtAnchor(
          chain,
          _anchors
              .where(
                (Certificate a) => !chain.any(
                  (Certificate c) =>
                      c.sameCa(a) || listEquals(c.issuer, a.subject),
                ),
              )
              .toList(),
        ),
        isFalse,
      );
    });

    test('the pin check refuses an interception proxy\'s chain', () {
      final List<Certificate> chain = _chain('interceptedChain');
      // A valid chain in itself: the test CA signed the leaf ...
      expect(chain[0].isIssuedBy(chain[1]), isTrue);
      // ... but no key in it is pinned, and it ends at no anchor.
      expect(chain.where((Certificate c) => _pins.contains(c.pin)), isEmpty);
      expect(chainEndsAtAnchor(chain, _anchors), isFalse);
    });

    test('every anchor loads into a security context', () {
      expect(payriffTrustAnchors, hasLength(13));
      for (final ({String name, String pem}) anchor in payriffTrustAnchors) {
        expect(
          () => SecurityContext().setTrustedCertificatesBytes(
            utf8.encode(anchor.pem),
          ),
          returnsNormally,
          reason: anchor.name,
        );
      }
      expect(payriffSecurityContext, isA<SecurityContext>());
    });
  });

  group('a pinning failure', () {
    final FakeCardClock clock = FakeCardClock();
    tearDown(() => debugPayriffClientApiHttpClient = null);

    for (final Exception tls in <Exception>[
      const HandshakeException('CERTIFICATE_VERIFY_FAILED'),
      const CertificateException('bad certificate'),
      const TlsException('alert'),
    ]) {
      test('is NETWORK_ERROR, not retryable: ${tls.runtimeType}', () async {
        int sent = 0;
        debugPayriffClientApiHttpClient = () => MockClient((_) async {
          sent++;
          throw tls;
        });
        final ClientApi api = testClientApi(clock);
        addTearDown(api.close);
        _expectPinningFailure(await _errorOf(api.retrieveOrder('o1')));
        expect(sent, 1);
      });
    }

    test('/pay is not retried after it, unlike a request without an '
        'answer', () async {
      final List<String> attempts = <String>[];
      Object failure = const HandshakeException('CERTIFICATE_VERIFY_FAILED');
      debugPayriffClientApiHttpClient = () =>
          MockClient((http.Request request) async {
            attempts.add(request.url.path);
            throw failure;
          });
      final ClientApi api = testClientApi(clock);
      addTearDown(api.close);
      _expectPinningFailure(await _errorOf(api.pay('o1', testPayRequest())));
      expect(attempts, hasLength(1));

      attempts.clear();
      failure = http.ClientException('offline');
      final PayriffError offline = await _errorOf(
        api.pay('o1', testPayRequest()),
      );
      expect(offline.code, PayriffErrorCode.networkError);
      expect(offline.isRetryable, isTrue);
      expect(attempts, hasLength(2));
    });
  });

  group('the pinned client against a local TLS server', () {
    late TestCertificates certificates;
    late HttpServer server;
    late List<String> served;

    setUpAll(() => certificates = TestCertificates.create());

    setUp(() async {
      served = <String>[];
      final SecurityContext serverContext = SecurityContext()
        ..useCertificateChainBytes(utf8.encode(certificates.serverChainPem))
        ..usePrivateKeyBytes(utf8.encode(certificates.serverKeyPem));
      server = await HttpOverrides.runWithHttpOverrides(
        () => HttpServer.bindSecure(
          InternetAddress.loopbackIPv4,
          0,
          serverContext,
        ),
        _RealHttp(),
      );
      server.listen(
        (HttpRequest request) async {
          served.add(request.uri.path);
          await request.drain<void>();
          request.response
            ..headers.contentType = ContentType.json
            ..write('{"code":"00000","payload":{"orderId":"o1"}}');
          await request.response.close();
        },
        // Failed handshakes end here; the test asserts on the client.
        onError: (Object _) {},
      );
      addTearDown(() => server.close(force: true));
    });

    String base() => 'https://localhost:${server.port}';

    ClientApi api() => ClientApi(
      baseUrl: base(),
      publishableKey: testPublishableKey,
      clientSecret: testClientSecret,
      appId: testAppId,
      clock: const SystemCardClock(),
    );

    test('a client that trusts the TEST CA gets an answer', () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final HttpClient trusting = HttpClient(
          context: SecurityContext()
            ..setTrustedCertificatesBytes(utf8.encode(certificates.caPem)),
        );
        addTearDown(trusting.close);
        final HttpClientResponse response = await (await trusting.getUrl(
          Uri.parse('${base()}/api/v3/client/orders/o1'),
        )).close();
        expect(response.statusCode, 200);
        await response.drain<void>();
      }, _RealHttp());
      expect(served, <String>['/api/v3/client/orders/o1']);
    });

    test('the Client API refuses it before sending anything', () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final ClientApi client = api();
        addTearDown(client.close);
        _expectPinningFailure(await _errorOf(client.retrieveOrder('o1')));
        _expectPinningFailure(
          await _errorOf(client.pay('o1', testPayRequest())),
        );
      }, _RealHttp());
      expect(served, isEmpty);
    });

    test('an app-wide override that accepts every certificate does not turn '
        'pinning off', () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        // The override really accepts the server for an ordinary client ...
        final HttpClient ordinary = HttpClient();
        addTearDown(ordinary.close);
        final HttpClientResponse response = await (await ordinary.getUrl(
          Uri.parse('${base()}/ordinary'),
        )).close();
        expect(response.statusCode, 200);
        await response.drain<void>();
        // ... but not for the SDK's.
        final ClientApi client = api();
        addTearDown(client.close);
        _expectPinningFailure(await _errorOf(client.status('o1')));
      }, _AcceptAnyCertificate());
      expect(served, <String>['/ordinary']);
    });
  });
}
