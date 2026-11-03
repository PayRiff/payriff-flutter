import '../config.dart';
import '../error.dart';
import '../strings.dart';

/// Keys of the SDK's UI copy (CONTRACT §10, `vectors/strings.json`).
enum PayriffStringKey {
  /// `title`
  title('title'),

  /// `secure_payment`
  securePayment('secure_payment'),

  /// `creating_order`
  creatingOrder('creating_order'),

  /// `verifying`
  verifying('verifying'),

  /// `close`
  close('close'),

  /// `retry`
  retry('retry'),

  /// `cancel_confirm_title`
  cancelConfirmTitle('cancel_confirm_title'),

  /// `cancel_confirm_message`
  cancelConfirmMessage('cancel_confirm_message'),

  /// `cancel_confirm_yes`
  cancelConfirmYes('cancel_confirm_yes'),

  /// `cancel_confirm_no`
  cancelConfirmNo('cancel_confirm_no'),

  /// `result_success_title`
  resultSuccessTitle('result_success_title'),

  /// `result_success_message`
  resultSuccessMessage('result_success_message'),

  /// `result_declined_title`
  resultDeclinedTitle('result_declined_title'),

  /// `result_declined_message`
  resultDeclinedMessage('result_declined_message'),

  /// `result_cancelled_title`
  resultCancelledTitle('result_cancelled_title'),

  /// `result_cancelled_message`
  resultCancelledMessage('result_cancelled_message'),

  /// `result_pending_title`
  resultPendingTitle('result_pending_title'),

  /// `result_pending_message`
  resultPendingMessage('result_pending_message'),

  /// `error_title`
  errorTitle('error_title'),

  /// `page_load_error`
  pageLoadError('page_load_error'),

  /// `dialog_ok`: the OK button of JavaScript `alert`, `confirm` and
  /// `prompt` dialogs the SDK renders itself (iOS).
  dialogOk('dialog_ok'),

  /// `dialog_cancel`: the Cancel button of JavaScript `confirm` and `prompt`
  /// dialogs the SDK renders itself (iOS).
  dialogCancel('dialog_cancel');

  const PayriffStringKey(this.id);

  /// The key as written in `strings.json`.
  final String id;
}

/// The SDK's UI copy, keyed by `strings.json` key and then by language code
/// (`az`, `en`, `ru`, `ar`). It must stay identical to `vectors/strings.json`; a
/// unit test enforces that.
const Map<String, Map<String, String>>
payriffStringTable = <String, Map<String, String>>{
  'title': <String, String>{
    'az': 'Ödəniş',
    'en': 'Payment',
    'ru': 'Оплата',
    'ar': 'الدفع',
  },
  'secure_payment': <String, String>{
    'az': 'Təhlükəsiz ödəniş',
    'en': 'Secure payment',
    'ru': 'Безопасная оплата',
    'ar': 'دفع آمن',
  },
  'creating_order': <String, String>{
    'az': 'Ödəniş hazırlanır…',
    'en': 'Preparing payment…',
    'ru': 'Подготовка платежа…',
    'ar': 'جارٍ تجهيز الدفع…',
  },
  'verifying': <String, String>{
    'az': 'Ödəniş yoxlanılır…',
    'en': 'Checking payment…',
    'ru': 'Проверяем платёж…',
    'ar': 'جارٍ التحقق من الدفع…',
  },
  'close': <String, String>{
    'az': 'Bağla',
    'en': 'Close',
    'ru': 'Закрыть',
    'ar': 'إغلاق',
  },
  'retry': <String, String>{
    'az': 'Yenidən cəhd et',
    'en': 'Try again',
    'ru': 'Повторить',
    'ar': 'إعادة المحاولة',
  },
  'cancel_confirm_title': <String, String>{
    'az': 'Pəncərəni bağlayaq?',
    'en': 'Close this window?',
    'ru': 'Закрыть окно?',
    'ar': 'إغلاق هذه النافذة؟',
  },
  'cancel_confirm_message': <String, String>{
    'az':
        'Ödəniş hələ tamamlanmayıb. Pəncərəni bağlasanız, ödənişin statusunu yoxlayacağıq.',
    'en':
        'The payment isn\'t finished yet. If you close this window, we\'ll check its status.',
    'ru': 'Оплата ещё не завершена. Если закрыть окно, мы проверим её статус.',
    'ar': 'لم يكتمل الدفع بعد. إذا أغلقت هذه النافذة، فسنتحقق من حالته.',
  },
  'cancel_confirm_yes': <String, String>{
    'az': 'Bağla',
    'en': 'Close',
    'ru': 'Закрыть',
    'ar': 'إغلاق',
  },
  'cancel_confirm_no': <String, String>{
    'az': 'Ödənişə davam et',
    'en': 'Continue payment',
    'ru': 'Продолжить оплату',
    'ar': 'متابعة الدفع',
  },
  'result_success_title': <String, String>{
    'az': 'Ödəniş uğurla tamamlandı',
    'en': 'Payment successful',
    'ru': 'Оплата прошла успешно',
    'ar': 'تم الدفع بنجاح',
  },
  'result_success_message': <String, String>{
    'az': 'Təşəkkür edirik!',
    'en': 'Thank you!',
    'ru': 'Спасибо!',
    'ar': 'شكرًا لك!',
  },
  'result_declined_title': <String, String>{
    'az': 'Ödəniş rədd edildi',
    'en': 'Payment declined',
    'ru': 'Платёж отклонён',
    'ar': 'تم رفض الدفع',
  },
  'result_declined_message': <String, String>{
    'az': 'Kartınızdan vəsait çıxılmadı. Başqa kartla yenidən cəhd edin.',
    'en': 'Your card was not charged. Please try again with another card.',
    'ru': 'Средства не списаны. Попробуйте другую карту.',
    'ar': 'لم يُخصم أي مبلغ من بطاقتك. يرجى المحاولة مرة أخرى ببطاقة أخرى.',
  },
  'result_cancelled_title': <String, String>{
    'az': 'Ödəniş ləğv edildi',
    'en': 'Payment cancelled',
    'ru': 'Оплата отменена',
    'ar': 'تم إلغاء الدفع',
  },
  'result_cancelled_message': <String, String>{
    'az': 'Ödəniş tamamlanmadı.',
    'en': 'The payment was not completed.',
    'ru': 'Оплата не была завершена.',
    'ar': 'لم يكتمل الدفع.',
  },
  'result_pending_title': <String, String>{
    'az': 'Ödəniş emal olunur',
    'en': 'Payment is processing',
    'ru': 'Платёж обрабатывается',
    'ar': 'جارٍ معالجة الدفع',
  },
  'result_pending_message': <String, String>{
    'az':
        'Ödənişin statusunu hələ təsdiqləyə bilmədik. Bir az sonra yenidən yoxlayın.',
    'en':
        'We couldn\'t confirm the payment status yet. Please check again shortly.',
    'ru':
        'Мы пока не смогли подтвердить статус платежа. Проверьте немного позже.',
    'ar': 'لم نتمكن من تأكيد حالة الدفع بعد. يرجى التحقق مرة أخرى بعد قليل.',
  },
  'error_title': <String, String>{
    'az': 'Ödənişi başlatmaq mümkün olmadı',
    'en': 'Couldn\'t start the payment',
    'ru': 'Не удалось начать оплату',
    'ar': 'تعذّر بدء الدفع',
  },
  'page_load_error': <String, String>{
    'az': 'Səhifə yüklənmədi. İnternet bağlantınızı yoxlayın.',
    'en': 'The page couldn\'t be loaded. Check your internet connection.',
    'ru': 'Не удалось загрузить страницу. Проверьте подключение к интернету.',
    'ar': 'تعذّر تحميل الصفحة. تحقّق من اتصالك بالإنترنت.',
  },
  'dialog_ok': <String, String>{
    'az': 'OK',
    'en': 'OK',
    'ru': 'ОК',
    'ar': 'حسنًا',
  },
  'dialog_cancel': <String, String>{
    'az': 'İmtina',
    'en': 'Cancel',
    'ru': 'Отмена',
    'ar': 'إلغاء',
  },
};

