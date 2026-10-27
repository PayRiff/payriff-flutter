// TEST ONLY. A throwaway certificate authority and a server certificate for
// localhost, made at test time with fresh P-256 keys that never leave
// memory, so the pinning tests can run a real TLS server on the loopback
// interface without a key in the repository. Nothing here is secure: the
// nonces come from Random.secure(), but the code is written for clarity, not
// for side channels.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

/// A TEST CA and a localhost server certificate it signed, valid from an
/// hour ago for one day (Apple refuses server certificates valid for more
/// than 825 days).
final class TestCertificates {
  TestCertificates._(
    this.caPem,
    this.serverPem,
    this.serverKeyPem, {
    String? intermediatesPem,
  }) : serverChainPem = '$serverPem${intermediatesPem ?? caPem}';

  /// Makes new keys and certificates.
  factory TestCertificates.create() {
    final (DateTime from, DateTime to) = _validity();
    final _KeyPair ca = _KeyPair.generate();
    final _KeyPair server = _KeyPair.generate();
    final List<int> caName = _name('Payriff SDK TEST CA');
    return TestCertificates._(
      _pem('CERTIFICATE', _caCertificate(caName, ca, caName, ca, from, to)),
      _pem('CERTIFICATE', _serverCertificate(caName, ca, server, from, to)),
      _pem('PRIVATE KEY', server.pkcs8()),
    );
  }

  /// A chain shaped like api.gccpay.sa's (CONTRACT §16.15): the server
  /// certificate is issued by an intermediate of a TEST root, and the server
  /// sends that root cross-signed by a second TEST root, which nobody
  /// trusts. [caPem] is the self-signed first root, so a client that trusts
  /// only it must end the path there.
  factory TestCertificates.crossSigned() {
    final (DateTime from, DateTime to) = _validity();
    final _KeyPair root = _KeyPair.generate();
    final _KeyPair otherRoot = _KeyPair.generate();
    final _KeyPair intermediate = _KeyPair.generate();
    final _KeyPair server = _KeyPair.generate();
    final List<int> rootName = _name('Payriff SDK TEST Root');
    final List<int> otherRootName = _name('Payriff SDK TEST Other Root');
    final List<int> intermediateName = _name('Payriff SDK TEST Intermediate');
    return TestCertificates._(
      _pem(
        'CERTIFICATE',
        _caCertificate(rootName, root, rootName, root, from, to),
      ),
      _pem(
        'CERTIFICATE',
        _serverCertificate(intermediateName, intermediate, server, from, to),
      ),
      _pem('PRIVATE KEY', server.pkcs8()),
      intermediatesPem:
          _pem(
            'CERTIFICATE',
            _caCertificate(
              rootName,
              root,
              intermediateName,
              intermediate,
              from,
              to,
            ),
          ) +
          _pem(
            'CERTIFICATE',
            _caCertificate(otherRootName, otherRoot, rootName, root, from, to),
          ),
    );
  }

  /// The TEST CA's certificate: the root a client trusts.
  final String caPem;

  /// The server certificate for `localhost` and `127.0.0.1`.
  final String serverPem;

  /// The server's private key, PKCS #8.
  final String serverKeyPem;

  /// What the server sends: its certificate, then the CA (or the
  /// intermediate and the cross-signed root).
  final String serverChainPem;
}

(DateTime, DateTime) _validity() {
  final DateTime now = DateTime.now().toUtc();
  return (
    now.subtract(const Duration(hours: 1)),
    now.add(const Duration(days: 1)),
  );
}

/// A CA certificate for [subject] and [subjectKey], signed by [issuerKey].
Uint8List _caCertificate(
  List<int> issuer,
  _KeyPair issuerKey,
  List<int> subject,
  _KeyPair subjectKey,
  DateTime from,
  DateTime to,
) => _certificate(
  issuer: issuer,
  issuerKey: issuerKey,
  subject: subject,
  subjectKey: subjectKey,
  from: from,
  to: to,
  extensions: <List<int>>[
    // basicConstraints, critical: CA.
    _extension(_oidBasicConstraints, _sequence(<List<int>>[_true])),
    // keyUsage, critical: keyCertSign and cRLSign.
    _extension(_oidKeyUsage, _tlv(0x03, <int>[0x01, 0x06])),
  ],
);

