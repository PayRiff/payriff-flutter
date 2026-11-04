import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../config.dart';
import '../error.dart';
import '../internal/amount.dart';
import '../internal/card/card_strings.dart';
import '../internal/card/device_integrity.dart';
import '../internal/card/payment_view_scope.dart';
import '../internal/language.dart';
import '../internal/logger.dart';
import '../internal/ui/glyphs.dart';
import '../internal/ui/smooth_rect.dart';
import '../internal/wallet/wallet_button.dart';
import '../internal/wallet/wallet_payment.dart';
import '../internal/wallet/wallet_rules.dart';
import '../payment_method.dart';
import '../payriff.dart';
import '../result.dart';
import '../strings.dart';
import 'card_form.dart';
import 'card_types.dart';
import 'client_order.dart';
import 'payment_view_style.dart';

/// Key of the payment view's Pay button.
const Key paymentViewPayButtonKey = ValueKey<String>('payriff.view.pay');

/// Key of the spinner that replaces the Pay button's title while paying.
const Key paymentViewSpinnerKey = ValueKey<String>('payriff.view.spinner');

/// Key of the error line under the Pay button.
const Key paymentViewErrorKey = ValueKey<String>('payriff.view.error');

/// Key of the row of card badges.
const Key paymentViewBadgesKey = ValueKey<String>('payriff.view.badges');

/// Key of the frame of a card badge: `mastercard` or `visa`.
Key paymentViewBadgeKey(String brand) =>
    ValueKey<String>('payriff.view.badge.$brand');

/// The default border of the card badges (CONTRACT §18.4).
const Color paymentViewBadgeBorderColor = Color(0xFFECEEF0);

/// Key of the lock and "Proceed securely by PCI DSS" line.
const Key paymentViewSecureKey = ValueKey<String>('payriff.view.secure');

/// Key of the "Powered by Payriff" footer.
const Key paymentViewPoweredByKey = ValueKey<String>('payriff.view.poweredBy');

/// Key of the Apple Pay or Google Pay button above the card form.
const Key paymentViewWalletButtonKey = ValueKey<String>('payriff.view.wallet');

/// Key of the "Or pay by card" divider under the wallet button.
const Key paymentViewWalletDividerKey = ValueKey<String>(
  'payriff.view.walletDivider',
);

/// The images of the payment view (CONTRACT §16.14, §18.4), package assets
/// of `payriff` with 2.0x and 3.0x variants.
abstract final class PaymentViewAssets {
  /// The package that holds the images.
  static const String package = 'payriff';

  /// The Mastercard mark of its badge, 43×28 and without the frame, which
  /// the view draws.
  static const String mastercardMark =
      'assets/payment_view/mastercard-mark.png';

  /// The Visa mark of its badge, 42×28 and without the frame, which the
  /// view draws.
  static const String visaMark = 'assets/payment_view/visa-mark.png';

  /// The Payriff logo of the footer in light mode, 82×16.
  static const String logo = 'assets/payment_view/payriff-logo.png';

  /// The Payriff logo of the footer in dark mode, 82×16: the wordmark in
  /// `#E1E4E8`.
  static const String logoDark = 'assets/payment_view/payriff-logo-dark.png';

  /// Every image.
  static const List<String> all = <String>[
    mastercardMark,
    visaMark,
    logo,
    logoDark,
  ];

  /// The footer's logo: [logo], or [logoDark] in dark mode.
  static String footerLogo({required bool dark}) => dark ? logoDark : logo;
}

