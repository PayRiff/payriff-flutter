// CONTRACT §17.12: every section of test/vectors/wallet.json. Merchant ID
// normalisation, availability, amounts, Google Pay environments and JSON
// (compared as JSON values), the Apple Pay request, the wallet /pay request
// (headers present and absent, body), the Apple Pay sheet table, the button
// styles, the Apple Pay networks, and revision 10's platform guard and
// Google Pay gateway parameters. No network: /pay goes to a mock client.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:payriff/payriff.dart';
import 'package:payriff/src/card/payment_view.dart';
import 'package:payriff/src/config.dart'
    show normalizedApplePayMerchantIdentifier;
import 'package:payriff/src/internal/amount.dart';
import 'package:payriff/src/internal/card/card_strings.dart';
import 'package:payriff/src/internal/card/client_api.dart';
import 'package:payriff/src/internal/logger.dart';
import 'package:payriff/src/internal/wallet/wallet_payment.dart';
import 'package:payriff/src/internal/wallet/wallet_rules.dart';

import 'support/card_support.dart';
import 'support/wallet_support.dart';

final Map<String, Object?> _v = walletVectors();

List<Map<String, Object?>> _list(Object? value) =>
    (value! as List<Object?>).cast<Map<String, Object?>>();

PayriffClientOrder _order(Object? payload) => PayriffClientOrder.fromPayload(
  payload! as Map<String, Object?>,
  requestedOrderId: testOrderId,
);

PayriffRegion _region(Object? name) =>
    PayriffRegion.values.byName(name! as String);

/// [value] as plain JSON, so maps and lists compare as JSON values.
Object? _json(Object? value) => jsonDecode(jsonEncode(value));

/// The Google Pay configuration of a case: its `gateway` and
/// `gatewayMerchantId` (`null` keeps the defaults), and its `merchantId` and
/// `merchantName` when the case has them.
PayriffGooglePayConfig _googleConfig(Object? value) {
  final Map<String, Object?> c = (value as Map<String, Object?>?) ?? const {};
  final String? gateway = c['gateway'] as String?;
  return gateway == null
      ? PayriffGooglePayConfig(
          merchantId: c['merchantId'] as String?,
          merchantName: c['merchantName'] as String?,
          gatewayMerchantId: c['gatewayMerchantId'] as String?,
        )
      : PayriffGooglePayConfig(
          merchantId: c['merchantId'] as String?,
          merchantName: c['merchantName'] as String?,
          gatewayMerchantId: c['gatewayMerchantId'] as String?,
          gateway: gateway,
        );
}

