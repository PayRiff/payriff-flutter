import Flutter
import Foundation
import PassKit

/// Builds the PassKit values of CONTRACT §17.6 from what Dart sends (`applePayRequest` in
/// `lib/src/internal/wallet/wallet_rules.dart`, `wallet.json` → `applePayRequests`).
enum PayriffApplePayRequest {
  /// The `PKPaymentNetwork`s of `names`; unknown names are dropped.
  static func networks(_ names: [String]) -> [PKPaymentNetwork] {
    names.compactMap { name in
      switch name {
      case "visa": return .visa
      case "masterCard": return .masterCard
      default: return nil
      }
    }
  }

  /// The `PKMerchantCapability` of `names`; unknown names are dropped.
  static func capabilities(_ names: [String]) -> PKMerchantCapability {
    var capabilities: PKMerchantCapability = []
    if names.contains("threeDSecure") { capabilities.insert(.threeDSecure) }
    return capabilities
  }

  /// The amount text (`10.50`) read with the POSIX locale; nil when it is not a decimal number.
  static func amount(_ text: String) -> NSDecimalNumber? {
    let amount = NSDecimalNumber(string: text, locale: Locale(identifier: "en_US_POSIX"))
    return amount.decimalValue.isNaN ? nil : amount
  }

  /// The `PKPaymentRequest` of `args`, with no shipping or billing contact fields; nil when a
  /// value is missing or invalid.
  static func make(_ args: [String: Any]) -> PKPaymentRequest? {
    guard let merchantIdentifier = args["merchantIdentifier"] as? String, !merchantIdentifier.isEmpty,
      let countryCode = args["countryCode"] as? String, !countryCode.isEmpty,
      let currencyCode = args["currencyCode"] as? String, !currencyCode.isEmpty,
      let items = args["summaryItems"] as? [[String: Any]], !items.isEmpty
    else { return nil }
    let networks = networks(args["supportedNetworks"] as? [String] ?? [])
    let capabilities = capabilities(args["merchantCapabilities"] as? [String] ?? [])
    guard !networks.isEmpty, !capabilities.isEmpty else { return nil }
    var summary: [PKPaymentSummaryItem] = []
    for item in items {
      guard let label = item["label"] as? String, let text = item["amount"] as? String,
        let amount = amount(text)
      else { return nil }
      summary.append(PKPaymentSummaryItem(label: label, amount: amount, type: .final))
    }
    let request = PKPaymentRequest()
    request.merchantIdentifier = merchantIdentifier
    request.countryCode = countryCode
    request.currencyCode = currencyCode
    request.supportedNetworks = networks
    request.merchantCapabilities = capabilities
    request.paymentSummaryItems = summary
    request.requiredShippingContactFields = []
    request.requiredBillingContactFields = []
    return request
  }
}

/// What a session needs from the Apple Pay sheet, so tests can replace PassKit.
protocol PayriffApplePaySheet: AnyObject {
  func present(_ completion: @escaping (Bool) -> Void)
  func dismiss(_ completion: @escaping () -> Void)
}

/// The real sheet: a `PKPaymentAuthorizationController`, which needs no view controller.
final class PayriffPassKitSheet: PayriffApplePaySheet {
  private let controller: PKPaymentAuthorizationController

  init(request: PKPaymentRequest, delegate: PKPaymentAuthorizationControllerDelegate) {
    controller = PKPaymentAuthorizationController(paymentRequest: request)
    controller.delegate = delegate
  }

  func present(_ completion: @escaping (Bool) -> Void) {
    controller.present(completion: completion)
  }

  func dismiss(_ completion: @escaping () -> Void) {
    controller.dismiss(completion: completion)
  }
}

/// One Apple Pay sheet, from `applePayPresent` until it is gone (CONTRACT §17.6). Main thread
/// only.
///
/// - `start` presents the sheet. Its reply is `{event: "authorized", paymentData}` (the
///   token's `paymentData` as UTF-8 text) when the customer authorizes, `{event: "closed"}`
///   when the sheet closes first, or `{event: "notPresented"}`.
/// - After an authorization the sheet waits until `complete` brings Dart's decision. PassKit's
///   handler is called exactly once: with that decision, or with `.failure` when no decision
///   arrives within `safetyNet` seconds, or when the sheet goes away first.
/// - After `.failure` the session dismisses the sheet itself, so the customer cannot authorize
///   again in it. After `.success` PassKit shows its confirmation, then finishes.
/// - `complete` replies `{status}` (the status the handler got) once the sheet is gone.
///
/// Nothing here logs; the token is only passed on.
final class PayriffApplePaySession: NSObject, PKPaymentAuthorizationControllerDelegate {
  /// Seconds after the authorization before the session completes the sheet with `.failure`
  /// itself. Dart decides within 20 s; this is a safety net.
  static let safetyNet: TimeInterval = 25

