// CONTRACT §19.1 (revision 9): the 3-D Secure Method step of Payriff.js
// 1.3.1. The hidden WebViews, the wait for their first pages, one
// `/three-ds` with a 60 s timeout and one retry, `wait` every 2 s for at most
// 30 s, and what follows. A scripted Client API, fake time and a fake sheet.
// No network.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:payriff/payriff.dart';
import 'package:payriff/src/internal/card/card_crypto.dart';
import 'package:payriff/src/internal/card/card_flow.dart';
import 'package:payriff/src/internal/card/client_api.dart';
import 'package:payriff/src/internal/strings.dart';

import 'support/card_support.dart';

const CardPlaintext _card = CardPlaintext(
  pan: '4111111111111111',
  cardHolder: 'Unknown',
  expiryYear: '2030',
  expiryMonth: '12',
  cvv: '123',
);

const String _callback =
    'https://sb-api.payriff.com/api/v3/gateway/atb/callback/o1';

/// A `THREE_DS` step without `accessUrl` and with these clientRequest
/// values.
Map<String, Object?> _method({
  String? url = 'https://acs.bank.example/method',
  String? data = 'METHOD-DATA',
  String? server = 'https://3ds.bank.example/gather',
}) => <String, Object?>{
  'nextAction': 'THREE_DS',
  'channel': 'ATB',
  'clientRequest': <Object?>[
    <String, Object?>{'key': 'threeDSMethodUrl', 'value': url},
    <String, Object?>{'key': 'threeDSMethodData', 'value': data},
    <String, Object?>{'key': 'threeDSMethodUrlServer', 'value': server},
  ],
};

const Map<String, Object?> _wait = <String, Object?>{'nextAction': 'WAIT'};
const Map<String, Object?> _checkStatus = <String, Object?>{
  'nextAction': 'CHECK_STATUS',
};
const Map<String, Object?> _challenge = <String, Object?>{
  'nextAction': 'THREE_DS',
  'accessUrl': 'https://acs.bank.example/challenge',
  'clientRequest': <Object?>[
    <String, Object?>{'key': 'creq', 'value': 'CREQ'},
  ],
};
const Map<String, Object?> _redirect = <String, Object?>{
  'nextAction': 'REDIRECT',
  'redirectUrl': 'https://bank.example/redirect',
};

/// One scripted `/three-ds` answer: a payload, an HTTP status, or no
/// response, after [delay].
typedef _Answer = ({Duration delay, Object reply});

_Answer _now(Object reply) => (delay: Duration.zero, reply: reply);

/// A Client API: a payable order, `/pay` with [pay], `/three-ds` from
/// [threeDs] (the last repeats), `/status` [status].
class _Api {
  _Api({required this.pay, required this.threeDs, this.status = 'APPROVED'});

  final Map<String, Object?> pay;
  final List<_Answer> threeDs;
  final String status;
  final List<String> calls = <String>[];

  int get threeDsCalls => calls.where((String c) => c == 'three-ds').length;
  int get statusCalls => calls.where((String c) => c == 'status').length;

  void install() {
    debugPayriffClientApiHttpClient = () => MockClient(_handle);
    addTearDown(() => debugPayriffClientApiHttpClient = null);
  }

  Future<http.Response> _handle(http.Request request) async {
    http.Response ok(Map<String, Object?> payload) =>
        http.Response.bytes(utf8.encode(envelope(payload)), 200);
    final String path = request.url.path;
    if (path.endsWith('/pay')) {
      calls.add('pay');
      return ok(pay);
    }
    if (path.endsWith('/three-ds')) {
      calls.add('three-ds');
      final _Answer answer = threeDs.length > 1
          ? threeDs.removeAt(0)
          : threeDs.first;
      if (answer.delay > Duration.zero) {
        await Future<void>.delayed(answer.delay);
      }
      final Object reply = answer.reply;
      if (reply == 'offline') throw http.ClientException('offline');
      if (reply is int) {
        return http.Response('{"code":"01000","message":"failed"}', reply);
      }
      return ok(reply as Map<String, Object?>);
    }
    if (path.endsWith('/status')) {
      calls.add('status');
      return ok(<String, Object?>{
        'orderId': testOrderId,
        'status': status,
        'amount': 10.5,
        'currency': 'AZN',
      });
    }
    calls.add('order');
    return ok(<String, Object?>{
      'orderId': testOrderId,
      'amount': 10.5,
      'currency': 'AZN',
      'status': 'CREATED',
      'paymentMethods': <String>['CARD'],
    });
  }
}

