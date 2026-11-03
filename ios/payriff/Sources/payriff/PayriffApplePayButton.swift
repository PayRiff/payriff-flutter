import Flutter
import PassKit
import UIKit

/// The platform view `payriff/apple_pay_button` (CONTRACT §17.10): Apple's own
/// `PKPaymentButton`. The creation parameters are style values only (`type`, `theme`,
/// `cornerRadius`); Dart resolves the `automatic` theme from the page. A tap goes to Dart as
/// `tap` on the view's channel `payriff/apple_pay_button/<id>`.
final class PayriffApplePayButtonFactory: NSObject, FlutterPlatformViewFactory {
  static let viewType = "payriff/apple_pay_button"

  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(
    withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?
  ) -> FlutterPlatformView {
    PayriffApplePayButtonView(
      frame: frame, viewId: viewId, arguments: args as? [String: Any], messenger: messenger)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

final class PayriffApplePayButtonView: NSObject, FlutterPlatformView {
  private let button: PKPaymentButton
  private let channel: FlutterMethodChannel

  init(
    frame: CGRect, viewId: Int64, arguments: [String: Any]?, messenger: FlutterBinaryMessenger
  ) {
    button = PKPaymentButton(
      paymentButtonType: Self.type(arguments?["type"] as? String),
      paymentButtonStyle: Self.style(arguments?["theme"] as? String))
    button.frame = frame
    button.cornerRadius = CGFloat(
      max(0, (arguments?["cornerRadius"] as? NSNumber)?.doubleValue ?? 16))
    channel = FlutterMethodChannel(
      name: "\(PayriffApplePayButtonFactory.viewType)/\(viewId)", binaryMessenger: messenger)
    super.init()
    button.addTarget(self, action: #selector(tapped), for: .touchUpInside)
  }

  func view() -> UIView { button }

  @objc private func tapped() {
    channel.invokeMethod("tap", arguments: nil)
  }

  /// The `PKPaymentButtonType` of a `PayriffApplePayButtonType` name; `plain` otherwise.
  static func type(_ name: String?) -> PKPaymentButtonType {
    switch name {
    case "buy": return .buy
    case "checkout": return .checkout
    case "book": return .book
    case "donate": return .donate
    case "subscribe": return .subscribe
    case "order":
      if #available(iOS 14.0, *) { return .order }
      return .plain
    default: return .plain
    }
  }

  /// The `PKPaymentButtonStyle` of a theme name; `black` otherwise.
  static func style(_ name: String?) -> PKPaymentButtonStyle {
    switch name {
    case "white": return .white
    case "whiteOutline": return .whiteOutline
    case "automatic":
      if #available(iOS 14.0, *) { return .automatic }
      return .black
    default: return .black
    }
  }
}
