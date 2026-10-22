import CryptoKit
import Foundation
import Security

/// Every failure of ``PayriffCardCrypto``. Cases carry no data, so nothing from the input can leak.
enum PayriffCardCryptoError: Error {
  case invalidInput
  case invalidKey
  case randomUnavailable
  case encryptionFailed
}

/// The two Base64 inputs of `/pay`, as raw bytes.
struct PayriffCardCiphertext: CustomStringConvertible, CustomDebugStringConvertible {
  /// AES-256-GCM ciphertext followed by the 16-byte tag (no IV prefix).
  let encryptedMessage: Data
  /// RSA-OAEP-SHA256 (MGF1-SHA256, empty label) of `aesKey || iv`.
  let wrappedKey: Data

  var description: String { "PayriffCardCiphertext(<redacted>)" }
  var debugDescription: String { description }
}

/// CONTRACT §16.6 card encryption (vectors: `test/vectors/card_crypto.json`).
///
/// Foundation, CryptoKit and Security only (no UIKit or Flutter), so it also compiles with
/// plain `swiftc` for tests. Nothing here logs.
enum PayriffCardCrypto {
  static let keyLength = 32
  static let ivLength = 12
  static let minimumRSABits = 2048

  /// Encrypts `card` with a fresh key and IV from the system CSPRNG. Both are zeroed afterwards.
  static func encrypt(card: Data, spki: Data) throws -> PayriffCardCiphertext {
    var aesKey = [UInt8](repeating: 0, count: keyLength)
    var iv = [UInt8](repeating: 0, count: ivLength)
    defer {
      wipe(&aesKey)
      wipe(&iv)
    }
    guard SecRandomCopyBytes(kSecRandomDefault, aesKey.count, &aesKey) == errSecSuccess,
      SecRandomCopyBytes(kSecRandomDefault, iv.count, &iv) == errSecSuccess
    else {
      throw PayriffCardCryptoError.randomUnavailable
    }
    return try encrypt(card: card, spki: spki, aesKey: aesKey, iv: iv)
  }

  /// Deterministic core with an injected key and IV (tests only pass fixed values).
  /// The caller owns and zeroes `aesKey` and `iv`; the `aesKey || iv` buffer built here is
  /// zeroed before returning.
  static func encrypt(card: Data, spki: Data, aesKey: [UInt8], iv: [UInt8]) throws
    -> PayriffCardCiphertext
  {
    guard !card.isEmpty, aesKey.count == keyLength, iv.count == ivLength else {
      throw PayriffCardCryptoError.invalidInput
    }
    let publicKey = try rsaPublicKey(spki: spki)

    let encryptedMessage: Data
    do {
      let sealed = try AES.GCM.seal(
        card, using: SymmetricKey(data: aesKey), nonce: AES.GCM.Nonce(data: iv))
      var combined = Data(capacity: card.count + 16)
      combined.append(sealed.ciphertext)
      combined.append(sealed.tag)
      encryptedMessage = combined
    } catch {
      throw PayriffCardCryptoError.encryptionFailed
    }

    // aesKey || iv lives in one CF buffer that this function zeroes itself.
    let total = keyLength + ivLength
    guard let keyIv = CFDataCreateMutable(kCFAllocatorDefault, total) else {
      throw PayriffCardCryptoError.encryptionFailed
    }
    CFDataSetLength(keyIv, total)
    guard let keyIvBytes = CFDataGetMutableBytePtr(keyIv) else {
      throw PayriffCardCryptoError.encryptionFailed
    }
    defer { _ = memset_s(keyIvBytes, total, 0, total) }
    aesKey.withUnsafeBufferPointer { keyIvBytes.update(from: $0.baseAddress!, count: keyLength) }
    iv.withUnsafeBufferPointer {
      (keyIvBytes + keyLength).update(from: $0.baseAddress!, count: ivLength)
    }

    var error: Unmanaged<CFError>?
    guard
      let wrapped = SecKeyCreateEncryptedData(
        publicKey, .rsaEncryptionOAEPSHA256, keyIv, &error) as Data?
    else {
      error?.release()
      throw PayriffCardCryptoError.encryptionFailed
    }
    return PayriffCardCiphertext(encryptedMessage: encryptedMessage, wrappedKey: wrapped)
  }

