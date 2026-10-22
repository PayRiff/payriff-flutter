import Flutter
import UIKit

/// Native half of the payriff plugin, channel `payriff/native` (CONTRACT §16.11):
///
/// - `encryptCard` {card: bytes, spki: bytes} -> {encryptedMessage, wrappedKey} (Base64, §16.6)
/// - `appId` -> the bundle identifier, for `X-Client-App-Id`
/// - `setSecure` {secure: bool} -> nil. Reference-counted: while the count is above zero an
///   opaque cover hides the app whenever it resigns active, so app-switcher snapshots show
///   no card data (§16.0 item 4).
/// - `openExternal` {url} -> bool, `UIApplication.open` after the §7.5 scheme checks.
///
/// Nothing here logs. Error messages are fixed strings without input data.
public final class PayriffPlugin: NSObject, FlutterPlugin {
  static let channelName = "payriff/native"
  static let encryptionFailed = "encryption_failed"

  /// Number of open `setSecure(true)` requests.
  private(set) var secureCount = 0
  private var covers: [UIView] = []

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    let instance = PayriffPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
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
    default:
      result(FlutterMethodNotImplemented)
    }
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
}
