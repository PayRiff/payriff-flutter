# Changelog

## 1.0.0-rc.6 - 2026-11-04

### Changed

- Apple Pay and Google Pay follow the app's configuration only (CONTRACT
  revision 10): the order's `paymentMethods` are no longer checked, so a
  configured wallet appears for every order that is `CREATED` or `PENDING`
  with an amount and a currency. Apple Pay is offered only on iOS and
  Google Pay only on Android, whatever is configured.

### Added

- `PayriffGooglePayConfig.gatewayMerchantId` and `gateway` (default
  `payriff`): Google Pay's tokenization parameters when the order has no
  `googlePay` object. The order's values win when it has them; without a
  `gatewayMerchantId` anywhere, Google Pay is not offered (the debug line
  says `no gatewayMerchantId`).

## 1.0.0-rc.5 - 2026-11-04

### Fixed

- iOS: the card holder field opened the name and phone pad (`TextInputType.name`), which ignores auto-capitalization, so the keyboard showed lower case while the field upper-cased the text. It now opens the default keyboard in caps mode (CONTRACT §16.4). Android is unchanged.

## 1.0.0-rc.4 - 2026-11-04

### Added

- Design options (CONTRACT revision 8), all off by default; without them
  every screen looks and behaves as before:
  - `PayriffPaymentViewStyle.payButtonTitle`: the whole Pay button text,
    without the amount. The wallet sheets and the 3-D Secure page still show
    the real amount; showing the charge on your screen is up to you.
  - `PayriffPaymentViewStyle.cornerSmoothing` and
    `PayriffCardFormStyle.cornerSmoothing` (0–1): Figma-style smooth corners
    for the fields, the card box, the brand mark, the Pay button and the
    badges.
  - `PayriffPaymentViewStyle.buttonDisabledColor` and
    `buttonDisabledTextColor`: a disabled Pay button in these colours at
    full opacity.
  - `PayriffPaymentViewStyle.badgeBorderColor` and
    `PayriffCardFormStyle.brandMarkBorderColor`.
  - `PayriffStrings` for every visible text of the card form, the payment
    view and the 3-D Secure sheet, with `errorMessages` for the on-screen
    error lines (the view's error line, and the device, not-payable and
    page-load lines when their own field is not set):
    `PayriffConfig.strings` app-wide, `PayriffPaymentView.strings` per view
    (it wins field by field).
  - `PayriffPaymentView.onPaymentStarted` (`PayriffPaymentMethod`),
    `onOrderLoaded` and `onLoadFailed`.
  - Right-to-left layouts: the view, the form and the 3-D Secure sheet follow
    `Directionality`; the card number, expiry and CVC stay left to right.
  - `Payriff.isSupported()`: `true` on iOS 16+ and Android 7.0+.
- Payriff.js 1.3.1 alignment (CONTRACT revision 9):
  - mada cards (`PayriffCardBrand.mada`) with their BINs and brand mark. mada
    is recognised once the whole 6- or 8-digit BIN is typed, so a card that
    is also Visa or Mastercard shows that brand until then.
  - Arabic (`PayriffLanguage.ar`), laid out right to left. With no language
    set, a device language the SDK does not have now gives Arabic in region
    `sa` (English in region `az`, as before).
  - Apple Pay offers mada in region `sa`.

### Changed

- The 3-D Secure Method follows Payriff.js 1.3.1: the issuer's hidden page
  runs only with both its URL and its data, `/three-ds` waits until the
  hidden pages have loaded (at most 10 s), has a 60 s timeout and one retry
  on a network error or HTTP 5xx, and a `wait` answer is followed every 2 s
  for at most 30 s before status polling. The 1 s × 30 loop is gone.
- The Mastercard and Visa badges are their frameless marks in a frame drawn
  by the SDK; the framed badge images are no longer shipped. With the
  defaults they look as before.
