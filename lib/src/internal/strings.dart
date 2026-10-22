import '../config.dart';

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
/// (`az`, `en`, `ru`). It must stay identical to `vectors/strings.json`; a
/// unit test enforces that.
const Map<String, Map<String, String>>
payriffStringTable = <String, Map<String, String>>{
  'title': <String, String>{'az': 'Ödəniş', 'en': 'Payment', 'ru': 'Оплата'},
  'secure_payment': <String, String>{
    'az': 'Təhlükəsiz ödəniş',
    'en': 'Secure payment',
    'ru': 'Безопасная оплата',
  },
  'creating_order': <String, String>{
    'az': 'Ödəniş hazırlanır…',
    'en': 'Preparing payment…',
    'ru': 'Подготовка платежа…',
  },
  'verifying': <String, String>{
    'az': 'Ödəniş yoxlanılır…',
    'en': 'Checking payment…',
    'ru': 'Проверяем платёж…',
  },
  'close': <String, String>{'az': 'Bağla', 'en': 'Close', 'ru': 'Закрыть'},
  'retry': <String, String>{
    'az': 'Yenidən cəhd et',
    'en': 'Try again',
    'ru': 'Повторить',
  },
  'cancel_confirm_title': <String, String>{
    'az': 'Pəncərəni bağlayaq?',
    'en': 'Close this window?',
    'ru': 'Закрыть окно?',
  },
  'cancel_confirm_message': <String, String>{
    'az':
        'Ödəniş hələ tamamlanmayıb. Pəncərəni bağlasanız, ödənişin statusunu yoxlayacağıq.',
    'en':
        'The payment isn\'t finished yet. If you close this window, we\'ll check its status.',
    'ru': 'Оплата ещё не завершена. Если закрыть окно, мы проверим её статус.',
  },
  'cancel_confirm_yes': <String, String>{
    'az': 'Bağla',
    'en': 'Close',
    'ru': 'Закрыть',
  },
  'cancel_confirm_no': <String, String>{
    'az': 'Ödənişə davam et',
    'en': 'Continue payment',
    'ru': 'Продолжить оплату',
  },
  'result_success_title': <String, String>{
    'az': 'Ödəniş uğurla tamamlandı',
    'en': 'Payment successful',
    'ru': 'Оплата прошла успешно',
  },
  'result_success_message': <String, String>{
    'az': 'Təşəkkür edirik!',
    'en': 'Thank you!',
    'ru': 'Спасибо!',
  },
  'result_declined_title': <String, String>{
    'az': 'Ödəniş rədd edildi',
    'en': 'Payment declined',
    'ru': 'Платёж отклонён',
  },
  'result_declined_message': <String, String>{
    'az': 'Kartınızdan vəsait çıxılmadı. Başqa kartla yenidən cəhd edin.',
    'en': 'Your card was not charged. Please try again with another card.',
    'ru': 'Средства не списаны. Попробуйте другую карту.',
  },
  'result_cancelled_title': <String, String>{
    'az': 'Ödəniş ləğv edildi',
    'en': 'Payment cancelled',
    'ru': 'Оплата отменена',
  },
  'result_cancelled_message': <String, String>{
    'az': 'Ödəniş tamamlanmadı.',
    'en': 'The payment was not completed.',
    'ru': 'Оплата не была завершена.',
  },
  'result_pending_title': <String, String>{
    'az': 'Ödəniş emal olunur',
    'en': 'Payment is processing',
    'ru': 'Платёж обрабатывается',
  },
  'result_pending_message': <String, String>{
    'az':
        'Ödənişin statusunu hələ təsdiqləyə bilmədik. Bir az sonra yenidən yoxlayın.',
    'en':
        'We couldn\'t confirm the payment status yet. Please check again shortly.',
    'ru':
        'Мы пока не смогли подтвердить статус платежа. Проверьте немного позже.',
  },
  'error_title': <String, String>{
    'az': 'Ödənişi başlatmaq mümkün olmadı',
    'en': 'Couldn\'t start the payment',
    'ru': 'Не удалось начать оплату',
  },
  'page_load_error': <String, String>{
    'az': 'Səhifə yüklənmədi. İnternet bağlantınızı yoxlayın.',
    'en': 'The page couldn\'t be loaded. Check your internet connection.',
    'ru': 'Не удалось загрузить страницу. Проверьте подключение к интернету.',
  },
  'dialog_ok': <String, String>{'az': 'OK', 'en': 'OK', 'ru': 'ОК'},
  'dialog_cancel': <String, String>{
    'az': 'İmtina',
    'en': 'Cancel',
    'ru': 'Отмена',
  },
};

/// Localized UI strings for one [PayriffLanguage].
final class PayriffStrings {
  /// Creates the string set for [language].
  const PayriffStrings(this.language);

  /// The language these strings are in.
  final PayriffLanguage language;

  /// Returns the text for [key].
  String operator [](PayriffStringKey key) =>
      payriffStringTable[key.id]![language.value.toLowerCase()]!;
}
