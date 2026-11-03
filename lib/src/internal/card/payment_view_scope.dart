import 'package:flutter/widgets.dart';

import '../../strings.dart';

/// What `PayriffPaymentView` hands the `PayriffCardForm` inside it: the
/// view's corner smoothing and badge border, for the form's style to fall
/// back on (CONTRACT §18.2, §18.4), and the view's own texts, which win over
/// `PayriffConfig.strings` (§18.6). Internal to the SDK.
class PaymentViewScope extends InheritedWidget {
  /// Creates the scope around [child].
  const PaymentViewScope({
    super.key,
    required this.cornerSmoothing,
    required this.badgeBorderColor,
    required this.strings,
    required super.child,
  });

  /// `PayriffPaymentViewStyle.cornerSmoothing`.
  final double cornerSmoothing;

  /// `PayriffPaymentViewStyle.badgeBorderColor`.
  final Color? badgeBorderColor;

  /// `PayriffPaymentView.strings`.
  final PayriffStrings? strings;

  /// The scope above [context], or `null` outside a payment view.
  static PaymentViewScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PaymentViewScope>();

  @override
  bool updateShouldNotify(PaymentViewScope oldWidget) =>
      oldWidget.cornerSmoothing != cornerSmoothing ||
      oldWidget.badgeBorderColor != badgeBorderColor ||
      oldWidget.strings != strings;
}
