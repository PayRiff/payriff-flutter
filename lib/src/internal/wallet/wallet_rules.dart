/// CONTRACT §17 (`vectors/wallet.json`): the pure rules of Apple Pay and
/// Google Pay. Which wallet a platform has and when it is offered, the
/// values both wallets share, the Google Pay JSON, the Apple Pay request,
/// the `/pay` body, how the Apple Pay sheet is completed and how the buttons
/// look. No I/O and no widgets.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../card/client_order.dart';
import '../../config.dart';
import '../../error.dart';
import '../../result.dart';
import '../../status.dart';
import '../../wallet/wallet_button_style.dart';
import '../amount.dart';
import '../request.dart';

/// A wallet the SDK can pay with.
enum WalletKind {
  /// Apple Pay, on iOS (PassKit).
  applePay(
    method: 'APPLE_PAY',
    label: 'Apple Pay',
    viewType: 'payriff/apple_pay_button',
  ),

  /// Google Pay, on Android (the Google Pay API).
  googlePay(
    method: 'GOOGLE_PAY',
    label: 'Google Pay',
    viewType: 'payriff/google_pay_button',
  );

  const WalletKind({
    required this.method,
    required this.label,
    required this.viewType,
  });

  /// The order's payment method and the `/pay` body's `method`.
  final String method;

  /// The name in log lines and messages.
  final String label;

  /// The platform view type of the official button (CONTRACT §17.10).
  final String viewType;
}

/// The wallet of the platform the app runs on: Apple Pay on iOS, Google Pay
/// on Android, otherwise none.
WalletKind? get platformWallet => switch (defaultTargetPlatform) {
  TargetPlatform.iOS => WalletKind.applePay,
  TargetPlatform.android => WalletKind.googlePay,
  _ => null,
};

/// How long the SDK may take after the Apple Pay authorization before it
/// completes the sheet (`wallet.json` → `applePaySheet.budgetSeconds`).
const Duration applePaySheetBudget = Duration(seconds: 20);

/// The Visa and Mastercard networks of the Apple Pay request and of
/// `canMakePayments` (CONTRACT §17.4), as `PKPaymentNetwork` names: region
/// [PayriffRegion.az]'s.
const List<String> applePayNetworks = <String>['visa', 'masterCard'];

/// The Apple Pay networks of [region] (CONTRACT §19.4, `wallet.json` →
/// `applePayNetworks`): [PayriffRegion.sa] adds mada, which needs the
/// country code `SA` that the region sets.
List<String> applePayNetworksFor(PayriffRegion region) => switch (region) {
  PayriffRegion.az => applePayNetworks,
  PayriffRegion.sa => const <String>['mada', 'visa', 'masterCard'],
};

/// The merchant capabilities of the Apple Pay request and of
/// `canMakePayments`, as `PKMerchantCapability` names.
const List<String> applePayCapabilities = <String>['threeDSecure'];

// ---------------------------------------------------------------------------
// Configuration (§17.2)

/// CONTRACT §17.2 (`wallet.json` → `googlePayMerchantIds`): the merchant ID
/// without surrounding white space; `null` when it is `null` or blank.
String? normalizedGooglePayMerchantId(String? value) => trimToNull(value);

/// Why `PayriffConfig.applePay` is not usable, for the warning of
/// `Payriff.configure` (`Invalid Apple Pay configuration: …`); `null` when
/// it is valid. Never quotes the value.
String? applePayConfigProblem(PayriffApplePayConfig config) {
  final String id = config.merchantIdentifier.trim();
  if (normalizedApplePayMerchantIdentifier(id) != null) return null;
  if (id.isEmpty) return 'merchantIdentifier is empty';
  if (!id.startsWith('merchant.') || id == 'merchant.') {
    return 'merchantIdentifier must be an Apple Pay merchant ID, for '
        'example merchant.com.example.shop';
  }
  return 'merchantIdentifier contains white space or a control character';
}

/// CONTRACT §17.3 item 1, the configuration part: why [kind] is off in
/// [config], or `null` when its configuration is set and valid.
String? walletConfigProblem(PayriffConfig? config, WalletKind kind) {
  switch (kind) {
    case WalletKind.applePay:
      final PayriffApplePayConfig? apple = config?.applePay;
      if (apple == null) return 'not configured';
      return normalizedApplePayMerchantIdentifier(apple.merchantIdentifier) ==
              null
          ? 'invalid configuration'
          : null;
    case WalletKind.googlePay:
      return config?.googlePay == null ? 'not configured' : null;
  }
}

