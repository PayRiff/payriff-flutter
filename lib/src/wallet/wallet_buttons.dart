import 'dart:async';

import 'package:flutter/widgets.dart';

import '../card/card_form.dart';
import '../card/client_order.dart';
import '../config.dart';
import '../error.dart';
import '../internal/card/device_integrity.dart';
import '../internal/logger.dart';
import '../internal/wallet/wallet_button.dart';
import '../internal/wallet/wallet_payment.dart';
import '../internal/wallet/wallet_rules.dart';
import '../payriff.dart';
import '../result.dart';
import 'wallet_button_style.dart';

/// The width of a wallet button whose parent sets no width, such as a
/// `Row`.
const double _unboundedWidth = 240;

/// The Apple Pay button on its own, for a payment screen of your own
/// (CONTRACT §17.10), as `PayriffCardForm` and `Payriff.confirmCardPayment`
/// are for cards. `PayriffPaymentView` already shows it above the card form.
///
/// It reads the order and shows Apple's own button only on iOS and only
/// when Apple Pay is offered (CONTRACT §17.3): `PayriffConfig.applePay` is
/// set and valid, the device is not compromised, the order is `CREATED` or
/// `PENDING` with an amount and a currency, and the device can pay with Visa
/// or Mastercard. The order's `paymentMethods` are not checked (revision
/// 10). Until that is decided, and whenever it is not offered (on
/// Android always), it takes no space; [onAvailabilityChange] gets each
/// decision. An order that does not load only makes it unavailable.
///
/// A tap shows the Apple Pay sheet, pays the order and passes the result to
/// [onResult]. When the bank asks for 3-D Secure, its page opens in the
/// SDK's sheet after the Apple Pay sheet is gone. Closing the Apple Pay
/// sheet without paying gives `cancelled(userClosed)` with the order id and
/// an unknown status. Call `Payriff.configure` first.
///
/// ```dart
/// PayriffApplePayButton(
///   orderId: order.orderId,
///   clientSecret: order.clientSecret,
///   style: const PayriffApplePayButtonStyle(
///     type: PayriffApplePayButtonType.buy,
///   ),
///   onAvailabilityChange: (bool available) =>
///       setState(() => _applePay = available),
///   onResult: handleResult,
/// )
/// ```
class PayriffApplePayButton extends StatelessWidget {
  /// Creates the Apple Pay button for the order [orderId].
  const PayriffApplePayButton({
    super.key,
    required this.orderId,
    required this.clientSecret,
    required this.onResult,
    this.style = const PayriffApplePayButtonStyle(),
    this.onAvailabilityChange,
  });

  /// The id of the order your server created.
  final String orderId;

  /// The order's client secret (`pr_cs_…`) from your server.
  final String clientSecret;

  /// The look of the button. Its `height` defaults to 44 and its
  /// `cornerRadius` to 16.
  final PayriffApplePayButtonStyle style;

  /// Called with `true` when the button appears and with `false` when it is
  /// not offered, for example to hide a divider of your own.
  final ValueChanged<bool>? onAvailabilityChange;

  /// Called with the result of each payment. The result is for the user
  /// interface: fulfil the order on your server.
  final ValueChanged<PayriffResult> onResult;

  @override
  Widget build(BuildContext context) => _StandaloneWalletButton(
    kind: WalletKind.applePay,
    orderId: orderId,
    clientSecret: clientSecret,
    height: style.height,
    cornerRadius: style.cornerRadius,
    params: (bool dark, double cornerRadius, PayriffClientOrder order) =>
        applePayButtonParams(style, dark: dark, cornerRadius: cornerRadius),
    onAvailabilityChange: onAvailabilityChange,
    onResult: onResult,
  );
}

