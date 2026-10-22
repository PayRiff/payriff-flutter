// Just enough X.509 for the pinning tests (CONTRACT §16.15): PEM and DER,
// the names and key of a certificate, its SubjectPublicKeyInfo SHA-256 and
// RSA signature checks. Validity dates are never read.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart' show listEquals;

/// One DER element: its tag, the whole encoding and the content.
final class Der {
  Der._(this.tag, this.encoded, this.content);

  /// Reads the element at [offset] of [data].
  factory Der.read(Uint8List data, [int offset = 0]) {
    final int tag = data[offset];
    int length = data[offset + 1];
    int header = 2;
    if (length & 0x80 != 0) {
      final int count = length & 0x7f;
      length = 0;
      for (int i = 0; i < count; i++) {
        length = (length << 8) | data[offset + 2 + i];
      }
      header += count;
    }
    final int end = offset + header + length;
    if (end > data.length) throw const FormatException('truncated DER');
    return Der._(
      tag,
      Uint8List.sublistView(data, offset, end),
      Uint8List.sublistView(data, offset + header, end),
    );
  }

  final int tag;
  final Uint8List encoded;
  final Uint8List content;

  /// The elements inside a SEQUENCE, SET or explicit tag.
  List<Der> get children {
    final List<Der> items = <Der>[];
    int offset = 0;
    while (offset < content.length) {
      final Der item = Der.read(content, offset);
      items.add(item);
      offset += item.encoded.length;
    }
    return items;
  }
}

/// The DER of the first certificate in [pem].
Uint8List pemToDer(String pem) {
  final String body = pem
      .split('\n')
      .where((String line) => line.isNotEmpty && !line.startsWith('-----'))
      .join();
  return base64.decode(body);
}

/// The base64 SHA-256 of [bytes], the form of `tls_pins.json` → `pins`.
String sha256Base64(List<int> bytes) =>
    base64.encode(crypto.sha256.convert(bytes).bytes);

/// The fields of a certificate that chain building needs.
final class Certificate {
  Certificate._(this.tbs, this.signatureAlgorithm, this.signature)
    : _fields = Der.read(tbs).children;

  /// Parses a PEM certificate.
  factory Certificate.fromPem(String pem) {
    final List<Der> parts = Der.read(pemToDer(pem)).children;
    return Certificate._(
      parts[0].encoded,
      parts[1].children.first.content,
      // A BIT STRING: the first byte counts unused bits (always 0 here).
      Uint8List.sublistView(parts[2].content, 1),
    );
  }

  /// The signed part, `tbsCertificate`.
  final Uint8List tbs;

  /// The encoded OID of the signature algorithm.
  final Uint8List signatureAlgorithm;

  /// The signature over [tbs].
  final Uint8List signature;

  final List<Der> _fields;

  // version [0] is optional; it is present in every certificate here.
  int get _base => _fields.first.tag == 0xa0 ? 1 : 0;

  /// The issuer Name, DER.
  Uint8List get issuer => _fields[_base + 2].encoded;

  /// The subject Name, DER.
  Uint8List get subject => _fields[_base + 4].encoded;

  /// The SubjectPublicKeyInfo, DER.
  Uint8List get spki => _fields[_base + 5].encoded;

  /// The base64 SHA-256 of [spki]: the certificate's pin.
  String get pin => sha256Base64(spki);

  /// Whether the subject equals the issuer.
  bool get isSelfIssued => listEquals(subject, issuer);

  /// Whether [other] has this certificate's subject and key: the same CA.
  bool sameCa(Certificate other) =>
      listEquals(subject, other.subject) && listEquals(spki, other.spki);

  /// Whether [issuerCertificate] names and signed this certificate. RSA
  /// signatures (PKCS #1 v1.5, SHA-256/384/512) are checked; any other kind
  /// counts as not verified.
  bool isIssuedBy(Certificate issuerCertificate) =>
      listEquals(issuer, issuerCertificate.subject) &&
      rsaSignatureVerifies(
        issuerCertificate.spki,
        tbs,
        signature,
        signatureAlgorithm,
      );
}

