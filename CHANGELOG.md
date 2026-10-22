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
  footer, pays with `confirmCardPayment` and passes each result to
  `onResult`. Works as a page, in a bottom sheet and in a dialog.
- `PayriffPaymentView` says "This order cannot be paid by card" in the
  view's language (Azerbaijani, English or Russian) when the order loaded but
  cannot be paid by card.
- `PayriffPaymentViewStyle`: background, padding, the Pay button's colour,
  text, height and corners, the secondary text colour, `showBadges`,
  `showSecureNote`, `showPoweredBy` and the form's `formStyle`.
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
  sites; Android deletes their web storage and cookies and clears the
  WebView cache.
- Screen protection for the form and the sheet (Android `FLAG_SECURE`, an
  iOS cover while the app is inactive); copy and cut off for the number and
  the CVV, the CVV masked and never autofilled, values cleared after a final
  result and on dispose.
- `PayriffConfig`: `publishableKey`, `environment`, `language` and
  `enableLogging`. `Payriff.configure` never throws.
- Typed `PayriffResult` (`PayriffResultSuccess`, `PayriffResultDeclined`,
  `PayriffResultCancelled`, `PayriffResultPending`, `PayriffResultFailed`)
  with `payment`, `error` and `isSuccess` helpers and the shared JSON shape;
  `PayriffError` with the card error codes and `isFatal`.
- `Payriff.logStream` with `PayriffLogEntry.formatted`; card data, keys and
  secrets never reach the logs. Debug builds also log every API request and
  response as redacted, pretty-printed JSON. Only debug builds print to the
  console.
- HTTP: the SDK's own client ignores app-wide `http.runWithClient` clients,
  never follows redirects and refuses response bodies over 1 MB.