/// The Google Pay button on its own, for a payment screen of your own
/// (CONTRACT §17.10), as `PayriffCardForm` and `Payriff.confirmCardPayment`
/// are for cards. `PayriffPaymentView` already shows it above the card form.
///
/// It reads the order and shows Google's own button only on Android and
/// only when Google Pay is offered (CONTRACT §17.3):
/// `PayriffConfig.googlePay` is set, the device is not compromised, the
/// order is `CREATED` or `PENDING` with an amount and a currency, a gateway
/// merchant id comes from the order or
/// `PayriffGooglePayConfig.gatewayMerchantId`, and Google Pay is ready on
/// the device. The order's `paymentMethods` are not checked (revision 10).
/// Until that
/// is decided, and whenever it is not offered (on iOS always), it takes no
/// space; [onAvailabilityChange] gets each decision. An order that does not
/// load only makes it unavailable.
///
/// A tap shows the Google Pay sheet, pays the order and passes the result
/// to [onResult]. When the bank asks for 3-D Secure, its page opens in the
/// SDK's sheet. Closing the Google Pay sheet without paying gives
/// `cancelled(userClosed)` with the order id and an unknown status. Call
/// `Payriff.configure` first.
///
/// ```dart
/// PayriffGooglePayButton(
///   orderId: order.orderId,
///   clientSecret: order.clientSecret,
///   style: const PayriffGooglePayButtonStyle(
///     type: PayriffGooglePayButtonType.pay,
///   ),
///   onResult: handleResult,
/// )
/// ```
class PayriffGooglePayButton extends StatelessWidget {
  /// Creates the Google Pay button for the order [orderId].
  const PayriffGooglePayButton({
    super.key,
    required this.orderId,
    required this.clientSecret,
    required this.onResult,
    this.style = const PayriffGooglePayButtonStyle(),
    this.onAvailabilityChange,
  });

  /// The id of the order your server created.
  final String orderId;

  /// The order's client secret (`pr_cs_…`) from your server.
  final String clientSecret;

  /// The look of the button. Its `height` defaults to 44 and its
  /// `cornerRadius` to 16.
  final PayriffGooglePayButtonStyle style;

  /// Called with `true` when the button appears and with `false` when it is
  /// not offered, for example to hide a divider of your own.
  final ValueChanged<bool>? onAvailabilityChange;

  /// Called with the result of each payment. The result is for the user
  /// interface: fulfil the order on your server.
  final ValueChanged<PayriffResult> onResult;

  @override
  Widget build(BuildContext context) => _StandaloneWalletButton(
    kind: WalletKind.googlePay,
    orderId: orderId,
    clientSecret: clientSecret,
    height: style.height,
    cornerRadius: style.cornerRadius,
    params: (bool dark, double cornerRadius, PayriffClientOrder order) {
      final List<Object?>? methods = googlePayAllowedPaymentMethods(
        order,
        Payriff.config?.googlePay,
      );
      return methods == null
          ? null
          : googlePayButtonParams(
              style,
              dark: dark,
              cornerRadius: cornerRadius,
              allowedPaymentMethods: methods,
            );
    },
    onAvailabilityChange: onAvailabilityChange,
    onResult: onResult,
  );
}

/// The creation parameters of a button for [order]; `null` when it cannot
/// be shown.
typedef _ButtonParams =
    Map<String, Object?>? Function(
      bool dark,
      double cornerRadius,
      PayriffClientOrder order,
    );

/// A standalone wallet button: loads the order, applies CONTRACT §17.3 and
/// runs the payment on tap.
class _StandaloneWalletButton extends StatefulWidget {
  const _StandaloneWalletButton({
    required this.kind,
    required this.orderId,
    required this.clientSecret,
    required this.height,
    required this.cornerRadius,
    required this.params,
    required this.onAvailabilityChange,
    required this.onResult,
  });

  final WalletKind kind;
  final String orderId;
  final String clientSecret;
  final double? height;
  final double? cornerRadius;
  final _ButtonParams params;
  final ValueChanged<bool>? onAvailabilityChange;
  final ValueChanged<PayriffResult> onResult;

  @override
  State<_StandaloneWalletButton> createState() =>
      _StandaloneWalletButtonState();
}

class _StandaloneWalletButtonState extends State<_StandaloneWalletButton> {
  /// The order while the wallet is offered for it; `null` hides the button.
  PayriffClientOrder? _order;

  /// The availability last passed to `onAvailabilityChange`.
  bool? _reported;
  bool _paying = false;

