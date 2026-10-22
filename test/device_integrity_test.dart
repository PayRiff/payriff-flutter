// CONTRACT §16.16 on the Dart side: the reply of the plugin's
// `deviceIntegrity`, the allowCompromisedDevices policy, failing closed when
// the checks cannot complete, the checks of confirmCardPayment (at its start
// and right before the card is encrypted), Payriff.isDeviceCompromised and
// retrieveOrder, with a fake Client API and a mocked `payriff/native`
// channel. The native checks themselves are tested
// in android/src/test (Kotlin) and example/ios/RunnerTests (Swift); the
// payment view's part is in payment_view_test.dart.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:payriff/payriff.dart';
import 'package:payriff/src/card/card_form.dart';
import 'package:payriff/src/internal/card/card_clock.dart';
import 'package:payriff/src/internal/card/device_integrity.dart';
import 'package:payriff/src/internal/logger.dart';
import 'package:payriff/src/internal/native_bridge.dart';

import 'support/card_support.dart';
import 'support/fake_webview.dart';

const PayriffConfig _config = PayriffConfig(
  environment: PayriffEnvironment.sandbox,
  publishableKey: testPublishableKey,
  enableLogging: true,
);

/// The warnings logged while [body] runs.
Future<List<String>> _warnings(Future<void> Function() body) async {
  final List<String> warnings = <String>[];
  final StreamSubscription<PayriffLogEntry> logs = Payriff.logStream.listen((
    PayriffLogEntry entry,
  ) {
    if (entry.level == PayriffLogLevel.warning) warnings.add(entry.message);
  });
  try {
    await body();
    // logStream is asynchronous.
    await Future<void>.delayed(Duration.zero);
  } finally {
    await logs.cancel();
  }
  return warnings;
}

/// [report] says [compromised] with [signals].
void _expectReport(
  DeviceIntegrityReport? report,
  bool compromised,
  List<String> signals,
) {
  expect(report, isNotNull);
  expect(report!.compromised, compromised);
  expect(report.signals, signals);
}