- The Android part pins the Kotlin Gradle plugin at 2.2.10 (was 2.4.0), so
  it never asks for a newer one than the app's.
- `PayriffCardBrand` and `PayriffLanguage` have new values (`mada`, `ar`): a
  `switch` over them needs a case for each.

## 1.0.0-rc.3 - 2026-11-03

### Added

- Apple Pay on iOS and Google Pay on Android (CONTRACT revision 7):
  `PayriffConfig.applePay` (`PayriffApplePayConfig`: `merchantIdentifier`,
  `merchantName`) and `PayriffConfig.googlePay` (`PayriffGooglePayConfig`:
  `merchantId`, `merchantName`), both off by default. The wallet's token
  goes to Payriff's Client API (`/pay` with `APPLE_PAY` or `GOOGLE_PAY`,
  without `x-secret-key`); 3-D Secure, status polling and the result are the
  same as for cards.
- `PayriffPaymentView` shows the official Apple Pay or Google Pay button
  above the card form, with an "Or pay by card" divider (Azerbaijani,
  English and Russian), when the wallet is offered for the order: it is
  configured, the device is not compromised, the order accepts the wallet
  and the device can pay. Without a wallet the view is unchanged. Closing
  the wallet's sheet reports nothing; the customer can pay by card.
- `PayriffPaymentViewStyle.applePayButton`, `googlePayButton`,
  `walletDividerText` and `showWalletDivider`, and the button styles
  `PayriffApplePayButtonStyle` (`PayriffApplePayButtonType`,
  `PayriffApplePayButtonTheme`) and `PayriffGooglePayButtonStyle`
  (`PayriffGooglePayButtonType`, `PayriffGooglePayButtonTheme`): type,
  theme (`automatic` follows the page), corner radius and height.
- Standalone `PayriffApplePayButton` and `PayriffGooglePayButton` widgets
  (`orderId`, `clientSecret`, `style`, `onAvailabilityChange`, `onResult`)
  for screens of your own. Closing the sheet gives `cancelled(userClosed)`.
- `PayriffClientOrder.applePay` (`PayriffClientOrderApplePay`) and
  `PayriffClientOrder.googlePay` (`PayriffClientOrderGooglePay`).
- `PayriffErrorCode.walletFailed` (`WALLET_FAILED`): the wallet's sheet
  could not be shown, failed or returned no token. Not fatal.

### Changed

- The Android part of the plugin depends on
  `com.google.android.gms:play-services-wallet` (19.5.0) and enables the
  Google Pay API in its manifest. The iOS part links PassKit.
- `Payriff.isPaymentInProgress` covers wallet payments too: one payment at a
  time, card or wallet.
- `PayriffConfig.toString()` shows `applePay` (the merchant ID) and
  `googlePay` (`on`); `Payriff.configure` logs a warning for an invalid
  Apple Pay merchant ID.
- The Pay button's amount uses decimal rounding (the same text as the
  wallet sheets): an amount such as `1.005` shows `1.01`.

### Security

- Wallet tokens are never logged and never appear in error messages or
  `toString`; they are sent over the same pinned connection as cards, with
  a new idempotency key per token. The device checks also run when a wallet
  button appears, on tap and right before the token is sent.

## 1.0.0-rc.2 - 2026-10-27

Second release candidate of 1.0.0. The API can still change before 1.0.0.

### Added

- `PayriffConfig.region`: `PayriffRegion.az` (the default,
  `api.payriff.com`) or `PayriffRegion.sa` (Saudi Arabia, GCC Pay,
  `https://api.gccpay.sa`). There is no Saudi sandbox: region `sa` with
  `PayriffEnvironment.sandbox` also uses `https://api.gccpay.sa`, so sandbox
  payments go to production and charge real cards. `Payriff.configure` logs
  a warning for that combination (with `enableLogging`).
- `PayriffConfig.apiBaseUrl` (read-only): the Client API base URL of the
  configured region and environment.

### Changed