/// The Pay button's title (CONTRACT §16.14, §18.1): [title] (the style's
/// `payButtonTitle`) without white space around it, as the whole text;
/// otherwise `view.pay` (or `PayriffStrings.pay` through [strings]), or
/// [label] (the style's `payButtonLabel`) without white space around it,
/// then the amount with 2 decimals and `.` as the separator, then the
/// currency, for example "Pay 1.02 AZN". Only the word while the amount is
/// unknown. The amount is the one the Apple Pay and Google Pay sheets show
/// (CONTRACT §17.4).
String paymentViewPayTitle(
  PayriffCardStrings strings,
  PayriffClientOrder? order, {
  String? label,
  String? title,
}) {
  // CONTRACT §18.1: the whole text in every state; blank counts as none.
  final String? whole = title?.trim();
  if (whole != null && whole.isNotEmpty) return whole;
  // A blank label counts as none (CONTRACT §16.14).
  final String? custom = label?.trim();
  final String pay = custom == null || custom.isEmpty ? strings.pay : custom;
  final String? amount = formatAmount2(order?.amount);
  if (amount == null) return pay;
  final String currency = order?.currency?.trim() ?? '';
  return <String>[
    if (pay.isNotEmpty) pay,
    amount,
    if (currency.isNotEmpty) currency,
  ].join(' ');
}

/// The SDK's ready-made card payment screen (CONTRACT §16.14), like the card
/// part of Payriff's hosted payment page (pay.payriff.com).
///
/// It shows a [PayriffCardForm], a Pay button with the order's amount, the
/// accepted card badges, a "Proceed securely by PCI DSS" line and a
/// "Powered by Payriff" footer, on the page's background. It reads the order
/// with [Payriff.retrieveOrder] when it appears, and tapping Pay runs
/// [Payriff.confirmCardPayment] and passes the result to [onResult].
///
/// The Pay button stays disabled while the order loads, when it cannot be
/// paid by card or did not load (an error line then says why), while the
/// form is incomplete and while paying. A fatal error (for example an
/// expired client secret) is also passed to [onResult], once.
///
/// On a compromised device (rooted or jailbroken, a hooking framework such
/// as Frida, a debugger on a release build, or a check that cannot
/// complete; CONTRACT §16.16) the view does not read the order: it says
/// that card payments are not available on this device, keeps Pay disabled
/// and passes [PayriffErrorCode.deviceCompromised] to [onResult], once. With
/// `PayriffConfig.allowCompromisedDevices` in a debug build it only logs a
/// warning; profile and release builds ignore that flag.
///
/// **Apple Pay and Google Pay** (CONTRACT §17.9). With
/// `PayriffConfig.applePay` on iOS or `PayriffConfig.googlePay` on Android,
/// the view shows the wallet's official button above the card form, with an
/// "Or pay by card" divider, when the wallet is offered for the order: the
/// order can be paid and the device can pay. The app's configuration
/// decides, on the wallet's own platform only; the order's
/// `paymentMethods` are not checked (CONTRACT §17.3, revision 10). Until
/// that is decided, and without a wallet, the view looks exactly as above.
/// A wallet payment's result goes to [onResult] like a card payment's;
/// closing the wallet's sheet without paying reports nothing, so the
/// customer can try again or pay by card. While any payment runs, the form
/// is locked, Pay shows its spinner and the wallet button is dimmed. An
/// order that accepts a wallet but no card says that it cannot be paid by
/// card, and the wallet button stays usable.
///
/// **Design options** (CONTRACT §18). [PayriffPaymentViewStyle] can set the
/// whole Pay button text, smooth corners, the disabled Pay colours and the
/// badge borders; [strings] (over `PayriffConfig.strings`) replaces any text
/// of the view and of the sheets it opens. The view follows a right-to-left
/// layout ([Directionality]), and is right to left in Arabic; the card
/// number, expiry and CVC stay left to right. [onPaymentStarted],
/// [onOrderLoaded] and [onLoadFailed] report what happens before a result.
///
/// Give it the whole screen, for example as a `Scaffold` body: it scrolls
/// when the keyboard is up and keeps the footer at the bottom when there is
/// room. Call [Payriff.configure] first.
///
/// ```dart
/// Scaffold(
///   appBar: AppBar(),
///   body: PayriffPaymentView(
///     orderId: order.orderId,
///     clientSecret: order.clientSecret,
///     onResult: (PayriffResult result) {
///       Navigator.of(context).pop(result);
///     },
///   ),
/// )
/// ```
///
/// [PayriffCardForm] and [Payriff.confirmCardPayment] remain available to
/// build your own screen.
class PayriffPaymentView extends StatefulWidget {
  /// Creates a payment view for the order [orderId].
  const PayriffPaymentView({
    super.key,
    required this.orderId,
    required this.clientSecret,
    required this.onResult,
    this.language,
    this.style = const PayriffPaymentViewStyle(),
    this.strings,
    this.onPaymentStarted,
    this.onOrderLoaded,
    this.onLoadFailed,
  });