  /// Bumped for every order load, so a stale answer is dropped.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void didUpdateWidget(_StandaloneWalletButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orderId != widget.orderId ||
        oldWidget.clientSecret != widget.clientSecret) {
      _order = null;
      unawaited(_start());
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  /// When the button appears: the device check (CONTRACT §17.11), the order
  /// and the rest of §17.3.
  Future<void> _start() async {
    final int generation = ++_generation;
    // Every decision reaches onAvailabilityChange after the current build.
    await Future<void>.value();
    if (!_current(generation)) return;
    final WalletKind kind = widget.kind;
    final PayriffConfig? config = Payriff.config;
    final SdkLogger logger = sdkLoggerFor(config);
    if (platformWallet != kind) {
      logger.debug(walletDecisionLine(kind, 'not available on this platform'));
      return _decide(generation, null);
    }
    final PayriffError? refused = await deviceIntegrityError(
      allowCompromisedDevices: config?.allowCompromisedDevices ?? false,
      logger: logger,
      point: '${kind.label} button',
      payments: '${kind.label} payments',
    );
    if (!_current(generation)) return;
    if (refused != null) {
      logger.debug(walletDecisionLine(kind, 'device compromised'));
      return _decide(generation, null);
    }
    final PayriffClientOrder order;
    try {
      order = await Payriff.retrieveOrder(
        orderId: widget.orderId,
        clientSecret: widget.clientSecret,
      );
    } on PayriffException catch (e) {
      if (!_current(generation)) return;
      logger.debug(
        walletDecisionLine(kind, 'order not loaded (${e.error.code.value})'),
      );
      return _decide(generation, null);
    } on Object {
      if (!_current(generation)) return;
      logger.debug(walletDecisionLine(kind, 'order not loaded'));
      return _decide(generation, null);
    }
    if (!_current(generation)) return;
    final bool offered = await decideWalletOffer(
      kind: kind,
      order: order,
      config: config,
      logger: logger,
    );
    _decide(generation, offered ? order : null);
  }

  bool _current(int generation) => mounted && generation == _generation;

  void _decide(int generation, PayriffClientOrder? order) {
    if (!_current(generation)) return;
    setState(() => _order = order);
    final bool available = order != null;
    if (_reported != available) {
      _reported = available;
      widget.onAvailabilityChange?.call(available);
    }
  }

  Future<void> _pay() async {
    final PayriffClientOrder? order = _order;
    if (order == null || _paying) return;
    setState(() => _paying = true);
    final PayriffResult? result = await payWithWallet(
      context,
      kind: widget.kind,
      order: order,
      orderId: widget.orderId,
      clientSecret: widget.clientSecret,
    );
    if (!mounted) return;
    setState(() => _paying = false);
    // CONTRACT §17.8: closing the wallet's sheet without paying; the
    // payment's status stays unknown.
    final PayriffResult reported =
        result ??
        PayriffResultCancelled(
          reason: PayriffCancelReason.userClosed,
          payment: PayriffPayment(orderId: widget.orderId.trim()),
        );
    // A device refused on tap (CONTRACT §17.3 item 2) or an order that
    // ended no longer offers the wallet.
    final PayriffError? error = reported.error;
    if (error != null &&
        (error.isFatal || error.code == PayriffErrorCode.deviceCompromised)) {
      _decide(_generation, null);
    }
    widget.onResult(reported);
  }

  @override
  Widget build(BuildContext context) {
    final PayriffClientOrder? order = _order;
    if (order == null) return const SizedBox.shrink();
    final double cornerRadius = walletButtonCornerRadius(
      widget.cornerRadius,
      walletDefaultCornerRadius,
    );
    final Map<String, Object?>? params = widget.params(
      payriffIsDark(context),
      cornerRadius,
      order,
    );
    if (params == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) => SizedBox(
        width: constraints.hasBoundedWidth
            ? constraints.maxWidth
            : _unboundedWidth,
        child: WalletPlatformButton(
          kind: widget.kind,
          params: params,
          height: walletButtonHeight(widget.height, walletDefaultButtonHeight),
          enabled: !_paying,
          onTap: _pay,
        ),
      ),
    );
  }
}