/// A server certificate for `localhost` and `127.0.0.1`.
Uint8List _serverCertificate(
  List<int> issuer,
  _KeyPair issuerKey,
  _KeyPair serverKey,
  DateTime from,
  DateTime to,
) => _certificate(
  issuer: issuer,
  issuerKey: issuerKey,
  subject: _name('localhost'),
  subjectKey: serverKey,
  from: from,
  to: to,
  extensions: <List<int>>[
    _extension(_oidBasicConstraints, _sequence(const <List<int>>[])),
    // keyUsage, critical: digitalSignature.
    _extension(_oidKeyUsage, _tlv(0x03, <int>[0x07, 0x80])),
    // extKeyUsage: serverAuth.
    _extension(
      _oidExtKeyUsage,
      _sequence(<List<int>>[_tlv(0x06, _oidServerAuth)]),
      critical: false,
    ),
    // subjectAltName: DNS localhost, IP 127.0.0.1.
    _extension(
      _oidSubjectAltName,
      _sequence(<List<int>>[
        _tlv(0x82, ascii.encode('localhost')),
        _tlv(0x87, <int>[127, 0, 0, 1]),
      ]),
      critical: false,
    ),
  ],
);

// ---------------------------------------------------------------------------
// P-256 and ECDSA with SHA-256

final BigInt _p = BigInt.parse(
  'ffffffff00000001000000000000000000000000ffffffffffffffffffffffff',
  radix: 16,
);
final BigInt _n = BigInt.parse(
  'ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551',
  radix: 16,
);
final _Point _g = (
  x: BigInt.parse(
    '6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296',
    radix: 16,
  ),
  y: BigInt.parse(
    '4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5',
    radix: 16,
  ),
);

/// An affine point; `null` is the point at infinity.
typedef _Point = ({BigInt x, BigInt y});

_Point? _add(_Point? a, _Point? b) {
  if (a == null) return b;
  if (b == null) return a;
  final BigInt slope;
  if (a.x == b.x) {
    if ((a.y + b.y) % _p == BigInt.zero) return null;
    // Doubling; the curve's a is -3.
    slope =
        ((BigInt.from(3) * a.x * a.x - BigInt.from(3)) % _p) *
        ((BigInt.two * a.y) % _p).modInverse(_p) %
        _p;
  } else {
    slope = ((b.y - a.y) % _p) * ((b.x - a.x) % _p).modInverse(_p) % _p;
  }
  final BigInt x = (slope * slope - a.x - b.x) % _p;
  return (x: x, y: (slope * (a.x - x) - a.y) % _p);
}

_Point? _multiply(BigInt k, _Point point) {
  _Point? result;
  _Point? addend = point;
  for (BigInt rest = k; rest > BigInt.zero; rest >>= 1) {
    if (rest.isOdd) result = _add(result, addend);
    addend = _add(addend, addend);
  }
  return result;
}

final Random _random = Random.secure();

/// A uniform scalar in [1, n - 1].
BigInt _scalar() {
  while (true) {
    final BigInt k = _unsigned(
      List<int>.generate(32, (_) => _random.nextInt(256)),
    );
    if (k > BigInt.zero && k < _n) return k;
  }
}

BigInt _unsigned(List<int> bytes) =>
    bytes.fold(BigInt.zero, (BigInt n, int b) => (n << 8) | BigInt.from(b));

List<int> _fixed(BigInt value, int length) {
  final List<int> out = List<int>.filled(length, 0);
  BigInt rest = value;
  for (int i = length - 1; i >= 0; i--) {
    out[i] = (rest & BigInt.from(0xff)).toInt();
    rest >>= 8;
  }
  return out;
}

final class _KeyPair {
  _KeyPair._(this.secret, this.public);

  factory _KeyPair.generate() {
    final BigInt secret = _scalar();
    return _KeyPair._(secret, _multiply(secret, _g)!);
  }

  final BigInt secret;
  final _Point public;

  /// The uncompressed public point: 04 || X || Y.
  List<int> get point => <int>[
    0x04,
    ..._fixed(public.x, 32),
    ..._fixed(public.y, 32),
  ];

  /// SubjectPublicKeyInfo.
  List<int> spki() => _sequence(<List<int>>[_ecAlgorithm, _bitString(point)]);

  /// ECDSA over SHA-256 of [message]: the DER `ECDSA-Sig-Value`.
  List<int> sign(List<int> message) {
    final BigInt z = _unsigned(crypto.sha256.convert(message).bytes);
    while (true) {
      final BigInt k = _scalar();
      final BigInt r = _multiply(k, _g)!.x % _n;
      if (r == BigInt.zero) continue;
      final BigInt s = k.modInverse(_n) * (z + r * secret) % _n;
      if (s == BigInt.zero) continue;
      return _sequence(<List<int>>[_integer(r), _integer(s)]);
    }
  }

  /// PrivateKeyInfo (PKCS #8) with an ECPrivateKey that includes the point.
  List<int> pkcs8() => _sequence(<List<int>>[
    _integer(BigInt.zero),
    _ecAlgorithm,
    _tlv(
      0x04,
      _sequence(<List<int>>[
        _integer(BigInt.one),
        _tlv(0x04, _fixed(secret, 32)),
        _tlv(0xa1, _bitString(point)),
      ]),
    ),
  ]);
}

