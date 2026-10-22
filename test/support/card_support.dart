import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:payriff/payriff.dart';
import 'package:payriff/src/card/card_form.dart';
import 'package:payriff/src/internal/card/card_clock.dart';
import 'package:payriff/src/internal/card/client_api.dart';

/// The card flow's test keys.
const String testPublishableKey = 'pr_pk_live_TEST';
const String testClientSecret = 'pr_cs_TEST';
const String testAppId = 'com.payriff.example.ios';
const String testOrderId = 'o1';

/// A clock whose sleeps return at once (or after fake time, see
/// [realDelays]) and advance [now].
class FakeCardClock implements CardClock {
  FakeCardClock({this.realDelays = false});

  /// When true, sleeps also wait on the test's fake async time.
  final bool realDelays;

  DateTime _now = DateTime.utc(2026, 10, 15, 12);
  final List<Duration> sleeps = <Duration>[];

  @override
  DateTime now() => _now;

  @override
  Future<void> sleep(Duration duration) async {
    sleeps.add(duration);
    if (realDelays) await Future<void>.delayed(duration);
    _now = _now.add(duration);
  }
}

/// A Client API session against the sandbox with the test keys.
ClientApi testClientApi(CardClock clock, {String? appId = testAppId}) =>
    ClientApi(
      baseUrl: clientApiBaseUrl(PayriffEnvironment.sandbox),
      publishableKey: testPublishableKey,
      clientSecret: testClientSecret,
      appId: appId,
      clock: clock,
    );

/// A `/pay` request with fixed test values.
PayRequest testPayRequest() => PayRequest(
  body: payBody('ENC+/='),
  wrappedKey: 'WRAPPED+/=',
  idempotencyKey: newIdempotencyKey(),
);

/// A recorded call on the `payriff/native` channel.
class NativeCalls {
  final List<MethodCall> calls = <MethodCall>[];

  /// Replies of `encryptCard`; `null` makes it fail.
  Map<String, Object?>? encryptReply = <String, Object?>{
    'encryptedMessage': 'ENCRYPTED+/=',
    'wrappedKey': 'WRAPPED+/=',
  };

  String? appId = testAppId;
  bool openExternalReply = true;

  /// When true, `clearWebsiteData` fails with a [PlatformException].
  bool clearWebsiteDataFails = false;

  /// The reply of `deviceIntegrity` (CONTRACT §16.16): a clean device by
  /// default. An [Exception] is thrown instead.
  Object? integrityReply = clean;

  /// Replies of `deviceIntegrity` used before [integrityReply], one per
  /// call: for a tool that attaches during a payment.
  final List<Object?> integrityReplies = <Object?>[];

  /// A `deviceIntegrity` reply of a device without signals.
  static const Map<String, Object?> clean = <String, Object?>{
    'compromised': false,
    'signals': <String>[],
  };

  /// A `deviceIntegrity` reply of a compromised device.
  static Map<String, Object?> compromised([
    List<String> signals = const <String>['su binary', 'Frida'],
  ]) => <String, Object?>{'compromised': true, 'signals': signals};

  List<MethodCall> named(String method) =>
      calls.where((MethodCall c) => c.method == method).toList();

  /// The net screen-protection count: `true` adds one, `false` removes one.
  int get secureCount => named('setSecure').fold(
    0,
    (int n, MethodCall c) =>
        n + ((c.arguments as Map)['secure'] == true ? 1 : -1),
  );

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('payriff/native'), (
          MethodCall call,
        ) async {
          calls.add(call);
          switch (call.method) {
            case 'encryptCard':
              final Map<String, Object?>? reply = encryptReply;
              if (reply == null) {
                throw PlatformException(code: 'encryption_failed');
              }
              return reply;
            case 'appId':
              return appId;
            case 'setSecure':
              return null;
            case 'openExternal':
              return openExternalReply;
            case 'clearWebsiteData':
              if (clearWebsiteDataFails) {
                throw PlatformException(code: 'website_data_failed');
              }
              return null;
            case 'deviceIntegrity':
              final Object? reply = integrityReplies.isNotEmpty
                  ? integrityReplies.removeAt(0)
                  : integrityReply;
              if (reply is Exception) throw reply;
              return reply;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('payriff/native'),
            null,
          ),
    );
  }
}

String envelope(Map<String, Object?> payload) => jsonEncode(<String, Object?>{
  'code': '00000',
  'message': 'OK',
  'route': '/api/v3/client/orders',
  'responseId': 'r-1',
  'payload': payload,
});

