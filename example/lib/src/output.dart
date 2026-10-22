import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:payriff/payriff.dart';

/// The outcome of a payment, as shown in the result sheet: a large icon and
/// title, then the amount, order id, status and error, and the result's JSON
/// (CONTRACT §5.3).
class ResultView extends StatelessWidget {
  const ResultView({super.key, required this.result});

  final PayriffResult result;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final (String title, IconData icon, Color color) = switch (result) {
      PayriffResultSuccess() => (
        'Payment successful',
        Icons.check_circle,
        Colors.green.shade600,
      ),
      PayriffResultDeclined() => (
        'Payment declined',
        Icons.cancel,
        colors.error,
      ),
      PayriffResultPending() => (
        'Payment pending',
        Icons.schedule,
        Colors.orange.shade700,
      ),
      PayriffResultCancelled() => (
        'Payment cancelled',
        Icons.remove_circle,
        colors.outline,
      ),
      PayriffResultFailed() => ('Payment failed', Icons.error, colors.error),
    };
    return Column(
      key: const ValueKey<String>('result-view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Icon(icon, size: 64, color: color),
        const SizedBox(height: 8),
        Text(
          title,
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        for (final (String label, String? value) in _rows(result))
          if (value != null && value.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 110,
                    child: Text(label, style: theme.textTheme.bodySmall),
                  ),
                  Expanded(child: SelectableText(value)),
                ],
              ),
            ),
        const Divider(height: 24),
        SelectableText(
          const JsonEncoder.withIndent('  ').convert(result.toJson()),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ],
    );
  }

  static List<(String, String?)> _rows(PayriffResult result) {
    final PayriffPayment? payment = result.payment;
    return <(String, String?)>[
      ('Amount', formatAmount(payment?.amount, payment?.currency)),
      ('Order ID', payment?.orderId),
      ('Status', payment?.status.value),
      ('Raw status', payment?.rawStatus),
      if (result case PayriffResultCancelled(:final PayriffCancelReason reason))
        ('Reason', reason.name),
      if (result case PayriffResultPending(:final PayriffPendingReason reason))
        ('Reason', reason.name),
      if (result case PayriffResultFailed(
        :final PayriffError error,
      )) ...<(String, String?)>[
        ('Error code', error.code.value),
        ('Message', error.message),
        if (error.fields case final List<PayriffCardFieldError> fields
            when fields.isNotEmpty)
          (
            'Fields',
            fields
                .map(
                  (PayriffCardFieldError f) =>
                      '${f.field.value}: ${f.error.value}',
                )
                .join(', '),
          ),
        ('HTTP', error.httpStatus?.toString()),
        ('Payriff code', error.payriffCode),
        ('Ticket', error.supportTicket),
      ],
    ];
  }
}

/// `10.50 AZN`, or `null` without an amount.
String? formatAmount(num? amount, String? currency) {
  if (amount == null) return null;
  return '${amount.toStringAsFixed(2)} ${currency ?? ''}'.trim();
}
