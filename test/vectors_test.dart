// Conformance tests: every case of every file and section in test/vectors
// (synced from spec/vectors by scripts/sync-spec.sh) must pass. Each case is
// asserted on the pure function that implements the rule and, where the
// rule is observable, through the public API. The card flow's files are
// asserted in card_vectors_test.dart.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payriff/payriff.dart';
import 'package:payriff/src/internal/card/card_flow.dart';
import 'package:payriff/src/internal/language.dart';
import 'package:payriff/src/internal/status_resolution.dart';
import 'package:payriff/src/internal/strings.dart';
import 'package:payriff/src/internal/ui/presenter.dart';

Map<String, Object?> _load(String name) =>
    jsonDecode(File('test/vectors/$name').readAsStringSync())
        as Map<String, Object?>;

List<Map<String, Object?>> _cases(Map<String, Object?> file, String key) =>
    (file[key]! as List<Object?>).cast<Map<String, Object?>>();

/// Compares two JSON values; numbers compare numerically and maps must have
/// exactly the same keys.
void _expectJsonEquals(Object? actual, Object? expected, String path) {
  if (expected is num) {
    expect(actual, isA<num>(), reason: path);
    expect((actual! as num).toDouble(), expected.toDouble(), reason: path);
  } else if (expected is Map) {
    expect(actual, isA<Map<Object?, Object?>>(), reason: path);
    final Map<Object?, Object?> map = actual! as Map<Object?, Object?>;
    expect(map.keys.toSet(), expected.keys.toSet(), reason: '$path keys');
    for (final Object? key in expected.keys) {
      _expectJsonEquals(map[key], expected[key], '$path.$key');
    }
  } else {
    expect(actual, expected, reason: path);
  }
}

PayriffPayment? _paymentFromJson(Object? json) {
  if (json == null) return null;
  final Map<String, Object?> m = json as Map<String, Object?>;
  return PayriffPayment(
    orderId: m['orderId']! as String,
    status: PayriffPaymentStatus.values.firstWhere(
      (PayriffPaymentStatus s) => s.value == m['status'],
    ),
    rawStatus: m['rawStatus'] as String?,
    amount: m['amount'] as num?,
    currency: m['currency'] as String?,
    transactionId: m['transactionId'] as String?,
    originalOrderId: m['originalOrderId'] as String?,
  );
}

/// CONTRACT §16.9 keeps `payment.originalOrderId` in the §5.3 shape, always
/// present (and always `null` in the card flow). `result_json.json` predates
/// revision 4, so its payments expect the key with `null`.
Map<String, Object?> _withRevision4Keys(Map<String, Object?> json) {
  final Object? payment = json['payment'];
  if (payment is! Map<String, Object?> ||
      payment.containsKey('originalOrderId')) {
    return json;
  }
  return <String, Object?>{
    ...json,
    'payment': <String, Object?>{...payment, 'originalOrderId': null},
  };
}

/// Builds the result object that a `result_json.json` case describes.
PayriffResult _resultFromJson(Map<String, Object?> json) {
  switch (json['type']) {
    case 'success':
      return PayriffResultSuccess(payment: _paymentFromJson(json['payment'])!);
    case 'declined':
      return PayriffResultDeclined(payment: _paymentFromJson(json['payment'])!);
    case 'cancelled':
      return PayriffResultCancelled(
        reason: PayriffCancelReason.values.byName(json['reason']! as String),
        payment: _paymentFromJson(json['payment']),
      );
    case 'pending':
      return PayriffResultPending(
        reason: PayriffPendingReason.values.byName(json['reason']! as String),
        payment: _paymentFromJson(json['payment'])!,
      );
    case 'failed':
      final Map<String, Object?> e = json['error']! as Map<String, Object?>;
      return PayriffResultFailed(
        error: PayriffError(
          code: PayriffErrorCode.values.firstWhere(
            (PayriffErrorCode c) => c.value == e['code'],
          ),
          message: e['message']! as String,
          isRetryable: e['isRetryable']! as bool,
          httpStatus: e['httpStatus'] as int?,
          payriffCode: e['payriffCode'] as String?,
          supportTicket: e['supportTicket'] as String?,
        ),
      );
  }
  throw ArgumentError('unknown type ${json['type']}');
}