- The API host follows the region as well as the environment:
  `PayriffConfig.apiBaseUrl` replaces the host per `PayriffEnvironment`.
  `PayriffEnvironment.sandbox` is region `az`'s sandbox
  (`https://sb-api.payriff.com`).
- `PayriffConfig.toString()` and the `Configured: …` log line include the
  region.
- The 3-D Secure bank callback is recognised on the configured region's
  host only (`https://api.gccpay.sa/api/v3/gateway/…` in region `sa`).

### Security

- Certificate pinning covers `api.gccpay.sa`. GTS Root R1 (its current root,
  which it sends cross-signed by GlobalSign Root CA) was already an anchor;
  GTS Root R4 is added as a backup for Google's ECDSA chains. The other
  anchors are unchanged.
- Logs keep the paths of `api.gccpay.sa` URLs, shortened like those of
  `api.payriff.com`; other hosts still log as `scheme://host[:port]` only.

## 1.0.0-rc.1 - 2026-10-24

Release candidate of 1.0.0 for the security review. The API can still change
before 1.0.0.

- First release.
- Card-only SDK (CONTRACT revision 5): the merchant's server creates the
  order with its secret key and gives the app `orderId` and `clientSecret`;
  the app pays it with the publishable key. The SDK never creates orders and
  holds no secret key.
- `PayriffPaymentView`: the ready-made card payment screen, like the card
  part of Payriff's hosted payment page (pay.payriff.com). It reads the
  order, shows the card form, a Pay button with the amount ("Pay 1.00 AZN"),
  the accepted card badges, the secure line and a "Powered by Payriff"
  footer (its logo has a light wordmark in dark mode), pays with
  `confirmCardPayment` and passes each result to `onResult`. Works as a
  page, in a bottom sheet and in a dialog.
- `PayriffPaymentView` says "This order cannot be paid by card" in the
  view's language (Azerbaijani, English or Russian) when the order loaded but
  cannot be paid by card.
- `PayriffPaymentViewStyle`: background, padding, the Pay button's colour,
  text, height and corners, the secondary text colour, `showBadges`,
  `showSecureNote`, `showPoweredBy` and the form's `formStyle`.
  `payButtonLabel` replaces the word "Pay" (the amount and currency still
  follow it) and `secureNoteText` the text of the secure line.
- `PayriffCardForm` + `PayriffCardController`: card number, expiry, CVV and
  the holder name (shown by default, as on pay.payriff.com;
  `showHolder: false` hides it and sends `Unknown`), validated and formatted
  like Payriff.js (Visa and Mastercard, at most 16 digits, Luhn, expiry,
  3-digit CVV, upper-case holder), Visa and Mastercard marks,
  `autoAdvance`, light and dark mode, Azerbaijani, English and Russian copy,
  and `onChanged` events that never carry card values.
- `PayriffCardFormStyle`: the card form looks like Payriff's hosted payment
  page by default (the holder, then one "Card information" box, one error
  line per section); its layout (`grouped` or `stacked`), colours, text
  styles, sizes and labels can all be changed.
- `Payriff.confirmCardPayment`: validates the form, checks that the order
  can be paid by card, encrypts the card natively (AES-256-GCM, key wrapped
  with Payriff's pinned RSA key), sends it with `X-Client-App-Id`, runs the
  API's next step (3-D Secure challenge or redirect in the SDK's sheet, the
  3-D Secure Method in hidden WebViews, `/three-ds` polling) and polls the
  status every 2.5 s for up to 120 s. Retries a `429` three times and a
  request without an answer once, with the same idempotency key.