// ---------------------------------------------------------------------------
// The order (§17.3 item 3)

/// CONTRACT §17.3 item 3 (`wallet.json` → `availability`): why [order]
/// cannot be paid with [kind], or `null` when it can. The status must be
/// `CREATED` or `PENDING`, and the order needs an amount and a currency to
/// fill the wallet's sheet. Its `paymentMethods` are not checked (revision
/// 10): the app's configuration decides. Google Pay also needs a gateway
/// merchant id, from the order or [googlePay] ([googlePayGateway]). Apple
/// Pay does not use the order's `applePay` part.
String? walletOrderProblem(
  PayriffClientOrder order,
  WalletKind kind, {
  PayriffGooglePayConfig? googlePay,
}) {
  if (order.status != PayriffPaymentStatus.created &&
      order.status != PayriffPaymentStatus.pending) {
    return 'order status ${order.rawStatus ?? 'unknown'}';
  }
  if (kind == WalletKind.googlePay &&
      googlePayGateway(order, googlePay) == null) {
    return 'no gatewayMerchantId';
  }
  if (formatAmount2(order.amount) == null) return 'no amount';
  if (walletCurrencyCode(order) == null) return 'no currency';
  return null;
}

/// The default tokenization `gateway` of Google Pay (CONTRACT §17.5).
const String googlePayDefaultGateway = 'payriff';

/// CONTRACT §17.5 (`wallet.json` → `googlePayGateway`): Google Pay's
/// tokenization parameters, each trimmed and skipped when blank.
/// `gatewayMerchantId` is the order's, else [config]'s; `gateway` the
/// order's, else [config]'s, else `payriff`. `null` without a
/// `gatewayMerchantId`: Google Pay is then not offered.
({String gateway, String gatewayMerchantId})? googlePayGateway(
  PayriffClientOrder order,
  PayriffGooglePayConfig? config,
) {
  final String? merchant =
      trimToNull(order.googlePay?.gatewayMerchantId) ??
      trimToNull(config?.gatewayMerchantId);
  if (merchant == null) return null;
  final String gateway =
      trimToNull(order.googlePay?.gateway) ??
      trimToNull(config?.gateway) ??
      googlePayDefaultGateway;
  return (gateway: gateway, gatewayMerchantId: merchant);
}

/// The availability line of CONTRACT §17.3, logged once per order:
/// `Apple Pay offered: true`, or `Apple Pay offered: false (<reason>)` with
/// the first condition that failed.
String walletDecisionLine(WalletKind kind, String? problem) =>
    '${kind.label} offered: ${problem == null}'
    '${problem == null ? '' : ' ($problem)'}';

/// How long the payment view waits for the device check (CONTRACT §17.3
/// item 4) after the order arrived, before it shows the order without the
/// wallet (§20.3, `wallet.json` → `viewReveal.waitMs`).
const Duration walletDeviceCheckWait = Duration(seconds: 1);

/// The reason of the availability line when the device check did not
/// answer within [walletDeviceCheckWait] (CONTRACT §20.3).
const String walletDeviceCheckLate = 'the device check did not answer in time';

// ---------------------------------------------------------------------------
// Shared values (§17.4)

/// The country of [region]: `AZ` or `SA`.
String walletCountryCode(PayriffRegion region) => switch (region) {
  PayriffRegion.az => 'AZ',
  PayriffRegion.sa => 'SA',
};

/// The order's currency, trimmed and upper-cased; `null` when blank.
String? walletCurrencyCode(PayriffClientOrder order) =>
    trimToNull(order.currency)?.toUpperCase();

/// The merchant name of the wallet's sheet: the wallet configuration's
/// name, else the order's, else the app's display name. Each is trimmed and
/// skipped when blank.
String? walletMerchantName({
  String? configName,
  String? orderName,
  String? appName,
}) => trimToNull(configName) ?? trimToNull(orderName) ?? trimToNull(appName);

