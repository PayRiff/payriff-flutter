import 'package:payriff/payriff.dart';

// Build-time defaults from example/config.json (git-ignored):
//   flutter run --dart-define-from-file=config.json
// Copy config.example.json to config.json and fill in the publishable key.
// The app reads only these two keys. It has no secret key: orders come from
// your server.
const String _envEnvironment = String.fromEnvironment(
  'PAYRIFF_ENVIRONMENT',
  defaultValue: 'sandbox',
);
// The publishable key (pr_pk_live_…) is meant to ship in apps: it only works
// together with an order's clientSecret.
const String _envPublishableKey = String.fromEnvironment(
  'PAYRIFF_PUBLISHABLE_KEY',
);

/// The settings of the example app, from `--dart-define-from-file`.
class ExampleSettings {
  ExampleSettings({
    required this.environment,
    this.publishableKey = '',
    this.language,
    this.enableLogging = true,
  });

  /// Defaults from `--dart-define-from-file=config.json`.
  factory ExampleSettings.fromEnvironment() => ExampleSettings(
    environment: _envEnvironment.toLowerCase() == 'production'
        ? PayriffEnvironment.production
        : PayriffEnvironment.sandbox,
    publishableKey: _envPublishableKey,
  );

  PayriffEnvironment environment;

  /// The publishable key; empty shows the "add a publishable key" message on
  /// the home screen.
  String publishableKey;

  /// `null` uses the device language ("Auto").
  PayriffLanguage? language;

  bool enableLogging;

  bool get hasPublishableKey => publishableKey.trim().isNotEmpty;

  PayriffConfig toConfig() => PayriffConfig(
    publishableKey: hasPublishableKey ? publishableKey.trim() : null,
    environment: environment,
    language: language,
    enableLogging: enableLogging,
  );
}
