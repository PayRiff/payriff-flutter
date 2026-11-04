import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'wallet_rules.dart';

/// The official Apple Pay or Google Pay button (CONTRACT §17.10) as a
/// platform view: `PKPaymentButton` in a [UiKitView]
/// (`payriff/apple_pay_button`), Google's `PayButton` in an [AndroidView]
/// (`payriff/google_pay_button`). Nothing else draws the wallets' marks.
///
/// [params] are style values only ([applePayButtonParams],
/// [googlePayButtonParams]), never a key or the client secret. A tap comes
/// back on the view's own channel (`<viewType>/<id>`, method `tap`) and
/// reaches [onTap] while [enabled]. Disabled, the button is shown at 50%
/// opacity and takes no touches. New [params] create a new native view,
/// because a platform view keeps the parameters it was created with.
class WalletPlatformButton extends StatefulWidget {
  /// Creates the button of [kind].
  const WalletPlatformButton({
    super.key,
    required this.kind,
    required this.params,
    required this.height,
    required this.enabled,
    required this.onTap,
  });

  /// Which wallet's button.
  final WalletKind kind;

  /// The creation parameters of the native button.
  final Map<String, Object?> params;

  /// The height; the width is the parent's. `null` takes the parent's
  /// height too, which must then be bounded: the payment view gives its
  /// wallet button the Pay button's height that way (CONTRACT §20.2).
  final double? height;

  /// Whether taps reach [onTap].
  final bool enabled;

  /// Called when the customer taps the button.
  final VoidCallback onTap;

  @override
  State<WalletPlatformButton> createState() => _WalletPlatformButtonState();
}

class _WalletPlatformButtonState extends State<WalletPlatformButton> {
  MethodChannel? _channel;

  void _created(int id) {
    _channel?.setMethodCallHandler(null);
    _channel = MethodChannel('${widget.kind.viewType}/$id')
      ..setMethodCallHandler(_handle);
  }

  Future<Object?> _handle(MethodCall call) async {
    if (call.method == 'tap' && mounted && widget.enabled) widget.onTap();
    return null;
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Key key = ValueKey<String>(jsonEncode(widget.params));
    const StandardMessageCodec codec = StandardMessageCodec();
    final Widget view = switch (widget.kind) {
      WalletKind.applePay => UiKitView(
        key: key,
        viewType: widget.kind.viewType,
        creationParams: widget.params,
        creationParamsCodec: codec,
        onPlatformViewCreated: _created,
      ),
      WalletKind.googlePay => AndroidView(
        key: key,
        viewType: widget.kind.viewType,
        creationParams: widget.params,
        creationParamsCodec: codec,
        onPlatformViewCreated: _created,
      ),
    };
    return SizedBox(
      height: widget.height,
      child: IgnorePointer(
        ignoring: !widget.enabled,
        child: Opacity(opacity: widget.enabled ? 1 : 0.5, child: view),
      ),
    );
  }
}