/// The Google Pay environment (`wallet.json` → `googlePayEnvironments`):
/// `TEST` for Payriff's sandbox host, otherwise `PRODUCTION`.
String googlePayEnvironment(PayriffConfig config) =>
    config.apiBaseUrl == 'https://sb-api.payriff.com' ? 'TEST' : 'PRODUCTION';

// ---------------------------------------------------------------------------
// Google Pay JSON (§17.5)

Map<String, Object?> _googlePayCardMethod() => <String, Object?>{
  'type': 'CARD',
  'parameters': <String, Object?>{
    'allowedAuthMethods': <String>['PAN_ONLY', 'CRYPTOGRAM_3DS'],
    'allowedCardNetworks': <String>['VISA', 'MASTERCARD'],
  },
};

/// The `isReadyToPayRequest` (`wallet.json` → `googlePayRequests`): one
/// `CARD` method with the networks and auth methods, no tokenization.
Map<String, Object?> googlePayIsReadyToPayRequest() => <String, Object?>{
  'apiVersion': 2,
  'apiVersionMinor': 0,
  'allowedPaymentMethods': <Object?>[_googlePayCardMethod()],
};

/// The `allowedPaymentMethods` of the `paymentDataRequest`, also given to
/// the Google Pay button (`buttonAllowedPaymentMethods`): the `CARD` method
/// with the gateway parameters of [order] and [config]
/// ([googlePayGateway]). `null` without a gateway merchant id.
List<Object?>? googlePayAllowedPaymentMethods(
  PayriffClientOrder order,
  PayriffGooglePayConfig? config,
) {
  final ({String gateway, String gatewayMerchantId})? gateway =
      googlePayGateway(order, config);
  if (gateway == null) return null;
  return <Object?>[
    <String, Object?>{
      ..._googlePayCardMethod(),
      'tokenizationSpecification': <String, Object?>{
        'type': 'PAYMENT_GATEWAY',
        'parameters': <String, Object?>{
          'gateway': gateway.gateway,
          'gatewayMerchantId': gateway.gatewayMerchantId,
        },
      },
    },
  ];
}

/// The `paymentDataRequest` for [order] (`wallet.json` →
/// `googlePayRequests`), or `null` when the order cannot fill one (see
/// [walletOrderProblem]).
Map<String, Object?>? googlePayPaymentDataRequest({
  required PayriffClientOrder order,
  required PayriffRegion region,
  required PayriffGooglePayConfig config,
  String? appName,
}) {
  final List<Object?>? methods = googlePayAllowedPaymentMethods(order, config);
  final String? amount = formatAmount2(order.amount);
  final String? currency = walletCurrencyCode(order);
  if (methods == null || amount == null || currency == null) return null;
  final String? merchantName = walletMerchantName(
    configName: config.merchantName,
    orderName: order.merchantName,
    appName: appName,
  );
  final String? merchantId = normalizedGooglePayMerchantId(config.merchantId);
  return <String, Object?>{
    'apiVersion': 2,
    'apiVersionMinor': 0,
    'merchantInfo': <String, Object?>{
      'merchantName': ?merchantName,
      'merchantId': ?merchantId,
    },
    'allowedPaymentMethods': methods,
    'transactionInfo': <String, Object?>{
      'totalPriceStatus': 'FINAL',
      'totalPrice': amount,
      'currencyCode': currency,
      'countryCode': walletCountryCode(region),
    },
  };
}

// ---------------------------------------------------------------------------
// Apple Pay request (§17.6)

/// The Apple Pay request for [order] (`wallet.json` → `applePayRequests`),
/// as the plugin builds its `PKPaymentRequest` from it, or `null` when the
/// configuration is invalid or the order cannot fill one. The amount is the
/// 2-decimal text that the plugin reads with the POSIX locale; there are no
/// shipping or billing contact fields.
Map<String, Object?>? applePayRequest({
  required PayriffClientOrder order,
  required PayriffRegion region,
  required PayriffApplePayConfig config,
  String? appName,
}) {
  final String? merchantIdentifier = normalizedApplePayMerchantIdentifier(
    config.merchantIdentifier,
  );
  final String? amount = formatAmount2(order.amount);
  final String? currency = walletCurrencyCode(order);
  if (merchantIdentifier == null || amount == null || currency == null) {
    return null;
  }
  return <String, Object?>{
    'merchantIdentifier': merchantIdentifier,
    'countryCode': walletCountryCode(region),
    'currencyCode': currency,
    'supportedNetworks': applePayNetworksFor(region),
    'merchantCapabilities': applePayCapabilities,
    'summaryItems': <Object?>[
      <String, Object?>{
        'label':
            walletMerchantName(
              configName: config.merchantName,
              orderName: order.merchantName,
              appName: appName,
            ) ??
            '',
        'amount': amount,
        'type': 'final',
      },
    ],
  };
}