  /// The id of the order your server created.
  final String orderId;

  /// The order's client secret (`pr_cs_…`) from your server.
  final String clientSecret;

  /// Called with the result of each payment attempt, and once with a fatal
  /// error that ends the order (`PayriffError.isFatal`) or with
  /// [PayriffErrorCode.deviceCompromised]. The result is for the user
  /// interface: fulfil the order on your server.
  final ValueChanged<PayriffResult> onResult;

  /// The language of the view and the form. `null` uses
  /// `PayriffConfig.language`, then the device language.
  final PayriffLanguage? language;

  /// The colours, sizes, texts and parts of the view, and the form's look.
  final PayriffPaymentViewStyle style;

  /// Texts of your own for this view and the 3-D Secure sheet it opens
  /// (CONTRACT §18.6). A field set here wins over the same field of
  /// `PayriffConfig.strings`; a field left `null` or blank keeps the
  /// config's, else the SDK's own text. The style's text options win over
  /// both.
  final PayriffStrings? strings;

  /// Called once per payment attempt, when it starts (CONTRACT §18.5): for
  /// [PayriffPaymentMethod.card] when Pay is tapped with a complete form,
  /// before anything is sent; for Apple Pay or Google Pay when its button
  /// is tapped, before its sheet opens.
  final ValueChanged<PayriffPaymentMethod>? onPaymentStarted;

  /// Called after every successful read of the order by the view (when it
  /// appears, and again for a new `orderId` or `clientSecret`), also when
  /// the order cannot be paid by card.
  final ValueChanged<PayriffClientOrder>? onOrderLoaded;

  /// Called when the view gets no order: the order could not be read, or
  /// the device is compromised ([PayriffErrorCode.deviceCompromised]), in
  /// which case the view does not read it. A fatal error, and a compromised
  /// device, also go to [onResult] once.
  final ValueChanged<PayriffError>? onLoadFailed;

  @override
  State<PayriffPaymentView> createState() => _PayriffPaymentViewState();
}

class _PayriffPaymentViewState extends State<PayriffPaymentView> {
  final PayriffCardController _card = PayriffCardController();

  PayriffClientOrder? _order;
  bool _loading = true;

  /// Why the order did not load or can no longer be paid; its message, or
  /// the app's text for its code (CONTRACT §18.6), shows under the button.
  /// An order that loaded but cannot be paid by card shows
  /// `view.notPayable` instead, in the view's language.
  PayriffError? _error;

  /// A payment ended with a status, or the order can no longer be paid.
  bool _finished = false;

  /// CONTRACT §16.16: card payments are refused on this device; the error
  /// line shows `view.deviceNotSupported`.
  bool _deviceRefused = false;
  bool _paying = false;

  /// CONTRACT §17.3: the wallet offered for the loaded order, once decided;
  /// `null` hides the wallet button and the divider.
  WalletKind? _wallet;

  /// A failure that ends this view's order (fatal, or a refused device) was
  /// passed to `onResult`.
  bool _failureReported = false;

  /// Bumped for every order load, so a stale answer is dropped.
  int _loadGeneration = 0;

  bool get _payable =>
      !_loading &&
      !_finished &&
      !_deviceRefused &&
      _error == null &&
      (_order?.isPayableByCard ?? false);

  bool get _canPay =>
      _payable && _card.isComplete && !_paying && !_card.isProcessing;

  /// CONTRACT §17.9: the wallet button is disabled while any payment runs,
  /// and once the order was paid or ended.
  bool get _walletEnabled =>
      _wallet != null &&
      !_paying &&
      !_card.isProcessing &&
      !_finished &&
      !_deviceRefused &&
      _error == null;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void didUpdateWidget(PayriffPaymentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orderId != widget.orderId ||
        oldWidget.clientSecret != widget.clientSecret) {
      _failureReported = false;
      unawaited(_start());
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _card.dispose();
    super.dispose();
  }

