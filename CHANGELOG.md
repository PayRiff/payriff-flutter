# Changelog

## [1.0.0] - Unreleased

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
