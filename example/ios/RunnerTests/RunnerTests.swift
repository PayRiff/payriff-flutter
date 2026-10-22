import CryptoKit
import Flutter
import Security
import UIKit
import XCTest

@testable import payriff

/// Native tests of the payriff plugin: every case of `test/vectors/card_crypto.json`
/// (CONTRACT §16.6), the external-URL rules (§7.5) and the channel surface.
final class RunnerTests: XCTestCase {
  private static let vectors: [String: Any] = {
    // RunnerTests.swift sits in example/ios/RunnerTests; the vectors are in the package's test/.
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // RunnerTests
      .deletingLastPathComponent()  // ios
      .deletingLastPathComponent()  // example
      .deletingLastPathComponent()  // package root
      .appendingPathComponent("test/vectors/card_crypto.json")
    let data = try! Data(contentsOf: url)
    return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
  }()

  private func b64(_ key: String) -> Data {
    Data(base64Encoded: Self.vectors[key] as! String)!
  }

  private var aesKey: [UInt8] { [UInt8](b64("aesKey")) }
  private var iv: [UInt8] { [UInt8](b64("iv")) }
  private var keyIv: Data { b64("keyIv") }
  private var testSpki: Data { b64("testPublicKeySpki") }
  private var aesGcmCases: [[String: Any]] { Self.vectors["aesGcm"] as! [[String: Any]] }

  /// PKCS#8 PrivateKeyInfo -> PKCS#1 RSAPrivateKey -> SecKey.
  private func testPrivateKey() throws -> SecKey {
    let der = [UInt8](b64("testPrivateKeyPkcs8"))
    let info = try PayriffDER.element(der, at: 0, tag: 0x30)
    let version = try PayriffDER.element(der, at: info.body.lowerBound, tag: 0x02)
    let algorithm = try PayriffDER.element(der, at: version.end, tag: 0x30)
    let octets = try PayriffDER.element(der, at: algorithm.end, tag: 0x04)
    let attributes: [CFString: Any] = [
      kSecAttrKeyType: kSecAttrKeyTypeRSA,
      kSecAttrKeyClass: kSecAttrKeyClassPrivate,
    ]
    var error: Unmanaged<CFError>?
    let key = SecKeyCreateWithData(
      Data(der[octets.body]) as CFData, attributes as CFDictionary, &error)
    return try XCTUnwrap(key, "test private key")
  }

  private func unwrap(_ secretKey: Data) throws -> Data {
    var error: Unmanaged<CFError>?
    let plain = SecKeyCreateDecryptedData(
      try testPrivateKey(), .rsaEncryptionOAEPSHA256, secretKey as CFData, &error)
    return try XCTUnwrap(plain as Data?, "OAEP-SHA256 unwrap")
  }

  private func gcmOpen(key: Data, iv: Data, sealed: Data) throws -> Data {
    let box = try AES.GCM.SealedBox(
      nonce: AES.GCM.Nonce(data: iv), ciphertext: sealed.dropLast(16), tag: sealed.suffix(16))
    return try AES.GCM.open(box, using: SymmetricKey(data: key))
  }

  func testVectorKeyAndIvAreConsistent() {
    XCTAssertEqual(aesKey.count, PayriffCardCrypto.keyLength)
    XCTAssertEqual(iv.count, PayriffCardCrypto.ivLength)
    XCTAssertEqual(Data(aesKey + iv), keyIv)
    XCTAssertGreaterThanOrEqual(aesGcmCases.count, 4)
  }

  func testVectorWrapDecryptsWithTestPrivateKey() throws {
    XCTAssertEqual(try unwrap(b64("rsaWrappedKeyIv")), keyIv)
  }

  func testEveryAesGcmCaseMatchesWithFixedKeyAndIv() throws {
    for (index, testCase) in aesGcmCases.enumerated() {
      let cardJson = Data((testCase["cardJson"] as! String).utf8)
      let output = try PayriffCardCrypto.encrypt(
        card: cardJson, spki: testSpki, aesKey: aesKey, iv: iv)
      XCTAssertEqual(
        output.encryptedMessage.base64EncodedString(), testCase["encryptedMessage"] as? String,
        "aesGcm[\(index)] encryptedMessage")
      XCTAssertEqual(output.encryptedMessage.count, cardJson.count + 16, "aesGcm[\(index)] length")
      XCTAssertEqual(try unwrap(output.wrappedKey), keyIv, "aesGcm[\(index)] wrappedKey")
      XCTAssertEqual(
        try gcmOpen(key: Data(aesKey), iv: Data(iv), sealed: output.encryptedMessage), cardJson,
        "aesGcm[\(index)] round trip")
    }
  }

