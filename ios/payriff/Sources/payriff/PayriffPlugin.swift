import Flutter
import PassKit
import UIKit
import WebKit

/// Native half of the payriff plugin, channel `payriff/native` (CONTRACT §16.11):
///
/// - `encryptCard` {card: bytes, spki: bytes} -> {encryptedMessage, wrappedKey} (Base64, §16.6)
/// - `appId` -> the bundle identifier, for `X-Client-App-Id`
/// - `setSecure` {secure: bool} -> nil. Reference-counted: while the count is above zero an
///   opaque cover hides the app whenever it resigns active, so app-switcher snapshots show
///   no card data (§16.0 item 4).
/// - `openExternal` {url} -> bool, `UIApplication.open` after the §7.5 scheme checks.
/// - `clearWebsiteData` {hosts, origins, urls} -> nil once WebKit is done: removes the default
///   data store's records (all types) of the sites a payment's 3-D Secure WebViews loaded (§9.1a).
/// - `deviceIntegrity` -> {compromised: bool, signals: [String]}: jailbreak, hooking and debugger
///   checks (§16.16, `PayriffDeviceIntegrity`), run off the main thread.
/// - `appName` -> `CFBundleDisplayName`, then `CFBundleName`: the last fallback of the Apple Pay
///   sheet's merchant name (§17.4).
/// - `applePayCanMakePayments` {networks, capabilities} -> bool (§17.3 item 4).
/// - `applePayPresent` {request} -> {event: authorized, paymentData} | {event: closed} |
///   {event: notPresented}, and `applePayComplete` {status} -> {status} once the sheet is gone
///   (§17.6, `PayriffApplePaySession`).
/// - `isSupported` -> bool: iOS 16 or later, for `Payriff.isSupported` (§18.8).
///
/// The platform view `payriff/apple_pay_button` is Apple's `PKPaymentButton`
/// (`PayriffApplePayButtonFactory`, §17.10).
///
/// Nothing here logs. Error messages are fixed strings without input data. The Apple Pay token
/// is only passed on to Dart.
public final class PayriffPlugin: NSObject, FlutterPlugin {
  static let channelName = "payriff/native"
  static let encryptionFailed = "encryption_failed"

  /// Number of open `setSecure(true)` requests.
  private(set) var secureCount = 0
  private var covers: [UIView] = []

