import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../config.dart';
import '../error.dart';
import '../internal/card/card_strings.dart';
import '../internal/language.dart';
import '../internal/ui/glyphs.dart';
import '../payriff.dart';
import '../result.dart';
import 'card_form.dart';
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

/// Key of the lock and "Proceed securely by PCI DSS" line.
const Key paymentViewSecureKey = ValueKey<String>('payriff.view.secure');

/// Key of the "Powered by Payriff" footer.
const Key paymentViewPoweredByKey = ValueKey<String>('payriff.view.poweredBy');

/// The images of the payment view (CONTRACT §16.14), package assets of
/// `payriff` with 2.0x and 3.0x variants.
abstract final class PaymentViewAssets {
  /// The package that holds the images.
  static const String package = 'payriff';

  /// The Mastercard acceptance badge, 43×28.
  static const String mastercard = 'assets/payment_view/mastercard.png';

  /// The Visa acceptance badge, 42×28.
  static const String visa = 'assets/payment_view/visa.png';

  /// The Payriff logo of the footer, 82×16.
  static const String logo = 'assets/payment_view/payriff-logo.png';

  /// Every image.
  static const List<String> all = <String>[mastercard, visa, logo];
}

/// The Pay button's title (CONTRACT §16.14): `view.pay`, then the amount
/// with 2 decimals and `.` as the separator, then the currency, for example
/// "Pay 1.02 AZN". Only `view.pay` while the amount is unknown.
String paymentViewPayTitle(
  PayriffCardStrings strings,
  PayriffClientOrder? order,
) {
  final num? amount = order?.amount;
  if (amount == null || !amount.isFinite) return strings.pay;
  final String currency = order?.currency?.trim() ?? '';
  return <String>[
    strings.pay,
    amount.toStringAsFixed(2),
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
  });

  /// The id of the order your server created.
  final String orderId;

  /// The order's client secret (`pr_cs_…`) from your server.
  final String clientSecret;

  /// Called with the result of each payment attempt, and once with a fatal
  /// error that ends the order (`PayriffError.isFatal`). The result is for
  /// the user interface: fulfil the order on your server.
  final ValueChanged<PayriffResult> onResult;

  /// The language of the view and the form. `null` uses
  /// `PayriffConfig.language`, then the device language.
  final PayriffLanguage? language;

  /// The colours, sizes and parts of the view, and the form's look.
  final PayriffPaymentViewStyle style;

  @override
  State<PayriffPaymentView> createState() => _PayriffPaymentViewState();
}

class _PayriffPaymentViewState extends State<PayriffPaymentView> {
  final PayriffCardController _card = PayriffCardController();

  PayriffClientOrder? _order;
  bool _loading = true;

  /// Why the order did not load or can no longer be paid (an error
  /// message); shown under the button. An order that loaded but cannot be
  /// paid by card shows `view.notPayable` instead, in the view's language.
  String? _error;

  /// A payment ended with a status, or the order can no longer be paid.
  bool _finished = false;
  bool _paying = false;
  bool _fatalReported = false;

  /// Bumped for every order load, so a stale answer is dropped.
  int _loadGeneration = 0;

  bool get _payable =>
      !_loading &&
      !_finished &&
      _error == null &&
      (_order?.isPayableByCard ?? false);

  bool get _canPay =>
      _payable && _card.isComplete && !_paying && !_card.isProcessing;

  @override
  void initState() {
    super.initState();
    unawaited(_loadOrder());
  }

  @override
  void didUpdateWidget(PayriffPaymentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orderId != widget.orderId ||
        oldWidget.clientSecret != widget.clientSecret) {
      _fatalReported = false;
      unawaited(_loadOrder());
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _card.dispose();
    super.dispose();
  }