  func testRandomKeyAndIvAreFreshAndRoundTrip() throws {
    let cardJson = Data((aesGcmCases[0]["cardJson"] as! String).utf8)
    let first = try PayriffCardCrypto.encrypt(card: cardJson, spki: testSpki)
    let second = try PayriffCardCrypto.encrypt(card: cardJson, spki: testSpki)
    let firstKeyIv = try unwrap(first.wrappedKey)
    let secondKeyIv = try unwrap(second.wrappedKey)
    XCTAssertEqual(firstKeyIv.count, PayriffCardCrypto.keyLength + PayriffCardCrypto.ivLength)
    XCTAssertNotEqual(firstKeyIv, secondKeyIv)
    XCTAssertNotEqual(first.encryptedMessage, second.encryptedMessage)
    for (output, unwrapped) in [(first, firstKeyIv), (second, secondKeyIv)] {
      let key = unwrapped.prefix(PayriffCardCrypto.keyLength)
      let nonce = unwrapped.suffix(PayriffCardCrypto.ivLength)
      XCTAssertEqual(
        try gcmOpen(key: Data(key), iv: Data(nonce), sealed: output.encryptedMessage), cardJson)
    }
  }

  func testOaepIsRandomizedAndUsesTheKeySize() throws {
    let one = try PayriffCardCrypto.encrypt(card: Data("{}".utf8), spki: testSpki, aesKey: aesKey, iv: iv)
    let two = try PayriffCardCrypto.encrypt(card: Data("{}".utf8), spki: testSpki, aesKey: aesKey, iv: iv)
    XCTAssertEqual(one.wrappedKey.count, 256)
    XCTAssertNotEqual(one.wrappedKey, two.wrappedKey)
    XCTAssertEqual(one.encryptedMessage, two.encryptedMessage)
  }

  func testPayriffProductionKeyParsesAndMatchesItsPin() throws {
    let spki = b64("payriffPublicKeySpki")
    let hash = SHA256.hash(data: spki).map { String(format: "%02x", $0) }.joined()
    XCTAssertEqual(hash, Self.vectors["payriffPublicKeySha256"] as? String)
    let output = try PayriffCardCrypto.encrypt(card: Data("{}".utf8), spki: spki)
    XCTAssertGreaterThanOrEqual(output.wrappedKey.count, 256)
  }

  func testRejectsBadInput() {
    let card = Data("{\"pan\":\"4111111111111111\"}".utf8)
    let pkcs8 = b64("testPrivateKeyPkcs8")
    let cases: [(String, () throws -> PayriffCardCiphertext)] = [
      ("empty card", { try PayriffCardCrypto.encrypt(card: Data(), spki: self.testSpki, aesKey: self.aesKey, iv: self.iv) }),
      ("short key", { try PayriffCardCrypto.encrypt(card: card, spki: self.testSpki, aesKey: [UInt8](repeating: 1, count: 16), iv: self.iv) }),
      ("long iv", { try PayriffCardCrypto.encrypt(card: card, spki: self.testSpki, aesKey: self.aesKey, iv: [UInt8](repeating: 1, count: 16)) }),
      ("garbage spki", { try PayriffCardCrypto.encrypt(card: card, spki: Data([1, 2, 3])) }),
      ("empty spki", { try PayriffCardCrypto.encrypt(card: card, spki: Data()) }),
      ("truncated spki", { try PayriffCardCrypto.encrypt(card: card, spki: self.testSpki.dropLast(10)) }),
      ("pkcs8 instead of spki", { try PayriffCardCrypto.encrypt(card: card, spki: pkcs8) }),
    ]
    for (name, block) in cases {
      XCTAssertThrowsError(try block(), name)
    }
  }

  func testCiphertextDescriptionIsRedacted() throws {
    let output = try PayriffCardCrypto.encrypt(card: Data("{}".utf8), spki: testSpki, aesKey: aesKey, iv: iv)
    XCTAssertEqual(String(describing: output), "PayriffCardCiphertext(<redacted>)")
    XCTAssertEqual(String(reflecting: output), "PayriffCardCiphertext(<redacted>)")
  }

