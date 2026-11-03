/// CONTRACT §17.3, §17.5–§17.8: when a wallet is offered, and one Apple Pay
/// or Google Pay payment from a tap on its button. From `/pay` on, a wallet
/// payment is the card flow's [CardPayment]: the same pinned client, retries,
/// `nextAction`, 3-D Secure sheet and status polling.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../card/client_order.dart';
import '../../config.dart';
import '../../error.dart';
import '../../payriff.dart';
import '../../result.dart';
import '../../strings.dart';
import '../card/card_clock.dart';
import '../card/card_flow.dart';
import '../card/client_api.dart';
import '../card/device_integrity.dart';
import '../language.dart';
import '../logger.dart';
import '../native_bridge.dart';
import '../payment_support.dart';
import '../request.dart';
import '../strings.dart';
import '../ui/presenter.dart';
import '../ui/three_ds_presentation.dart';
import 'wallet_rules.dart';

/// CONTRACT §17.3: whether [kind] is offered for [order], which was loaded
/// after the device check of the view or button passed (item 2). Checks, in
/// this order, the platform and [config] (item 1), the order (item 3) and
/// whether the device can pay (item 4: `canMakePayments` or
/// `isReadyToPay`), and logs the decision at `debug` level with the first
/// condition that failed. Never throws.
Future<bool> decideWalletOffer({
  required WalletKind kind,
  required PayriffClientOrder order,
  required PayriffConfig? config,
  required SdkLogger logger,
}) async {
  final String? problem = await _walletProblem(kind, order, config);
  logger.debug(walletDecisionLine(kind, problem));
  return problem == null;
}

Future<String?> _walletProblem(
  WalletKind kind,
  PayriffClientOrder order,
  PayriffConfig? config,
) async {
  if (platformWallet != kind) return 'not available on this platform';
  final String? configProblem = walletConfigProblem(config, kind);
  if (configProblem != null || config == null) {
    return configProblem ?? 'not configured';
  }
  final String? orderProblem = walletOrderProblem(order, kind);
  if (orderProblem != null) return orderProblem;
  switch (kind) {
    case WalletKind.applePay:
      final bool canPay = await NativeBridge.applePayCanMakePayments(
        // CONTRACT §19.4: mada too in region sa.
        networks: applePayNetworksFor(config.region),
        capabilities: applePayCapabilities,
      );
      return canPay ? null : 'the device cannot pay with Visa or Mastercard';
    case WalletKind.googlePay:
      final bool ready = await NativeBridge.googlePayIsReady(
        environment: googlePayEnvironment(config),
        request: jsonEncode(googlePayIsReadyToPayRequest()),
      );
      return ready ? null : 'Google Pay is not ready on this device';
  }
}

