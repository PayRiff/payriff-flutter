/// CONTRACT §16.16: card payments on compromised devices. The plugin's
/// native checks look for root, a jailbreak, hooking frameworks and a
/// debugger (`deviceIntegrity` on `payriff/native`); this applies
/// `PayriffConfig.allowCompromisedDevices` to what they found.
///
/// The checks are local, so a determined attacker can get past them; they
/// stop the common tools (Magisk, Frida, Xposed, Substrate and the like).
library;

import '../../error.dart';
import '../logger.dart';
import '../native_bridge.dart';

/// The error of a payment refused on a compromised device. Not retryable
/// and not fatal: the order can still be paid on another device.
const PayriffError deviceCompromisedError = PayriffError(
  code: PayriffErrorCode.deviceCompromised,
  message: 'Card payments are not available on this device.',
);

/// The signal of checks that could not complete: no plugin, a platform
/// error or a malformed reply.
const String checkFailedSignal = 'check failed';

/// What the plugin's checks find now. Fails closed: when they cannot
/// complete, the device counts as compromised with [checkFailedSignal], so
/// breaking the check does not skip it. Never throws.
Future<DeviceIntegrityReport> deviceIntegrityReport() async =>
    await NativeBridge.deviceIntegrity() ??
    (compromised: true, signals: const <String>[checkFailedSignal]);

/// Checks the device at [point] of a payment: when the payment view
/// appears, when `confirmCardPayment` starts and right before the card is
/// encrypted. Returns [deviceCompromisedError] when the payment must stop,
/// otherwise `null`.
///
/// Every call asks the plugin again, so a hooking tool or a debugger that
/// attached after an earlier point is found. On a compromised device a
/// warning names the signals; with [allowCompromisedDevices] that warning is
/// all that happens. Checks that cannot complete count as the signal
/// [checkFailedSignal], like any other.
Future<PayriffError?> deviceIntegrityError({
  required bool allowCompromisedDevices,
  required SdkLogger logger,
  required String point,
}) async {
  final DeviceIntegrityReport report = await deviceIntegrityReport();
  if (!report.compromised) return null;
  final String signals = report.signals.isEmpty
      ? 'unnamed signal'
      : report.signals.join(', ');
  if (allowCompromisedDevices) {
    logger.warning(
      'Compromised device ($signals) at $point: allowed by '
      'PayriffConfig.allowCompromisedDevices',
    );
    return null;
  }
  logger.warning(
    'Compromised device ($signals) at $point: card payments are refused',
  );
  return deviceCompromisedError;
}