  /// CONTRACT §16.14: reads the order when the view appears.
  Future<void> _loadOrder() async {
    final int generation = ++_loadGeneration;
    _order = null;
    _error = null;
    _finished = false;
    _loading = true;
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
      if (error != null) _error = error.message;
    });
    if (error != null && error.isFatal) _reportFatal(error);
  }

  void _reportFatal(PayriffError error) {
    if (_fatalReported) return;
    _fatalReported = true;
    widget.onResult(PayriffResultFailed(error: error));
  }

  Future<void> _pay() async {
    if (!_canPay) return;
    setState(() => _paying = true);
    final PayriffResult result = await Payriff.confirmCardPayment(
      context,
      _card,
      orderId: widget.orderId,
      clientSecret: widget.clientSecret,
    );
    final PayriffError? error = result.error;
    final bool orderEnded =
        error != null &&
        (error.isFatal || error.code == PayriffErrorCode.orderNotPayable);
    if (mounted) {
      setState(() {
        _paying = false;
        // A payment that reached a status, or an order that can no longer
        // be paid: the order is not paid again from this view.
        if (result is! PayriffResultFailed) _finished = true;
        if (orderEnded) _error = error.message;
      });
    }
    if (error != null && error.isFatal) _fatalReported = true;
    widget.onResult(result);
  }

  @override
  Widget build(BuildContext context) {
    final PayriffPaymentViewStyle style = widget.style;
    final bool dark = payriffIsDark(context);
    final PayriffLanguage language =
        widget.language ?? Payriff.config?.language ?? deviceLanguage();
    final PayriffCardStrings strings = PayriffCardStrings(language);
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
    // CONTRACT §16.14: an error message, or `view.notPayable` for an order
    // that loaded but cannot be paid by card.
    final String? error =
        _error ??
        (order != null && !order.isPayableByCard ? strings.notPayable : null);

    final Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PayriffCardForm(
          controller: _card,
          language: language,
          style: style.formStyle,
        ),
        const SizedBox(height: 24),
        ListenableBuilder(
          listenable: _card,
          builder: (BuildContext context, _) => _PayButton(
            key: paymentViewPayButtonKey,
            title: paymentViewPayTitle(strings, order),
            enabled: _canPay,
            busy: _paying || _card.isProcessing,
            color: style.buttonColor ?? payriffBrandColor,
            textStyle: const TextStyle(
              color: Color(0xFFFFFFFF),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ).merge(style.buttonTextStyle),
            height: style.buttonHeight,
            cornerRadius: style.buttonCornerRadius,
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
          const _Badges(key: paymentViewBadgesKey),
        ],
        if (style.showSecureNote) ...<Widget>[
          SizedBox(height: style.showBadges ? 20 : 24),
          _SecureLine(
            key: paymentViewSecureKey,
            text: strings.secure,
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
            ),
          )
        : null;

    // A Material ancestor gives the text the app's font and no debug
    // underline, also inside a CupertinoApp.
    return Material(
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
    );
  }
}

/// The Pay button: full width, the brand colour, white title; 50% opacity
/// while disabled, and a white spinner instead of the title while [busy].
class _PayButton extends StatefulWidget {
  const _PayButton({
    super.key,
    required this.title,
    required this.enabled,
    required this.busy,
    required this.color,
    required this.textStyle,
    required this.height,
    required this.cornerRadius,
    required this.onPressed,
  });

  final String title;
  final bool enabled;
  final bool busy;
  final Color color;
  final TextStyle textStyle;
  final double height;
  final double cornerRadius;
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
    final Color foreground = widget.textStyle.color ?? const Color(0xFFFFFFFF);
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
            style: widget.textStyle,
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
            opacity: enabled ? (_pressed ? 0.8 : 1) : 0.5,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(widget.cornerRadius),
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

/// The accepted cards (CONTRACT §16.14): Mastercard and Visa, 28 high, 8
/// apart, centred.
class _Badges extends StatelessWidget {
  const _Badges({super.key});

  @override
  Widget build(BuildContext context) => const Wrap(
    alignment: WrapAlignment.center,
    spacing: 8,
    runSpacing: 8,
    children: <Widget>[
      _Asset(
        PaymentViewAssets.mastercard,
        width: 43,
        height: 28,
        label: 'Mastercard',
      ),
      _Asset(PaymentViewAssets.visa, width: 42, height: 28, label: 'Visa'),
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

/// `view.poweredBy` with the Payriff logo where "Payriff" is, centred.
class _PoweredBy extends StatelessWidget {
  const _PoweredBy({super.key, required this.strings, required this.style});

  final PayriffCardStrings strings;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final ({String before, String after})? parts = strings.poweredByParts;
    return Semantics(
      container: true,
      label: strings.poweredBy,
      excludeSemantics: true,
      child: parts == null
          ? Text(strings.poweredBy, style: style, textAlign: TextAlign.center)
          : Text.rich(
              TextSpan(
                style: style,
                children: <InlineSpan>[
                  if (parts.before.isNotEmpty) TextSpan(text: parts.before),
                  const WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: _Asset(
                      PaymentViewAssets.logo,
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
