import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'card/card_form.dart';
import 'card/card_types.dart';
import 'card/client_order.dart';
import 'config.dart';
import 'error.dart';
import 'internal/card/card_clock.dart';
import 'internal/card/card_crypto.dart';
import 'internal/card/card_flow.dart';
import 'internal/card/client_api.dart';
import 'internal/card/device_integrity.dart';
import 'internal/language.dart';
import 'internal/logger.dart';
import 'internal/native_bridge.dart';
import 'internal/payment_support.dart';
import 'internal/request.dart';
import 'internal/strings.dart';
import 'internal/ui/presenter.dart';
import 'internal/ui/three_ds_presentation.dart';
import 'internal/wallet/wallet_rules.dart';
import 'log.dart';
import 'result.dart';

/// The Payriff SDK entry point.
///
/// 1. Call [configure] once, for example in `main`, with your publishable
///    key.
/// 2. Your server creates the order with its secret key and gives the app
///    the order's `orderId` and `clientSecret`.
/// 3. Show a [PayriffCardForm] and call [confirmCardPayment] with its
///    controller.
/// 4. Handle the returned [PayriffResult]. Only [PayriffResultSuccess] is
///    shown as paid; your server fulfils the order once it has confirmed the
///    payment with Payriff.
///
/// `PayriffPaymentView` does all of this for you, and adds Apple Pay or
/// Google Pay above the card form when `PayriffConfig.applePay` or
/// `PayriffConfig.googlePay` is set.
///
/// ```dart
/// Payriff.configure(const PayriffConfig(
///   publishableKey: 'pr_pk_live_…',
///   environment: PayriffEnvironment.sandbox,
/// ));
/// final order = await myBackend.startCheckout(cart);
/// final result = await Payriff.confirmCardPayment(
///   context,
///   cardController,
///   orderId: order.orderId,
///   clientSecret: order.clientSecret,
/// );
/// ```
abstract final class Payriff {
  /// The version of this package.
  static const String version = '1.0.0-rc.3';

  static PayriffConfig? _config;

  /// The configuration passed to [configure], or `null`.
  static PayriffConfig? get config => _config;

  /// Whether a payment is running: [confirmCardPayment], or an Apple Pay or
  /// Google Pay payment of `PayriffPaymentView`, `PayriffApplePayButton` or
  /// `PayriffGooglePayButton`. Only one runs at a time.
  static bool get isPaymentInProgress => paymentInProgress;

  /// SDK log entries, emitted while `PayriffConfig.enableLogging` is on.
  ///
  /// This is a broadcast stream; entries emitted while nobody listens are
  /// dropped. In debug builds each entry's `formatted` line is also printed
  /// to the console; profile and release builds print nothing.
  static Stream<PayriffLogEntry> get logStream => sdkLogStream;

  /// Sets the SDK configuration. Calling it again replaces the configuration
  /// for later calls; a payment that is already running keeps the old one.
  ///
  /// Never throws. A publishable key that is not a `pr_pk_live_…` key is
  /// logged as a warning (`Invalid configuration: …`) and makes the card
  /// calls fail with [PayriffErrorCode.invalidConfig]. Outside debug builds
  /// `PayriffConfig.allowCompromisedDevices` is ignored, with a warning.
  /// [PayriffRegion.sa] with [PayriffEnvironment.sandbox] logs a warning:
  /// that region has no sandbox, so its payments charge real cards. An
  /// invalid `PayriffConfig.applePay` is logged as a warning
  /// (`Invalid Apple Pay configuration: …`) and leaves Apple Pay off; card
  /// payments are not affected.
  static void configure(PayriffConfig config) {
    _config = config;
    final SdkLogger logger = _loggerFor(config);
    final String? key = trimToNull(config.publishableKey);
    logger.info(
      'Configured: environment ${config.environment.name}, '
      'region ${config.region.name}, publishable key ${redactSecret(key)}',
    );
    // CONTRACT §16.2: region sa has no sandbox.
    if (config.region == PayriffRegion.sa &&
        config.environment == PayriffEnvironment.sandbox) {
      logger.warning(
        'Region sa has no sandbox: card payments go to production '
        '(${config.apiBaseUrl}) and charge real cards.',
      );
    }
    if (key != null && usablePublishableKey(key) == null) {
      logger.warning(
        'Invalid configuration: publishableKey is not a publishable key '
        '(pr_pk_live_…); confirmCardPayment and retrieveOrder fail with '
        'INVALID_CONFIG.',
      );
    }
    // CONTRACT §16.16: the opt-out works only in development builds.
    if (config.allowCompromisedDevices && !isDevelopmentBuild) {
      logger.warning(
        '$allowCompromisedDevicesIgnored: card payments are refused on '
        'compromised devices.',
      );
    }
    // CONTRACT §17.2: an invalid wallet configuration leaves that wallet off
    // and nothing else.
    final PayriffApplePayConfig? applePay = config.applePay;
    final String? applePayProblem = applePay == null
        ? null
        : applePayConfigProblem(applePay);
    if (applePayProblem != null) {
      logger.warning(
        'Invalid Apple Pay configuration: $applePayProblem; Apple Pay is off.',
      );
    }
  }