// ---------------------------------------------------------------------------
// Pay request (§17.7)

/// The wallet `/pay` body (`wallet.json` → `payRequests`), byte-exact:
/// `{"method":"GOOGLE_PAY"|"APPLE_PAY","encryptedMessage":"<token>"}` with
/// the token exactly as the wallet returned it, not re-encoded and not
/// wrapped.
Uint8List walletPayBody(WalletKind kind, String token) => utf8.encode(
  jsonEncode(<String, Object?>{
    'method': kind.method,
    'encryptedMessage': token,
  }),
);

// ---------------------------------------------------------------------------
// The Apple Pay sheet (§17.6 step 3)

/// How the Apple Pay sheet is completed.
enum ApplePaySheetStatus {
  /// `PKPaymentAuthorizationStatus.success`.
  success,

  /// `PKPaymentAuthorizationStatus.failure`. The SDK then dismisses the
  /// sheet itself, so the customer cannot authorize again in it.
  failure,
}

/// What the flow does once the Apple Pay sheet is completed.
enum ApplePaySheetThen {
  /// Return the result when the sheet is gone.
  returnResult,

  /// Continue after the sheet is gone: open the 3-D Secure sheet, or keep
  /// polling.
  continueAfterSheet,
}

/// The situations of the Apple Pay sheet table (`wallet.json` →
/// `applePaySheet.cases[].outcome`).
enum ApplePayOutcome {
  /// A final success status.
  finalSuccess,

  /// A final declined status.
  finalDeclined,

  /// A final `CANCELED` or `EXPIRED` status.
  finalCancelled,

  /// A final status outside the groups, such as `REFUNDED`.
  finalUnexpected,

  /// `failed(…)` from `/pay` or the flow.
  failed,

  /// The device check right before `/pay` refused the device.
  deviceCompromised,

  /// `nextAction` challenge.
  challenge,

  /// `nextAction` redirect.
  redirect,

  /// No final status within [applePaySheetBudget].
  budgetExpired,
}

/// The Apple Pay sheet table (`wallet.json` → `applePaySheet`).
({ApplePaySheetStatus sheet, ApplePaySheetThen then}) applePaySheetRule(
  ApplePayOutcome outcome,
) => switch (outcome) {
  ApplePayOutcome.finalSuccess => (
    sheet: ApplePaySheetStatus.success,
    then: ApplePaySheetThen.returnResult,
  ),
  ApplePayOutcome.finalDeclined ||
  ApplePayOutcome.finalCancelled ||
  ApplePayOutcome.finalUnexpected ||
  ApplePayOutcome.failed ||
  ApplePayOutcome.deviceCompromised => (
    sheet: ApplePaySheetStatus.failure,
    then: ApplePaySheetThen.returnResult,
  ),
  ApplePayOutcome.challenge ||
  ApplePayOutcome.redirect ||
  ApplePayOutcome.budgetExpired => (
    sheet: ApplePaySheetStatus.success,
    then: ApplePaySheetThen.continueAfterSheet,
  ),
};

/// The situation of a flow that ended with [result] while the Apple Pay
/// sheet was still up. A pending result without a final status (the status
/// could not be read, or polling ended) counts as
/// [ApplePayOutcome.budgetExpired]: the payment may still complete, so the
/// sheet does not say that it failed.
ApplePayOutcome applePayOutcomeOf(PayriffResult result) => switch (result) {
  PayriffResultSuccess() => ApplePayOutcome.finalSuccess,
  PayriffResultDeclined() => ApplePayOutcome.finalDeclined,
  PayriffResultCancelled() => ApplePayOutcome.finalCancelled,
  PayriffResultPending(reason: PayriffPendingReason.unexpectedStatus) =>
    ApplePayOutcome.finalUnexpected,
  PayriffResultPending() => ApplePayOutcome.budgetExpired,
  PayriffResultFailed(:final PayriffError error) =>
    error.code == PayriffErrorCode.deviceCompromised
        ? ApplePayOutcome.deviceCompromised
        : ApplePayOutcome.failed,
};