void _expectRefused(PayriffResult result) {
  expect(result, isA<PayriffResultFailed>());
  final PayriffError error = result.error!;
  expect(error.code, PayriffErrorCode.deviceCompromised);
  expect(error.message, 'Card payments are not available on this device.');
  expect(error.isRetryable, isFalse);
  expect(error.isFatal, isFalse);
  expect(error.toJson()['code'], 'DEVICE_COMPROMISED');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    Payriff.debugReset();
    installFakeWebView();
    debugPayriffCardClock = FakeCardClock();
  });

  tearDown(() {
    debugPayriffCardClock = null;
    Payriff.debugReset();
  });

  group('the plugin reply', () {
    test('clean and compromised devices', () async {
      final NativeCalls native = NativeCalls()..install();
      _expectReport(await NativeBridge.deviceIntegrity(), false, <String>[]);
      native.integrityReply = NativeCalls.compromised();
      _expectReport(await NativeBridge.deviceIntegrity(), true, <String>[
        'su binary',
        'Frida',
      ]);
      expect(native.named('deviceIntegrity'), hasLength(2));
    });

    test('signal names of another shape are dropped; a signal makes the '
        'device compromised', () async {
      final NativeCalls native = NativeCalls()..install();
      native.integrityReply = <String, Object?>{
        'compromised': false,
        'signals': <Object?>[
          'DYLD_INSERT_LIBRARIES',
          'frida-server',
          '/data/adb/magisk',
          'line\nbreak',
          'x' * 41,
          42,
          null,
        ],
      };
      _expectReport(await NativeBridge.deviceIntegrity(), true, <String>[
        'DYLD_INSERT_LIBRARIES',
        'frida-server',
      ]);
      native.integrityReply = <String, Object?>{'compromised': true};
      _expectReport(await NativeBridge.deviceIntegrity(), true, <String>[]);
    });

    test('no plugin, an error or a reply without the flag: unknown', () async {
      expect(await NativeBridge.deviceIntegrity(), isNull);
      final NativeCalls native = NativeCalls()..install();
      for (final Object? reply in <Object?>[
        null,
        'compromised',
        <String, Object?>{'compromised': 'true'},
        <String, Object?>{
          'signals': <String>['Frida'],
        },
        PlatformException(code: 'unavailable'),
      ]) {
        native.integrityReply = reply;
        expect(await NativeBridge.deviceIntegrity(), isNull, reason: '$reply');
      }
    });
  });

  group('Payriff.isDeviceCompromised', () {
    test('reports the device without configure, whatever the policy', () async {
      final NativeCalls native = NativeCalls()..install();
      expect(await Payriff.isDeviceCompromised(), isFalse);
      native.integrityReply = NativeCalls.compromised();
      expect(await Payriff.isDeviceCompromised(), isTrue);
      Payriff.configure(const PayriffConfig(allowCompromisedDevices: true));
      expect(await Payriff.isDeviceCompromised(), isTrue);
    });

    test('true when the checks cannot complete: no plugin, an error or a '
        'malformed reply', () async {
      expect(await Payriff.isDeviceCompromised(), isTrue);
      final NativeCalls native = NativeCalls()..install();
      for (final Object? reply in <Object?>[
        PlatformException(code: 'unavailable'),
        <String, Object?>{'signals': <String>[]},
      ]) {
        native.integrityReply = reply;
        expect(await Payriff.isDeviceCompromised(), isTrue, reason: '$reply');
      }
    });
  });

  group('the policy (allowCompromisedDevices)', () {
    final SdkLogger logger = sdkLoggerFor(_config);

    test('a clean device goes on, without a warning', () async {
      NativeCalls().install();
      final List<String> warnings = await _warnings(() async {
        expect(
          await deviceIntegrityError(
            allowCompromisedDevices: false,
            logger: logger,
            point: 'test',
          ),
          isNull,
        );
      });
      expect(warnings, isEmpty);
    });

    test('a compromised device is refused by default, with a warning that '
        'names the signals', () async {
      NativeCalls()
        ..integrityReply = NativeCalls.compromised(<String>['Magisk', 'Frida'])
        ..install();
      final List<String> warnings = await _warnings(() async {
        expect(
          await deviceIntegrityError(
            allowCompromisedDevices: false,
            logger: logger,
            point: 'test',
          ),
          deviceCompromisedError,
        );
      });
      expect(warnings, <String>[
        'Compromised device (Magisk, Frida) at test: card payments are '
            'refused',
      ]);
    });

    test('allowCompromisedDevices only logs the warning', () async {
      NativeCalls()
        ..integrityReply = NativeCalls.compromised(<String>['debugger'])
        ..install();
      final List<String> warnings = await _warnings(() async {
        expect(
          await deviceIntegrityError(
            allowCompromisedDevices: true,
            logger: logger,
            point: 'test',
          ),
          isNull,
        );
      });
      expect(warnings, <String>[
        'Compromised device (debugger) at test: allowed by '
            'PayriffConfig.allowCompromisedDevices',
      ]);
    });

    test('checks that cannot complete fail closed with the signal "check '
        'failed"', () async {
      _expectReport(await deviceIntegrityReport(), true, <String>[
        'check failed',
      ]);
      final List<String> warnings = await _warnings(() async {
        // No plugin, then an error and malformed replies.
        expect(
          await deviceIntegrityError(
            allowCompromisedDevices: false,
            logger: logger,
            point: 'test',
          ),
          deviceCompromisedError,
        );
        final NativeCalls native = NativeCalls()..install();
        for (final Object? reply in <Object?>[
          PlatformException(code: 'integrity_failed'),
          null,
          <String, Object?>{'compromised': 'false'},
        ]) {
          native.integrityReply = reply;
          expect(
            await deviceIntegrityError(
              allowCompromisedDevices: false,
              logger: logger,
              point: 'test',
            ),
            deviceCompromisedError,
            reason: '$reply',
          );
        }
      });
      expect(
        warnings,
        List<String>.filled(
          4,
          'Compromised device (check failed) at test: card payments are '
          'refused',
        ),
      );
    });

    test('allowCompromisedDevices lets a failed check through, with the '
        'warning', () async {
      final List<String> warnings = await _warnings(() async {
        expect(
          await deviceIntegrityError(
            allowCompromisedDevices: true,
            logger: logger,
            point: 'test',
          ),
          isNull,
        );
      });
      expect(warnings, <String>[
        'Compromised device (check failed) at test: allowed by '
            'PayriffConfig.allowCompromisedDevices',
      ]);
    });
  });

  group('confirmCardPayment', () {
    testWidgets('a compromised device sends nothing and gets '
        'DEVICE_COMPROMISED', (WidgetTester tester) async {
      final _Run run = await _start(tester);
      run.native.integrityReply = NativeCalls.compromised();

      final PayriffResult result = await run.confirm();

      _expectRefused(result);
      expect(run.backend.requests, isEmpty);
      expect(run.native.named('encryptCard'), isEmpty);
      expect(run.native.named('deviceIntegrity'), hasLength(1));
      expect(run.warnings, <String>[
        'Compromised device (su binary, Frida) at confirmCardPayment: card '
            'payments are refused',
      ]);
      // The card is not kept on a device it may not be paid from.
      expect(run.text(cardNumberFieldKey), isEmpty);
      expect(Payriff.isPaymentInProgress, isFalse);
      expect(run.controller.isProcessing, isFalse);
    });

    testWidgets('a hooking tool that attaches while the order loads stops '
        'the payment before the card is encrypted', (
      WidgetTester tester,
    ) async {
      final _Run run = await _start(tester);
      run.native.integrityReplies.addAll(<Object?>[
        NativeCalls.clean,
        NativeCalls.compromised(<String>['Frida']),
      ]);

      final PayriffResult result = await run.confirm();

      _expectRefused(result);
      expect(
        run.backend.requests.map(
          (http.Request r) => '${r.method} ${r.url.path}',
        ),
        <String>['GET /api/v3/client/orders/o1'],
      );
      expect(run.native.named('encryptCard'), isEmpty);
      expect(run.native.named('deviceIntegrity'), hasLength(2));
      expect(run.warnings, <String>[
        'Compromised device (Frida) at card encryption: card payments are '
            'refused',
      ]);
    });

    testWidgets('allowCompromisedDevices pays, with a warning at both '
        'checks', (WidgetTester tester) async {
      final _Run run = await _start(
        tester,
        config: const PayriffConfig(
          environment: PayriffEnvironment.sandbox,
          publishableKey: testPublishableKey,
          enableLogging: true,
          allowCompromisedDevices: true,
        ),
      );
      run.native.integrityReply = NativeCalls.compromised(<String>['Magisk']);

      final PayriffResult result = await run.confirm();

      expect(result, isA<PayriffResultSuccess>());
      expect(run.native.named('deviceIntegrity'), hasLength(2));
      expect(run.native.named('encryptCard'), hasLength(1));
      expect(run.backend.to('/pay'), hasLength(1));
      expect(run.warnings, <String>[
        'Compromised device (Magisk) at confirmCardPayment: allowed by '
            'PayriffConfig.allowCompromisedDevices',
        'Compromised device (Magisk) at card encryption: allowed by '
            'PayriffConfig.allowCompromisedDevices',
      ]);
    });

    testWidgets('checks that cannot complete refuse the payment', (
      WidgetTester tester,
    ) async {
      final _Run run = await _start(tester);
      run.native.integrityReply = PlatformException(code: 'unavailable');

      final PayriffResult result = await run.confirm();

      _expectRefused(result);
      expect(run.backend.requests, isEmpty);
      expect(run.native.named('encryptCard'), isEmpty);
      expect(run.warnings, <String>[
        'Compromised device (check failed) at confirmCardPayment: card '
            'payments are refused',
      ]);
    });

    testWidgets('a check that fails right before the card is encrypted '
        'stops the payment', (WidgetTester tester) async {
      final _Run run = await _start(tester);
      run.native.integrityReplies.addAll(<Object?>[
        NativeCalls.clean,
        'malformed',
      ]);

      final PayriffResult result = await run.confirm();

      _expectRefused(result);
      expect(run.backend.to('/pay'), isEmpty);
      expect(run.native.named('encryptCard'), isEmpty);
      expect(run.warnings, <String>[
        'Compromised device (check failed) at card encryption: card payments '
            'are refused',
      ]);
    });
  });

  testWidgets('retrieveOrder is never blocked', (WidgetTester tester) async {
    final NativeCalls native = NativeCalls()
      ..integrityReply = NativeCalls.compromised()
      ..install();
    FakeClientBackend().install();
    Payriff.configure(_config);
    final PayriffClientOrder order = await Payriff.retrieveOrder(
      orderId: testOrderId,
      clientSecret: testClientSecret,
    );
    expect(order.orderId, testOrderId);
    expect(native.named('deviceIntegrity'), isEmpty);
  });
}

