/// Payriff card payments for Flutter, with Apple Pay and Google Pay.
///
/// Your server creates the order with its secret key and gives the app the
/// order's `orderId` and `clientSecret`. The app shows the SDK's
/// [PayriffPaymentView], a ready-made payment screen that pays the order with
/// the publishable key: the card is encrypted on the device, 3-D Secure runs
/// in the SDK's sheet, and `onResult` gets a verified, typed [PayriffResult].
/// With [PayriffConfig.applePay] or [PayriffConfig.googlePay] it also shows
/// the wallet's button above the card form. For a screen of your own, use
/// the [PayriffCardForm] and [Payriff.confirmCardPayment] it is built on, and
/// [PayriffApplePayButton] or [PayriffGooglePayButton]. The secret key never
/// ships in the app.
///
/// The result in the app is for the user interface. Fulfil orders on your
/// server, after it confirms them with Payriff.
library;

export 'src/card/card_form.dart' show PayriffCardController, PayriffCardForm;
export 'src/card/card_form_style.dart'
    show PayriffCardFormLayout, PayriffCardFormStyle;
export 'src/card/card_types.dart'
    show
        PayriffCardBrand,
        PayriffCardField,
        PayriffCardFieldError,
        PayriffCardFieldErrorCode,
        PayriffCardFormChange;
export 'src/card/client_order.dart'
    show
        PayriffClientOrder,
        PayriffClientOrderApplePay,
        PayriffClientOrderGooglePay;
export 'src/card/payment_view.dart' show PayriffPaymentView;
export 'src/card/payment_view_style.dart' show PayriffPaymentViewStyle;
export 'src/config.dart'
    show
        PayriffApplePayConfig,
        PayriffConfig,
        PayriffEnvironment,
        PayriffGooglePayConfig,
        PayriffLanguage,
        PayriffRegion;
export 'src/error.dart' show PayriffError, PayriffErrorCode, PayriffException;
export 'src/log.dart' show PayriffLogEntry, PayriffLogLevel;
export 'src/payriff.dart' show Payriff;
export 'src/result.dart'
    show
        PayriffCancelReason,
        PayriffPayment,
        PayriffPendingReason,
        PayriffResult,
        PayriffResultCancelled,
        PayriffResultDeclined,
        PayriffResultFailed,
        PayriffResultPending,
        PayriffResultSuccess;
export 'src/status.dart' show PayriffPaymentStatus;
export 'src/wallet/wallet_button_style.dart'
    show
        PayriffApplePayButtonStyle,
        PayriffApplePayButtonTheme,
        PayriffApplePayButtonType,
        PayriffGooglePayButtonStyle,
        PayriffGooglePayButtonTheme,
        PayriffGooglePayButtonType;
export 'src/wallet/wallet_buttons.dart'
    show PayriffApplePayButton, PayriffGooglePayButton;