  typealias Schedule = (_ delay: TimeInterval, _ work: @escaping () -> Void) -> () -> Void

  private let makeSheet: (PKPaymentAuthorizationControllerDelegate) -> PayriffApplePaySheet
  private let schedule: Schedule
  private var sheet: PayriffApplePaySheet?
  private var presentReply: FlutterResult?
  private var completeReplies: [FlutterResult] = []
  private var handler: ((PKPaymentAuthorizationStatus) -> Void)?
  private var cancelSafetyNet: (() -> Void)?
  private var dismissing = false

  /// The status PassKit's handler got, once it was called.
  private(set) var completedStatus: PKPaymentAuthorizationStatus?

  /// Whether the sheet is gone (or was never shown).
  private(set) var finished = false

  init(
    makeSheet: @escaping (PKPaymentAuthorizationControllerDelegate) -> PayriffApplePaySheet,
    schedule: @escaping Schedule = PayriffApplePaySession.mainQueueSchedule
  ) {
    self.makeSheet = makeSheet
    self.schedule = schedule
    super.init()
  }

  /// Runs `work` on the main queue after `delay` seconds; the returned closure cancels it.
  static func mainQueueSchedule(_ delay: TimeInterval, _ work: @escaping () -> Void) -> () -> Void
  {
    let item = DispatchWorkItem(block: work)
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    return { item.cancel() }
  }

  /// Presents the sheet; `reply` gets the first event.
  func start(reply: @escaping FlutterResult) {
    presentReply = reply
    let sheet = makeSheet(self)
    self.sheet = sheet
    sheet.present { [weak self] presented in
      guard let self, !presented else { return }
      self.replyPresent(["event": "notPresented"])
      self.markFinished()
    }
  }

  /// The customer authorized the payment. `completion` is PassKit's handler.
  func authorized(
    paymentData: Data, completion: @escaping (PKPaymentAuthorizationStatus) -> Void
  ) {
    guard handler == nil, completedStatus == nil, !finished else {
      // One authorization per sheet: a second one is refused at once.
      completion(.failure)
      return
    }
    handler = completion
    cancelSafetyNet = schedule(Self.safetyNet) { [weak self] in
      self?.callHandler(.failure)
    }
    let text: Any = String(data: paymentData, encoding: .utf8) ?? NSNull()
    replyPresent(["event": "authorized", "paymentData": text])
  }

  /// Dart's decision. `reply` gets `{status}` once the sheet is gone.
  func complete(status: PKPaymentAuthorizationStatus, reply: @escaping FlutterResult) {
    if finished {
      reply(["status": Self.name(completedStatus ?? .failure)])
      return
    }
    completeReplies.append(reply)
    if handler != nil {
      callHandler(status)
    } else if completedStatus == nil {
      // No authorization to complete: close the sheet.
      completedStatus = .failure
      dismissSheet()
    }
  }

  /// The engine went away: the sheet must not stay up.
  func cancel() {
    callHandler(.failure)
    replyPresent(["event": "closed"])
    dismissSheet()
  }

  /// `paymentAuthorizationControllerDidFinish`: the sheet closed, after a completion or because
  /// the customer cancelled it.
  func sheetDidFinish() {
    replyPresent(["event": "closed"])
    // The handler is called exactly once, also when the sheet went away first.
    callHandler(.failure)
    dismissSheet()
  }

  private func callHandler(_ status: PKPaymentAuthorizationStatus) {
    guard let handler else { return }
    self.handler = nil
    cancelSafetyNet?()
    cancelSafetyNet = nil
    completedStatus = status
    handler(status)
    if status != .success { dismissSheet() }
  }

  private func dismissSheet() {
    guard !dismissing, !finished else { return }
    dismissing = true
    guard let sheet else {
      markFinished()
      return
    }
    sheet.dismiss { [weak self] in self?.markFinished() }
  }

  private func markFinished() {
    guard !finished else { return }
    finished = true
    sheet = nil
    cancelSafetyNet?()
    cancelSafetyNet = nil
    replyPresent(["event": "closed"])
    let replies = completeReplies
    completeReplies = []
    let status = Self.name(completedStatus ?? .failure)
    replies.forEach { $0(["status": status]) }
  }

  private func replyPresent(_ value: [String: Any]) {
    guard let reply = presentReply else { return }
    presentReply = nil
    reply(value)
  }

  static func name(_ status: PKPaymentAuthorizationStatus) -> String {
    status == .success ? "success" : "failure"
  }

  // MARK: - PKPaymentAuthorizationControllerDelegate

  func paymentAuthorizationController(
    _ controller: PKPaymentAuthorizationController, didAuthorizePayment payment: PKPayment,
    handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
  ) {
    authorized(paymentData: payment.token.paymentData) { status in
      completion(PKPaymentAuthorizationResult(status: status, errors: nil))
    }
  }

  func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
    sheetDidFinish()
  }
}