  /// When the view appears: checks the device (CONTRACT §16.16), then reads
  /// the order (§16.14). The order is not read on a refused device.
  Future<void> _start() async {
    final int generation = ++_loadGeneration;
    _order = null;
    _error = null;
    _finished = false;
    _deviceRefused = false;
    _wallet = null;
    _loading = true;
    final PayriffConfig? config = Payriff.config;
    final PayriffError? refused = await deviceIntegrityError(
      allowCompromisedDevices: config?.allowCompromisedDevices ?? false,
      logger: sdkLoggerFor(config),
      point: 'payment view',
    );
    if (!mounted || generation != _loadGeneration) return;
    if (refused != null) {
      setState(() {
        _loading = false;
        _deviceRefused = true;
      });
      // CONTRACT §18.5: the view gets no order.
      widget.onLoadFailed?.call(refused);
      _reportOnce(refused);
      return;
    }
    await _loadOrder(generation);
  }

  Future<void> _loadOrder(int generation) async {
    PayriffClientOrder? order;
    PayriffError? error;
    try {
      order = await Payriff.retrieveOrder(
        orderId: widget.orderId,
        clientSecret: widget.clientSecret,
      );
    } on PayriffException catch (e) {
      error = e.error;
    } on Object {
      error = const PayriffError(
        code: PayriffErrorCode.unknown,
        message: 'The order could not be loaded.',
      );
    }
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _loading = false;
      _order = order;
      if (error != null) _error = error;
    });
    // CONTRACT §18.5: after every read, and for every read that failed.
    if (error != null) {
      widget.onLoadFailed?.call(error);
      if (error.isFatal) _reportOnce(error);
    }
    if (order != null) {
      widget.onOrderLoaded?.call(order);
      if (!mounted || generation != _loadGeneration) return;
      await _decideWallet(generation, order);
    }
  }

  /// CONTRACT §17.3 for the loaded [order]; the device check passed when
  /// the view appeared.
  Future<void> _decideWallet(int generation, PayriffClientOrder order) async {
    final WalletKind? kind = platformWallet;
    if (kind == null) return;
    final PayriffConfig? config = Payriff.config;
    final bool offered = await decideWalletOffer(
      kind: kind,
      order: order,
      config: config,
      logger: sdkLoggerFor(config),
    );
    if (!offered || !mounted || generation != _loadGeneration) return;
    setState(() => _wallet = kind);
  }

  void _reportOnce(PayriffError error) {
    if (_failureReported) return;
    _failureReported = true;
    widget.onResult(PayriffResultFailed(error: error));
  }

  Future<void> _pay() async {
    if (!_canPay) return;
    // CONTRACT §18.5: the form is complete; nothing was sent yet.
    widget.onPaymentStarted?.call(PayriffPaymentMethod.card);
    setState(() => _paying = true);
    final PayriffResult result = await confirmCardPaymentWithStrings(
      context,
      _card,
      orderId: widget.orderId,
      clientSecret: widget.clientSecret,
      viewStrings: widget.strings,
    );
    _finishPayment(result);
  }

  /// A tap on the wallet button (CONTRACT §17.5, §17.6).
  Future<void> _payWithWallet() async {
    final WalletKind? kind = _wallet;
    final PayriffClientOrder? order = _order;
    if (kind == null || order == null || !_walletEnabled) return;
    // CONTRACT §18.5: before the wallet's sheet opens.
    widget.onPaymentStarted?.call(switch (kind) {
      WalletKind.applePay => PayriffPaymentMethod.applePay,
      WalletKind.googlePay => PayriffPaymentMethod.googlePay,
    });
    setState(() => _paying = true);
    // CONTRACT §17.9: the form is locked while any payment runs.
    setCardFormProcessing(_card, true);
    final PayriffResult? result;
    try {
      result = await payWithWallet(
        context,
        kind: kind,
        order: order,
        orderId: widget.orderId,
        clientSecret: widget.clientSecret,
        viewStrings: widget.strings,
      );
    } finally {
      setCardFormProcessing(_card, false);
    }
    if (result == null) {
      // CONTRACT §17.8: the wallet's sheet closed without paying. Nothing is
      // reported; the customer can try again or pay by card.
      if (mounted) setState(() => _paying = false);
      return;
    }
    _finishPayment(result);
  }

  /// Ends a card or wallet payment with [result] and reports it.
  void _finishPayment(PayriffResult result) {
    final PayriffError? error = result.error;
    final bool orderEnded =
        error != null &&
        (error.isFatal || error.code == PayriffErrorCode.orderNotPayable);
    // A hooking tool or a debugger that attached after the view appeared.
    final bool deviceRefused =
        error?.code == PayriffErrorCode.deviceCompromised;
    if (mounted) {
      setState(() {
        _paying = false;
        // A payment that reached a status, or an order that can no longer
        // be paid: the order is not paid again from this view.
        if (result is! PayriffResultFailed) _finished = true;
        if (orderEnded) _error = error;
        if (deviceRefused) _deviceRefused = true;
      });
    }
    if (error != null && (error.isFatal || deviceRefused)) {
      _failureReported = true;
    }
    widget.onResult(result);
  }

  @override
  Widget build(BuildContext context) {
    final PayriffPaymentViewStyle style = widget.style;
    final bool dark = payriffIsDark(context);
    final PayriffLanguage language = effectiveLanguage(
      widget.language,
      Payriff.config,
    );
    // CONTRACT §18.6: the view's texts, then the config's, then the SDK's.
    final PayriffCardStrings strings = PayriffCardStrings(
      language,
      overrides: <PayriffStrings>[?widget.strings, ?Payriff.config?.strings],
    );
    final CardFormLook formLook = CardFormLook(style.formStyle, dark: dark);
    final Color background =
        style.backgroundColor ??
        (dark ? const Color(0xFF222224) : const Color(0xFFFCFCFD));
    final TextStyle secondary = TextStyle(
      color: style.secondaryTextColor ?? const Color(0xFF76787F),
      fontSize: 12,
      fontWeight: FontWeight.w400,
    );
    final PayriffClientOrder? order = _order;
    // CONTRACT §16.16 `view.deviceNotSupported` on a refused device; else
    // §16.14: an error message, or `view.notPayable` for an order that
    // loaded but cannot be paid by card.
    final PayriffError? failure = _error;
    final String? error = _deviceRefused
        ? strings.deviceNotSupported
        : failure != null
        ? strings.errorLine(failure)
        : (order != null && !order.isPayableByCard ? strings.notPayable : null);
    final WalletKind? wallet = _deviceRefused ? null : _wallet;
    final List<Widget> walletRow = wallet == null || order == null
        ? const <Widget>[]
        : _walletRow(wallet, order, style, strings, formLook, secondary, dark);

    final Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // CONTRACT §17.9: the wallet button and the divider above the form,
        // only once the wallet is offered; it slides in rather than jumping.
        // Without a configured wallet the layout is exactly §16.14.
        if (platformWallet case final WalletKind kind
            when walletConfigProblem(Payriff.config, kind) == null)
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: walletRow.isEmpty
                ? const SizedBox(width: double.infinity)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: walletRow,
                  ),
          ),
        // CONTRACT §18.2, §18.4, §18.6: the form falls back on the view's
        // smoothing and badge border, and takes the view's texts.
        PaymentViewScope(
          cornerSmoothing: style.cornerSmoothing,
          badgeBorderColor: style.badgeBorderColor,
          strings: widget.strings,
          child: PayriffCardForm(
            controller: _card,
            language: language,
            style: style.formStyle,
          ),
        ),
        const SizedBox(height: 24),
        ListenableBuilder(
          listenable: _card,
          builder: (BuildContext context, _) => _PayButton(
            key: paymentViewPayButtonKey,
            title: paymentViewPayTitle(
              strings,
              order,
              label: style.payButtonLabel,
              title: style.payButtonTitle,
            ),
            enabled: _canPay,
            busy: _paying || _card.isProcessing,
            color: style.buttonColor ?? payriffBrandColor,
            textStyle: const TextStyle(
              color: Color(0xFFFFFFFF),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ).merge(style.buttonTextStyle),
            disabledColor: style.buttonDisabledColor,
            disabledTextColor: style.buttonDisabledTextColor,
            height: style.buttonHeight,
            cornerRadius: style.buttonCornerRadius,
            cornerSmoothing: style.cornerSmoothing,
            onPressed: _pay,
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              container: true,
              liveRegion: true,
              child: Text(
                error,
                key: paymentViewErrorKey,
                style: formLook.errorText,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        if (style.showBadges) ...<Widget>[
          const SizedBox(height: 24),
          _Badges(
            key: paymentViewBadgesKey,
            borderColor: style.badgeBorderColor ?? paymentViewBadgeBorderColor,
            cornerSmoothing: style.cornerSmoothing,
          ),
        ],
        if (style.showSecureNote) ...<Widget>[
          SizedBox(height: style.showBadges ? 20 : 24),
          _SecureLine(
            key: paymentViewSecureKey,
            text: _orLocalized(style.secureNoteText, strings.secure),
            style: secondary,
          ),
        ],
      ],
    );
    final Widget? footer = style.showPoweredBy
        ? Padding(
            padding: const EdgeInsets.only(top: 24),
            child: _PoweredBy(
              key: paymentViewPoweredByKey,
              strings: strings,
              style: secondary,
              dark: dark,
            ),
          )
        : null;

    // A Material ancestor gives the text the app's font and no debug
    // underline, also inside a CupertinoApp. CONTRACT §18.7, §19.3: right to
    // left in a right-to-left app, and in Arabic.
    return Directionality(
      textDirection: viewTextDirection(context, language),
      child: Material(
        type: MaterialType.transparency,
        child: ColoredBox(
          color: background,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              // The safe area, and the keyboard when the parent leaves it in
              // the view (a Scaffold that resizes for it removes it).
              final EdgeInsets padding =
                  style.padding +
                  (MediaQuery.maybePaddingOf(context) ?? EdgeInsets.zero) +
                  EdgeInsets.only(
                    bottom: MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0,
                  );
              if (!constraints.hasBoundedHeight) {
                // Inside a parent that scrolls already.
                return Padding(
                  padding: padding,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[content, ?footer],
                  ),
                );
              }
              return SingleChildScrollView(
                padding: padding,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: math.max(
                      0,
                      constraints.maxHeight - padding.vertical,
                    ),
                  ),
                  // The footer goes to the bottom when there is room, else
                  // 24 below the content.
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[content, ?footer],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// The wallet button and the divider (CONTRACT §17.9): the button full
  /// width, as high as the wallet style's `height` or the view's
  /// `buttonHeight`, with the wallet style's `cornerRadius` or the view's
  /// `buttonCornerRadius`; the divider 16 below it and the form 16 below
  /// that. Empty when the order cannot fill the button.
  List<Widget> _walletRow(
    WalletKind kind,
    PayriffClientOrder order,
    PayriffPaymentViewStyle style,
    PayriffCardStrings strings,
    CardFormLook formLook,
    TextStyle secondary,
    bool dark,
  ) {
    final double? height = switch (kind) {
      WalletKind.applePay => style.applePayButton.height,
      WalletKind.googlePay => style.googlePayButton.height,
    };
    final double cornerRadius = walletButtonCornerRadius(switch (kind) {
      WalletKind.applePay => style.applePayButton.cornerRadius,
      WalletKind.googlePay => style.googlePayButton.cornerRadius,
    }, style.buttonCornerRadius);
    final List<Object?>? googlePayMethods = kind == WalletKind.googlePay
        ? googlePayAllowedPaymentMethods(order, Payriff.config?.googlePay)
        : null;
    final Map<String, Object?>? params = switch (kind) {
      WalletKind.applePay => applePayButtonParams(
        style.applePayButton,
        dark: dark,
        cornerRadius: cornerRadius,
      ),
      WalletKind.googlePay =>
        googlePayMethods == null
            ? null
            : googlePayButtonParams(
                style.googlePayButton,
                dark: dark,
                cornerRadius: cornerRadius,
                allowedPaymentMethods: googlePayMethods,
              ),
    };
    if (params == null) return const <Widget>[];
    return <Widget>[
      ListenableBuilder(
        listenable: _card,
        builder: (BuildContext context, _) => WalletPlatformButton(
          key: paymentViewWalletButtonKey,
          kind: kind,
          params: params,
          height: walletButtonHeight(height, style.buttonHeight),
          enabled: _walletEnabled,
          onTap: _payWithWallet,
        ),
      ),
      if (style.showWalletDivider) ...<Widget>[
        const SizedBox(height: 16),
        _WalletDivider(
          key: paymentViewWalletDividerKey,
          text: _orLocalized(style.walletDividerText, strings.orPayByCard),
          style: secondary,
          lineColor: formLook.border,
        ),
      ],
      const SizedBox(height: 16),
    ];
  }
}

/// "Or pay by card" between the wallet button and the card form (CONTRACT
/// §17.9): the text centred, with a 1-high line in the border colour on
/// each side, 12 from the text.
class _WalletDivider extends StatelessWidget {
  const _WalletDivider({
    super.key,
    required this.text,
    required this.style,
    required this.lineColor,
  });

  final String text;
  final TextStyle style;
  final Color lineColor;

  @override
  Widget build(BuildContext context) {
    final Widget line = Expanded(
      child: SizedBox(height: 1, child: ColoredBox(color: lineColor)),
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) => Row(
        children: <Widget>[
          line,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ConstrainedBox(
              // A long text wraps, and the lines keep some length.
              constraints: BoxConstraints(
                maxWidth: math.max(0, (constraints.maxWidth - 24) * 0.8),
              ),
              child: Text(text, style: style, textAlign: TextAlign.center),
            ),
          ),
          line,
        ],
      ),
    );
  }
}