final class _Sheet implements ThreeDsSheet {
  bool closed = false;

  @override
  void close() => closed = true;
}

/// One card payment through [CardPayment], with the sheet it opens.
class _Payment {
  _Payment(this.api, this.clock);

  final _Api api;
  final FakeCardClock clock;
  ThreeDsSession? session;
  final List<_Sheet> sheets = <_Sheet>[];
  PayriffResult? result;

  Future<PayriffResult> start() {
    NativeCalls().install();
    api.install();
    final ClientApi client = testClientApi(clock);
    addTearDown(client.close);
    return CardPayment(
      api: client,
      orderId: testOrderId,
      clock: clock,
      strings: const PayriffSheetStrings(PayriffLanguage.en),
      openSheet: (ThreeDsSession s) {
        session = s;
        final _Sheet sheet = _Sheet();
        sheets.add(sheet);
        return sheet;
      },
    ).run(_card).then((PayriffResult r) => result = r);
  }
}

/// Pumps fake time in steps of [step] for [total].
Future<void> _advance(
  WidgetTester tester,
  Duration total, {
  Duration step = const Duration(milliseconds: 100),
}) async {
  for (Duration t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}

void main() {
  setUp(Payriff.debugReset);
  tearDown(Payriff.debugReset);

  testWidgets('the hidden WebViews start back to back, and /three-ds waits '
      'for their first pages', (WidgetTester tester) async {
    final _Payment run = _Payment(
      _Api(pay: _method(), threeDs: <_Answer>[_now(_checkStatus)]),
      FakeCardClock(realDelays: true),
    );
    final Future<PayriffResult> future = run.start();
    await tester.pump(const Duration(milliseconds: 100));
    final ThreeDsSession session = run.session!;
    expect(session.hidden.map((ThreeDsRequest r) => r.url.toString()), <String>[
      'https://acs.bank.example/method',
      'https://3ds.bank.example/gather',
    ]);
    expect(
      utf8.decode(session.hidden.first.body!),
      'threeDSMethodData=METHOD-DATA',
    );
    expect(session.hidden.last.body, isEmpty);
    expect(run.api.threeDsCalls, 0);

    session.onHiddenPageDone(session.hiddenGeneration, 0);
    await _advance(tester, const Duration(seconds: 1));
    expect(run.api.threeDsCalls, 0, reason: 'the server one is still loading');
    session.onHiddenPageDone(session.hiddenGeneration, 1);
    await tester.pump(const Duration(milliseconds: 100));
    expect(run.api.threeDsCalls, 1);

    await _advance(tester, const Duration(seconds: 12));
    expect(await future, isA<PayriffResultSuccess>());
    expect(run.api.statusCalls, 1);
    expect(session.hidden, isEmpty, reason: 'destroyed after the hand-over');
  });

  testWidgets('/three-ds goes on after 10 s when a page never loads', (
    WidgetTester tester,
  ) async {
    final _Payment run = _Payment(
      _Api(pay: _method(), threeDs: <_Answer>[_now(_checkStatus)]),
      FakeCardClock(realDelays: true),
    );
    final Future<PayriffResult> future = run.start();
    await _advance(tester, const Duration(milliseconds: 9900));
    expect(run.api.threeDsCalls, 0);
    await _advance(tester, const Duration(milliseconds: 200));
    expect(run.api.threeDsCalls, 1);
    await _advance(tester, const Duration(seconds: 5));
    expect(await future, isA<PayriffResultSuccess>());
  });

  testWidgets('the issuer WebView needs both its URL and its data; without '
      'any WebView /three-ds follows at once and no sheet opens', (
    WidgetTester tester,
  ) async {
    _Payment run = _Payment(
      _Api(
        pay: _method(data: ''),
        threeDs: <_Answer>[_now(_checkStatus)],
      ),
      FakeCardClock(realDelays: true),
    );
    Future<PayriffResult> future = run.start();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      run.session!.hidden.map((ThreeDsRequest r) => r.url.toString()),
      <String>['https://3ds.bank.example/gather'],
    );
    run.session!.onHiddenPageDone(run.session!.hiddenGeneration, 0);
    await _advance(tester, const Duration(seconds: 12));
    expect(await future, isA<PayriffResultSuccess>());

    run = _Payment(
      _Api(
        pay: _method(url: null, data: null, server: null),
        threeDs: <_Answer>[_now(_checkStatus)],
      ),
      FakeCardClock(realDelays: true),
    );
    future = run.start();
    await tester.pump(const Duration(milliseconds: 100));
    expect(run.api.threeDsCalls, 1);
    expect(run.session, isNull);
    await _advance(tester, const Duration(seconds: 5));
    expect(await future, isA<PayriffResultSuccess>());
  });

  testWidgets('/three-ds may take up to 60 s', (WidgetTester tester) async {
    final _Payment run = _Payment(
      _Api(
        pay: _method(url: null, server: null),
        threeDs: <_Answer>[
          (delay: const Duration(seconds: 40), reply: _checkStatus),
        ],
      ),
      FakeCardClock(realDelays: true),
    );
    final Future<PayriffResult> future = run.start();
    await _advance(
      tester,
      const Duration(seconds: 45),
      step: const Duration(seconds: 1),
    );
    expect(await future, isA<PayriffResultSuccess>());
    expect(run.api.threeDsCalls, 1);
  });

  testWidgets('a /three-ds without an answer in 60 s is retried once', (
    WidgetTester tester,
  ) async {
    final _Payment run = _Payment(
      _Api(
        pay: _method(url: null, server: null),
        threeDs: <_Answer>[
          (delay: const Duration(seconds: 61), reply: _checkStatus),
          _now(_checkStatus),
        ],
      ),
      FakeCardClock(realDelays: true),
    );
    final Future<PayriffResult> future = run.start();
    await _advance(
      tester,
      const Duration(seconds: 59),
      step: const Duration(seconds: 1),
    );
    expect(run.api.threeDsCalls, 1);
    await _advance(
      tester,
      const Duration(seconds: 6),
      step: const Duration(seconds: 1),
    );
    expect(run.api.threeDsCalls, 2);
    expect(await future, isA<PayriffResultSuccess>());
  });

  for (final (String name, List<Object> replies, int calls)
      in <(String, List<Object>, int)>[
        ('an HTTP 503, then an answer', <Object>[503, _checkStatus], 2),
        ('no response twice', <Object>['offline', 'offline'], 2),
        ('an HTTP 500 twice', <Object>[500, 500], 2),
        ('an HTTP 400: no retry', <Object>[400], 1),
      ]) {
    testWidgets('retry: $name, then status polling', (
      WidgetTester tester,
    ) async {
      final FakeCardClock clock = FakeCardClock();
      final _Payment run = _Payment(
        _Api(
          pay: _method(url: null, server: null),
          threeDs: <_Answer>[for (final Object reply in replies) _now(reply)],
        ),
        clock,
      );
      final PayriffResult result = await pumpUntilDone(tester, run.start());
      expect(result, isA<PayriffResultSuccess>());
      expect(run.api.threeDsCalls, calls);
      expect(run.api.statusCalls, 1);
    });
  }

  testWidgets('wait: every 2 s for at most 30 s from the first answer, then '
      'status polling', (WidgetTester tester) async {
    final FakeCardClock clock = FakeCardClock();
    final _Payment run = _Payment(
      _Api(
        pay: _method(url: null, server: null),
        threeDs: <_Answer>[_now(_wait)],
      ),
      clock,
    );
    final PayriffResult result = await pumpUntilDone(tester, run.start());
    expect(result, isA<PayriffResultSuccess>());
    // The first answer, then 15 more 2 s apart.
    expect(run.api.threeDsCalls, 16);
    expect(
      clock.sleeps.where((Duration d) => d == threeDsWaitInterval),
      hasLength(15),
    );
    expect(run.api.calls.last, 'status');
  });

  testWidgets('a wait from /pay: /three-ds in 2 s, then as after the '
      'Method', (WidgetTester tester) async {
    final FakeCardClock clock = FakeCardClock();
    final _Payment run = _Payment(
      _Api(pay: _wait, threeDs: <_Answer>[_now(_wait), _now(_checkStatus)]),
      clock,
    );
    final PayriffResult result = await pumpUntilDone(tester, run.start());
    expect(result, isA<PayriffResultSuccess>());
    expect(run.api.threeDsCalls, 2);
    expect(clock.sleeps.take(2), <Duration>[
      threeDsWaitInterval,
      threeDsWaitInterval,
    ]);
    expect(run.session, isNull);
  });

  for (final (String name, Map<String, Object?> answer, String? page)
      in <(String, Map<String, Object?>, String?)>[
        ('a challenge', _challenge, 'https://acs.bank.example/challenge'),
        ('a redirect', _redirect, 'https://bank.example/redirect'),
        ('a challenge without accessUrl', _method(), null),
        ('an invalid step', <String, Object?>{'nextAction': 'FOO'}, null),
        ('checkStatus', _checkStatus, null),
      ]) {
    testWidgets('after the Method: $name', (WidgetTester tester) async {
      final _Payment run = _Payment(
        _Api(pay: _method(), threeDs: <_Answer>[_now(_wait), _now(answer)]),
        FakeCardClock(realDelays: true),
      );
      final Future<PayriffResult> future = run.start();
      await tester.pump(const Duration(milliseconds: 100));
      final ThreeDsSession session = run.session!;
      session
        ..onHiddenPageDone(session.hiddenGeneration, 0)
        ..onHiddenPageDone(session.hiddenGeneration, 1);
      await tester.pump(const Duration(milliseconds: 100));
      // The hidden WebViews stay while `wait` is followed.
      expect(session.hidden, hasLength(2));
      await _advance(tester, const Duration(seconds: 3));
      expect(run.api.threeDsCalls, 2);
      expect(session.hidden, isEmpty);
      if (page != null) {
        expect(session.view, ThreeDsView.page);
        expect(session.page!.url.toString(), page);
        expect(run.api.statusCalls, 0);
        session.onPageFinished(_callback);
      } else {
        expect(session.page, isNull);
      }
      await _advance(tester, const Duration(seconds: 12));
      // Status polling decides, never UNEXPECTED_RESPONSE.
      expect(await future, isA<PayriffResultSuccess>());
      expect(run.api.statusCalls, 1);
    });
  }

  testWidgets('closing the sheet during the wait for the pages checks the '
      'status once', (WidgetTester tester) async {
    final _Payment run = _Payment(
      _Api(
        pay: _method(),
        threeDs: <_Answer>[_now(_checkStatus)],
        status: 'PENDING',
      ),
      FakeCardClock(realDelays: true),
    );
    final Future<PayriffResult> future = run.start();
    await tester.pump(const Duration(milliseconds: 100));
    await run.session!.requestClose();
    await _advance(tester, const Duration(seconds: 11));
    final PayriffResult result = await future;
    expect(
      (result as PayriffResultPending).reason,
      PayriffPendingReason.notFinal,
    );
    expect(run.api.threeDsCalls, 0);
    expect(run.api.statusCalls, 1);
  });

  test('timing values (card_next_action.json → threeDsTiming)', () {
    expect(threeDsMethodLoadTimeout, const Duration(seconds: 10));
    expect(threeDsRequestTimeout, const Duration(seconds: 60));
    expect(threeDsRetries, 1);
    expect(threeDsWaitInterval, const Duration(seconds: 2));
    expect(threeDsWaitLimit, const Duration(seconds: 30));
    expect(
      isThreeDsRetryable(
        const PayriffError(
          code: PayriffErrorCode.networkError,
          message: 'pinning',
        ),
      ),
      isFalse,
      reason: 'a refused certificate is not retried',
    );
  });
}
