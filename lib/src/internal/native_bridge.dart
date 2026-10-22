import 'dart:async';

import 'package:flutter/services.dart';

import '../error.dart';

/// What the native device integrity checks found (CONTRACT §16.16):
/// whether the device is compromised and the names of the signals that
/// matched, for example `su binary` or `Frida`.
typedef DeviceIntegrityReport = ({bool compromised, List<String> signals});

/// The one wrapper around the plugin's `payriff/native` method channel
/// (CONTRACT §16.11): card encryption, the app id, screen protection,
/// hardened external launches, the removal of 3-D Secure website data
/// (§9.1a) and the device integrity checks (§16.16). Nothing else in the SDK
/// touches the channel.
///
/// Arguments and replies are never logged: `encryptCard` carries card data.
abstract final class NativeBridge {
  /// The channel. Tests mock it with
  /// `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
  /// .setMockMethodCallHandler`.
  static const MethodChannel channel = MethodChannel('payriff/native');

  static Future<String?>? _appId;

  /// CONTRACT §16.6: encrypts the card JSON [card] (UTF-8) with a fresh
  /// AES-256-GCM key and IV, wrapped with RSA-OAEP-SHA-256 under [spki].
  ///
  /// Returns `encryptedMessage` (Base64 ciphertext‖tag) and `wrappedKey`
  /// (Base64 RSA ciphertext, sent as `x-secret-key`). Throws a
  /// [PayriffException] when the device cannot encrypt; the error never
  /// carries the platform's message or details.
  static Future<({String encryptedMessage, String wrappedKey})> encryptCard(
    Uint8List card,
    Uint8List spki,
  ) async {
    final Object? reply;
    try {
      reply = await channel.invokeMethod<Object?>(
        'encryptCard',
        <String, Object?>{'card': card, 'spki': spki},
      );
    } on PlatformException catch (e) {
      throw _encryptionFailed(e.code);
    } on MissingPluginException {
      throw _encryptionFailed('missing_plugin');
    }
    if (reply is Map) {
      final Object? message = reply['encryptedMessage'];
      final Object? key = reply['wrappedKey'];
      if (message is String &&
          message.isNotEmpty &&
          key is String &&
          key.isNotEmpty) {
        return (encryptedMessage: message, wrappedKey: key);
      }
    }
    throw _encryptionFailed('invalid_reply');
  }

  static PayriffException _encryptionFailed(String reason) => PayriffException(
    PayriffError(
      code: PayriffErrorCode.unknown,
      message: 'The card could not be encrypted on this device ($reason).',
    ),
  );

  /// The app's identity for `X-Client-App-Id`: the iOS bundle id or the
  /// Android package name. `null` when unknown (the header is then
  /// omitted). Asked once per process.
  static Future<String?> appId() => _appId ??= _readAppId();

  static final RegExp _appIdShape = RegExp(r'^[A-Za-z0-9._-]{1,255}$');

  static Future<String?> _readAppId() async {
    try {
      final String? id = await channel.invokeMethod<String>('appId');
      // Only a plain bundle id or package name becomes a header value.
      return id != null && _appIdShape.hasMatch(id) ? id : null;
    } on Object {
      return null;
    }
  }

  /// CONTRACT §16.0 item 4: screen protection, reference-counted by the
  /// native side (`true` adds one, `false` removes one). Never throws: a
  /// missing plugin must not break a payment.
  static Future<void> setSecure(bool secure) async {
    try {
      await channel.invokeMethod<void>('setSecure', <String, Object?>{
        'secure': secure,
      });
    } on Object {
      // Logged by nobody: the call has no payment data and no fallback.
    }
  }

  /// CONTRACT §7.5: opens [url] in another app through the native,
  /// hardened launcher (no `file:`/`content:`/`javascript:`/`data:`;
  /// Android `intent:` URLs without component, selector or URI grants).
  /// Returns whether an app handled it; `false` on any failure.
  static Future<bool> openExternal(String url) async {
    try {
      return await channel.invokeMethod<bool>('openExternal', <String, Object?>{
            'url': url,
          }) ??
          false;
    } on Object {
      return false;
    }
  }

  /// CONTRACT §9.1a: removes the website data that a payment's 3-D Secure
  /// WebViews left for the sites they loaded. iOS removes the default data
  /// store's records whose display name is one of [hosts] or a parent domain
  /// of one; Android deletes the web storage of [origins], expires the
  /// cookies of [urls] and clears the WebView cache. Completes when the
  /// native side is done.
  ///
  /// Throws when that fails (a [PlatformException], or a
  /// [MissingPluginException] without the plugin): the caller logs it and
  /// goes on.
  static Future<void> clearWebsiteData({
    required List<String> hosts,
    required List<String> origins,
    required List<String> urls,
  }) => channel.invokeMethod<void>('clearWebsiteData', <String, Object?>{
    'hosts': hosts,
    'origins': origins,
    'urls': urls,
  });

  // A signal name as the plugin reports it: a few words, never a path or
  // file contents.
  static final RegExp _signalShape = RegExp(r'^[A-Za-z0-9 _.\-]{1,40}$');

  /// CONTRACT §16.16: runs the plugin's root, jailbreak, hooking and
  /// debugger checks. The plugin may keep its root and jailbreak file
  /// results for the process; the hooking and debugger checks run at every
  /// call.
  ///
  /// `null` when the checks cannot complete (no plugin, a platform error, or
  /// a reply without a `compromised` flag); `deviceIntegrityReport` turns
  /// that into a compromised device (it fails closed). Signal names of
  /// another shape are dropped; a device with a signal counts as
  /// compromised. Never throws.
  static Future<DeviceIntegrityReport?> deviceIntegrity() async {
    final Object? reply;
    try {
      reply = await channel.invokeMethod<Object?>('deviceIntegrity');
    } on Object {
      return null;
    }
    if (reply is! Map) return null;
    final Object? compromised = reply['compromised'];
    if (compromised is! bool) return null;
    final Object? signals = reply['signals'];
    final List<String> names = <String>[
      if (signals is List)
        for (final Object? signal in signals)
          if (signal is String && _signalShape.hasMatch(signal)) signal,
    ];
    return (
      compromised: compromised || names.isNotEmpty,
      signals: List<String>.unmodifiable(names),
    );
  }

  /// Forgets the cached app id (`Payriff.debugReset`).
  static void resetCache() => _appId = null;
}
