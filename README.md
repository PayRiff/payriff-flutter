# Payriff for Flutter

Accept [Payriff](https://payriff.com) card payments in Flutter apps. Your
server creates the order; the app shows `PayriffPaymentView`, a ready-made
payment screen that pays the order with your **publishable key**, runs 3-D
Secure in a native sheet and returns a verified, typed `PayriffResult`. For a
screen of your own, use the `PayriffCardForm` and `Payriff.confirmCardPayment`
it is built on.

- **The secret key never ships.** The app uses only the publishable key
  (`pr_pk_live_…`) and the order's `clientSecret`, like Payriff.js on the
  web. The SDK never creates orders.
- **Ready-made payment view**: looks like the card part of Payriff's hosted
  payment page (pay.payriff.com) by default and can be restyled; validation
  and formatting as the customer types, Visa and Mastercard marks,
  Azerbaijani, English and Russian copy, light and dark mode.
- **Card data stays protected**: the card is encrypted on the device
  (AES-256-GCM, key wrapped with Payriff's pinned RSA key) and only the
  ciphertext leaves the SDK. WebViews appear only for 3-D Secure.
- **Verified results**: the SDK reads the order status from Payriff. The
  result drives your UI; your server fulfils the order (see
  [Fulfil on your server](#fulfil-on-your-server)).
- A Flutter plugin on top of `webview_flutter`. Its small native part (card
  encryption, app id, screen protection, hardened app hand-offs) needs no
  setup.

## Requirements

| | Minimum |
|---|---|
| Flutter | 3.38 (Dart 3.10) |
| iOS | 16.0 |
| Android | 7.0 (API 24) |

**iOS 16 or later is required** for the 3-D Secure pages, which need a
modern WebKit. The package can build for lower iOS versions (Flutter's own
minimum), but those versions are unsupported and untested.

## Installation

```sh
flutter pub add payriff
```

Then complete the [platform setup](#platform-setup).

## How it works

1. **Your server creates the order** with its secret key
   (`POST /api/v3/orders`) and returns the order's `orderId` and
   `clientSecret` to the app. The secret key stays on your server.
2. **The app shows `PayriffPaymentView`** with the `orderId` and the
   `clientSecret`. It shows the amount on its Pay button; when the customer
   taps Pay, it calls `Payriff.confirmCardPayment`.
3. **The SDK pays the order** through Payriff's Client API: it checks that
   the order can be paid by card, encrypts the card on the device, sends it,
   runs 3-D Secure in its sheet when the bank asks for it, and polls the
   status until it is final.
4. **Your server fulfils the order** after it has confirmed the payment with
   Payriff.

## Quick start

```dart
import 'package:flutter/material.dart';
import 'package:payriff/payriff.dart';

void main() {
  Payriff.configure(const PayriffConfig(publishableKey: 'pr_pk_live_…'));
  runApp(const MyApp());
}

/// Shows the payment view for an order your server created. Completes with
/// the result, or null when the customer goes back without paying.
Future<PayriffResult?> pay(BuildContext context, Order order) =>
    Navigator.of(context).push<PayriffResult>(
      MaterialPageRoute<PayriffResult>(
        builder: (BuildContext context) => Scaffold(
          appBar: AppBar(),
          body: PayriffPaymentView(
            orderId: order.orderId,
            clientSecret: order.clientSecret,
            onResult: (PayriffResult result) =>
                Navigator.of(context).pop(result),
          ),
        ),
      ),
    );

Future<void> checkout(BuildContext context, Cart cart) async {
  // Your server creates the order and returns orderId + clientSecret.
  final Order order = await myBackend.startCheckout(cart);
  if (!context.mounted) return;
  switch (await pay(context, order)) {
    case PayriffResultSuccess(:final payment):
      showReceipt(payment.orderId); // Fulfil on your server.
    case PayriffResultDeclined():
      showMessage('Card declined');
    case PayriffResultCancelled():
      showMessage('Payment cancelled');
    case PayriffResultPending(:final payment):
      checkOnServer(payment.orderId);
    case PayriffResultFailed(:final error):
      showMessage(error.message);
    case null:
      break; // Closed without paying.
  }
}
```

`Payriff.retrieveOrder(orderId:, clientSecret:)` returns a
`PayriffClientOrder` (amount, currency, description, merchant name, status
and payment methods), for example to show the amount next to the form. It
throws a `PayriffException`.

## The payment view

```dart
PayriffPaymentView(
  orderId: order.orderId,           // from your server
  clientSecret: order.clientSecret, // from your server (pr_cs_…)
  onResult: (PayriffResult result) {},
  language: null, // null: PayriffConfig.language, then the device
  style: const PayriffPaymentViewStyle(), // see "Customise the payment view"
)
```

- It shows the card form, a Pay button with the order's amount ("Pay
  1.00 AZN"), the accepted card badges, a "Proceed securely by PCI DSS" line
  and a "Powered by Payriff" footer, like the card part of pay.payriff.com.
- It reads the order with `Payriff.retrieveOrder` when it appears. The Pay
  button stays disabled while the order loads, when the order cannot be paid
  by card or did not load (an error line then says why), while the form is
  incomplete and while paying.
- Pay runs `Payriff.confirmCardPayment`. `onResult` gets the result of each
  payment attempt, and once a fatal error that ends the order (for example
  an expired client secret, `error.isFatal`). After a result with a status,
  the view does not pay the order again.
- A failure with `error.isRetryable` (no answer, or a server error) leaves
  the order payable: show the view again with the same `orderId` and
  `clientSecret`.
- Call `Payriff.configure` before you show it.

### Page, bottom sheet or dialog

Give the view the whole screen, for example as a `Scaffold` body (see the
quick start): it scrolls when the keyboard is up and keeps the footer at the
bottom when there is room. Inside a parent that scrolls already, it takes
the height of its content, so it also fits a modal bottom sheet or a dialog:

```dart
// A bottom sheet that is as tall as the view.
showModalBottomSheet<PayriffResult>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (BuildContext context) => SingleChildScrollView(
    child: PayriffPaymentView(
      orderId: order.orderId,
      clientSecret: order.clientSecret,
      style: const PayriffPaymentViewStyle(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
      ),
      onResult: (PayriffResult result) => Navigator.of(context).pop(result),
    ),
  ),
);

// A dialog. It does not touch the screen edges, so it removes the safe area
// that the view would otherwise add to its padding.
showDialog<PayriffResult>(
  context: context,
  builder: (BuildContext context) => Dialog(
    clipBehavior: Clip.antiAlias,
    child: MediaQuery.removePadding(
      context: context,
      removeTop: true,
      removeBottom: true,
      child: SingleChildScrollView(
        child: PayriffPaymentView(
          orderId: order.orderId,
          clientSecret: order.clientSecret,
          onResult: (PayriffResult result) =>
              Navigator.of(context).pop(result),
        ),
      ),
    ),
  ),
);
```

The view paints its own background (`#FCFCFD`, `#222224` in dark mode). Give
the sheet or the dialog the same `backgroundColor`, or set the view's
`backgroundColor` to `Colors.transparent` to show theirs. The example app
(`example/lib/src/presentations.dart`) shows all three.

### Customise the payment view

Pass a `PayriffPaymentViewStyle`. Every property is optional and keeps its
default when you leave it out; a colour you set applies in light and dark
mode.

```dart
PayriffPaymentView(
  orderId: order.orderId,
  clientSecret: order.clientSecret,
  onResult: handleResult,
  style: const PayriffPaymentViewStyle(
    buttonColor: Color(0xFF6D28D9),
    buttonCornerRadius: 26,
    buttonHeight: 52,
    showPoweredBy: false,
    formStyle: PayriffCardFormStyle(
      layout: PayriffCardFormLayout.stacked,
      focusedBorderColor: Color(0xFF6D28D9),
      cornerRadius: 14,
    ),
  ),
)
```

| Property | Default |
|---|---|
| `backgroundColor` | `#FCFCFD`, `#222224` in dark mode |
| `padding` | 20 on every side; the view adds the safe area, and the keyboard when its parent does not make room for it |
| `buttonColor` | Payriff's brand colour `#4DBDC6` |
| `buttonTextStyle` | 16 semibold, white; merged over the default |
| `buttonHeight`, `buttonCornerRadius` | 44, 16 |
| `secondaryTextColor` | `#76787F`: the secure line and the footer |
| `showBadges` | `true`: the Mastercard and Visa badges under the button |
| `showSecureNote` | `true`: the lock and "Proceed securely by PCI DSS" |
| `showPoweredBy` | `true`: the "Powered by Payriff" footer |
| `formStyle` | `PayriffCardFormStyle()`, see [Customise the card form](#customise-the-card-form) |

The view follows your app's theme brightness (`Theme`, or `CupertinoTheme`
in a `CupertinoApp`) for light and dark mode.

## Fulfil on your server

The SDK's result is for the user interface only. Payment state that decides
whether you ship goods must come from your server:

1. **Fulfil only after your server confirms the order with Payriff**, from
   Payriff's server-to-server callback or from its own order lookup with the
   secret key. Never ship on `PayriffResultSuccess` alone: the app can be
   killed mid-payment, and a modified app can report anything.
2. **Check that it is your order:** the order id is one your server created
   for this cart, and the amount and currency Payriff reports are the ones
   you charged.

`PayriffResultPending` means the same: confirm on your server, then tell the
customer.

## Build your own screen

`PayriffPaymentView` is built from two public parts you can use on a screen
of your own: `PayriffCardForm` and `Payriff.confirmCardPayment`.

```dart
class _CheckoutPageState extends State<CheckoutPage> {
  final PayriffCardController _card = PayriffCardController();

  @override
  void dispose() {
    _card.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    final PayriffResult result = await Payriff.confirmCardPayment(
      context,
      _card,
      orderId: widget.order.orderId,
      clientSecret: widget.order.clientSecret,
    );
    if (mounted) handleResult(result);
  }

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      PayriffCardForm(controller: _card),
      ListenableBuilder(
        listenable: _card,
        builder: (BuildContext context, _) => FilledButton(
          onPressed: _card.isProcessing ? null : _pay,
          child: _card.isProcessing
              ? const CircularProgressIndicator()
              : const Text('Pay'),
        ),
      ),
    ],
  );
}
```

### The card form

```dart
PayriffCardForm(
  controller: card,        // required; dispose() it with your State
  showHolder: true,        // cardholder name; false hides it and sends "Unknown"
  autoAdvance: true,       // number → expiry → CVV when a field is complete
  language: null,          // null: PayriffConfig.language, then the device
  style: const PayriffCardFormStyle(), // see "Customise the card form"
  onChanged: (PayriffCardFormChange change) {},
)
```

- By default the form looks like the card form of Payriff's hosted payment
  page (pay.payriff.com): "Card holder" first, then one "Card information"
  box with the card number and the brand mark on top and the expiry and the
  CVC side by side below it. Each section has one error line; under the box
  it shows the first error of the number, the expiry and the CVC.

- Validation and formatting follow Payriff.js: Visa and Mastercard, at most
  16 digits, Luhn, an expiry that is not in the past and at most 20 years
  ahead, a 3-digit CVV, and a holder name of at most 50 characters without
  control characters or `<` / `>`. The holder name is always shown and sent
  in upper case.
- Errors appear when they help: definite errors at once, an incomplete field
  after it loses focus or after Pay, an empty required field only after Pay.
- The brand shows as the Visa or Mastercard mark inside the number field as
  soon as the first digits identify it.
- `onChanged` reports `{field, valid, empty, error, brand, complete}`. No
  event or API exposes the card number, expiry, CVV or holder name.
- `PayriffCardController` tells whether the form `isComplete`, the detected
  `brand` and whether a payment `isProcessing` (the form is locked
  meanwhile). It also has `clear()` and `focus(field)`.
- **Security**: copy and cut are off for the number and the CVV, the CVV is
  masked and never offered to autofill, the keyboard neither corrects,
  suggests nor learns, screenshots and app-switcher snapshots are blocked
  while the form or the 3-D Secure sheet is shown (Android `FLAG_SECURE`, an
  iOS cover while the app is inactive), and the values are cleared after a
  final result and when the form is disposed.

### Customise the card form

Pass a `PayriffCardFormStyle` to `PayriffCardForm`, or to the payment view
through `PayriffPaymentViewStyle.formStyle`. Every property is optional and
keeps its default when you leave it out.

```dart
PayriffCardForm(
  controller: card,
  style: PayriffCardFormStyle(
    layout: PayriffCardFormLayout.stacked, // default: grouped
    cornerRadius: 20,
    borderColor: Colors.teal.shade100,
    focusedBorderColor: Colors.teal,
    fieldBackgroundColor: Colors.teal.shade50,
    labelTextStyle: const TextStyle(fontSize: 12, letterSpacing: 0.8),
  ),
)
```

| Property | Default |
|---|---|
| `layout` | `grouped`: the holder, then one "Card information" box. `stacked`: every field on its own, with its label above it and its error below it |
| `labelTextStyle` | 14 semibold, `#34363A` (`#E1E4E8` in dark mode) |
| `inputTextStyle` | 14 regular, `#4D4F54` (`#8E8E93` in dark mode) |
| `placeholderColor` | `#76787F` (`#5F6167` in dark mode) |
| `errorTextStyle` | 13 regular, `errorColor` |
| `showLabels` | `true`; the fields keep their accessibility labels without them |
| `holderLabel`, `cardLabel` | "Card holder", "Card information" in the form's language |
| `fieldBackgroundColor` | transparent: the fields show the background behind the form |
| `borderColor` | `#ECEEF0` (`#3F4145` in dark mode) |
| `focusedBorderColor` | Payriff's brand colour `#4DBDC6` |
| `errorColor` | `#EC4D3D` (`#EC5545` in dark mode) |
| `borderWidth`, `cornerRadius` | 1, 12 |
| `holderHeight`, `rowHeight` | 46, 40; they grow with large text |
| `horizontalPadding`, `labelSpacing`, `sectionSpacing` | 14, 10, 16 |

Text styles are merged over the defaults, so set only what you change. A
colour you set applies in light and dark mode; take it from your theme to
follow both. A section's outline turns `errorColor` while it shows an error,
otherwise `focusedBorderColor` while one of its fields has the focus.

### `confirmCardPayment`

1. The form is validated. An invalid form shows its errors and returns
   `failed(VALIDATION_FAILED)` with `error.fields`; nothing is sent.
2. The order must be `CREATED` or `PENDING` and accept `CARD`, otherwise
   the result is `failed(ORDER_NOT_PAYABLE)`.
3. The card is encrypted on the device and sent with `X-Client-App-Id` (your
   bundle id or package name). A `429` is retried three times (1 s, 2 s,
   4 s) and a request without an answer once, with the same idempotency key.
4. When the bank asks for 3-D Secure, its page opens in the SDK's sheet (a
   Cupertino-style sheet on iOS, a Material bottom sheet on Android) with a
   title, a close button and a native loader; bank pages get margins, so they
   do not run to the screen edges. The 3-D Secure Method runs invisibly
   behind the loader.
5. The status is polled every 2.5 s for up to 120 s.

Once the card was sent the result is never `cancelled(userClosed)`: closing
the 3-D Secure sheet (✕, a pull on the header, or the Android back gesture)
asks for confirmation, checks the status once and returns the final result,
or `pending(notFinal)` while the payment may still complete.

Only one payment runs at a time; a second call returns
`failed(PAYMENT_IN_PROGRESS)`. The sheet is pushed on the root navigator, so
`confirmCardPayment` works from any `BuildContext` below your `MaterialApp`
or `CupertinoApp`. Links to bank apps open outside the app through the
plugin's hardened launcher; `file:` and `content:` URLs never leave the app.

## Configuration

`Payriff.configure(config)` never throws and may be called again; the new
configuration applies to later calls.

| `PayriffConfig` field | Default | Notes |
|---|---|---|
| `publishableKey` | `null` | Your application's publishable key (`pr_pk_live_…`), sent as `X-Public-Key`. Safe to ship: it only works with an order's `clientSecret`. A missing key, or any other kind of key (for example the secret key), makes the card calls fail with `invalidConfig`. |
| `environment` | `production` | `production` uses `https://api.payriff.com`, `sandbox` uses `https://sb-api.payriff.com`. The sandbox host is provisional until Payriff confirms it. |
| `language` | `null` | `PayriffLanguage.az`, `en` or `ru` for the form and the 3-D Secure sheet. `null` uses the device language (Azerbaijani, Russian, otherwise English). |
| `enableLogging` | `false` | See [Logging](#logging). |

## Handling `PayriffResult`

`confirmCardPayment` never throws. It completes with exactly one of:

| Variant | When | Payload |
|---|---|---|
| `PayriffResultSuccess` | Status `APPROVED` or `PREAUTH_APPROVED`. **The only result to show as paid** in the app; fulfil on your server. | `payment` |
| `PayriffResultDeclined` | Status `DECLINED`. | `payment` |
| `PayriffResultCancelled` | `reason`: `canceled` (`CANCELED`) or `expired` (`EXPIRED`, `PREAUTH_EXPIRED`). | `payment` |
| `PayriffResultPending` | `reason`: `notFinal` (not final after polling, or the sheet was closed with a non-final status), `verificationFailed` (the status could no longer be read), `unexpectedStatus` (for example `REFUNDED`). Verify on your server. | `payment` |
| `PayriffResultFailed` | The payment could not start or run: configuration, arguments, an invalid form, an order that cannot be paid or a Client API error. | `error` |

`PayriffPayment` carries `orderId`, `status` (`PayriffPaymentStatus`),
`rawStatus`, `amount` and `currency` (from the status check), and
`transactionId` and `originalOrderId`, which the card flow leaves `null`.

Every result also has these helpers:

- `result.isSuccess`: `true` only for `PayriffResultSuccess`.
- `result.payment`: the `PayriffPayment`, or `null` for failed results.
- `result.error`: the `PayriffError` of a failed result, otherwise `null`.
- `result.toJson()`: the JSON shape shared by all Payriff SDKs. Every key is
  present and unknown values are `null`.

Other helpers: `Payriff.version`, `Payriff.config`,
`Payriff.isPaymentInProgress` and `PayriffPaymentStatus.parse(raw)`.

### Errors

`PayriffError` has `code`, `message`, `isRetryable`, `httpStatus`,
`payriffCode`, `supportTicket`, `isFatal` (`true`: this order can no longer
be paid from the app; create a new order) and, for `validationFailed`,
`fields`.

| `PayriffErrorCode` | Meaning |
|---|---|
| `notConfigured` | `Payriff.configure` was not called. |
| `invalidConfig` | `publishableKey` is missing or is not a `pr_pk_live_…` key. |
| `invalidOrder` | The `orderId` or `clientSecret` (`pr_cs_…`) argument cannot be used. |
| `paymentInProgress` | Another payment is running. |
| `presentationFailed` | No `Navigator` above the `BuildContext`. |
| `validationFailed` | The card form is not valid; `error.fields` lists the fields. Nothing was sent. |
| `orderNotPayable` | The order is not `CREATED`/`PENDING`, does not accept `CARD`, or the API answered HTTP 400. |
| `invalidRequest` | HTTP 400 with code `15400`: the request format was rejected. |
| `unauthorized` | HTTP 401: wrong or revoked publishable key, or this app is not allowed for it. Fatal. |
| `sessionExpired` | HTTP 404: the order does not exist or its `clientSecret` expired. Fatal. |
| `rateLimited` | HTTP 429 after the SDK's retries. Fatal. |
| `paymentFailed` | Any other unsuccessful answer, with Payriff's message. The customer may try again. |
| `unexpectedResponse` | Payriff's next step could not be understood and the status was not final. |
| `networkError` | Offline, DNS, TLS or timeout. |
| `unknown` | Anything else, for example a device that cannot encrypt. |
| `apiError` | Part of the code set shared by all Payriff SDKs; the card flow does not produce it. |

## Logging

```dart
Payriff.configure(const PayriffConfig(enableLogging: true /* ... */));
// In debug builds each entry is also printed to the console as
// entry.formatted, for example:
// [Payriff] [INFO] confirmCardPayment: order 7c9e6679-…
Payriff.logStream.listen((entry) => myLogger.log(entry.formatted));
```

`PayriffLogEntry` has `level`, `message`, `timestamp` and `formatted` (the
`[Payriff] [LEVEL] message` line). Logs never contain card data, and keys
and secrets show only as `***(<length>)`. `http(s)` URLs are logged without
their query string and fragment; any other URL is logged as `<scheme>:…`.

In **debug builds**, each API request and response is also logged at `debug`
level as pretty-printed JSON (method, URL, headers, body). `X-Client-Secret`
and `x-secret-key` show as `***(<length>)`, `X-Public-Key` as
`pr_pk_live_***(<length>)`, and `clientSecret`, `encryptedMessage`, `creq`,
the card fields and other secrets are redacted at any depth. Release builds
never log HTTP details.

Profile and release builds never print to the console, so the payment trail
does not reach the device log (logcat, Console); entries still reach
`logStream` while `enableLogging` is on. Leave logging off in production
unless you collect the entries yourself.

## Platform setup

### Android

- `minSdk` 24 or higher.
- Flutter's template adds the `INTERNET` permission only to debug and
  profile builds. Add it to `android/app/src/main/AndroidManifest.xml` for
  release builds:

  ```xml
  <uses-permission android:name="android.permission.INTERNET" />
  ```

- The 3-D Secure WebView has third-party cookies on (bank pages need them)
  and file and content-provider access off. Its JavaScript dialogs use the
  WebView's own dialogs.

### iOS

Set the deployment target to iOS 16.0 or later. No other setup is needed.
The SDK injects no JavaScript into bank pages and leaves the user agent
alone. A bank page's JavaScript `alert`, `confirm` and `prompt` dialogs show
as native alerts with localized OK and Cancel buttons, titled with the host
of the page that opened them; after three, later ones are answered without
showing them, so a page cannot lock the sheet.

## Example app

`example/` contains the integration to copy (application id and bundle id
`com.payriff.example.flutter`). Its one screen takes an order your server
created (`orderId` and `clientSecret`, or **Paste** for the JSON
`{"orderId", "clientSecret"}`) and opens `PayriffPaymentView` in a page, a
bottom sheet or a popup. The app has no secret key and never creates orders.

```sh
cd example
cp config.example.json config.json   # git-ignored; put your publishable key in it
flutter run --dart-define-from-file=config.json
```

See [example/README.md](example/README.md).

## Known limitations

- **Card values live in Dart strings.** Flutter keeps what the customer
  types in Dart `String`s (text fields, validation, the JSON before
  encryption), and the Dart heap cannot be wiped. The SDK clears the fields
  after a final result and on dispose, zeroes the byte buffers it owns, and
  encrypts in native code, but copies of the strings may stay in memory until
  the garbage collector reuses it.
- **iOS: `target="_blank"` links to app schemes are blocked** in the 3-D
  Secure sheet. `webview_flutter_wkwebview` reports new-window actions like
  subframe navigations. Same-window links and redirects to a bank app's
  scheme open the app normally.
- **Android: a page that ends the 3-D Secure step is stopped by loading
  `about:blank`.** `webview_flutter` has no `stopLoading`.
- **JavaScript `prompt()` on iOS:** Cancel answers with an empty string
  instead of `null`, because the plugin's prompt handler cannot return
  `null`.
- **Order ids `.` and `..` cannot be used.** Dart's `Uri` removes dot
  segments, so these ids are rejected with `invalidOrder` instead of
  reaching another endpoint. Payriff order ids never look like this.
- **Process death.** If the operating system ends the app process during a
  payment, the `Future` returned by `confirmCardPayment` ends with it.
  Nothing is restored when the app starts again: confirm the order on your
  server.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `notConfigured` | Call `Payriff.configure` first. |
| `invalidConfig` | Set `publishableKey` to your application's `pr_pk_live_…` key. The secret key is always refused. |
| `invalidOrder` | Pass the `orderId` and the `clientSecret` (`pr_cs_…`) your server got when it created the order. |
| `unauthorized` | The publishable key is wrong or revoked, or this app's bundle id / package name is not allowed for it. |
| `sessionExpired` | The order does not exist in the selected environment, or its `clientSecret` expired. Create a new order. |
| `orderNotPayable` | The order was already paid, expired, or does not accept cards. |
| Blank 3-D Secure page or `networkError` in Android release builds | Add the `INTERNET` permission to the main manifest. |
| `presentationFailed` | The `BuildContext` has no `Navigator` above it (for example a context above `MaterialApp`). |
| Payment lost after the app was killed | The app process ended mid-payment. Reconcile the order on your server. |

Turn on `enableLogging` to see every request, 3-D Secure step and status
check.

## Support

- Documentation: [docs.payriff.com](https://docs.payriff.com)
- Issues: [github.com/PayRiff/payriff-flutter/issues](https://github.com/PayRiff/payriff-flutter/issues)
- Security: report vulnerabilities privately, see [SECURITY.md](SECURITY.md)

## License

The Payriff SDK License, the same terms as Payriff.js: you may include the SDK
unmodified in your app to accept payments through Payriff. See
[LICENSE](LICENSE) for the full text.