  func testExternalUrlRules() {
    for url in [
      "file:///etc/hosts", "FILE:///x", "content://x/y", "javascript:alert(1)", "JavaScript:1",
      "data:text/html,x", "blob:https://pay.payriff.com/x", "about:blank", "", "no-scheme",
      "://x", "1abc:x", " https://x", "https://x\n", "bank://pay\u{0}",
    ] {
      XCTAssertFalse(PayriffExternalUrl.mayLaunch(url), url)
    }
    for url in ["https://bank.example/3ds", "http://bank.example/", "bankapp://pay?id=1", "tel:+994000000000"] {
      XCTAssertTrue(PayriffExternalUrl.mayLaunch(url), url)
    }
    XCTAssertEqual(PayriffExternalUrl.scheme(of: "Bank+App.V2-x://pay"), "bank+app.v2-x")
  }

  func testWebsiteDataOfVisitedSites() {
    let hosts: Set<String> = ["acs.bank.example", "sb-api.payriff.com"]
    for site in ["bank.example", "acs.bank.example", "Payriff.com", "sb-api.payriff.com"] {
      XCTAssertTrue(PayriffPlugin.isVisitedSite(site, hosts: hosts), site)
    }
    for site in ["", "ank.example", "other-bank.example", "pay.payriff.com"] {
      XCTAssertFalse(PayriffPlugin.isVisitedSite(site, hosts: hosts), site)
    }

    let plugin = PayriffPlugin()
    let invalid = expectation(description: "clearWebsiteData without hosts")
    plugin.handle(
      FlutterMethodCall(methodName: "clearWebsiteData", arguments: [String: Any]())
    ) { value in
      XCTAssertEqual((value as? FlutterError)?.code, "invalid_argument")
      invalid.fulfill()
    }
    let empty = expectation(description: "clearWebsiteData with no hosts")
    plugin.handle(
      FlutterMethodCall(
        methodName: "clearWebsiteData",
        arguments: ["hosts": [String](), "origins": [String](), "urls": [String]()])
    ) { value in
      XCTAssertNil(value)
      empty.fulfill()
    }
    waitForExpectations(timeout: 5)
  }

  func testChannelSurface() {
    let plugin = PayriffPlugin()

    let appId = expectation(description: "appId")
    plugin.handle(FlutterMethodCall(methodName: "appId", arguments: nil)) { value in
      XCTAssertEqual(value as? String, Bundle.main.bundleIdentifier)
      appId.fulfill()
    }

    let refused = expectation(description: "openExternal refuses file:")
    plugin.handle(
      FlutterMethodCall(methodName: "openExternal", arguments: ["url": "file:///etc/hosts"])
    ) { value in
      XCTAssertEqual(value as? Bool, false)
      refused.fulfill()
    }

    let failed = expectation(description: "encryptCard fails closed")
    plugin.handle(
      FlutterMethodCall(
        methodName: "encryptCard",
        arguments: [
          "card": FlutterStandardTypedData(bytes: Data("{}".utf8)),
          "spki": FlutterStandardTypedData(bytes: Data([1, 2, 3])),
        ])
    ) { value in
      let error = value as? FlutterError
      XCTAssertEqual(error?.code, "encryption_failed")
      XCTAssertNil(error?.details)
      failed.fulfill()
    }

    let encrypted = expectation(description: "encryptCard returns Base64")
    plugin.handle(
      FlutterMethodCall(
        methodName: "encryptCard",
        arguments: [
          "card": FlutterStandardTypedData(bytes: Data("{}".utf8)),
          "spki": FlutterStandardTypedData(bytes: testSpki),
        ])
    ) { value in
      let map = value as? [String: String]
      XCTAssertEqual(map?.keys.sorted(), ["encryptedMessage", "wrappedKey"])
      XCTAssertEqual(Data(base64Encoded: map?["encryptedMessage"] ?? "")?.count, 2 + 16)
      XCTAssertEqual(Data(base64Encoded: map?["wrappedKey"] ?? "")?.count, 256)
      encrypted.fulfill()
    }

    plugin.setSecure(true)
    plugin.setSecure(true)
    XCTAssertEqual(plugin.secureCount, 2)
    plugin.setSecure(false)
    plugin.setSecure(false)
    plugin.setSecure(false)
    XCTAssertEqual(plugin.secureCount, 0)

    let secure = expectation(description: "setSecure")
    plugin.handle(FlutterMethodCall(methodName: "setSecure", arguments: ["secure": true])) { value in
      XCTAssertNil(value)
      secure.fulfill()
    }
    XCTAssertEqual(plugin.secureCount, 1)

    waitForExpectations(timeout: 5)
  }
}