/// The Pay button: full width, the brand colour, white title; 50% opacity
/// while disabled, and a white spinner instead of the title while [busy].
/// With [disabledColor] or [disabledTextColor] (CONTRACT §18.3) a disabled
/// button is drawn in those colours at full opacity.
class _PayButton extends StatefulWidget {
  const _PayButton({
    super.key,
    required this.title,
    required this.enabled,
    required this.busy,
    required this.color,
    required this.textStyle,
    required this.disabledColor,
    required this.disabledTextColor,
    required this.height,
    required this.cornerRadius,
    required this.cornerSmoothing,
    required this.onPressed,
  });

  final String title;
  final bool enabled;
  final bool busy;
  final Color color;
  final TextStyle textStyle;
  final Color? disabledColor;
  final Color? disabledTextColor;
  final double height;
  final double cornerRadius;
  final double cornerSmoothing;
  final VoidCallback onPressed;

  @override
  State<_PayButton> createState() => _PayButtonState();
}

class _PayButtonState extends State<_PayButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  void _activate() {
    _setPressed(false);
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.enabled && !widget.busy;
    if (!enabled) _pressed = false;
    // CONTRACT §18.3: the disabled colours, when set, replace the 50% opacity.
    final bool disabledColors =
        widget.disabledColor != null || widget.disabledTextColor != null;
    final bool dimmed = !enabled && !disabledColors;
    final Color background = enabled || !disabledColors
        ? widget.color
        : widget.disabledColor ?? widget.color;
    final TextStyle textStyle = enabled || !disabledColors
        ? widget.textStyle
        : widget.textStyle.copyWith(
            color: widget.disabledTextColor ?? widget.textStyle.color,
          );
    final Color foreground = textStyle.color ?? const Color(0xFFFFFFFF);
    final Widget child = widget.busy
        ? SizedBox.square(
            key: paymentViewSpinnerKey,
            dimension: 20,
            child: switch (defaultTargetPlatform) {
              TargetPlatform.iOS || TargetPlatform.macOS =>
                CupertinoActivityIndicator(color: foreground),
              _ => CircularProgressIndicator(strokeWidth: 2, color: foreground),
            },
          )
        : Text(
            widget.title,
            style: textStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          );
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.title,
      onTap: enabled ? _activate : null,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTapDown: enabled ? (_) => _setPressed(true) : null,
          onTapCancel: enabled ? () => _setPressed(false) : null,
          onTap: enabled ? _activate : null,
          child: Opacity(
            opacity: dimmed ? 0.5 : (_pressed ? 0.8 : 1),
            child: DecoratedBox(
              decoration: roundedRectDecoration(
                color: background,
                radius: widget.cornerRadius,
                smoothing: widget.cornerSmoothing,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: widget.height),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Center(widthFactor: 1, heightFactor: 1, child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An image of the payment view at its size in points.
class _Asset extends StatelessWidget {
  const _Asset(
    this.name, {
    required this.width,
    required this.height,
    this.label,
  });

  final String name;
  final double width;
  final double height;
  final String? label;

  @override
  Widget build(BuildContext context) => Image.asset(
    name,
    package: PaymentViewAssets.package,
    width: width,
    height: height,
    fit: BoxFit.contain,
    semanticLabel: label,
    excludeFromSemantics: label == null,
  );
}

/// The accepted cards (CONTRACT §16.14, §18.4): Mastercard and Visa, 28
/// high, 8 apart, centred. Each badge is its mark in a frame drawn here: a
/// 1-wide [borderColor] stroke with an outer radius of 4 and no fill.
class _Badges extends StatelessWidget {
  const _Badges({
    super.key,
    required this.borderColor,
    required this.cornerSmoothing,
  });

  final Color borderColor;
  final double cornerSmoothing;

  Widget _badge(String brand, String mark, double width, String label) =>
      DecoratedBox(
        key: paymentViewBadgeKey(brand),
        decoration: roundedRectDecoration(
          side: BorderSide(color: borderColor),
          radius: 4,
          smoothing: cornerSmoothing,
        ),
        child: _Asset(mark, width: width, height: 28, label: label),
      );

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    spacing: 8,
    runSpacing: 8,
    children: <Widget>[
      _badge(
        PayriffCardBrand.mastercard.value,
        PaymentViewAssets.mastercardMark,
        43,
        'Mastercard',
      ),
      _badge(
        PayriffCardBrand.visa.value,
        PaymentViewAssets.visaMark,
        42,
        'Visa',
      ),
    ],
  );
}

/// The colour of the lock before the secure line.
const Color _lockColor = Color(0xFF56BE3D);

/// The lock, 6 apart from `view.secure`, centred.
class _SecureLine extends StatelessWidget {
  const _SecureLine({super.key, required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: <Widget>[
      const GlyphIcon(Glyph.lock, color: _lockColor, size: 15),
      const SizedBox(width: 6),
      Flexible(
        child: Text(text, style: style, textAlign: TextAlign.center),
      ),
    ],
  );
}

/// `view.poweredBy` (or `PayriffStrings.poweredBy`) with the Payriff logo
/// where "Payriff" is, or after the text without it, centred. The logo has a
/// light wordmark in dark mode.
class _PoweredBy extends StatelessWidget {
  const _PoweredBy({
    super.key,
    required this.strings,
    required this.style,
    required this.dark,
  });

  final PayriffCardStrings strings;
  final TextStyle style;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    // CONTRACT §18.6: a text without "Payriff" is followed by the logo.
    final ({String before, String after}) parts = strings.poweredByParts;
    return Semantics(
      container: true,
      label: '${parts.before}$payriffWordmark${parts.after}',
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          style: style,
          children: <InlineSpan>[
            if (parts.before.isNotEmpty) TextSpan(text: parts.before),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: _Asset(
                PaymentViewAssets.footerLogo(dark: dark),
                width: 82,
                height: 16,
                label: payriffWordmark,
              ),
            ),
            if (parts.after.isNotEmpty) TextSpan(text: parts.after),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// [custom] without surrounding white space, or [localized] when it is null or
/// blank (CONTRACT §16.14).
String _orLocalized(String? custom, String localized) {
  final String? trimmed = custom?.trim();
  return trimmed == null || trimmed.isEmpty ? localized : trimmed;
}
