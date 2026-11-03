/// What card and wallet payments share before anything is sent: one payment
/// at a time (CONTRACT §9.5) and the checks of the configuration and the
/// arguments.
library;

import '../error.dart';
import 'request.dart';

/// Whether a payment runs, card or wallet (`Payriff.isPaymentInProgress`).
/// A payment claims it before its first `await`, so a second tap cannot
/// start another one, and releases it when it ends.
bool paymentInProgress = false;

/// The error of a payment started while another one runs.
const PayriffError paymentInProgressError = PayriffError(
  code: PayriffErrorCode.paymentInProgress,
  message: 'Another Payriff payment is already running.',
);

/// The error of a payment without a navigator for the 3-D Secure sheet.
const PayriffError noNavigatorError = PayriffError(
  code: PayriffErrorCode.presentationFailed,
  message:
      'No Navigator was found above the BuildContext. Pass a context '
      'from a widget inside your MaterialApp or CupertinoApp.',
);

/// The error of a configuration without a usable publishable key.
PayriffError publishableKeyError() => invalidConfig(
  'The card flow needs PayriffConfig.publishableKey: the publishable key '
  '(pr_pk_live_…) of your Payriff application, never the secret key.',
);

/// The error of an [orderId] (trimmed) or a client secret ([secret], `null`
/// when not usable) that cannot be used, or `null`. Never echoes a value.
PayriffError? orderArgumentError(String orderId, String? secret) {
  if (orderId.isEmpty || orderId == '.' || orderId == '..') {
    return invalidOrder('orderId must be the Payriff order id.');
  }
  if (secret == null) {
    return invalidOrder(
      'clientSecret must be the order\'s client secret (pr_cs_…) from '
      'your server.',
    );
  }
  return null;
}
