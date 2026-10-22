# Payriff Flutter example

A test app for the `payriff` package. Application id / bundle id:
`com.payriff.example.flutter`, so it installs next to the other Payriff
example apps.

The app holds **no secret key** and never creates orders. As in a real app,
the order comes from your server: it creates the order with its secret key
(`POST /api/v3/orders`) and hands over `orderId` and `clientSecret`.

## Run it

```sh
cp config.example.json config.json   # config.json is git-ignored
# Put your publishable key (pr_pk_live_…) into config.json, then:
flutter run --dart-define-from-file=config.json
```

`config.json` keys (the app reads only these two):

| Key | Values |
|---|---|
| `PAYRIFF_PUBLISHABLE_KEY` | The publishable key of your Payriff application (`pr_pk_live_…`). Safe to ship: it only works with an order's `clientSecret`. |
| `PAYRIFF_ENVIRONMENT` | `sandbox` (default) or `production`. |

Payriff only accepts apps it knows: ask Payriff to allow the bundle id and
package name `com.payriff.example.flutter` for your publishable key.

To run on an iPhone, put your Apple team into the git-ignored
`ios/Flutter/Signing.xcconfig`:

```
DEVELOPMENT_TEAM = ABCDE12345
```

## What it shows

One screen:

- `orderId` and `clientSecret` fields, and **Paste**, which reads the JSON
  `{"orderId", "clientSecret"}` from the clipboard (or the two values
  separated by white space).
- **Pay in page**, **Pay in bottom sheet** and **Pay in popup** open the
  SDK's `PayriffPaymentView` in a full-screen page, a modal bottom sheet or
  a dialog (`lib/src/presentations.dart`). 3-D Secure opens in the SDK's
  sheet.
- The outcome opens in a result sheet: a large icon and title ("Payment
  successful", "Payment declined", "Payment pending", "Payment cancelled" or
  "Payment failed"), then the amount, order id, status, error and the
  result's JSON.

In a real app your server creates the order and fulfils it only after it has
confirmed the payment with Payriff.

The app keeps the SDK's defaults for security: its connections to Payriff
are pinned, so a proxy such as Charles or Burp makes them fail, and on a
rooted or jailbroken device, or with Frida attached, the payment view says
that card payments aren't available on this device; the SDK log says which
signal matched. To pay from such a test device anyway, add
`allowCompromisedDevices: true` to `toConfig()` in `lib/src/settings.dart`
for that run.

The app's iOS deployment target is 16.0, the minimum the SDK supports.

Sandbox test cards are listed on https://docs.payriff.com.