  /// Pays the order [orderId] with the card typed into the [PayriffCardForm]
  /// of [controller], and completes with the verified result
  /// (CONTRACT §16.7).
  ///
  /// Your server creates the order with its secret key and gives the app
  /// its `orderId` and `clientSecret`. The app needs only
  /// `PayriffConfig.publishableKey`; the secret key is never used.
  ///
  /// 1. The form is validated. Invalid fields are shown and the result is
  ///    [PayriffResultFailed] with [PayriffErrorCode.validationFailed] and
  ///    `PayriffError.fields`; no request is made.
  /// 2. The device is checked (CONTRACT §16.16). On a rooted or jailbroken
  ///    device, with a hooking framework or a debugger on a release build,
  ///    or when the check cannot complete, the result is
  ///    [PayriffErrorCode.deviceCompromised] and nothing is sent, unless
  ///    `PayriffConfig.allowCompromisedDevices` is set in a debug build
  ///    (profile and release builds ignore it). The check runs again right
  ///    before the card is encrypted.
  /// 3. The order must be `CREATED` or `PENDING` and accept `CARD`, else
  ///    [PayriffErrorCode.orderNotPayable].
  /// 4. The card is encrypted on the device and sent; the form is locked
  ///    meanwhile ([PayriffCardController.isProcessing]).
  /// 5. 3-D Secure runs in the SDK's sheet when the bank asks for it, then
  ///    the status is polled (every 2.5 s, up to 120 s).
  ///
  /// Once the card was sent the result is never `cancelled(userClosed)`:
  /// closing the 3-D Secure sheet checks the status once and gives
  /// [PayriffResultPending] unless it is final. The card values are cleared
  /// after a final result. Never throws.
  ///
  /// The result is for the user interface: fulfil the order on your server
  /// after it confirms the payment with Payriff.
  static Future<PayriffResult> confirmCardPayment(
    BuildContext context,
    PayriffCardController controller, {
    required String orderId,
    required String clientSecret,
  }) async {
    if (isPaymentInProgress) {
      return const PayriffResultFailed(error: paymentInProgressError);
    }
    final PayriffConfig? config = _config;
    if (config == null) {
      return PayriffResultFailed(
        error: notConfigured(
          'Call Payriff.configure before Payriff.confirmCardPayment.',
        ),
      );
    }
    final String? publishableKey = usablePublishableKey(config.publishableKey);
    if (publishableKey == null) {
      return PayriffResultFailed(error: publishableKeyError());
    }
    final String id = orderId.trim();
    final String? secret = usableClientSecret(clientSecret);
    final PayriffError? argumentError = orderArgumentError(id, secret);
    if (argumentError != null) {
      return PayriffResultFailed(error: argumentError);
    }
    final NavigatorState? navigator = context.mounted
        ? Navigator.maybeOf(context, rootNavigator: true)
        : null;
    if (navigator == null) {
      return const PayriffResultFailed(error: noNavigatorError);
    }

    // Step 1: validation, before any request.
    final CardFormCheck? check = checkCardForm(controller);
    if (check == null) {
      return const PayriffResultFailed(
        error: PayriffError(
          code: PayriffErrorCode.validationFailed,
          message:
              'Show a PayriffCardForm with this controller before calling '
              'confirmCardPayment.',
          fields: <PayriffCardFieldError>[],
        ),
      );
    }
    final CardPlaintext? card = check.card;
    if (card == null) {
      return PayriffResultFailed(
        error: PayriffError(
          code: PayriffErrorCode.validationFailed,
          message: 'The card details are not valid.',
          fields: List<PayriffCardFieldError>.unmodifiable(check.errors),
        ),
      );
    }

    final SdkLogger logger = _loggerFor(config);
    final PayriffStrings strings = PayriffStrings(
      config.language ?? deviceLanguage(),
    );
    final bool material = context.mounted
        ? SheetPresenter.prefersMaterial(context)
        : defaultTargetPlatform != TargetPlatform.iOS;
    final String apiBaseUrl = config.apiBaseUrl;
    // Claimed before the first await, so a second tap cannot start another
    // payment.
    paymentInProgress = true;
    setCardFormProcessing(controller, true);
    bool submitted = false;
    ClientApi? api;
    PayriffResult result;
    // CONTRACT §16.16: before anything is sent, and again right before the
    // card is encrypted.
    Future<PayriffError?> checkDevice(String point) => deviceIntegrityError(
      allowCompromisedDevices: config.allowCompromisedDevices,
      logger: logger,
      point: point,
    );
    try {
      final PayriffError? refused = await checkDevice('confirmCardPayment');
      if (refused != null) {
        result = PayriffResultFailed(error: refused);
      } else {
        final ClientApi client = api = ClientApi(
          baseUrl: apiBaseUrl,
          publishableKey: publishableKey,
          clientSecret: secret!,
          appId: await NativeBridge.appId(),
          clock: cardClock,
          logger: logger,
        );
        final CardPayment payment = CardPayment(
          api: client,
          orderId: id,
          clock: cardClock,
          strings: strings,
          logger: logger,
          onSubmitted: () => submitted = true,
          checkDevice: () => checkDevice('card encryption'),
          openSheet: (ThreeDsSession session) => presentThreeDsSheet(
            context.mounted ? context : navigator.context,
            navigator,
            material,
            strings,
            logger,
            session,
          ),
        );
        logger.info('confirmCardPayment: order $id');
        result = await payment.run(card);
      }
    } finally {
      paymentInProgress = false;
      api?.close();
      setCardFormProcessing(controller, false);
    }
    final PayriffPayment? paid = result.payment;
    logger.info(
      'Card payment finished: ${result.type}'
      '${paid == null ? '' : ' (${paid.status.value})'}'
      '${result.error == null ? '' : ' (${result.error!.code.value})'}',
    );
    // CONTRACT §16.5: the card values do not outlive a final result (or a
    // card that was sent, an order that can no longer be paid, or a device
    // the card may not be paid from).
    if (submitted ||
        result is! PayriffResultFailed ||
        result.error.isFatal ||
        result.error.code == PayriffErrorCode.orderNotPayable ||
        result.error.code == PayriffErrorCode.deviceCompromised) {
      clearCardForm(controller);
    }
    return result;
  }