/// One card form on screen, the mocks and the warnings logged.
final class _Run {
  _Run(this.context, this.controller, this.native, this.backend);

  final BuildContext Function() context;
  final PayriffCardController controller;
  final NativeCalls native;
  final FakeClientBackend backend;
  final List<String> warnings = <String>[];

  Future<PayriffResult> confirm() => pumpUntilDone(
    _tester!,
    Payriff.confirmCardPayment(
      context(),
      controller,
      orderId: testOrderId,
      clientSecret: testClientSecret,
    ),
  );

  String text(Key key) =>
      (find.byKey(key).evaluate().single.widget as TextField).controller!.text;
}

WidgetTester? _tester;

/// Shows a filled card form with a clean device, a payable order and the
/// warnings collected.
Future<_Run> _start(
  WidgetTester tester, {
  PayriffConfig config = _config,
}) async {
  _tester = tester;
  addTearDown(() => _tester = null);
  final NativeCalls native = NativeCalls()..install();
  final FakeClientBackend backend = FakeClientBackend()..install();
  Payriff.configure(config);
  final PayriffCardController controller = PayriffCardController();
  addTearDown(controller.dispose);
  final BuildContext Function() context = await pumpCardApp(
    tester,
    controller,
    showHolder: false,
  );
  await fillCard(tester);
  final _Run run = _Run(context, controller, native, backend);
  final StreamSubscription<PayriffLogEntry> logs = Payriff.logStream.listen((
    PayriffLogEntry entry,
  ) {
    if (entry.level == PayriffLogLevel.warning) run.warnings.add(entry.message);
  });
  addTearDown(logs.cancel);
  return run;
}
