import 'dart:async';

import 'package:flutter/services.dart';

import '../error.dart';

/// What the native device integrity checks found (CONTRACT §16.16):
/// whether the device is compromised and the names of the signals that
/// matched, for example `su binary` or `Frida`.
typedef DeviceIntegrityReport = ({bool compromised, List<String> signals});

/// How the Apple Pay sheet of `applePayPresent` ended its first part
/// (CONTRACT §17.6).
sealed class ApplePaySheetEvent {
  const ApplePaySheetEvent();
}

/// The customer authorized the payment. The sheet waits, with its handler
/// open, until `applePayComplete`.
final class ApplePayAuthorized extends ApplePaySheetEvent {
  /// Creates the event for [paymentData].
  const ApplePayAuthorized(this.paymentData);

  /// `PKPaymentToken.paymentData` as UTF-8 text, unchanged; `null` when it
  /// is not UTF-8. The wallet token: never logged.
  final String? paymentData;

  @override
  String toString() => 'ApplePayAuthorized(<redacted>)';
}

/// The sheet closed without an authorization.
final class ApplePayClosed extends ApplePaySheetEvent {
  /// Creates the event.
  const ApplePayClosed();
}

/// The sheet could not be shown.
final class ApplePayNotPresented extends ApplePaySheetEvent {
  /// Creates the event.
  const ApplePayNotPresented();
}

/// The result of `googlePayLoad` (CONTRACT §17.5 step 3).
sealed class GooglePayLoadResult {
  const GooglePayLoadResult();
}

/// Google Pay returned payment data.
final class GooglePayOk extends GooglePayLoadResult {
  /// Creates the result for [token].
  const GooglePayOk(this.token);

  /// `paymentMethodData.tokenizationData.token`, exactly as Google Pay
  /// returned it; `null` when it was missing. The wallet token: never
  /// logged.
  final String? token;

  @override
  String toString() => 'GooglePayOk(<redacted>)';
}

/// The customer closed the Google Pay sheet.
final class GooglePayCancelled extends GooglePayLoadResult {
  /// Creates the result.
  const GooglePayCancelled();
}

/// Google Pay failed with the status [code].
final class GooglePayError extends GooglePayLoadResult {
  /// Creates the result for [code].
  const GooglePayError(this.code);

  /// The Google Play services status code, for example 10 (`DEVELOPER_ERROR`)
  /// or 8 (`INTERNAL_ERROR`).
  final int code;
}

/// The one wrapper around the plugin's `payriff/native` method channel
/// (CONTRACT §16.11): card encryption, the app id and name, screen
/// protection, hardened external launches, the removal of 3-D Secure website
/// data (§9.1a), the device integrity checks (§16.16), and PassKit and the
/// Google Pay API (§17). Nothing else in the SDK touches the channel; the
/// wallet buttons have their own channels (`payriff/apple_pay_button/<id>`,
/// `payriff/google_pay_button/<id>`) for their taps.
///
/// Arguments and replies are never logged: `encryptCard` carries card data,
/// and the wallet replies carry the wallet tokens.
abstract final class NativeBridge {
  /// The channel. Tests mock it with
  /// `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
  /// .setMockMethodCallHandler`.
  static const MethodChannel channel = MethodChannel('payriff/native');

  /// How long Dart waits for the Apple Pay sheet to go away after it was
  /// completed, before it goes on anyway. The plugin answers when PassKit
  /// has dismissed the sheet, normally within a second or two.
  static const Duration applePayDismissTimeout = Duration(seconds: 30);

  static Future<String?>? _appId;
  static Future<String?>? _appName;

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

  /// The app's display name, the last fallback of the wallet sheets'
  /// merchant name (CONTRACT §17.4): iOS `CFBundleDisplayName`, then
  /// `CFBundleName`; Android the application label. `null` when unknown.
  /// Asked once per process.
  static Future<String?> appName() => _appName ??= _readAppName();

  static Future<String?> _readAppName() async {
    try {
      final String? name = await channel.invokeMethod<String>('appName');
      final String? trimmed = name?.trim();
      return trimmed == null || trimmed.isEmpty ? null : trimmed;
    } on Object {
      return null;
    }
  }

  // ---------------------------------------------------------------------
  // Apple Pay (CONTRACT §17.6), iOS

