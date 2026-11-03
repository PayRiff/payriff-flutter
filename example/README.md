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

`config.json` keys (the app reads only these):

| Key | Values |
|---|---|
| `PAYRIFF_PUBLISHABLE_KEY` | The publishable key of your Payriff application (`pr_pk_live_…`). Safe to ship: it only works with an order's `clientSecret`. |
| `PAYRIFF_ENVIRONMENT` | `sandbox` (default) or `production`. |
| `PAYRIFF_REGION` | `az` (default, `api.payriff.com`) or `sa` (Saudi Arabia, GCC Pay, `api.gccpay.sa`). **Region `sa` has no sandbox:** with `PAYRIFF_ENVIRONMENT` `sandbox` its payments still go to production and charge real cards. |
| `PAYRIFF_APPLE_PAY_MERCHANT_ID` | iOS: your Apple Pay merchant ID (`merchant.…`). Empty (default) leaves Apple Pay off. See [Apple Pay and Google Pay](#apple-pay-and-google-pay). |
| `PAYRIFF_GOOGLE_PAY` | Android: `true` shows Google Pay; `false` (default) leaves it off. |
| `PAYRIFF_GOOGLE_PAY_MERCHANT_ID` | Android, optional: your merchant ID from the Google Pay & Wallet Console. |

Payriff only accepts apps it knows: ask Payriff to allow the bundle id and
package name `com.payriff.example.flutter` for your publishable key.

To run on an iPhone, put your Apple team into the git-ignored
`ios/Flutter/Signing.xcconfig`:

```
DEVELOPMENT_TEAM = ABCDE12345
```

## Apple Pay and Google Pay

With the keys above, the payment view shows the Apple Pay button (iOS) or
the Google Pay button (Android) above the card form, when the order accepts
`APPLE_PAY` or `GOOGLE_PAY` and the device can pay. The Payriff sandbox has
no wallets: try them with `"PAYRIFF_ENVIRONMENT": "production"` and a real
card.

**Apple Pay** also needs the Apple Pay capability with your merchant ID in
the Runner target. The example does not include it, because signing fails
for a team that does not own that merchant ID. Add it locally and do not
commit it:

1. Open `ios/Runner.xcworkspace` in Xcode and select the **Runner** target.
2. In **Signing & Capabilities**, choose your team, then **+ Capability** →
   **Apple Pay**.
3. Tick your merchant ID (`merchant.…`) under **Merchant IDs**. Xcode adds
   `Runner/Runner.entitlements` with
   `com.apple.developer.in-app-payments` and sets
   `CODE_SIGN_ENTITLEMENTS`; revert both before you commit.
4. Put the same merchant ID into `PAYRIFF_APPLE_PAY_MERCHANT_ID` and run on
   an iPhone with a Visa or Mastercard in Wallet.

The merchant ID needs an Apple Pay Payment Processing Certificate made
from the certificate signing request that Payriff gives you, otherwise
Payriff cannot read the payment.

**Google Pay** needs nothing in the app: the SDK's manifest enables the
Google Pay API. `PAYRIFF_ENVIRONMENT` `sandbox` in region `az` uses Google
Pay's `TEST` environment; everything else uses `PRODUCTION`, which needs
production access for the app in the Google Pay & Wallet Console
(integration type *Gateway*).

## What it shows

One screen:

- `orderId` and `clientSecret` fields, and **Paste**, which reads the JSON
  `{"orderId", "clientSecret"}` from the clipboard (or the two values
  separated by white space).
- **Pay in page**, **Pay in bottom sheet** and **Pay in popup** open the
  SDK's `PayriffPaymentView` in a full-screen page, a modal bottom sheet or
  a dialog (`lib/src/presentations.dart`), with the Apple Pay or Google Pay
  button on top when it is on. 3-D Secure opens in the SDK's sheet.
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
for that run. The SDK honours it only in debug builds (`flutter run` without
`--profile` or `--release`); other builds ignore it and still refuse the
device.

The app's iOS deployment target is 16.0, the minimum the SDK supports.

Sandbox test cards are listed on https://docs.payriff.com.
