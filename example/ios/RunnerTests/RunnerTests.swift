import CryptoKit
import Flutter
import PassKit
import Security
import UIKit
import XCTest

@testable import payriff

/// Native tests of the payriff plugin: every case of `test/vectors/card_crypto.json`
/// (CONTRACT §16.6), the external-URL rules (§7.5), the device integrity checks (§16.16) and the
/// channel surface. `ApplePayTests` below covers Apple Pay (§17.6, §17.10).
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

/// Apple Pay on the native side (CONTRACT §17.6, §17.10): the `PKPaymentRequest` built from what
/// Dart sends (`wallet.json` → `applePayRequests`), the button mapping (`buttonStyles`) and the
/// sheet session with a fake PassKit sheet: the handler is called exactly once, `.failure`
/// dismisses at once, the 25 s safety net, and closing before an authorization.
final class ApplePayTests: XCTestCase {
  private static let vectors: [String: Any] = {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // RunnerTests
      .deletingLastPathComponent()  // ios
      .deletingLastPathComponent()  // example
      .deletingLastPathComponent()  // package root
      .appendingPathComponent("test/vectors/wallet.json")
    let data = try! Data(contentsOf: url)
    return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
  }()

  /// A sheet that records what the session asks of PassKit.
  private final class FakeSheet: PayriffApplePaySheet {
    var presented = true
    var presents = 0
    var dismissals: [() -> Void] = []

    func present(_ completion: @escaping (Bool) -> Void) {
      presents += 1
      completion(presented)
    }

    func dismiss(_ completion: @escaping () -> Void) {
      dismissals.append(completion)
    }
  }

  private final class Clock {
    var scheduled: [(TimeInterval, () -> Void)] = []
    var cancelled = 0

    func schedule(_ delay: TimeInterval, _ work: @escaping () -> Void) -> () -> Void {
      scheduled.append((delay, work))
      return { [weak self] in self?.cancelled += 1 }
    }
  }

  private func session(_ sheet: FakeSheet, _ clock: Clock = Clock()) -> PayriffApplePaySession {
    PayriffApplePaySession(makeSheet: { _ in sheet }, schedule: clock.schedule)
  }

  func testRequestsOfTheVectors() throws {
    let cases = Self.vectors["applePayRequests"] as! [[String: Any]]
    XCTAssertFalse(cases.isEmpty)
    for item in cases {
      // `expect` is exactly what Dart sends.
      let expected = item["expect"] as! [String: Any]
      let request = try XCTUnwrap(PayriffApplePayRequest.make(expected), "\(item["name"]!)")
      XCTAssertEqual(request.merchantIdentifier, expected["merchantIdentifier"] as? String)
      XCTAssertEqual(request.countryCode, expected["countryCode"] as? String)
      XCTAssertEqual(request.currencyCode, expected["currencyCode"] as? String)
      XCTAssertEqual(request.supportedNetworks, [.visa, .masterCard])
      XCTAssertEqual(request.merchantCapabilities, .threeDSecure)
      XCTAssertTrue(request.requiredShippingContactFields.isEmpty)
      XCTAssertTrue(request.requiredBillingContactFields.isEmpty)
      let summary = (expected["summaryItems"] as! [[String: Any]]).first!
      let item = try XCTUnwrap(request.paymentSummaryItems.first)
      XCTAssertEqual(request.paymentSummaryItems.count, 1)
      XCTAssertEqual(item.label, summary["label"] as? String)
      XCTAssertEqual(item.type, .final)
      XCTAssertEqual(
        item.amount,
        NSDecimalNumber(string: summary["amount"] as? String, locale: Locale(identifier: "en_US_POSIX")))
    }
    // Decimal text in the POSIX locale only.
    XCTAssertEqual(PayriffApplePayRequest.amount("10.50")?.stringValue, "10.5")
    XCTAssertNil(PayriffApplePayRequest.amount("ten"))
    var bad = (cases.first!["expect"] as! [String: Any])
    bad["supportedNetworks"] = ["amex"]
    XCTAssertNil(PayriffApplePayRequest.make(bad))
  }