/// [text] when it is not blank after trimming, else `null` (CONTRACT §18.6:
/// a blank text counts as not set). The text itself is kept as given.
String? usableText(String? text) =>
    text == null || text.trim().isEmpty ? null : text;

/// CONTRACT §18.6 (`strings_override.json` → `fields`): the field of
/// [strings] that replaces the 3-D Secure sheet's text [key], or `null` when
/// none does.
String? sheetStringOverride(PayriffStrings strings, PayriffStringKey key) =>
    switch (key) {
      PayriffStringKey.title => strings.sheetTitle,
      PayriffStringKey.verifying => strings.verifying,
      PayriffStringKey.close => strings.close,
      PayriffStringKey.retry => strings.retry,
      PayriffStringKey.cancelConfirmTitle => strings.closeConfirmTitle,
      PayriffStringKey.cancelConfirmMessage => strings.closeConfirmMessage,
      PayriffStringKey.cancelConfirmYes => strings.closeConfirmClose,
      PayriffStringKey.cancelConfirmNo => strings.closeConfirmContinue,
      PayriffStringKey.pageLoadError => strings.pageLoadError,
      PayriffStringKey.dialogOk => strings.dialogOk,
      PayriffStringKey.dialogCancel => strings.dialogCancel,
      _ => null,
    };

/// The 3-D Secure sheet's UI strings in one [PayriffLanguage], with the
/// app's own texts (CONTRACT §18.6) over them.
final class PayriffSheetStrings {
  /// Creates the string set for [language]. [overrides] are the app's
  /// texts, the first that sets a field wins: `PayriffPaymentView.strings`,
  /// then `PayriffConfig.strings`.
  const PayriffSheetStrings(
    this.language, {
    this.overrides = const <PayriffStrings>[],
  });

  /// The language these strings are in.
  final PayriffLanguage language;

  /// The app's texts, in order of precedence.
  final List<PayriffStrings> overrides;

  /// Returns the text for [key]: the first override that is not blank; for
  /// the page-load error, then the first `errorMessages[NETWORK_ERROR]`
  /// that is not blank (CONTRACT §18.6); else the built-in text in
  /// [language].
  String operator [](PayriffStringKey key) {
    for (final PayriffStrings strings in overrides) {
      final String? text = usableText(sheetStringOverride(strings, key));
      if (text != null) return text;
    }
    if (key == PayriffStringKey.pageLoadError) {
      for (final PayriffStrings strings in overrides) {
        final String? text = usableText(
          strings.errorMessages[PayriffErrorCode.networkError],
        );
        if (text != null) return text;
      }
    }
    return payriffStringTable[key.id]![language.value.toLowerCase()]!;
  }
}
