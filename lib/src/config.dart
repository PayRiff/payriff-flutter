import 'package:flutter/foundation.dart';

/// The Payriff environment the SDK talks to.
enum PayriffEnvironment {
  /// Live payments: the Client API at `https://api.payriff.com`.
  production,

  /// Test payments with Payriff's sandbox cards: the Client API at
  /// `https://sb-api.payriff.com`. That host is provisional until Payriff
  /// confirms it (CONTRACT §16.2).
  sandbox,
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
  /// warning that names what was found. Set it only for development on a
  /// rooted or jailbroken test device, never in an app you ship.
  final bool allowCompromisedDevices;

  /// A description without secrets: the publishable key is shown as
  /// `***(<length>)`.
  @override
  String toString() {
    final String? publishable = publishableKey?.trim();
    final String publishableText = publishable == null || publishable.isEmpty
        ? 'null'
        : '***(${publishable.length})';
    return 'PayriffConfig(environment: ${environment.name}, '
        'language: ${language?.value}, enableLogging: $enableLogging, '
        'allowCompromisedDevices: $allowCompromisedDevices, '
        'publishableKey: $publishableText)';
  }
}