// ---------------------------------------------------------------------------
// Buttons (§17.9, §17.10)

/// The height of a wallet button outside the payment view, and the payment
/// view's default `buttonHeight` (`wallet.json` → `buttonStyles`).
const double walletDefaultButtonHeight = 44;

/// The corner radius of a wallet button outside the payment view, and the
/// payment view's default `buttonCornerRadius`.
const double walletDefaultCornerRadius = 16;

/// The lowest wallet button height.
const double walletMinButtonHeight = 40;

/// The button height: [height], else [fallback], raised to
/// [walletMinButtonHeight].
double walletButtonHeight(double? height, double fallback) {
  final double value = height != null && height.isFinite
      ? height
      : (fallback.isFinite ? fallback : walletDefaultButtonHeight);
  return value >= walletMinButtonHeight ? value : walletMinButtonHeight;
}

/// The wallet button's height in the payment view (CONTRACT §20.2,
/// `wallet.json` → `viewWalletHeight`): the wallet style's [styleHeight],
/// else [payButtonHeight], the Pay button's height as laid out (at least
/// the view's `buttonHeight`, taller at large text sizes); raised to
/// [walletMinButtonHeight] either way. The view lays the wallet button out
/// by this rule in Pay's layout pass.
double paymentViewWalletButtonHeight(
  double? styleHeight,
  double payButtonHeight,
) => walletButtonHeight(styleHeight, payButtonHeight);

/// The corner radius: [radius], else [fallback]; a negative radius counts
/// as 0.
double walletButtonCornerRadius(double? radius, double fallback) {
  final double value = radius ?? fallback;
  return value.isFinite && value > 0 ? value : 0;
}

/// The `PKPaymentButtonStyle` name of [theme]. Flutter resolves
/// `automatic` from the page: `black` on a light page, `white` on a dark one
/// (`wallet.json` → `buttonStyles.applePay.flutterAutomatic`).
String applePayButtonTheme(
  PayriffApplePayButtonTheme theme, {
  required bool dark,
}) => theme == PayriffApplePayButtonTheme.automatic
    ? (dark ? 'white' : 'black')
    : theme.name;

/// The `ButtonConstants.ButtonType` name of [type].
String googlePayButtonType(PayriffGooglePayButtonType type) =>
    type.name.toUpperCase();

/// The `ButtonConstants.ButtonTheme` name of [theme]. `automatic` is a dark
/// button on a light page and a light button on a dark one
/// (`wallet.json` → `buttonStyles.googlePay.automatic`).
String googlePayButtonTheme(
  PayriffGooglePayButtonTheme theme, {
  required bool dark,
}) => switch (theme) {
  PayriffGooglePayButtonTheme.automatic => dark ? 'LIGHT' : 'DARK',
  PayriffGooglePayButtonTheme.dark => 'DARK',
  PayriffGooglePayButtonTheme.light => 'LIGHT',
};

/// The creation parameters of the Apple Pay button's platform view: style
/// values only.
Map<String, Object?> applePayButtonParams(
  PayriffApplePayButtonStyle style, {
  required bool dark,
  required double cornerRadius,
}) => <String, Object?>{
  'type': style.type.name,
  'theme': applePayButtonTheme(style.theme, dark: dark),
  'cornerRadius': cornerRadius,
};

/// The creation parameters of the Google Pay button's platform view: style
/// values and the `buttonAllowedPaymentMethods` JSON. The corner radius is
/// in logical pixels; the plugin converts it to device pixels.
Map<String, Object?> googlePayButtonParams(
  PayriffGooglePayButtonStyle style, {
  required bool dark,
  required double cornerRadius,
  required List<Object?> allowedPaymentMethods,
}) => <String, Object?>{
  'type': googlePayButtonType(style.type),
  'theme': googlePayButtonTheme(style.theme, dark: dark),
  'cornerRadius': cornerRadius,
  'allowedPaymentMethods': jsonEncode(allowedPaymentMethods),
};