  func testButtonTypesAndThemesOfTheVectors() {
    let styles = (Self.vectors["buttonStyles"] as! [String: Any])["applePay"] as! [String: Any]
    let types: [String: PKPaymentButtonType] = [
      "plain": .plain, "buy": .buy, "checkout": .checkout, "book": .book, "donate": .donate,
      "order": .order, "subscribe": .subscribe,
    ]
    for (_, native) in styles["types"] as! [String: String] {
      XCTAssertEqual(PayriffApplePayButtonView.type(native), types[native], native)
    }
    let themes: [String: PKPaymentButtonStyle] = [
      "automatic": .automatic, "black": .black, "white": .white, "whiteOutline": .whiteOutline,
    ]
    for (_, native) in styles["themes"] as! [String: String] {
      XCTAssertEqual(PayriffApplePayButtonView.style(native), themes[native], native)
    }
    XCTAssertEqual(PayriffApplePayButtonView.type(nil), .plain)
    XCTAssertEqual(PayriffApplePayButtonView.style(nil), .black)
  }

  func testSuccessCompletesTheHandlerOnceAndRepliesWhenTheSheetIsGone() {
    let sheet = FakeSheet()
    let clock = Clock()
    let session = session(sheet, clock)
    var presentReplies: [[String: Any]] = []
    session.start { presentReplies.append($0 as! [String: Any]) }
    XCTAssertEqual(sheet.presents, 1)

    var statuses: [PKPaymentAuthorizationStatus] = []
    session.authorized(paymentData: Data("{\"version\":\"EC_v1\"}".utf8)) { statuses.append($0) }
    XCTAssertEqual(presentReplies.count, 1)
    XCTAssertEqual(presentReplies[0]["event"] as? String, "authorized")
    XCTAssertEqual(presentReplies[0]["paymentData"] as? String, "{\"version\":\"EC_v1\"}")
    XCTAssertEqual(clock.scheduled.map(\.0), [PayriffApplePaySession.safetyNet])
    XCTAssertEqual(PayriffApplePaySession.safetyNet, 25)

    var completeReplies: [String] = []
    session.complete(status: .success) {
      completeReplies.append(($0 as! [String: Any])["status"] as! String)
    }
    XCTAssertEqual(statuses, [.success])
    XCTAssertEqual(clock.cancelled, 1)
    // PassKit shows its confirmation, then finishes; only then the sheet is dismissed.
    XCTAssertTrue(sheet.dismissals.isEmpty)
    XCTAssertTrue(completeReplies.isEmpty)
    session.sheetDidFinish()
    XCTAssertEqual(sheet.dismissals.count, 1)
    sheet.dismissals[0]()
    XCTAssertEqual(completeReplies, ["success"])
    XCTAssertTrue(session.finished)

    // Nothing calls the handler again.
    clock.scheduled[0].1()
    session.sheetDidFinish()
    session.complete(status: .failure) {
      completeReplies.append(($0 as! [String: Any])["status"] as! String)
    }
    XCTAssertEqual(statuses, [.success])
    XCTAssertEqual(completeReplies, ["success", "success"])
    XCTAssertEqual(presentReplies.count, 1)
  }

  func testFailureDismissesTheSheetAtOnce() {
    let sheet = FakeSheet()
    let session = session(sheet)
    session.start { _ in }
    var statuses: [PKPaymentAuthorizationStatus] = []
    session.authorized(paymentData: Data("{}".utf8)) { statuses.append($0) }
    var replies: [String] = []
    session.complete(status: .failure) { replies.append(($0 as! [String: Any])["status"] as! String) }
    XCTAssertEqual(statuses, [.failure])
    XCTAssertEqual(sheet.dismissals.count, 1)
    // PassKit may still report the finish; it changes nothing.
    session.sheetDidFinish()
    XCTAssertEqual(sheet.dismissals.count, 1)
    sheet.dismissals[0]()
    XCTAssertEqual(replies, ["failure"])
    XCTAssertEqual(statuses, [.failure])
  }