  /// Parses a DER SubjectPublicKeyInfo. Only rsaEncryption keys of at least 2048 bits that
  /// support OAEP-SHA256 are accepted.
  static func rsaPublicKey(spki: Data) throws -> SecKey {
    let bytes = [UInt8](spki)
    do {
      // SubjectPublicKeyInfo ::= SEQUENCE { algorithm AlgorithmIdentifier, subjectPublicKey BIT STRING }
      let info = try PayriffDER.element(bytes, at: 0, tag: 0x30)
      guard info.end == bytes.count else { throw PayriffCardCryptoError.invalidKey }
      let algorithm = try PayriffDER.element(bytes, at: info.body.lowerBound, tag: 0x30)
      let oid = try PayriffDER.element(bytes, at: algorithm.body.lowerBound, tag: 0x06)
      guard Array(bytes[oid.body]) == PayriffDER.rsaEncryptionOID else {
        throw PayriffCardCryptoError.invalidKey
      }
      let bitString = try PayriffDER.element(bytes, at: algorithm.end, tag: 0x03)
      guard bitString.end == info.body.upperBound, bitString.body.count > 1,
        bytes[bitString.body.lowerBound] == 0
      else {
        throw PayriffCardCryptoError.invalidKey
      }
      let pkcs1 = Data(bytes[(bitString.body.lowerBound + 1)..<bitString.body.upperBound])
      let attributes: [CFString: Any] = [
        kSecAttrKeyType: kSecAttrKeyTypeRSA,
        kSecAttrKeyClass: kSecAttrKeyClassPublic,
      ]
      var error: Unmanaged<CFError>?
      guard let key = SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, &error)
      else {
        error?.release()
        throw PayriffCardCryptoError.invalidKey
      }
      guard SecKeyGetBlockSize(key) * 8 >= minimumRSABits,
        SecKeyIsAlgorithmSupported(key, .encrypt, .rsaEncryptionOAEPSHA256)
      else {
        throw PayriffCardCryptoError.invalidKey
      }
      return key
    } catch {
      throw PayriffCardCryptoError.invalidKey
    }
  }

  static func wipe(_ bytes: inout [UInt8]) {
    bytes.withUnsafeMutableBytes { raw in
      guard let base = raw.baseAddress else { return }
      _ = memset_s(base, raw.count, 0, raw.count)
    }
  }
}

/// Minimal DER reader for the key formats above (definite lengths only).
enum PayriffDER {
  /// 1.2.840.113549.1.1.1
  static let rsaEncryptionOID: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]

  /// Reads the element with `tag` starting at `offset`: its content range and the offset after it.
  static func element(_ bytes: [UInt8], at offset: Int, tag: UInt8) throws
    -> (body: Range<Int>, end: Int)
  {
    var index = offset
    guard index >= 0, index < bytes.count, bytes[index] == tag else {
      throw PayriffCardCryptoError.invalidKey
    }
    index += 1
    guard index < bytes.count else { throw PayriffCardCryptoError.invalidKey }
    var length = Int(bytes[index])
    index += 1
    if length & 0x80 != 0 {
      let count = length & 0x7F
      guard (1...3).contains(count), count <= bytes.count - index else {
        throw PayriffCardCryptoError.invalidKey
      }
      length = 0
      for _ in 0..<count {
        length = (length << 8) | Int(bytes[index])
        index += 1
      }
    }
    guard length <= bytes.count - index else { throw PayriffCardCryptoError.invalidKey }
    return (index..<(index + length), index + length)
  }
}