  /// Reads the order [orderId] through the Client API
  /// (`GET /api/v3/client/orders/{orderId}`) with
  /// `PayriffConfig.publishableKey` and the order's [clientSecret], for
  /// example to show the amount next to the card form.
  ///
  /// Throws a [PayriffException]: [PayriffErrorCode.notConfigured] before
  /// [configure], [PayriffErrorCode.invalidConfig] without a usable
  /// publishable key, [PayriffErrorCode.invalidOrder] for an invalid id or
  /// client secret, and the Client API errors of CONTRACT §16.3.
  static Future<PayriffClientOrder> retrieveOrder({
    required String orderId,
    required String clientSecret,
  }) async {
    final PayriffConfig? config = _config;
    if (config == null) {
      throw PayriffException(
        notConfigured('Call Payriff.configure before Payriff.retrieveOrder.'),
      );
    }
    final String? publishableKey = usablePublishableKey(config.publishableKey);
    if (publishableKey == null) throw PayriffException(publishableKeyError());
    final String id = orderId.trim();
    final String? secret = usableClientSecret(clientSecret);
    final PayriffError? argumentError = orderArgumentError(id, secret);
    if (argumentError != null) throw PayriffException(argumentError);
    final ClientApi api = ClientApi(
      baseUrl: config.apiBaseUrl,
      publishableKey: publishableKey,
      clientSecret: secret!,
      appId: await NativeBridge.appId(),
      clock: cardClock,
      logger: _loggerFor(config),
    );
    try {
      return PayriffClientOrder.fromPayload(
        await api.retrieveOrder(id),
        requestedOrderId: id,
      );
    } finally {
      api.close();
    }
  }

  /// Whether this device is compromised (CONTRACT §16.16): rooted or
  /// jailbroken, with a hooking framework such as Frida loaded, or with a
  /// debugger attached to a release build. Card payments are refused on such
  /// a device unless `PayriffConfig.allowCompromisedDevices` is set in a
  /// debug build.
  ///
  /// Ask it early, for example to offer another payment method. It reports
  /// the device whatever `allowCompromisedDevices` says and needs no
  /// [configure]. Never throws: `true` when the checks cannot complete (for
  /// example without the plugin's native part), as a payment would then be
  /// refused too.
  static Future<bool> isDeviceCompromised() async =>
      (await deviceIntegrityReport()).compromised;

  /// Clears the configuration and the in-progress guard. For tests only.
  @visibleForTesting
  static void debugReset() {
    _config = null;
    paymentInProgress = false;
    NativeBridge.resetCache();
  }

  static SdkLogger _loggerFor(PayriffConfig config) => sdkLoggerFor(config);
}
