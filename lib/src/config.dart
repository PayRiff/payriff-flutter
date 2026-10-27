import 'package:flutter/foundation.dart';

/// The Payriff environment the SDK talks to. Together with [PayriffRegion]
/// it picks the API host, [PayriffConfig.apiBaseUrl].
enum PayriffEnvironment {
  /// Live payments: the Client API of the region, `https://api.payriff.com`
  /// for [PayriffRegion.az].
  production,

  /// Test payments with Payriff's sandbox cards: the Client API at
  /// `https://sb-api.payriff.com`, region [PayriffRegion.az]'s sandbox. That
  /// host is provisional until Payriff confirms it (CONTRACT §16.2).
  ///
  /// [PayriffRegion.sa] has no sandbox: its sandbox payments go to
  /// production (`https://api.gccpay.sa`) and charge real cards.
  sandbox,
}

/// The Payriff region whose Client API the SDK talks to (CONTRACT §16.2).
enum PayriffRegion {
  /// Azerbaijan, the default: `https://api.payriff.com`, and
  /// `https://sb-api.payriff.com` in [PayriffEnvironment.sandbox].
  az,

  /// Saudi Arabia (GCC Pay): `https://api.gccpay.sa`.
  ///
  /// There is no Saudi sandbox: [PayriffEnvironment.sandbox] uses
  /// `https://api.gccpay.sa` too, so its payments charge real cards, and
  /// `Payriff.configure` logs a warning.
  sa,
}

/// Languages of the SDK's card form and 3-D Secure sheet.
enum PayriffLanguage {
  /// Azerbaijani.
  az('AZ'),

  /// English.
  en('EN'),

  /// Russian.
  ru('RU');

  const PayriffLanguage(this.value);

  /// The upper-case code (`AZ`, `EN` or `RU`).
  final String value;
}

/// SDK-wide configuration, passed to `Payriff.configure`.
///
/// The app needs only the [publishableKey]: your server creates each order
/// with its secret key and hands the app the order's `orderId` and
/// `clientSecret`. The secret key never ships in the app.
///
/// `Payriff.configure` never throws. A missing or invalid publishable key
/// makes `Payriff.confirmCardPayment` and `Payriff.retrieveOrder` fail with
/// `PayriffErrorCode.invalidConfig`.
@immutable
final class PayriffConfig {
  /// Creates a configuration. Every field is optional.
  const PayriffConfig({
    this.publishableKey,
    this.environment = PayriffEnvironment.production,
    this.region = PayriffRegion.az,
    this.language,
    this.enableLogging = false,
    this.allowCompromisedDevices = false,
  });

  /// The publishable key (`pr_pk_live_…`) of your Payriff application, sent
  /// as `X-Public-Key`.
  ///
  /// It is safe to ship in the app: it only works together with an order's
  /// `clientSecret`. Surrounding whitespace is removed. A key without the
  /// `pr_pk_live_` prefix (for example the secret key) is refused: the card
  /// calls fail with `PayriffErrorCode.invalidConfig`.
  final String? publishableKey;

  /// The Payriff environment. Defaults to [PayriffEnvironment.production].
  final PayriffEnvironment environment;

  /// The Payriff region. Defaults to [PayriffRegion.az].
  ///
  /// [PayriffRegion.sa] has no sandbox: with [PayriffEnvironment.sandbox],
  /// payments go to production and charge real cards.
  final PayriffRegion region;

  /// The language of the card form and of the 3-D Secure sheet. `null` uses
  /// the device language (Azerbaijani, Russian, otherwise English).
  final PayriffLanguage? language;

  /// Whether the SDK emits log entries to `Payriff.logStream` and, in debug
  /// builds, the console.
  final bool enableLogging;

  /// Whether card payments may run on a compromised device (CONTRACT
  /// §16.16): rooted or jailbroken, with a hooking framework such as Frida
  /// loaded, or with a debugger attached to a release build. A device whose
  /// check cannot complete counts as compromised too.
  ///
  /// `false` (the default) refuses them: `Payriff.confirmCardPayment` fails
  /// with `PayriffErrorCode.deviceCompromised` and `PayriffPaymentView` says
  /// that card payments are not available on this device. `true` only logs a
  /// warning that names what was found, for development on a rooted or
  /// jailbroken test device.
  ///
  /// `true` works only in debug builds (`kDebugMode`). Profile and release
  /// builds ignore it: compromised devices are refused as with `false`, and
  /// the log says that the flag is ignored outside debug builds. So a flag
  /// left on never reaches the app you ship.
  final bool allowCompromisedDevices;

  /// The Client API base URL of [region] and [environment] (CONTRACT
  /// §16.2), without a trailing slash. Every card call, the 3-D Secure
  /// callback check, certificate pinning and log redaction use its host.
  ///
  /// * [PayriffRegion.az]: `https://api.payriff.com`, and
  ///   `https://sb-api.payriff.com` in [PayriffEnvironment.sandbox] (that
  ///   host is provisional).
  /// * [PayriffRegion.sa]: `https://api.gccpay.sa` in both environments.
  ///   There is no Saudi sandbox: sandbox payments charge real cards.
  String get apiBaseUrl => switch ((region, environment)) {
    (PayriffRegion.az, PayriffEnvironment.production) =>
      'https://api.payriff.com',
    // Provisional until Payriff confirms it; it lives only here.
    (PayriffRegion.az, PayriffEnvironment.sandbox) =>
      'https://sb-api.payriff.com',
    (PayriffRegion.sa, PayriffEnvironment.production) =>
      'https://api.gccpay.sa',
    // No Saudi sandbox (owner decision 2026-10-27): sandbox payments go to
    // production.
    (PayriffRegion.sa, PayriffEnvironment.sandbox) => 'https://api.gccpay.sa',
  };

  /// A description without secrets: the publishable key is shown as
  /// `***(<length>)`.
  @override
  String toString() {
    final String? publishable = publishableKey?.trim();
    final String publishableText = publishable == null || publishable.isEmpty
        ? 'null'
        : '***(${publishable.length})';
    return 'PayriffConfig(environment: ${environment.name}, '
        'region: ${region.name}, language: ${language?.value}, '
        'enableLogging: $enableLogging, '
        'allowCompromisedDevices: $allowCompromisedDevices, '
        'publishableKey: $publishableText)';
  }
}