void main() {
  setUp(Payriff.debugReset);
  tearDown(Payriff.debugReset);

  group('status.json', () {
    final List<Map<String, Object?>> cases = _cases(
      _load('status.json'),
      'cases',
    );
    test('has cases', () => expect(cases, isNotEmpty));
    for (final Map<String, Object?> c in cases) {
      test('raw ${jsonEncode(c['raw'])}', () {
        // CONTRACT §12.1: the status parser is PayriffPaymentStatus.parse.
        final PayriffPaymentStatus status = PayriffPaymentStatus.parse(
          c['raw'] as String?,
        );
        expect(status.value, c['status']);
        final StatusOutcome outcome = outcomeOf(status);
        expect(outcome.name, c['outcome']);
        expect(status.isFinal, outcome != StatusOutcome.nonFinal);
        // The result mapping of CONTRACT §8.2, including the cancel reason.
        final PayriffResult? result = resultForFinalStatus(
          PayriffPayment(orderId: 'o', status: status),
        );
        switch (outcome) {
          case StatusOutcome.success:
            expect(result, isA<PayriffResultSuccess>());
          case StatusOutcome.declined:
            expect(result, isA<PayriffResultDeclined>());
          case StatusOutcome.cancelled:
            expect(result, isA<PayriffResultCancelled>());
            expect(
              (result! as PayriffResultCancelled).reason.name,
              c['cancelReason'],
            );
          case StatusOutcome.unexpectedFinal:
            expect(
              (result! as PayriffResultPending).reason,
              PayriffPendingReason.unexpectedStatus,
            );
          case StatusOutcome.nonFinal:
            expect(result, isNull);
        }
        if (outcome != StatusOutcome.cancelled) {
          expect(c.containsKey('cancelReason'), isFalse);
        }
        // The same raw string through a Client API status check keeps
        // rawStatus (CONTRACT §16.7 step 5).
        if (c['raw'] case final String raw when raw.trim().isNotEmpty) {
          final StatusReading reading = cardStatusReading(<String, Object?>{
            'status': raw,
          });
          expect(reading.status.value, c['status']);
          expect(reading.rawStatus, raw);
        }
      });
    }
  });

  group('language.json', () {
    final List<Map<String, Object?>> cases = _cases(
      _load('language.json'),
      'cases',
    );
    test('has cases', () => expect(cases, isNotEmpty));
    for (final Map<String, Object?> c in cases) {
      test('locale "${c['locale']}"', () {
        expect(
          languageForLocaleTag(c['locale']! as String).value,
          c['expected'],
        );
      });
    }
  });

  group('result_json.json', () {
    final List<Map<String, Object?>> cases = _cases(
      _load('result_json.json'),
      'cases',
    );
    test('has cases', () => expect(cases, isNotEmpty));
    for (final Map<String, Object?> c in cases) {
      test(c['name']! as String, () {
        final Map<String, Object?> json = _withRevision4Keys(
          c['json']! as Map<String, Object?>,
        );
        final PayriffResult result = _resultFromJson(json);
        // Serialised through real JSON text: every key present, null when
        // unknown, numbers as numbers.
        final Object? actual = jsonDecode(jsonEncode(result.toJson()));
        _expectJsonEquals(actual, json, 'result');
        // The §12.1 helpers agree with the JSON.
        expect(result.type, json['type']);
        expect(result.isSuccess, json['type'] == 'success');
        expect(result.payment?.toJson(), json['payment']);
        expect(result.error?.code.value, (json['error'] as Map?)?['code']);
      });
    }

    test('a set originalOrderId is serialized (§16.9)', () {
      final Map<String, Object?> json = _withRevision4Keys(
        _cases(_load('result_json.json'), 'cases').first['json']!
            as Map<String, Object?>,
      );
      final Map<String, Object?> switched = <String, Object?>{
        ...json,
        'payment': <String, Object?>{
          ...json['payment']! as Map<String, Object?>,
          'originalOrderId': 'o0',
        },
      };
      _expectJsonEquals(
        jsonDecode(jsonEncode(_resultFromJson(switched).toJson())),
        switched,
        'result',
      );
    });
  });

  group('strings.json', () {
    final Map<String, Object?> strings =
        _load('strings.json')['strings']! as Map<String, Object?>;

    test('the in-code table equals strings.json exactly', () {
      final Map<String, Map<String, String>> expected =
          <String, Map<String, String>>{
            for (final MapEntry<String, Object?> entry in strings.entries)
              entry.key: (entry.value! as Map<String, Object?>)
                  .cast<String, String>(),
          };
      expect(payriffStringTable, expected);
    });

    test('every key and language is reachable through PayriffStrings', () {
      expect(
        PayriffStringKey.values.map((PayriffStringKey k) => k.id).toSet(),
        strings.keys.toSet(),
      );
      for (final PayriffLanguage language in PayriffLanguage.values) {
        final PayriffStrings table = PayriffStrings(language);
        for (final PayriffStringKey key in PayriffStringKey.values) {
          final Map<String, Object?> byLanguage =
              strings[key.id]! as Map<String, Object?>;
          expect(table[key], byLanguage[language.value.toLowerCase()]);
        }
      }
    });

    for (final PayriffLanguage language in PayriffLanguage.values) {
      final String code = language.value.toLowerCase();
      String text(String key) =>
          (strings[key]! as Map<String, Object?>)[code]! as String;

      testWidgets('JavaScript dialogs use dialog_ok and dialog_cancel '
          '($code)', (WidgetTester tester) async {
        late BuildContext context;
        await tester.pumpWidget(
          CupertinoApp(
            home: Builder(
              builder: (BuildContext c) {
                context = c;
                return const SizedBox();
              },
            ),
          ),
        );
        final SheetPresenter presenter = SheetPresenter(
          navigator: Navigator.of(context),
          material: false,
          strings: PayriffStrings(language),
        );

        // alert(): OK only.
        final Future<void> alert = presenter.alert(context, 'Hello');
        await tester.pumpAndSettle();
        expect(find.text('Hello'), findsOneWidget);
        expect(find.text(text('dialog_ok')), findsOneWidget);
        expect(find.text(text('dialog_cancel')), findsNothing);
        await tester.tap(find.byKey(jsDialogOkKey));
        await tester.pumpAndSettle();
        await alert;

        // confirm(): Cancel and OK.
        Future<bool> confirm = presenter.confirm(context, 'Sure?');
        await tester.pumpAndSettle();
        expect(find.text(text('dialog_ok')), findsOneWidget);
        expect(find.text(text('dialog_cancel')), findsOneWidget);
        await tester.tap(find.byKey(jsDialogOkKey));
        await tester.pumpAndSettle();
        expect(await confirm, isTrue);
        confirm = presenter.confirm(context, 'Sure?');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(jsDialogCancelKey));
        await tester.pumpAndSettle();
        expect(await confirm, isFalse);

        // prompt(): a text field, Cancel and OK.
        Future<String?> prompt = presenter.prompt(
          context,
          'Name?',
          defaultText: 'Ada',
        );
        await tester.pumpAndSettle();
        expect(find.text(text('dialog_ok')), findsOneWidget);
        expect(find.text(text('dialog_cancel')), findsOneWidget);
        await tester.enterText(find.byKey(jsPromptFieldKey), 'Grace');
        await tester.tap(find.byKey(jsDialogOkKey));
        await tester.pumpAndSettle();
        expect(await prompt, 'Grace');
        prompt = presenter.prompt(context, 'Name?');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(jsDialogCancelKey));
        await tester.pumpAndSettle();
        expect(await prompt, isNull);
      });
    }
  });

  test('every vector file is covered by this file or by '
      'card_vectors_test.dart', () {
    final Set<String> files = Directory('test/vectors')
        .listSync()
        .whereType<File>()
        .map((File f) => f.uri.pathSegments.last)
        .toSet();
    // Revision 5 moved api.json, navigation.json, payment_url_order_id.json
    // and amount.json (the hosted checkout) to spec/archive; they are no
    // longer synced, so they must not come back here.
    const Set<String> covered = <String>{
      'language.json',
      'result_json.json',
      'status.json',
      'strings.json',
    };
    // CONTRACT §16 (revision 4): the native card flow's vectors, every case
    // asserted in test/card_vectors_test.dart. A new file fails this test
    // until it is assigned.
    const Set<String> coveredByCardTests = <String>{
      'card_3ds_navigation.json',
      'card_api.json',
      'card_crypto.json',
      'card_format.json',
      'card_next_action.json',
      'card_strings.json',
      'card_validation.json',
    };
    expect(files, <String>{...covered, ...coveredByCardTests});
  });
}
