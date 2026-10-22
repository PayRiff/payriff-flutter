import 'package:flutter/material.dart';
import 'package:payriff/payriff.dart';

/// Where the payment view appears. All three show the same
/// [PayriffPaymentView]; only the container differs.
enum PaymentPresentation {
  /// A full screen with a back button.
  page('Pay in page'),

  /// A modal bottom sheet, like Stripe's PaymentSheet.
  bottomSheet('Pay in bottom sheet'),

  /// A centred dialog.
  popup('Pay in popup');

  const PaymentPresentation(this.title);

  /// The button title on the home screen.
  final String title;
}

/// The order your backend created.
typedef PaymentOrder = ({String orderId, String clientSecret});

/// Shows the payment view in [presentation] and completes with its result,
/// or `null` when the customer closes it without paying.
Future<PayriffResult?> presentPayment(
  BuildContext context,
  PaymentPresentation presentation,
  PaymentOrder order,
) => switch (presentation) {
  PaymentPresentation.page => Navigator.of(context).push<PayriffResult>(
    MaterialPageRoute<PayriffResult>(
      builder: (BuildContext context) => _PaymentPage(order: order),
    ),
  ),
  PaymentPresentation.bottomSheet => showModalBottomSheet<PayriffResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: _background(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    // Sized by its content, like a payment sheet; it scrolls when the
    // keyboard needs the room.
    builder: (BuildContext context) => SingleChildScrollView(
      child: _view(
        context,
        order,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      ),
    ),
  ),
  PaymentPresentation.popup => showDialog<PayriffResult>(
    context: context,
    builder: (BuildContext context) => _PaymentPopup(order: order),
  ),
};

/// The background of pay.payriff.com, which the view paints too.
Color _background(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF222224)
    : const Color(0xFFFCFCFD);

/// The SDK's default payment view; its result closes the presentation.
Widget _view(
  BuildContext context,
  PaymentOrder order, {
  EdgeInsets padding = const EdgeInsets.all(20),
}) => PayriffPaymentView(
  key: const ValueKey<String>('payment-view'),
  orderId: order.orderId,
  clientSecret: order.clientSecret,
  style: PayriffPaymentViewStyle(padding: padding),
  onResult: (PayriffResult result) => Navigator.of(context).pop(result),
);

class _PaymentPage extends StatelessWidget {
  const _PaymentPage({required this.order});

  final PaymentOrder order;

  @override
  Widget build(BuildContext context) {
    final Color background = _background(context);
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: _view(context, order),
    );
  }
}

class _PaymentPopup extends StatelessWidget {
  const _PaymentPopup({required this.order});

  final PaymentOrder order;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: _background(context),
    insetPadding: const EdgeInsets.all(16),
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Stack(
        children: <Widget>[
          // The dialog sits clear of the status bar and the home indicator.
          MediaQuery.removePadding(
            context: context,
            removeTop: true,
            removeBottom: true,
            child: SingleChildScrollView(
              child: _view(
                context,
                order,
                padding: const EdgeInsets.fromLTRB(20, 48, 20, 20),
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              key: const ValueKey<String>('popup-close'),
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    ),
  );
}