/// Runs one [kind] payment of [order] after a tap on its button (CONTRACT
/// §17.5, §17.6) and completes with the result, or with `null` when the
/// customer closed the wallet's sheet without paying (§17.8: the payment
/// view reports nothing, a standalone button reports
/// `cancelled(userClosed)`). One payment at a time: while another one runs,
/// the result is `failed(PAYMENT_IN_PROGRESS)`. The 3-D Secure sheet shows
/// [viewStrings] (`PayriffPaymentView.strings`) over `PayriffConfig.strings`
/// (CONTRACT §18.6). Never throws.
Future<PayriffResult?> payWithWallet(
  BuildContext context, {
  required WalletKind kind,
  required PayriffClientOrder order,
  required String orderId,
  required String clientSecret,
  PayriffStrings? viewStrings,
}) async {
  if (paymentInProgress) {
    return const PayriffResultFailed(error: paymentInProgressError);
  }
  final PayriffConfig? config = Payriff.config;
  if (config == null) {
    return PayriffResultFailed(
      error: notConfigured(
        'Call Payriff.configure before paying with ${kind.label}.',
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
  if (argumentError != null) return PayriffResultFailed(error: argumentError);
  if (walletConfigProblem(config, kind) != null) {
    return PayriffResultFailed(
      error: invalidConfig(
        '${kind.label} needs a valid '
        'PayriffConfig.${kind == WalletKind.applePay ? 'applePay' : 'googlePay'}.',
      ),
    );
  }
  final NavigatorState? navigator = context.mounted
      ? Navigator.maybeOf(context, rootNavigator: true)
      : null;
  if (navigator == null) {
    return const PayriffResultFailed(error: noNavigatorError);
  }
  final SdkLogger logger = sdkLoggerFor(config);
  final PayriffSheetStrings strings = PayriffSheetStrings(
    effectiveLanguage(null, config),
    overrides: <PayriffStrings>[?viewStrings, ?config.strings],
  );
  final bool material = context.mounted
      ? SheetPresenter.prefersMaterial(context)
      : defaultTargetPlatform != TargetPlatform.iOS;
  // Claimed before the first await, so a second tap cannot start another
  // payment.
  paymentInProgress = true;
  final _WalletPayment payment = _WalletPayment(
    kind: kind,
    config: config,
    order: order,
    orderId: id,
    publishableKey: publishableKey,
    clientSecret: secret!,
    strings: strings,
    logger: logger,
    openSheet: (ThreeDsSession session) => presentThreeDsSheet(
      context.mounted ? context : navigator.context,
      navigator,
      material,
      strings,
      logger,
      session,
    ),
  );
  final PayriffResult? result;
  try {
    logger.info('${kind.label} payment: order $id');
    result = await payment.run();
  } finally {
    paymentInProgress = false;
    payment.close();
  }
  if (result == null) {
    logger.info('${kind.label} payment: closed without paying');
  } else {
    final PayriffPayment? paid = result.payment;
    final PayriffError? error = result.error;
    logger.info(
      '${kind.label} payment finished: ${result.type}'
      '${paid == null ? '' : ' (${paid.status.value})'}'
      '${error == null ? '' : ' (${error.code.value})'}',
    );
  }
  return result;
}

PayriffResult _walletFailed(String message) => PayriffResultFailed(
  error: PayriffError(code: PayriffErrorCode.walletFailed, message: message),
);

/// One wallet payment, from the tap to the result.
final class _WalletPayment {
  _WalletPayment({
    required this.kind,
    required this.config,
    required this.order,
    required this.orderId,
    required this.publishableKey,
    required this.clientSecret,
    required this.strings,
    required this.logger,
    required this.openSheet,
  });

  final WalletKind kind;
  final PayriffConfig config;
  final PayriffClientOrder order;
  final String orderId;
  final String publishableKey;
  final String clientSecret;
  final PayriffSheetStrings strings;
  final SdkLogger logger;
  final ThreeDsSheetOpener openSheet;
  ClientApi? _api;

  /// The result, or `null` when the customer closed the wallet's sheet.
  Future<PayriffResult?> run() async {
    try {
      // CONTRACT §17.11: on tap, before the wallet's sheet.
      final PayriffError? refused = await _checkDevice('${kind.label} tap');
      if (refused != null) return PayriffResultFailed(error: refused);
      return switch (kind) {
        WalletKind.applePay => await _runApplePay(),
        WalletKind.googlePay => await _runGooglePay(),
      };
    } on Object catch (e) {
      logger.error(
        'The ${kind.label} payment failed unexpectedly: '
        '${e.runtimeType}',
      );
      return const PayriffResultFailed(
        error: PayriffError(
          code: PayriffErrorCode.unknown,
          message: 'The payment failed unexpectedly.',
        ),
      );
    }
  }

  void close() => _api?.close();

  Future<PayriffError?> _checkDevice(String point) => deviceIntegrityError(
    allowCompromisedDevices: config.allowCompromisedDevices,
    logger: logger,
    point: point,
    payments: '${kind.label} payments',
  );

  /// CONTRACT §17.5.
  Future<PayriffResult?> _runGooglePay() async {
    final Map<String, Object?>? request = googlePayPaymentDataRequest(
      order: order,
      region: config.region,
      config: config.googlePay!,
      appName: await NativeBridge.appName(),
    );
    if (request == null) {
      return _walletFailed('The order cannot be paid with Google Pay.');
    }
    final GooglePayLoadResult loaded = await NativeBridge.googlePayLoad(
      environment: googlePayEnvironment(config),
      request: jsonEncode(request),
    );
    switch (loaded) {
      case GooglePayCancelled():
        logger.info('Google Pay: cancelled');
        return null;
      case GooglePayError(:final int code):
        logger.warning('Google Pay: error $code');
        return _walletFailed('Google Pay failed (status $code).');
      case GooglePayOk(:final String? token):
        logger.info('Google Pay: ok');
        if (token == null || token.trim().isEmpty) {
          return _walletFailed('Google Pay returned no payment token.');
        }
        // CONTRACT §17.11: the last point, right before /pay.
        final PayriffError? refused = await _checkDevice('Google Pay /pay');
        if (refused != null) return PayriffResultFailed(error: refused);
        return _pay(token);
    }
  }

  /// CONTRACT §17.6. The sheet's handler is completed exactly once: when
  /// the flow needs the 3-D Secure sheet, when [applePaySheetBudget] ends
  /// without a final status, or by the result (`wallet.json` →
  /// `applePaySheet`); the result is returned once the sheet is gone.
  Future<PayriffResult?> _runApplePay() async {
    final Map<String, Object?>? request = applePayRequest(
      order: order,
      region: config.region,
      config: config.applePay!,
      appName: await NativeBridge.appName(),
    );
    if (request == null) {
      return _walletFailed('The order cannot be paid with Apple Pay.');
    }
    final String? paymentData;
    switch (await NativeBridge.applePayPresent(request)) {
      case ApplePayNotPresented():
        logger.warning('The Apple Pay sheet could not be shown');
        return _walletFailed(
          'Apple Pay could not be shown. Check the merchant identifier and '
          'the Apple Pay capability.',
        );
      case ApplePayClosed():
        logger.info('Apple Pay sheet: closed');
        return null;
      case ApplePayAuthorized(paymentData: final String? data):
        paymentData = data;
    }
    final _ApplePaySheet sheet = _ApplePaySheet(logger);
    final Timer budget = Timer(applePaySheetBudget, () {
      logger.info(
        'Apple Pay: no final status ${applePaySheetBudget.inSeconds} s after '
        'the authorization',
      );
      unawaited(sheet.complete(ApplePaySheetStatus.success));
    });
    PayriffResult result = const PayriffResultFailed(
      error: PayriffError(
        code: PayriffErrorCode.unknown,
        message: 'The payment failed unexpectedly.',
      ),
    );
    try {
      // CONTRACT §17.6 step 1: the last point, right before /pay.
      final PayriffError? refused = await _checkDevice('Apple Pay /pay');
      if (refused != null) {
        result = PayriffResultFailed(error: refused);
      } else if (paymentData == null || paymentData.trim().isEmpty) {
        result = _walletFailed('Apple Pay returned no payment data.');
      } else {
        result = await _pay(
          paymentData,
          // A challenge or redirect (or the 3-D Secure Method, which runs in
          // the same sheet) completes the Apple Pay sheet with .success and
          // opens the 3-D Secure sheet once it is gone.
          beforeSheet: () => sheet.complete(ApplePaySheetStatus.success),
        );
      }
    } finally {
      budget.cancel();
      // Does nothing when the sheet was completed already; waits until it is
      // gone either way.
      await sheet.complete(applePaySheetRule(applePayOutcomeOf(result)).sheet);
    }
    return result;
  }

  /// CONTRACT §17.7 and §16.7 steps 4–5 with the wallet [token].
  Future<PayriffResult> _pay(
    String token, {
    Future<void> Function()? beforeSheet,
  }) async {
    final ClientApi api = _api = ClientApi(
      baseUrl: config.apiBaseUrl,
      publishableKey: publishableKey,
      clientSecret: clientSecret,
      appId: await NativeBridge.appId(),
      clock: cardClock,
      logger: logger,
    );
    final CardPayment payment = CardPayment(
      api: api,
      orderId: orderId,
      clock: cardClock,
      strings: strings,
      logger: logger,
      openSheet: openSheet,
      beforeSheet: beforeSheet,
    );
    return payment.runWallet(kind, token);
  }
}

/// The Apple Pay sheet after the authorization.
final class _ApplePaySheet {
  _ApplePaySheet(this._logger);

  final SdkLogger _logger;
  Future<void>? _completed;

  /// Completes the sheet with [status] the first time (CONTRACT §17.6 step
  /// 4: the handler is called exactly once); later calls only wait. Either
  /// way it completes when the sheet is gone.
  Future<void> complete(ApplePaySheetStatus status) => _completed ??= () async {
    final bool success = await NativeBridge.applePayComplete(
      success: status == ApplePaySheetStatus.success,
    );
    _logger.info('Apple Pay sheet: ${success ? 'success' : 'failure'}');
  }();
}
