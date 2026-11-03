import 'package:payriff/payriff.dart';

// Build-time defaults from example/config.json (git-ignored):
//   flutter run --dart-define-from-file=config.json
// Copy config.example.json to config.json and fill in the publishable key.
// The app reads only the keys below. It has no secret key: orders come from
// your server.
const String _envEnvironment = String.fromEnvironment(
  'PAYRIFF_ENVIRONMENT',
  defaultValue: 'sandbox',
);
// `az` (api.payriff.com) or `sa` (api.gccpay.sa). Region sa has no sandbox:
// with PAYRIFF_ENVIRONMENT sandbox it still charges real cards.
const String _envRegion = String.fromEnvironment(
  'PAYRIFF_REGION',
  defaultValue: 'az',
);
// The publishable key (pr_pk_live_…) is meant to ship in apps: it only works
// together with an order's clientSecret.
const String _envPublishableKey = String.fromEnvironment(
  'PAYRIFF_PUBLISHABLE_KEY',
);
// Apple Pay on iOS: your Apple Pay merchant ID (merchant.…). Empty leaves
// Apple Pay off. The Runner target also needs the Apple Pay capability with
// that merchant ID (see README.md).
const String _envApplePayMerchantId = String.fromEnvironment(
  'PAYRIFF_APPLE_PAY_MERCHANT_ID',
);
// Google Pay on Android: true or false.
const String _envGooglePay = String.fromEnvironment(
  'PAYRIFF_GOOGLE_PAY',
  defaultValue: 'false',
);
// Optional: your merchant ID from the Google Pay & Wallet Console.
const String _envGooglePayMerchantId = String.fromEnvironment(
  'PAYRIFF_GOOGLE_PAY_MERCHANT_ID',
);

/// The settings of the example app, from `--dart-define-from-file`.
class ExampleSettings {
  ExampleSettings({
    required this.environment,
    this.region = PayriffRegion.az,
    this.publishableKey = '',
    this.language,
    this.enableLogging = true,
    this.applePayMerchantId = '',
    this.googlePay = false,
    this.googlePayMerchantId = '',
  });

  /// Defaults from `--dart-define-from-file=config.json`.
  factory ExampleSettings.fromEnvironment() => ExampleSettings(
    environment: _envEnvironment.toLowerCase() == 'production'
        ? PayriffEnvironment.production
        : PayriffEnvironment.sandbox,
    region: _envRegion.toLowerCase() == 'sa'
        ? PayriffRegion.sa
        : PayriffRegion.az,
    publishableKey: _envPublishableKey,
    applePayMerchantId: _envApplePayMerchantId,
    googlePay: _envGooglePay.trim().toLowerCase() == 'true',
    googlePayMerchantId: _envGooglePayMerchantId,
  );

  PayriffEnvironment environment;

  /// The region; [PayriffRegion.sa] has no sandbox.
  PayriffRegion region;

  /// The publishable key; empty shows the "add a publishable key" message on
  /// the home screen.
  String publishableKey;

  /// `null` uses the device language ("Auto").
  PayriffLanguage? language;

  bool enableLogging;

  /// Your Apple Pay merchant ID; empty leaves Apple Pay off.
  String applePayMerchantId;

  /// Whether Google Pay is on.
  bool googlePay;

  /// Your Google Pay merchant ID; empty leaves it out of the request.
  String googlePayMerchantId;

  bool get hasPublishableKey => publishableKey.trim().isNotEmpty;

  PayriffConfig toConfig() => PayriffConfig(
    publishableKey: hasPublishableKey ? publishableKey.trim() : null,
    environment: environment,
    region: region,
    language: language,
    enableLogging: enableLogging,
    applePay: applePayMerchantId.trim().isEmpty
        ? null
        : PayriffApplePayConfig(merchantIdentifier: applePayMerchantId.trim()),
    googlePay: googlePay
        ? PayriffGooglePayConfig(
            merchantId: googlePayMerchantId.trim().isEmpty
                ? null
                : googlePayMerchantId.trim(),
          )
        : null,
  );
}