/// A scripted Client API: the order, `/pay`, `/three-ds` and `/status`.
class FakeClientBackend {
  FakeClientBackend({
    this.orderStatus = 'CREATED',
    this.paymentMethods = const <String>['CARD'],
    Map<String, Object?>? payPayload,
    List<Object>? threeDs,
    List<String>? statuses,
  }) : payPayload =
           payPayload ?? <String, Object?>{'nextAction': 'CHECK_STATUS'},
       threeDs =
           threeDs ??
           <Object>[
             <String, Object?>{'nextAction': 'WAIT'},
           ],
       statuses = statuses ?? <String>['APPROVED'];

  String orderStatus;
  List<String> paymentMethods;
  Map<String, Object?> payPayload;

  /// Successive `/three-ds` payloads (the last repeats). An `int` answers
  /// with that HTTP status instead.
  final List<Object> threeDs;

  /// Successive `/status` statuses (the last repeats). `!fail` answers 503,
  /// `!404` answers 404.
  final List<String> statuses;

  /// Successive `/pay` answers before [payPayload]: HTTP status codes, or
  /// `0` for no response.
  final List<int> payFailures = <int>[];

  final List<http.Request> requests = <http.Request>[];

  List<http.Request> to(String suffix) =>
      requests.where((http.Request r) => r.url.path.endsWith(suffix)).toList();

  int get statusChecks => to('/status').length;

  void install() {
    debugPayriffClientApiHttpClient = () => MockClient(_handle);
    addTearDown(() => debugPayriffClientApiHttpClient = null);
  }

  T _next<T>(List<T> list) => list.length > 1 ? list.removeAt(0) : list.first;

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    final String path = request.url.path;
    http.Response ok(Map<String, Object?> payload) =>
        http.Response.bytes(utf8.encode(envelope(payload)), 200);
    if (request.method == 'POST' && path.endsWith('/pay')) {
      if (payFailures.isNotEmpty) {
        final int failure = payFailures.removeAt(0);
        if (failure == 0) throw http.ClientException('offline');
        return http.Response('{"code":"01000","message":"busy"}', failure);
      }
      return ok(payPayload);
    }
    if (path.endsWith('/three-ds')) {
      final Object next = _next(threeDs);
      if (next is int) return http.Response('', next);
      return ok(next as Map<String, Object?>);
    }
    if (path.endsWith('/status')) {
      final String status = _next(statuses);
      if (status == '!fail') return http.Response('Bad Gateway', 503);
      if (status == '!404') {
        return http.Response(
          '{"code":"01000","message":"Order not found"}',
          404,
        );
      }
      return ok(<String, Object?>{
        'orderId': testOrderId,
        'status': status,
        'amount': 10.5,
        'currency': 'AZN',
      });
    }
    return ok(<String, Object?>{
      'orderId': testOrderId,
      'amount': 10.5,
      'currency': 'AZN',
      'description': 'Order #42',
      'merchantName': 'Test Merchant',
      'status': orderStatus,
      'language': 'AZ',
      'paymentMethods': paymentMethods,
    });
  }
}

/// Pumps an app with a card form for [controller]; returns a function that
/// gives a context below the Navigator. [showHolder] defaults to `true`, like
/// the form.
Future<BuildContext Function()> pumpCardApp(
  WidgetTester tester,
  PayriffCardController controller, {
  bool showHolder = true,
  PayriffLanguage? language = PayriffLanguage.en,
  ValueChanged<PayriffCardFormChange>? onChanged,
  PayriffCardFormStyle style = const PayriffCardFormStyle(),
  ThemeData? theme,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  late BuildContext pageContext;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) {
            pageContext = context;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                PayriffCardForm(
                  controller: controller,
                  showHolder: showHolder,
                  language: language,
                  onChanged: onChanged,
                  style: style,
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
  return () => pageContext;
}

/// Types a valid card into the form.
Future<void> fillCard(
  WidgetTester tester, {
  String number = '4111111111111111',
  String expiry = '1230',
  String cvv = '123',
  String? holder,
}) async {
  await tester.enterText(find.byKey(cardNumberFieldKey), number);
  await tester.enterText(find.byKey(cardExpiryFieldKey), expiry);
  await tester.enterText(find.byKey(cardCvvFieldKey), cvv);
  if (holder != null) {
    await tester.enterText(find.byKey(cardHolderFieldKey), holder);
  }
  await tester.pump();
}

/// Pumps until [future] completes.
Future<T> pumpUntilDone<T>(
  WidgetTester tester,
  Future<T> future, {
  Duration step = const Duration(milliseconds: 100),
  int maxSteps = 600,
}) async {
  T? value;
  bool done = false;
  unawaited(
    future.then((T v) {
      value = v;
      done = true;
    }),
  );
  for (int i = 0; i < maxSteps && !done; i++) {
    await tester.pump(step);
  }
  if (!done) fail('did not finish');
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
  return value as T;
}

/// Pumps a few frames so a sheet route finishes animating.
Future<void> settleSheet(WidgetTester tester) async {
  for (int i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