- `Payriff.retrieveOrder` returns a `PayriffClientOrder`.
- 3-D Secure sheet: an iOS 26-style sheet on iOS, a Material bottom sheet on
  Android; header with drag handle, title and close button (glass buttons on
  iOS), a native loader, bank pages inset from the edges, the close
  confirmation and one status check when the customer closes it, the
  page-load error with "Try again", JavaScript dialogs on iOS (titled with the
  page's host, at most three), and hardened hand-offs to bank apps.
- The close confirmation of the 3-D Secure sheet asks "Close this window?"
  and says that the payment's status will be checked. Closing checks the
  status once; the SDK never cancels the order.
- 3-D Secure website data: when a payment that opened 3-D Secure pages ends,
  the SDK removes the website data of the sites they loaded, without
  delaying the result. iOS removes the default data store's records of those
  sites; Android deletes their web storage and cookies (for every path of the
  pages, and `Secure`, `__Secure-` and `__Host-` cookies too) and clears the
  WebView cache.
- Screen protection for the form and the sheet (Android `FLAG_SECURE`, an
  iOS cover while the app is inactive); copy and cut off for the number and
  the CVV, the CVV masked and never autofilled, values cleared after a final
  result and on dispose.
- `PayriffConfig`: `publishableKey`, `environment`, `language`,
  `enableLogging` and `allowCompromisedDevices`. `Payriff.configure` never
  throws.
- Typed `PayriffResult` (`PayriffResultSuccess`, `PayriffResultDeclined`,
  `PayriffResultCancelled`, `PayriffResultPending`, `PayriffResultFailed`)
  with `payment`, `error` and `isSuccess` helpers and the shared JSON shape;
  `PayriffError` with the card error codes and `isFatal`.
- `Payriff.logStream` with `PayriffLogEntry.formatted`; card data, keys and
  secrets never reach the logs. Debug builds also log every API request and
  response as redacted, pretty-printed JSON. Only debug builds print to the
  console.
- One URL redaction for every log line, the HTTP details and URLs inside
  logged bodies: `http(s)` URLs lose their user info, query string and
  fragment; only Payriff's API hosts keep the path, with segments of 16 or
  more characters shortened (`/api/v3/client/orders/7c9e…0ae7/pay`); any
  other host, such as a bank's 3-D Secure page, is logged as
  `scheme://host[:port]`; any other scheme as `<scheme>:…`.
- HTTP: the SDK's own client ignores app-wide `http.runWithClient` clients,
  never follows redirects and refuses response bodies over 1 MB.
- Certificate pinning: every Client API call (order, pay, 3-D Secure steps,
  status) to `api.payriff.com` and `sb-api.payriff.com` trusts only
  Payriff's certificate authorities (the current Sectigo roots and backup
  roots of other major CAs), never the device's trust store. A failed check
  is `networkError`, not retryable, "Payriff's server certificate could not
  be verified."; nothing is sent. No setting turns it off; release builds
  also ignore app-wide `HttpOverrides`. The 3-D Secure pages are not pinned.
- Device integrity: card payments are refused on rooted or jailbroken
  devices and when a hooking framework (Frida, Xposed or LSPosed, Substrate
  and the like) or a debugger on a release build is found, checked when the
  payment view appears, when `confirmCardPayment` starts and right before the
  card is encrypted. `confirmCardPayment` returns `failed(DEVICE_COMPROMISED)`
  (new error code `deviceCompromised`) and sends nothing; the payment view
  says "Card payments aren't available on this device for security reasons",
  does not read the order and reports the failure to `onResult` once.
  `PayriffConfig.allowCompromisedDevices` (default `false`) only logs a
  warning instead, for development on test devices. It works only in debug
  builds (`kDebugMode`): profile and release builds ignore it with a warning
  and refuse compromised devices, so a flag left on never reaches
  production. `Payriff.retrieveOrder` is never blocked;
  `Payriff.isDeviceCompromised()` lets the app decide early. A check that
  cannot complete (for example without the plugin's native part) counts as a
  compromised device (`check failed`). On iOS, a debugger and
  `DYLD_INSERT_LIBRARIES` count only in App Store and TestFlight builds, so
  runs from Xcode are not blocked. The Android plugin declares the root
  manager apps it looks for in `<queries>`.