  /// The current Apple Pay sheet, kept after it is gone to answer a late `applePayComplete`.
  private var applePay: PayriffApplePaySession?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    let instance = PayriffPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.register(
      PayriffApplePayButtonFactory(messenger: registrar.messenger()),
      withId: PayriffApplePayButtonFactory.viewType)
  }

  override init() {
    super.init()
    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(appWillResignActive),
      name: UIApplication.willResignActiveNotification, object: nil)
    center.addObserver(
      self, selector: #selector(appDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification, object: nil)
    // Scene-based apps (Flutter's default since UIScene adoption) also post scene events.
    center.addObserver(
      self, selector: #selector(appWillResignActive),
      name: UIScene.willDeactivateNotification, object: nil)
    center.addObserver(
      self, selector: #selector(appDidBecomeActive),
      name: UIScene.didActivateNotification, object: nil)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    secureCount = 0
    removeCovers()
    applePay?.cancel()
    applePay = nil
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "encryptCard":
      encryptCard(args, result: result)
    case "appId":
      result(Bundle.main.bundleIdentifier)
    case "setSecure":
      guard let secure = args?["secure"] as? Bool else {
        result(
          FlutterError(
            code: "invalid_argument", message: "setSecure expects {secure: bool}.", details: nil))
        return
      }
      setSecure(secure)
      result(nil)
    case "openExternal":
      openExternal(args?["url"] as? String, result: result)
    case "clearWebsiteData":
      guard let hosts = args?["hosts"] as? [String] else {
        result(
          FlutterError(
            code: "invalid_argument", message: "clearWebsiteData expects {hosts: [String]}.",
            details: nil))
        return
      }
      clearWebsiteData(hosts: hosts, result: result)
    case "deviceIntegrity":
      deviceIntegrity(result: result)
    case "appName":
      result(Self.appName())
    case "isSupported":
      if #available(iOS 16.0, *) {
        result(true)
      } else {
        result(false)
      }
    case "applePayCanMakePayments":
      let networks = PayriffApplePayRequest.networks(args?["networks"] as? [String] ?? [])
      let capabilities = PayriffApplePayRequest.capabilities(
        args?["capabilities"] as? [String] ?? [])
      result(
        !networks.isEmpty && !capabilities.isEmpty
          && PKPaymentAuthorizationController.canMakePayments(
            usingNetworks: networks, capabilities: capabilities))
    case "applePayPresent":
      applePayPresent(args, result: result)
    case "applePayComplete":
      let status: PKPaymentAuthorizationStatus =
        (args?["status"] as? String) == "success" ? .success : .failure
      guard let session = applePay else {
        result(["status": "failure"])
        return
      }
      session.complete(status: status, reply: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Apple Pay (§17.6)

  /// The app's display name, trimmed; nil when it has none.
  static func appName() -> String? {
    for key in ["CFBundleDisplayName", "CFBundleName"] {
      if let name = (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty
      {
        return name
      }
    }
    return nil
  }

  /// One sheet at a time: while one is up, another request is not presented.
  private func applePayPresent(_ args: [String: Any]?, result: @escaping FlutterResult) {
    if let current = applePay, !current.finished {
      result(["event": "notPresented"])
      return
    }
    guard let args, let request = PayriffApplePayRequest.make(args) else {
      result(["event": "notPresented"])
      return
    }
    let session = PayriffApplePaySession(makeSheet: { delegate in
      PayriffPassKitSheet(request: request, delegate: delegate)
    })
    applePay = session
    session.start(reply: result)
  }

  // MARK: - Card encryption (§16.6)

  private func encryptCard(_ args: [String: Any]?, result: FlutterResult) {
    guard let card = (args?["card"] as? FlutterStandardTypedData)?.data,
      let spki = (args?["spki"] as? FlutterStandardTypedData)?.data
    else {
      result(Self.encryptionError())
      return
    }
    do {
      let output = try PayriffCardCrypto.encrypt(card: card, spki: spki)
      result([
        "encryptedMessage": output.encryptedMessage.base64EncodedString(),
        "wrappedKey": output.wrappedKey.base64EncodedString(),
      ])
    } catch {
      // Fixed message only: the error type carries no input data either.
      result(Self.encryptionError())
    }
  }

  private static func encryptionError() -> FlutterError {
    FlutterError(code: encryptionFailed, message: "Card encryption failed.", details: nil)
  }

  // MARK: - Screen protection (§16.0 item 4)

  func setSecure(_ secure: Bool) {
    secureCount = secure ? secureCount + 1 : max(0, secureCount - 1)
    if secureCount == 0 {
      removeCovers()
    }
  }

  @objc private func appWillResignActive() {
    guard secureCount > 0, covers.isEmpty else { return }
    for window in visibleWindows() {
      let cover = UIView(frame: window.bounds)
      cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      cover.backgroundColor = .systemBackground
      cover.isOpaque = true
      cover.accessibilityElementsHidden = true
      window.addSubview(cover)
      covers.append(cover)
    }
  }

  @objc private func appDidBecomeActive() {
    removeCovers()
  }

  private func removeCovers() {
    covers.forEach { $0.removeFromSuperview() }
    covers.removeAll()
  }

  private func visibleWindows() -> [UIWindow] {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .filter { !$0.isHidden }
  }

  // MARK: - External launches (§7.5)

  private func openExternal(_ raw: String?, result: @escaping FlutterResult) {
    guard let raw, PayriffExternalUrl.mayLaunch(raw), let url = URL(string: raw),
      let scheme = url.scheme?.lowercased(), !PayriffExternalUrl.refusedSchemes.contains(scheme)
    else {
      result(false)
      return
    }
    UIApplication.shared.open(url, options: [:]) { opened in
      result(opened)
    }
  }

  // MARK: - 3-D Secure website data (§9.1a)

  /// webview_flutter's WebViews use the default data store, which the app's own WebViews share.
  /// This removes its records, of every type, whose display name (a site such as `bank.example`)
  /// is one of `hosts` or a parent domain of one, then replies. Data of the same sites that the
  /// app stored itself goes with it.
  private func clearWebsiteData(hosts: [String], result: @escaping FlutterResult) {
    let visited = Set(hosts.map { $0.lowercased() }.filter { !$0.isEmpty })
    guard !visited.isEmpty else {
      result(nil)
      return
    }
    // WebKit's data store is used on the main thread only.
    DispatchQueue.main.async {
      let store = WKWebsiteDataStore.default()
      let types = WKWebsiteDataStore.allWebsiteDataTypes()
      store.fetchDataRecords(ofTypes: types) { records in
        let matching = records.filter { Self.isVisitedSite($0.displayName, hosts: visited) }
        guard !matching.isEmpty else {
          result(nil)
          return
        }
        store.removeData(ofTypes: types, for: matching) {
          result(nil)
        }
      }
    }
  }

  /// Whether the data record of `site` belongs to one of `hosts` (lower case): `site` is the
  /// host itself or one of its parent domains.
  static func isVisitedSite(_ site: String, hosts: Set<String>) -> Bool {
    let name = site.lowercased()
    guard !name.isEmpty else { return false }
    return hosts.contains { $0 == name || $0.hasSuffix("." + name) }
  }

  // MARK: - Device integrity (§16.16)

  /// One per process, so the jailbreak results are kept for the process.
  static let integrity = PayriffDeviceIntegrity(probes: PayriffDeviceProbes())
  private static let integrityQueue = DispatchQueue(
    label: "com.payriff.flutter.integrity", qos: .userInitiated)

  /// Runs the checks on their own queue (they read files and try a TCP connection to
  /// frida-server) and replies `{compromised, signals}` on the main thread. Signal names only: no
  /// paths or file contents.
  private func deviceIntegrity(result: @escaping FlutterResult) {
    Self.integrityQueue.async {
      let signals = Self.integrity.signals()
      DispatchQueue.main.async {
        result(["compromised": !signals.isEmpty, "signals": signals])
      }
    }
  }
}