  func testWithoutADecisionTheSafetyNetCompletesWithFailure() {
    let sheet = FakeSheet()
    let clock = Clock()
    let session = session(sheet, clock)
    session.start { _ in }
    var statuses: [PKPaymentAuthorizationStatus] = []
    session.authorized(paymentData: Data("{}".utf8)) { statuses.append($0) }
    clock.scheduled[0].1()
    XCTAssertEqual(statuses, [.failure])
    XCTAssertEqual(sheet.dismissals.count, 1)
    sheet.dismissals[0]()
    // Dart's late decision gets the status the sheet got.
    var replies: [String] = []
    session.complete(status: .success) { replies.append(($0 as! [String: Any])["status"] as! String) }
    XCTAssertEqual(replies, ["failure"])
    XCTAssertEqual(statuses, [.failure])
  }

  func testASecondAuthorizationIsRefusedAtOnce() {
    let session = session(FakeSheet())
    session.start { _ in }
    var first: [PKPaymentAuthorizationStatus] = []
    var second: [PKPaymentAuthorizationStatus] = []
    session.authorized(paymentData: Data("{}".utf8)) { first.append($0) }
    session.authorized(paymentData: Data("{}".utf8)) { second.append($0) }
    XCTAssertEqual(second, [.failure])
    XCTAssertEqual(first, [])
  }

  func testClosingBeforeAnAuthorizationAndASheetThatCannotBeShown() {
    let sheet = FakeSheet()
    let session = session(sheet)
    var replies: [[String: Any]] = []
    session.start { replies.append($0 as! [String: Any]) }
    session.sheetDidFinish()
    XCTAssertEqual(replies.map { $0["event"] as? String }, ["closed"])
    XCTAssertEqual(sheet.dismissals.count, 1)
    sheet.dismissals[0]()
    XCTAssertTrue(session.finished)

    let hidden = FakeSheet()
    hidden.presented = false
    let refused = self.session(hidden)
    var events: [String?] = []
    refused.start { events.append(($0 as! [String: Any])["event"] as? String) }
    XCTAssertEqual(events, ["notPresented"])
    XCTAssertTrue(refused.finished)
    XCTAssertTrue(hidden.dismissals.isEmpty)
  }

  func testPaymentDataThatIsNotUtf8IsSentAsNull() {
    let session = session(FakeSheet())
    var reply: [String: Any] = [:]
    session.start { reply = $0 as! [String: Any] }
    session.authorized(paymentData: Data([0xFF, 0xFE])) { _ in }
    XCTAssertEqual(reply["event"] as? String, "authorized")
    XCTAssertTrue(reply["paymentData"] is NSNull)
  }

  func testChannelSurface() {
    let plugin = PayriffPlugin()
    let name = expectation(description: "appName")
    plugin.handle(FlutterMethodCall(methodName: "appName", arguments: nil)) { value in
      XCTAssertEqual(value as? String, PayriffPlugin.appName())
      name.fulfill()
    }
    let present = expectation(description: "applePayPresent refuses an invalid request")
    plugin.handle(
      FlutterMethodCall(methodName: "applePayPresent", arguments: ["merchantIdentifier": ""])
    ) { value in
      XCTAssertEqual((value as? [String: Any])?["event"] as? String, "notPresented")
      present.fulfill()
    }
    let complete = expectation(description: "applePayComplete without a sheet")
    plugin.handle(
      FlutterMethodCall(methodName: "applePayComplete", arguments: ["status": "success"])
    ) { value in
      XCTAssertEqual((value as? [String: Any])?["status"] as? String, "failure")
      complete.fulfill()
    }
    let canPay = expectation(description: "applePayCanMakePayments without networks")
    plugin.handle(
      FlutterMethodCall(
        methodName: "applePayCanMakePayments", arguments: ["networks": [], "capabilities": []])
    ) { value in
      XCTAssertEqual(value as? Bool, false)
      canPay.fulfill()
    }
    waitForExpectations(timeout: 5)
  }
}