// sha256/384/512WithRSAEncryption: 1.2.840.113549.1.1.11 to .13.
const List<int> _rsaWithSha = <int>[
  0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, //
];

/// PKCS #1 v1.5 verification of [signature] over [message] with the RSA key
/// in [spki]. `false` for keys and algorithms other than RSA with SHA-2.
bool rsaSignatureVerifies(
  Uint8List spki,
  Uint8List message,
  Uint8List signature,
  Uint8List algorithm,
) {
  if (algorithm.length != _rsaWithSha.length + 1 ||
      !listEquals(algorithm.sublist(0, _rsaWithSha.length), _rsaWithSha)) {
    return false;
  }
  final (crypto.Hash, List<int>)? hash = switch (algorithm.last) {
    0x0b => (crypto.sha256, const <int>[0x01, 0x05, 0x00, 0x04, 0x20]),
    0x0c => (crypto.sha384, const <int>[0x02, 0x05, 0x00, 0x04, 0x30]),
    0x0d => (crypto.sha512, const <int>[0x03, 0x05, 0x00, 0x04, 0x40]),
    _ => null,
  };
  if (hash == null) return false;
  final List<Der> key = Der.read(spki).children;
  // rsaEncryption: 1.2.840.113549.1.1.1
  if (!listEquals(key[0].children.first.content, <int>[..._rsaWithSha, 0x01])) {
    return false;
  }
  final List<Der> numbers = Der.read(
    Uint8List.sublistView(key[1].content, 1),
  ).children;
  final BigInt modulus = _unsigned(numbers[0].content);
  final BigInt exponent = _unsigned(numbers[1].content);
  final int size = (modulus.bitLength + 7) >> 3;
  final BigInt decoded = _unsigned(signature).modPow(exponent, modulus);
  final List<int> digest = hash.$1.convert(message).bytes;
  // DigestInfo: SEQUENCE { AlgorithmIdentifier { sha2 OID, NULL }, OCTET
  // STRING }; the AlgorithmIdentifier takes 15 bytes, the digest's header 2.
  final List<int> digestInfo = <int>[
    0x30, 15 + 2 + digest.length, 0x30, 0x0d, 0x06, 0x09, //
    0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, //
    ...hash.$2,
    ...digest,
  ];
  final List<int> expected = <int>[
    0x00,
    0x01,
    ...List<int>.filled(size - 3 - digestInfo.length, 0xff),
    0x00,
    ...digestInfo,
  ];
  return listEquals(_bytes(decoded, size), expected);
}

BigInt _unsigned(List<int> bytes) =>
    bytes.fold(BigInt.zero, (BigInt n, int b) => (n << 8) | BigInt.from(b));

List<int> _bytes(BigInt value, int length) {
  final List<int> out = List<int>.filled(length, 0);
  BigInt rest = value;
  for (int i = length - 1; i >= 0 && rest > BigInt.zero; i--) {
    out[i] = (rest & BigInt.from(0xff)).toInt();
    rest >>= 8;
  }
  return out;
}

/// Flutter's pin check on parsed certificates (CONTRACT §16.15): whether a
/// TLS stack that trusts only [anchors] can build a path from the leaf of
/// [chain] (first) to one of them, following issuer names and signatures.
/// Validity dates are ignored.
bool chainEndsAtAnchor(List<Certificate> chain, List<Certificate> anchors) {
  Certificate current = chain.first;
  for (int step = 0; step <= chain.length; step++) {
    if (anchors.any(
      (Certificate a) => a.sameCa(current) || current.isIssuedBy(a),
    )) {
      return true;
    }
    final Iterable<Certificate> parents = chain.where(
      (Certificate c) => !identical(c, current) && current.isIssuedBy(c),
    );
    if (parents.isEmpty) return false;
    current = parents.first;
  }
  return false;
}