// ---------------------------------------------------------------------------
// DER

const List<int> _oidEcPublicKey = <int>[0x2a, 0x86, 0x48, 0xce, 0x3d, 2, 1];
const List<int> _oidP256 = <int>[0x2a, 0x86, 0x48, 0xce, 0x3d, 3, 1, 7];
const List<int> _oidEcdsaSha256 = <int>[0x2a, 0x86, 0x48, 0xce, 0x3d, 4, 3, 2];
const List<int> _oidCommonName = <int>[0x55, 0x04, 0x03];
const List<int> _oidOrganization = <int>[0x55, 0x04, 0x0a];
const List<int> _oidBasicConstraints = <int>[0x55, 0x1d, 0x13];
const List<int> _oidKeyUsage = <int>[0x55, 0x1d, 0x0f];
const List<int> _oidExtKeyUsage = <int>[0x55, 0x1d, 0x25];
const List<int> _oidSubjectAltName = <int>[0x55, 0x1d, 0x11];
const List<int> _oidServerAuth = <int>[0x2b, 6, 1, 5, 5, 7, 3, 1];

const List<int> _true = <int>[0x01, 0x01, 0xff];

final List<int> _ecAlgorithm = _sequence(<List<int>>[
  _tlv(0x06, _oidEcPublicKey),
  _tlv(0x06, _oidP256),
]);

final List<int> _ecdsaSha256 = _sequence(<List<int>>[
  _tlv(0x06, _oidEcdsaSha256),
]);

Uint8List _tlv(int tag, List<int> content) {
  final int length = content.length;
  return Uint8List.fromList(<int>[
    tag,
    if (length < 0x80)
      length
    else if (length < 0x100) ...<int>[0x81, length] else ...<int>[
      0x82,
      length >> 8,
      length & 0xff,
    ],
    ...content,
  ]);
}

Uint8List _sequence(List<List<int>> items) =>
    _tlv(0x30, <int>[for (final List<int> item in items) ...item]);

Uint8List _integer(BigInt value) {
  final List<int> bytes = value == BigInt.zero
      ? <int>[0]
      : _fixed(value, (value.bitLength + 7) >> 3);
  return _tlv(0x02, <int>[if (bytes.first & 0x80 != 0) 0, ...bytes]);
}

Uint8List _bitString(List<int> bytes) => _tlv(0x03, <int>[0, ...bytes]);

Uint8List _time(DateTime time) {
  String two(int v) => v.toString().padLeft(2, '0');
  return _tlv(
    0x17,
    ascii.encode(
      '${two(time.year % 100)}${two(time.month)}${two(time.day)}'
      '${two(time.hour)}${two(time.minute)}${two(time.second)}Z',
    ),
  );
}

List<int> _name(String commonName) => _sequence(<List<int>>[
  _tlv(
    0x31,
    _sequence(<List<int>>[
      _tlv(0x06, _oidOrganization),
      _tlv(0x0c, utf8.encode('Payriff SDK TEST')),
    ]),
  ),
  _tlv(
    0x31,
    _sequence(<List<int>>[
      _tlv(0x06, _oidCommonName),
      _tlv(0x0c, utf8.encode(commonName)),
    ]),
  ),
]);

List<int> _extension(List<int> oid, List<int> value, {bool critical = true}) =>
    _sequence(<List<int>>[
      _tlv(0x06, oid),
      if (critical) _true,
      _tlv(0x04, value),
    ]);

Uint8List _certificate({
  required List<int> issuer,
  required _KeyPair issuerKey,
  required List<int> subject,
  required _KeyPair subjectKey,
  required DateTime from,
  required DateTime to,
  required List<List<int>> extensions,
}) {
  final List<int> tbs = _sequence(<List<int>>[
    _tlv(0xa0, _integer(BigInt.two)), // v3
    _integer(_unsigned(List<int>.generate(12, (_) => _random.nextInt(256)))),
    _ecdsaSha256,
    issuer,
    _sequence(<List<int>>[_time(from), _time(to)]),
    subject,
    subjectKey.spki(),
    _tlv(0xa3, _sequence(extensions)),
  ]);
  return _sequence(<List<int>>[
    tbs,
    _ecdsaSha256,
    _bitString(issuerKey.sign(tbs)),
  ]);
}

String _pem(String label, List<int> der) {
  final String body = base64.encode(der);
  final StringBuffer out = StringBuffer('-----BEGIN $label-----\n');
  for (int i = 0; i < body.length; i += 64) {
    out
      ..write(body.substring(i, min(i + 64, body.length)))
      ..write('\n');
  }
  out.write('-----END $label-----\n');
  return out.toString();
}