  /// `PKPaymentAuthorizationController.canMakePayments(usingNetworks:
  /// capabilities:)` with [networks] (`PKPaymentNetwork` names) and
  /// [capabilities] (`PKMerchantCapability` names). `false` on any failure.
  static Future<bool> applePayCanMakePayments({
    required List<String> networks,
    required List<String> capabilities,
  }) async {
    try {
      return await channel.invokeMethod<bool>(
            'applePayCanMakePayments',
            <String, Object?>{
              'networks': networks,
              'capabilities': capabilities,
            },
          ) ??
          false;
    } on Object {
      return false;
    }
  }

  /// Presents the Apple Pay sheet for [request] (see `applePayRequest`) and
  /// completes when the customer authorizes the payment
  /// ([ApplePayAuthorized]) or closes the sheet ([ApplePayClosed]), or with
  /// [ApplePayNotPresented] when it cannot be shown. After an authorization
  /// the sheet stays up until [applePayComplete]; if that does not arrive
  /// within 25 s, the plugin completes it with `.failure` itself. Never
  /// throws.
  static Future<ApplePaySheetEvent> applePayPresent(
    Map<String, Object?> request,
  ) async {
    final Object? reply;
    try {
      reply = await channel.invokeMethod<Object?>('applePayPresent', request);
    } on Object {
      return const ApplePayNotPresented();
    }
    if (reply is! Map) return const ApplePayNotPresented();
    switch (reply['event']) {
      case 'authorized':
        final Object? data = reply['paymentData'];
        return ApplePayAuthorized(data is String ? data : null);
      case 'closed':
        return const ApplePayClosed();
    }
    return const ApplePayNotPresented();
  }

  /// Completes the authorization of [applePayPresent] with [success] (the
  /// plugin calls PassKit's handler exactly once) and completes when the
  /// sheet is gone; after `.failure` the plugin dismisses it at once.
  /// Completes with the status the sheet got: `false` when the plugin had
  /// already completed it with `.failure` (no decision within 25 s). Goes
  /// on after [applePayDismissTimeout] at the latest. Never throws.
  static Future<bool> applePayComplete({required bool success}) async {
    try {
      final Object? reply = await channel
          .invokeMethod<Object?>('applePayComplete', <String, Object?>{
            'status': success ? 'success' : 'failure',
          })
          .timeout(applePayDismissTimeout);
      if (reply is Map && reply['status'] is String) {
        return reply['status'] == 'success';
      }
    } on Object {
      // A missing plugin or a lost reply: the sheet is taken as gone.
    }
    return success;
  }

  // ---------------------------------------------------------------------
  // Google Pay (CONTRACT §17.5), Android

  /// `PaymentsClient.isReadyToPay` in [environment] (`TEST` or
  /// `PRODUCTION`) with the `isReadyToPayRequest` JSON [request]. An error
  /// counts as `false`. Never throws.
  static Future<bool> googlePayIsReady({
    required String environment,
    required String request,
  }) async {
    try {
      return await channel.invokeMethod<bool>(
            'googlePayIsReady',
            <String, Object?>{'environment': environment, 'request': request},
          ) ??
          false;
    } on Object {
      return false;
    }
  }

  /// `PaymentsClient.loadPaymentData` in [environment] with the
  /// `paymentDataRequest` JSON [request]: shows the Google Pay sheet and
  /// completes with its result. A failure of the channel itself is
  /// [GooglePayError] 8 (`INTERNAL_ERROR`). Never throws.
  static Future<GooglePayLoadResult> googlePayLoad({
    required String environment,
    required String request,
  }) async {
    const GooglePayLoadResult internalError = GooglePayError(8);
    final Object? reply;
    try {
      reply = await channel.invokeMethod<Object?>(
        'googlePayLoad',
        <String, Object?>{'environment': environment, 'request': request},
      );
    } on Object {
      return internalError;
    }
    if (reply is! Map) return internalError;
    switch (reply['status']) {
      case 'ok':
        final Object? token = reply['token'];
        return GooglePayOk(token is String ? token : null);
      case 'cancelled':
        return const GooglePayCancelled();
      case 'error':
        final Object? code = reply['code'];
        return GooglePayError(code is int ? code : 8);
    }
    return internalError;
  }

  /// Forgets the cached app id and name (`Payriff.debugReset`).
  static void resetCache() {
    _appId = null;
    _appName = null;
  }
}