void main() {
  test('the wallet tokens of the test support are the vectors', () {
    final List<Map<String, Object?>> pays = _list(_v['payRequests']);
    expect(pays[0]['walletToken'], testGooglePayToken);
    expect(pays[1]['walletToken'], testApplePayToken);
  });

  test('applePayMerchantIdentifiers: trimmed, merchant. and at least one '
      'more character, no white space or control character inside', () {
    final List<Map<String, Object?>> cases = _list(
      _v['applePayMerchantIdentifiers'],
    );
    expect(cases, isNotEmpty);
    for (final Map<String, Object?> c in cases) {
      final String value = c['value']! as String;
      final bool valid = c['valid']! as bool;
      final String? normalized = normalizedApplePayMerchantIdentifier(value);
      expect(normalized != null, valid, reason: jsonEncode(value));
      if (valid) expect(normalized, c['normalized']);
      final PayriffApplePayConfig config = PayriffApplePayConfig(
        merchantIdentifier: value,
      );
      // CONTRACT §17.2: the configure warning names a reason exactly when
      // the identifier is invalid, and the wallet stays off.
      expect(applePayConfigProblem(config) == null, valid);
      expect(
        walletConfigProblem(
          PayriffConfig(applePay: config),
          WalletKind.applePay,
        ),
        valid ? isNull : 'invalid configuration',
      );
      expect(
        PayriffConfig(applePay: config).toString(),
        contains('applePay: ${valid ? normalized : 'invalid'}'),
      );
    }
    expect(
      walletConfigProblem(const PayriffConfig(), WalletKind.applePay),
      'not configured',
    );
  });

  test('googlePayMerchantIds: trimmed, blank means null', () {
    for (final Map<String, Object?> c in _list(_v['googlePayMerchantIds'])) {
      expect(
        normalizedGooglePayMerchantId(c['value'] as String?),
        c['normalized'],
      );
    }
    expect(
      walletConfigProblem(const PayriffConfig(), WalletKind.googlePay),
      'not configured',
    );
    expect(
      walletConfigProblem(
        const PayriffConfig(googlePay: PayriffGooglePayConfig()),
        WalletKind.googlePay,
      ),
      isNull,
    );
  });

  test('availability: the order part of CONTRACT §17.3', () {
    final Map<String, Object?> availability =
        _v['availability']! as Map<String, Object?>;
    final List<Map<String, Object?>> cases = _list(availability['cases']);
    expect(cases, hasLength(greaterThan(5)));
    for (final Map<String, Object?> c in cases) {
      final PayriffClientOrder order = _order(c['order']);
      final Map<String, Object?> expected =
          c['expect']! as Map<String, Object?>;
      // Revision 10: paymentMethods is not checked; the case gives the
      // Google Pay configuration's gateway fields.
      final PayriffGooglePayConfig googlePay = _googleConfig(
        c['googlePayConfig'],
      );
      expect(
        walletOrderProblem(order, WalletKind.applePay, googlePay: googlePay) ==
            null,
        expected['applePay'],
        reason: '${c['name']}: Apple Pay',
      );
      expect(
        walletOrderProblem(order, WalletKind.googlePay, googlePay: googlePay) ==
            null,
        expected['googlePay'],
        reason: '${c['name']}: Google Pay',
      );
    }
  });

  test('availability: the first failed condition is named', () {
    final PayriffClientOrder paid = _order(<String, Object?>{
      'status': 'PAID',
      'amount': 1,
      'currency': 'AZN',
      'paymentMethods': <String>['APPLE_PAY'],
    });
    expect(
      walletDecisionLine(
        WalletKind.applePay,
        walletOrderProblem(paid, WalletKind.applePay),
      ),
      'Apple Pay offered: false (order status PAID)',
    );
    final PayriffClientOrder card = _order(<String, Object?>{
      'status': 'CREATED',
      'amount': 1,
      'currency': 'AZN',
      'paymentMethods': <String>['CARD'],
    });
    // Revision 10: a card-only order is fine; Google Pay only lacks its
    // gateway merchant id, which the configuration can give.
    expect(walletOrderProblem(card, WalletKind.applePay), isNull);
    expect(
      walletOrderProblem(card, WalletKind.googlePay),
      'no gatewayMerchantId',
    );
    expect(
      walletOrderProblem(
        card,
        WalletKind.googlePay,
        googlePay: const PayriffGooglePayConfig(gatewayMerchantId: 'PRF0001'),
      ),
      isNull,
    );
    expect(
      walletDecisionLine(WalletKind.googlePay, null),
      'Google Pay offered: true',
    );
  });

  test('amounts: 2 decimals, `.`, decimal arithmetic; the Pay button shows '
      'the same', () {
    final List<Map<String, Object?>> cases = _list(_v['amounts']);
    expect(cases, isNotEmpty);
    final PayriffCardStrings strings = PayriffCardStrings(PayriffLanguage.en);
    for (final Map<String, Object?> c in cases) {
      final num amount = c['amount']! as num;
      expect(formatAmount2(amount), c['formatted'], reason: '$amount');
      expect(
        paymentViewPayTitle(
          strings,
          PayriffClientOrder(orderId: 'o1', amount: amount, currency: 'AZN'),
        ),
        'Pay ${c['formatted']} AZN',
      );
    }
    // Decimal, not binary: 1.005 is 1.00499999… as a double.
    expect(formatAmount2(1.005), '1.01');
    expect(formatAmount2(10.499999), '10.50');
    expect(formatAmount2(2.675), '2.68');
    expect(formatAmount2(0), '0.00');
    expect(formatAmount2(1e-7), '0.00');
    expect(formatAmount2(1.5e21), '1500000000000000000000.00');
    expect(formatAmount2(-1.5), '-1.50');
    expect(formatAmount2(null), isNull);
    expect(formatAmount2(double.nan), isNull);
    expect(formatAmount2(double.infinity), isNull);
  });

  test('googlePayEnvironments: TEST only for the sandbox host', () {
    final List<Map<String, Object?>> cases = _list(_v['googlePayEnvironments']);
    expect(cases, hasLength(4));
    for (final Map<String, Object?> c in cases) {
      final PayriffConfig config = PayriffConfig(
        region: _region(c['region']),
        environment: PayriffEnvironment.values.byName(
          c['environment']! as String,
        ),
      );
      expect(googlePayEnvironment(config), c['expect'], reason: '$c');
    }
  });

  test('googlePayRequests: isReadyToPayRequest, paymentDataRequest and '
      'buttonAllowedPaymentMethods, compared as JSON values', () {
    final List<Map<String, Object?>> cases = _list(_v['googlePayRequests']);
    expect(cases, isNotEmpty);
    for (final Map<String, Object?> c in cases) {
      final PayriffGooglePayConfig config = _googleConfig(c['config']);
      final Map<String, Object?> expected =
          c['expect']! as Map<String, Object?>;
      final PayriffClientOrder order = _order(c['order']);
      final Map<String, Object?>? request = googlePayPaymentDataRequest(
        order: order,
        region: _region(c['region']),
        config: config,
        appName: c['appName'] as String?,
      );
      expect(
        _json(googlePayIsReadyToPayRequest()),
        expected['isReadyToPayRequest'],
        reason: '${c['name']}',
      );
      expect(
        _json(request),
        expected['paymentDataRequest'],
        reason: '${c['name']}',
      );
      expect(
        _json(googlePayAllowedPaymentMethods(order, config)),
        expected['buttonAllowedPaymentMethods'],
      );
      // The button's methods are the request's.
      expect(
        _json(googlePayAllowedPaymentMethods(order, config)),
        _json(request!['allowedPaymentMethods']),
      );
      // What the button's platform view gets.
      expect(
        jsonDecode(
          googlePayButtonParams(
                const PayriffGooglePayButtonStyle(),
                dark: false,
                cornerRadius: 16,
                allowedPaymentMethods: googlePayAllowedPaymentMethods(
                  order,
                  config,
                )!,
              )['allowedPaymentMethods']!
              as String,
        ),
        expected['buttonAllowedPaymentMethods'],
      );
    }
  });

  test('applePayRequests: the values of the PKPaymentRequest', () {
    final List<Map<String, Object?>> cases = _list(_v['applePayRequests']);
    expect(cases, isNotEmpty);
    for (final Map<String, Object?> c in cases) {
      final Map<String, Object?> config = c['config']! as Map<String, Object?>;
      expect(
        _json(
          applePayRequest(
            order: _order(c['order']),
            region: _region(c['region']),
            config: PayriffApplePayConfig(
              merchantIdentifier: config['merchantIdentifier']! as String,
              merchantName: config['merchantName'] as String?,
            ),
            appName: c['appName'] as String?,
          ),
        ),
        c['expect'],
        reason: '${c['name']}',
      );
    }
    // The networks and capabilities of canMakePayments are the request's.
    expect(applePayNetworks, <String>['visa', 'masterCard']);
    expect(applePayCapabilities, <String>['threeDSecure']);
  });

  test('applePayNetworks: region sa adds mada (CONTRACT §19.4)', () {
    final Map<String, Object?> networks =
        _v['applePayNetworks']! as Map<String, Object?>;
    for (final PayriffRegion region in PayriffRegion.values) {
      expect(applePayNetworksFor(region), networks[region.name]);
    }
  });

  group('payRequests', () {
    for (final Map<String, Object?> c in _list(_v['payRequests'])) {
      test(
        '${c['name']}: headers present and absent, the body as is',
        () async {
          final List<http.Request> sent = <http.Request>[];
          debugPayriffClientApiHttpClient = () =>
              MockClient((http.Request request) async {
                sent.add(request);
                return http.Response(
                  envelope(<String, Object?>{'nextAction': 'CHECK_STATUS'}),
                  200,
                );
              });
          addTearDown(() => debugPayriffClientApiHttpClient = null);
          final Map<String, Object?> body = c['body']! as Map<String, Object?>;
          final WalletKind kind = WalletKind.values.firstWhere(
            (WalletKind k) => k.method == body['method'],
          );
          final ClientApi api = testClientApi(FakeCardClock());
          await api.pay(
            testOrderId,
            PayRequest(
              body: walletPayBody(kind, c['walletToken']! as String),
              wrappedKey: null,
              idempotencyKey: newIdempotencyKey(),
            ),
          );
          api.close();

          final http.Request request = sent.single;
          expect(request.method, c['method']);
          expect(request.url.path, c['path']);
          final Map<String, String> headers = <String, String>{
            for (final MapEntry<String, String> e in request.headers.entries)
              e.key.toLowerCase(): e.value,
          };
          (c['headers']! as Map<String, Object?>).forEach((
            String name,
            Object? value,
          ) {
            expect(
              headers[name.toLowerCase()],
              startsWith('$value'),
              reason: name,
            );
          });
          for (final Object? name in c['requiredHeaders']! as List<Object?>) {
            expect(headers[(name! as String).toLowerCase()], isNotEmpty);
          }
          for (final Object? name in c['absentHeaders']! as List<Object?>) {
            expect(
              headers.containsKey((name! as String).toLowerCase()),
              isFalse,
            );
          }
          expect(headers['x-idempotency-key'], hasLength(36));
          // The token exactly as the wallet returned it: not re-encoded and
          // not wrapped.
          expect(jsonDecode(request.body), body);
          expect(
            (jsonDecode(request.body)
                as Map<String, Object?>)['encryptedMessage'],
            c['walletToken'],
          );
        },
      );
    }
  });

  test('applePaySheet: the sheet status and what follows for every '
      'situation', () {
    final Map<String, Object?> sheet =
        _v['applePaySheet']! as Map<String, Object?>;
    expect(
      applePaySheetBudget,
      Duration(seconds: sheet['budgetSeconds']! as int),
    );
    final List<Map<String, Object?>> cases = _list(sheet['cases']);
    expect(
      cases.map((Map<String, Object?> c) => c['outcome']).toSet(),
      ApplePayOutcome.values.map((ApplePayOutcome o) => o.name).toSet(),
    );
    for (final Map<String, Object?> c in cases) {
      final ({ApplePaySheetStatus sheet, ApplePaySheetThen then}) rule =
          applePaySheetRule(
            ApplePayOutcome.values.byName(c['outcome']! as String),
          );
      expect(rule.sheet.name, c['sheet'], reason: '${c['situation']}');
      expect(rule.then.name, c['then'], reason: '${c['situation']}');
    }
  });

  test('applePaySheet: a result maps to its situation', () {
    const PayriffPayment payment = PayriffPayment(orderId: testOrderId);
    expect(
      applePayOutcomeOf(const PayriffResultSuccess(payment: payment)),
      ApplePayOutcome.finalSuccess,
    );
    expect(
      applePayOutcomeOf(const PayriffResultDeclined(payment: payment)),
      ApplePayOutcome.finalDeclined,
    );
    expect(
      applePayOutcomeOf(
        const PayriffResultCancelled(
          reason: PayriffCancelReason.expired,
          payment: payment,
        ),
      ),
      ApplePayOutcome.finalCancelled,
    );
    expect(
      applePayOutcomeOf(
        const PayriffResultPending(
          payment: payment,
          reason: PayriffPendingReason.unexpectedStatus,
        ),
      ),
      ApplePayOutcome.finalUnexpected,
    );
    // No final status: like the end of the budget, the sheet says success.
    expect(
      applePayOutcomeOf(
        const PayriffResultPending(
          payment: payment,
          reason: PayriffPendingReason.notFinal,
        ),
      ),
      ApplePayOutcome.budgetExpired,
    );
    expect(
      applePayOutcomeOf(
        const PayriffResultFailed(
          error: PayriffError(
            code: PayriffErrorCode.paymentFailed,
            message: 'x',
          ),
        ),
      ),
      ApplePayOutcome.failed,
    );
    expect(
      applePayOutcomeOf(
        const PayriffResultFailed(
          error: PayriffError(
            code: PayriffErrorCode.deviceCompromised,
            message: 'x',
          ),
        ),
      ),
      ApplePayOutcome.deviceCompromised,
    );
  });

  group('buttonStyles', () {
    final Map<String, Object?> styles =
        _v['buttonStyles']! as Map<String, Object?>;

    test('heights and corner radii', () {
      expect(walletDefaultButtonHeight, styles['defaultHeight']);
      expect(walletDefaultCornerRadius, styles['defaultCornerRadius']);
      expect(walletMinButtonHeight, styles['minHeight']);
      expect(walletButtonHeight(null, walletDefaultButtonHeight), 44);
      expect(walletButtonHeight(null, 52), 52);
      expect(walletButtonHeight(48, 52), 48);
      // Below 40 is raised to 40.
      expect(walletButtonHeight(30, 52), 40);
      expect(walletButtonHeight(null, 36), 40);
      expect(walletButtonCornerRadius(null, walletDefaultCornerRadius), 16);
      expect(walletButtonCornerRadius(null, 8), 8);
      expect(walletButtonCornerRadius(4, 8), 4);
      // A negative radius counts as 0.
      expect(walletButtonCornerRadius(-3, 8), 0);
      expect(walletButtonCornerRadius(null, -1), 0);
    });

    test('Apple Pay: types and themes, automatic from the page', () {
      final Map<String, Object?> apple =
          styles['applePay']! as Map<String, Object?>;
      final Map<String, Object?> defaults =
          apple['defaults']! as Map<String, Object?>;
      const PayriffApplePayButtonStyle style = PayriffApplePayButtonStyle();
      expect(style.type.name, defaults['type']);
      expect(style.theme.name, defaults['theme']);
      expect(style.cornerRadius, isNull);
      expect(style.height, isNull);
      final Map<String, Object?> types =
          apple['types']! as Map<String, Object?>;
      expect(
        PayriffApplePayButtonType.values.map(
          (PayriffApplePayButtonType t) => t.name,
        ),
        unorderedEquals(types.keys),
      );
      types.forEach((String name, Object? native) {
        final PayriffApplePayButtonType type = PayriffApplePayButtonType.values
            .byName(name);
        expect(
          applePayButtonParams(
            PayriffApplePayButtonStyle(type: type),
            dark: false,
            cornerRadius: 16,
          )['type'],
          native,
        );
      });
      final Map<String, Object?> themes =
          apple['themes']! as Map<String, Object?>;
      expect(
        PayriffApplePayButtonTheme.values.map(
          (PayriffApplePayButtonTheme t) => t.name,
        ),
        unorderedEquals(themes.keys),
      );
      themes.forEach((String name, Object? native) {
        final PayriffApplePayButtonTheme theme = PayriffApplePayButtonTheme
            .values
            .byName(name);
        if (theme == PayriffApplePayButtonTheme.automatic) return;
        for (final bool dark in <bool>[false, true]) {
          expect(applePayButtonTheme(theme, dark: dark), native);
        }
      });
      final Map<String, Object?> automatic =
          apple['flutterAutomatic']! as Map<String, Object?>;
      expect(
        applePayButtonTheme(PayriffApplePayButtonTheme.automatic, dark: false),
        automatic['light'],
      );
      expect(
        applePayButtonTheme(PayriffApplePayButtonTheme.automatic, dark: true),
        automatic['dark'],
      );
      // Style values only.
      expect(
        applePayButtonParams(
          const PayriffApplePayButtonStyle(
            type: PayriffApplePayButtonType.buy,
            theme: PayriffApplePayButtonTheme.whiteOutline,
          ),
          dark: true,
          cornerRadius: 8,
        ),
        <String, Object?>{
          'type': 'buy',
          'theme': 'whiteOutline',
          'cornerRadius': 8.0,
        },
      );
    });

    test('Google Pay: types and themes, automatic from the page', () {
      final Map<String, Object?> google =
          styles['googlePay']! as Map<String, Object?>;
      final Map<String, Object?> defaults =
          google['defaults']! as Map<String, Object?>;
      const PayriffGooglePayButtonStyle style = PayriffGooglePayButtonStyle();
      expect(style.type.name, defaults['type']);
      expect(style.theme.name, defaults['theme']);
      final Map<String, Object?> types =
          google['types']! as Map<String, Object?>;
      expect(
        PayriffGooglePayButtonType.values.map(
          (PayriffGooglePayButtonType t) => t.name,
        ),
        unorderedEquals(types.keys),
      );
      types.forEach((String name, Object? native) {
        expect(
          googlePayButtonType(PayriffGooglePayButtonType.values.byName(name)),
          native,
        );
      });
      final Map<String, Object?> themes =
          google['themes']! as Map<String, Object?>;
      expect(
        PayriffGooglePayButtonTheme.values
            .where(
              (PayriffGooglePayButtonTheme t) =>
                  t != PayriffGooglePayButtonTheme.automatic,
            )
            .map((PayriffGooglePayButtonTheme t) => t.name),
        unorderedEquals(themes.keys),
      );
      themes.forEach((String name, Object? native) {
        for (final bool dark in <bool>[false, true]) {
          expect(
            googlePayButtonTheme(
              PayriffGooglePayButtonTheme.values.byName(name),
              dark: dark,
            ),
            native,
          );
        }
      });
      final Map<String, Object?> automatic =
          google['automatic']! as Map<String, Object?>;
      expect(
        googlePayButtonTheme(
          PayriffGooglePayButtonTheme.automatic,
          dark: false,
        ),
        automatic['light'],
      );
      expect(
        googlePayButtonTheme(PayriffGooglePayButtonTheme.automatic, dark: true),
        automatic['dark'],
      );
    });

    test('styles compare by value and copyWith keeps the rest', () {
      const PayriffApplePayButtonStyle apple = PayriffApplePayButtonStyle(
        type: PayriffApplePayButtonType.donate,
        height: 50,
      );
      expect(apple, apple.copyWith());
      expect(apple.copyWith(cornerRadius: 4).height, 50);
      expect(apple.hashCode, apple.copyWith().hashCode);
      expect(apple, isNot(const PayriffApplePayButtonStyle()));
      const PayriffGooglePayButtonStyle google = PayriffGooglePayButtonStyle(
        theme: PayriffGooglePayButtonTheme.light,
      );
      expect(
        google.copyWith(type: PayriffGooglePayButtonType.pay).theme,
        PayriffGooglePayButtonTheme.light,
      );
      expect(google, isNot(const PayriffGooglePayButtonStyle()));
    });
  });

  test('googlePayGateway: the order\'s values, else the configuration\'s, '
      'else payriff; trimmed, blank is missing (revision 10)', () {
    final Map<String, Object?> section =
        _v['googlePayGateway']! as Map<String, Object?>;
    final List<Map<String, Object?>> cases = _list(section['cases']);
    expect(cases, isNotEmpty);
    for (final Map<String, Object?> c in cases) {
      final Map<String, Object?>? orderGooglePay =
          c['orderGooglePay'] as Map<String, Object?>?;
      final PayriffClientOrder order = _order(<String, Object?>{
        'orderId': testOrderId,
        'amount': 10.5,
        'currency': 'AZN',
        'status': 'CREATED',
        'paymentMethods': <String>['CARD'],
        'googlePay': orderGooglePay,
      });
      final PayriffGooglePayConfig config = _googleConfig(c['config']);
      final ({String gateway, String gatewayMerchantId})? gateway =
          googlePayGateway(order, config);
      final Map<String, Object?>? expected =
          c['expect'] as Map<String, Object?>?;
      expect(
        gateway == null
            ? null
            : <String, Object?>{
                'gateway': gateway.gateway,
                'gatewayMerchantId': gateway.gatewayMerchantId,
              },
        expected,
        reason: '${c['name']}',
      );
      // Google Pay is offered exactly when the parameters resolve.
      expect(
        walletOrderProblem(order, WalletKind.googlePay, googlePay: config),
        expected == null ? 'no gatewayMerchantId' : isNull,
        reason: '${c['name']}',
      );
    }
    expect(googlePayDefaultGateway, 'payriff');
    expect(const PayriffGooglePayConfig().gateway, 'payriff');
  });

  group('platformGuard: each wallet only on its own platform (revision '
      '10)', () {
    final Map<String, Object?> section =
        _v['platformGuard']! as Map<String, Object?>;
    for (final Map<String, Object?> c in _list(section['cases'])) {
      final TargetPlatform platform = switch (c['platform']) {
        'ios' => TargetPlatform.iOS,
        'android' => TargetPlatform.android,
        _ => throw StateError('unknown platform ${c['platform']}'),
      };
      final PayriffConfig config = PayriffConfig(
        publishableKey: testPublishableKey,
        applePay: c['applePayConfigured'] == true
            ? const PayriffApplePayConfig(
                merchantIdentifier: 'merchant.com.example.shop',
              )
            : null,
        googlePay: c['googlePayConfigured'] == true
            ? const PayriffGooglePayConfig(gatewayMerchantId: 'PRF0001')
            : null,
      );
      testWidgets('${c['platform']}: Apple Pay configured '
          '${c['applePayConfigured']}, Google Pay configured '
          '${c['googlePayConfigured']}', (WidgetTester tester) async {
        NativeCalls().install();
        // A card-only order with no googlePay object: only the
        // configuration and the platform decide.
        final PayriffClientOrder order = _order(<String, Object?>{
          'orderId': testOrderId,
          'amount': 10.5,
          'currency': 'AZN',
          'status': 'CREATED',
          'paymentMethods': <String>['CARD'],
        });
        final Map<String, Object?> expected =
            c['expect']! as Map<String, Object?>;
        for (final (WalletKind kind, String name) in <(WalletKind, String)>[
          (WalletKind.applePay, 'applePay'),
          (WalletKind.googlePay, 'googlePay'),
        ]) {
          expect(
            await decideWalletOffer(
              kind: kind,
              order: order,
              config: config,
              logger: SdkLogger.silent,
            ),
            expected[name],
            reason: name,
          );
        }
        expect(
          platformWallet,
          platform == TargetPlatform.iOS
              ? WalletKind.applePay
              : WalletKind.googlePay,
        );
      }, variant: TargetPlatformVariant.only(platform));
    }
  });

  test('PayriffGooglePayConfig: the gateway fields take part in ==, '
      'hashCode and toString', () {
    const PayriffGooglePayConfig a = PayriffGooglePayConfig(
      gatewayMerchantId: 'PRF0001',
    );
    expect(a, const PayriffGooglePayConfig(gatewayMerchantId: 'PRF0001'));
    expect(
      a.hashCode,
      const PayriffGooglePayConfig(gatewayMerchantId: 'PRF0001').hashCode,
    );
    expect(a, isNot(const PayriffGooglePayConfig()));
    expect(
      a,
      isNot(
        const PayriffGooglePayConfig(
          gatewayMerchantId: 'PRF0001',
          gateway: 'gccpay',
        ),
      ),
    );
    expect(
      a.toString(),
      allOf(
        contains('gatewayMerchantId: PRF0001'),
        contains('gateway: payriff'),
      ),
    );
  });

  test('every section of wallet.json is asserted here', () {
    expect(_v.keys.toSet(), <String>{
      'description',
      'applePayMerchantIdentifiers',
      'googlePayMerchantIds',
      'availability',
      'amounts',
      'googlePayEnvironments',
      'googlePayRequests',
      'applePayRequests',
      'payRequests',
      'applePaySheet',
      'buttonStyles',
      'applePayNetworks',
      'platformGuard',
      'googlePayGateway',
    });
  });
}
