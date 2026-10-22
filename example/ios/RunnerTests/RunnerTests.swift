import CryptoKit
import Flutter
import Security
import UIKit
import XCTest

@testable import payriff

/// Native tests of the payriff plugin: every case of `test/vectors/card_crypto.json`
/// (CONTRACT §16.6), the external-URL rules (§7.5), the device integrity checks (§16.16) and the
/// channel surface.
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

    // The tests run on the simulator, where nothing is checked (§16.16).
    let integrity = expectation(description: "deviceIntegrity")
    plugin.handle(FlutterMethodCall(methodName: "deviceIntegrity", arguments: nil)) { value in
      let map = value as? [String: Any]
      XCTAssertEqual(map?["compromised"] as? Bool, false)
      XCTAssertEqual(map?["signals"] as? [String], [])
      XCTAssertTrue(Thread.isMainThread)
      integrity.fulfill()
    }

    waitForExpectations(timeout: 5)
  }

  // MARK: - Device integrity (§16.16)

  private final class FakeProbes: PayriffIntegrityProbes {
    var isSimulator = false
    var hasEmbeddedProvisioningProfile = false
    var files: Set<String> = []
    var writable = false
    var images = ["/usr/lib/libSystem.B.dylib", "/System/Library/Frameworks/UIKit.framework/UIKit"]
    var environment: [String: String] = [:]
    var fridaServer = false
    var traced = false
    var calls: [String] = []

    func fileExists(_ path: String) -> Bool {
      calls.append("file \(path)")
      return files.contains(path)
    }

    func canWriteFile(atPath path: String) -> Bool {
      calls.append("write \(path)")
      return writable
    }

    func loadedImages() -> [String] {
      calls.append("images")
      return images
    }

    func environmentValue(_ name: String) -> String? {
      calls.append("env \(name)")
      return environment[name]
    }

    func acceptsLoopbackConnection(port: UInt16, timeout: TimeInterval) -> Bool {
      calls.append("tcp \(port) \(timeout)")
      return fridaServer
    }

    func isTraced() -> Bool {
      calls.append("traced")
      return traced
    }
  }

  private func signals(_ setUp: (FakeProbes) -> Void) -> [String] {
    let probes = FakeProbes()
    setUp(probes)
    return PayriffDeviceIntegrity(probes: probes).signals()
  }

  func testIntegrityOfACleanDevice() {
    let probes = FakeProbes()
    XCTAssertEqual(PayriffDeviceIntegrity(probes: probes).signals(), [])
    XCTAssertTrue(probes.calls.contains("tcp 27042 0.1"), "frida-server on 127.0.0.1:27042, 100 ms")
    XCTAssertTrue(probes.calls.contains("write /private/payriff-jb-check"))
  }

  func testIntegrityEachJailbreakFileAndTheSandboxWrite() {
    XCTAssertEqual(PayriffDeviceIntegrity.jailbreakFiles.count, 20)
    for path in PayriffDeviceIntegrity.jailbreakFiles {
      XCTAssertEqual(signals { $0.files = [path] }, ["jailbreak files"], path)
    }
    XCTAssertEqual(signals { $0.writable = true }, ["sandbox write"])
  }

  func testIntegrityHookingLibrariesInsertedLibrariesAndFridaServer() {
    for part in PayriffDeviceIntegrity.hookingImages {
      let expected = part.lowercased().contains("frida") ? "Frida" : "hooking library"
      XCTAssertEqual(
        signals { $0.images.append("/usr/lib/tweaks/\(part.uppercased()).dylib") }, [expected], part)
    }
    XCTAssertEqual(
      signals {
        $0.images += ["/usr/lib/TweakInject/a.dylib", "/private/var/tmp/FridaGadget.dylib"]
      },
      ["hooking library", "Frida"])
    XCTAssertEqual(signals { $0.environment["DYLD_INSERT_LIBRARIES"] = "/x.dylib" }, ["DYLD_INSERT_LIBRARIES"])
    XCTAssertEqual(signals { $0.environment["DYLD_INSERT_LIBRARIES"] = "" }, [])
    XCTAssertEqual(signals { $0.fridaServer = true }, ["frida-server"])
  }

  func testIntegrityInsertedLibrariesOnlyInAppStoreAndTestFlightBuilds() {
    XCTAssertEqual(
      signals { $0.environment["DYLD_INSERT_LIBRARIES"] = "/x.dylib" }, ["DYLD_INSERT_LIBRARIES"])
    // A development build (embedded.mobileprovision) that Xcode runs with its Main Thread Checker.
    let probes = FakeProbes()
    probes.hasEmbeddedProvisioningProfile = true
    probes.environment["DYLD_INSERT_LIBRARIES"] = "/usr/lib/libMainThreadChecker.dylib"
    XCTAssertEqual(PayriffDeviceIntegrity(probes: probes).signals(), [])
    XCTAssertFalse(probes.calls.contains("env DYLD_INSERT_LIBRARIES"))
    // The other hooking checks still count there.
    XCTAssertEqual(
      signals {
        $0.hasEmbeddedProvisioningProfile = true
        $0.environment["DYLD_INSERT_LIBRARIES"] = "/x.dylib"
        $0.images.append("/private/var/tmp/FridaGadget.dylib")
        $0.fridaServer = true
      }, ["Frida", "frida-server"])
  }

  func testIntegrityDebuggerOnlyInAppStoreAndTestFlightBuilds() {
    XCTAssertEqual(signals { $0.traced = true }, ["debugger"])
    // A development build (embedded.mobileprovision) is debugged from Xcode all the time.
    XCTAssertEqual(
      signals {
        $0.traced = true
        $0.hasEmbeddedProvisioningProfile = true
      }, [])
  }

  func testIntegrityChecksNothingOnTheSimulator() {
    let probes = FakeProbes()
    probes.isSimulator = true
    probes.files = Set(PayriffDeviceIntegrity.jailbreakFiles)
    probes.writable = true
    probes.images.append("/usr/lib/frida-agent.dylib")
    probes.environment["DYLD_INSERT_LIBRARIES"] = "/x.dylib"
    probes.fridaServer = true
    probes.traced = true
    XCTAssertEqual(PayriffDeviceIntegrity(probes: probes).signals(), [])
    XCTAssertEqual(probes.calls, [])
  }

  func testIntegrityKeepsJailbreakResultsAndRepeatsRuntimeChecks() {
    let probes = FakeProbes()
    let integrity = PayriffDeviceIntegrity(probes: probes)
    XCTAssertEqual(integrity.signals(), [])
    probes.calls.removeAll()
    probes.files = ["/bin/bash"]
    probes.writable = true
    probes.fridaServer = true
    probes.traced = true
    XCTAssertEqual(integrity.signals(), ["frida-server", "debugger"])
    XCTAssertFalse(probes.calls.contains { $0.hasPrefix("file ") || $0.hasPrefix("write ") })
    for call in ["images", "env DYLD_INSERT_LIBRARIES", "tcp 27042 0.1", "traced"] {
      XCTAssertTrue(probes.calls.contains(call), call)
    }
  }
}
