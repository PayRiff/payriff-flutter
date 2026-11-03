import '../../card/card_types.dart';
import '../../config.dart';
import '../../error.dart';
import '../../strings.dart';
import '../strings.dart';

/// The card form and payment view copy from `vectors/card_strings.json`:
/// language code (`az`, `en`, `ru`, `ar`), then section (`number`, `expiry`, `cvv`, `holder`,
/// `placeholder`, `label`, `group`, `view`), then key. The error messages
/// come from the web SDK (`fields/i18n.js`); the labels, placeholders and
/// the payment view copy follow Payriff's hosted payment page. A unit test
/// keeps it identical to the vector.
const Map<String, Map<String, Map<String, String>>> payriffCardStringTable =
    <String, Map<String, Map<String, String>>>{
      'az': <String, Map<String, String>>{
        'number': <String, String>{
          'required': 'Kart nömrəsini daxil edin',
          'incomplete': 'Kart nömrəsi tam deyil',
          'invalid': 'Kart nömrəsi yanlışdır',
          'unsupported': 'Bu kart növü dəstəklənmir',
        },
        'expiry': <String, String>{
          'required': 'Bitmə tarixini daxil edin',
          'incomplete': 'Bitmə tarixi tam deyil',
          'invalid': 'Bitmə tarixi yanlışdır',
          'expired': 'Kartın müddəti bitib',
        },
        'cvv': <String, String>{
          'required': 'CVV daxil edin',
          'incomplete': 'CVV tam deyil',
          'invalid': 'CVV yanlışdır',
        },
        'holder': <String, String>{
          'required': 'Kart sahibinin adını daxil edin',
          'invalid': 'Kart sahibinin adı yanlışdır',
        },
        'placeholder': <String, String>{
          'number': '1234 1234 1234 1234',
          'expiry': 'MM / YY',
          'cvv': 'CVC',
          'holder': 'Kart sahibinin adı',
        },
        'label': <String, String>{
          'number': 'Kart nömrəsi',
          'expiry': 'Bitmə tarixi',
          'cvv': 'CVV kodu',
          'holder': 'Kart sahibinin adı',
        },
        'group': <String, String>{'cardInformation': 'Kart məlumatları'},
        'view': <String, String>{
          'pay': 'Ödə',
          'secure': 'PCI DSS ilə təhlükəsiz ödəniş',
          'poweredBy': 'Payriff tərəfindən hazırlanıb',
          'notPayable': 'Bu sifarişi kartla ödəmək mümkün deyil',
          'deviceNotSupported':
              'Təhlükəsizlik səbəbilə bu cihazda kartla ödəniş mümkün deyil',
          'orPayByCard': 'Və ya kartla ödəyin',
        },
      },
      'en': <String, Map<String, String>>{
        'number': <String, String>{
          'required': 'Enter your card number',
          'incomplete': 'Card number is incomplete',
          'invalid': 'Card number is invalid',
          'unsupported': 'This card type is not supported',
        },
        'expiry': <String, String>{
          'required': 'Enter the expiry date',
          'incomplete': 'Expiry date is incomplete',
          'invalid': 'Expiry date is invalid',
          'expired': 'This card has expired',
        },
        'cvv': <String, String>{
          'required': 'Enter the CVV',
          'incomplete': 'CVV is incomplete',
          'invalid': 'CVV is invalid',
        },
        'holder': <String, String>{
          'required': 'Enter the cardholder name',
          'invalid': 'Cardholder name is invalid',
        },
        'placeholder': <String, String>{
          'number': '1234 1234 1234 1234',
          'expiry': 'MM / YY',
          'cvv': 'CVC',
          'holder': 'Card holder',
        },
        'label': <String, String>{
          'number': 'Card number',
          'expiry': 'Expiry date',
          'cvv': 'Security code',
          'holder': 'Card holder',
        },
        'group': <String, String>{'cardInformation': 'Card information'},
        'view': <String, String>{
          'pay': 'Pay',
          'secure': 'Proceed securely by PCI DSS',
          'poweredBy': 'Powered by Payriff',
          'notPayable': 'This order cannot be paid by card',
          'deviceNotSupported':
              "Card payments aren't available on this device for security "
              'reasons',
          'orPayByCard': 'Or pay by card',
        },
      },
      'ru': <String, Map<String, String>>{
        'number': <String, String>{
          'required': 'Введите номер карты',
          'incomplete': 'Номер карты введён не полностью',
          'invalid': 'Неверный номер карты',
          'unsupported': 'Этот тип карты не поддерживается',
        },
        'expiry': <String, String>{
          'required': 'Введите срок действия',
          'incomplete': 'Срок действия введён не полностью',
          'invalid': 'Неверный срок действия',
          'expired': 'Срок действия карты истёк',
        },
        'cvv': <String, String>{
          'required': 'Введите CVV',
          'incomplete': 'CVV введён не полностью',
          'invalid': 'Неверный CVV',
        },
        'holder': <String, String>{
          'required': 'Введите имя владельца карты',
          'invalid': 'Неверное имя владельца карты',
        },
        'placeholder': <String, String>{
          'number': '1234 1234 1234 1234',
          'expiry': 'MM / YY',
          'cvv': 'CVC',
          'holder': 'Владелец карты',
        },
        'label': <String, String>{
          'number': 'Номер карты',
          'expiry': 'Срок действия',
          'cvv': 'Код безопасности',
          'holder': 'Владелец карты',
        },
        'group': <String, String>{'cardInformation': 'Информация о карте'},
        'view': <String, String>{
          'pay': 'Оплатить',
          'secure': 'Безопасная оплата по PCI DSS',
          'poweredBy': 'При поддержке Payriff',
          'notPayable': 'Этот заказ нельзя оплатить картой',
          'deviceNotSupported':
              'По соображениям безопасности оплата картой на этом '
              'устройстве недоступна',
          'orPayByCard': 'Или оплатите картой',
        },
      },
      'ar': <String, Map<String, String>>{
        'number': <String, String>{
          'required': 'أدخل رقم البطاقة',
          'incomplete': 'رقم البطاقة غير مكتمل',
          'invalid': 'رقم البطاقة غير صحيح',
          'unsupported': 'نوع البطاقة هذا غير مدعوم',
        },
        'expiry': <String, String>{
          'required': 'أدخل تاريخ الانتهاء',
          'incomplete': 'تاريخ الانتهاء غير مكتمل',
          'invalid': 'تاريخ الانتهاء غير صحيح',
          'expired': 'انتهت صلاحية هذه البطاقة',
        },
        'cvv': <String, String>{
          'required': 'أدخل رمز التحقق (CVV)',
          'incomplete': 'رمز التحقق غير مكتمل',
          'invalid': 'رمز التحقق غير صحيح',
        },
        'holder': <String, String>{
          'required': 'أدخل اسم حامل البطاقة',
          'invalid': 'اسم حامل البطاقة غير صحيح',
        },
        'placeholder': <String, String>{
          'number': '1234 1234 1234 1234',
          'expiry': 'MM / YY',
          'cvv': 'CVC',
          'holder': 'اسم حامل البطاقة',
        },
        'label': <String, String>{
          'number': 'رقم البطاقة',
          'expiry': 'تاريخ الانتهاء',
          'cvv': 'رمز التحقق',
          'holder': 'اسم حامل البطاقة',
        },
        'group': <String, String>{'cardInformation': 'معلومات البطاقة'},
        'view': <String, String>{
          'pay': 'ادفع',
          'secure': 'دفع آمن وفق PCI DSS',
          'poweredBy': 'مدعوم من Payriff',
          'notPayable': 'لا يمكن دفع هذا الطلب بالبطاقة',
          'deviceNotSupported':
              'الدفع بالبطاقة غير متاح على هذا الجهاز لأسباب أمنية',
          'orPayByCard': 'أو ادفع بالبطاقة',
        },
      },
    };

/// The word in `view.poweredBy` that the payment view replaces with the
/// Payriff logo.
const String payriffWordmark = 'Payriff';

/// CONTRACT §18.6 (`strings_override.json` → `poweredBy`): [text] split at
/// the first "Payriff", where the logo goes. A text without "Payriff" is
/// followed by a space and the logo.
({String before, String after}) poweredByPartsOf(String text) {
  final int at = text.indexOf(payriffWordmark);
  if (at < 0) return (before: '$text ', after: '');
  return (
    before: text.substring(0, at),
    after: text.substring(at + payriffWordmark.length),
  );
}

/// CONTRACT §18.6 (`strings_override.json` → `fields`): the field of
/// [strings] that replaces the `card_strings.json` text `<section>.<key>`,
/// or `null` when none does.
String? cardStringOverride(
  PayriffStrings strings,
  String section,
  String key,
) => switch ((section, key)) {
  ('label', 'holder') => strings.holderLabel,
  ('group', 'cardInformation') => strings.cardInformationLabel,
  ('label', 'number') => strings.numberAccessibilityLabel,
  ('label', 'expiry') => strings.expiryAccessibilityLabel,
  ('label', 'cvv') => strings.cvcAccessibilityLabel,
  ('placeholder', 'holder') => strings.holderPlaceholder,
  ('placeholder', 'number') => strings.numberPlaceholder,
  ('placeholder', 'expiry') => strings.expiryPlaceholder,
  ('placeholder', 'cvv') => strings.cvcPlaceholder,
  ('number', 'required') => strings.numberRequired,
  ('number', 'incomplete') => strings.numberIncomplete,
  ('number', 'invalid') => strings.numberInvalid,
  ('number', 'unsupported') => strings.numberUnsupported,
  ('expiry', 'required') => strings.expiryRequired,
  ('expiry', 'incomplete') => strings.expiryIncomplete,
  ('expiry', 'invalid') => strings.expiryInvalid,
  ('expiry', 'expired') => strings.expiryExpired,
  ('cvv', 'required') => strings.cvcRequired,
  ('cvv', 'incomplete') => strings.cvcIncomplete,
  ('cvv', 'invalid') => strings.cvcInvalid,
  ('holder', 'required') => strings.holderRequired,
  ('holder', 'invalid') => strings.holderInvalid,
  ('view', 'pay') => strings.pay,
  ('view', 'secure') => strings.secureNote,
  ('view', 'poweredBy') => strings.poweredBy,
  ('view', 'orPayByCard') => strings.orPayByCard,
  ('view', 'notPayable') => strings.notPayable,
  ('view', 'deviceNotSupported') => strings.deviceNotSupported,
  _ => null,
};

/// The card form and payment view copy in one language, with the app's own
/// texts (CONTRACT §18.6) over it.
final class PayriffCardStrings {
  /// Creates the copy for [language]. [overrides] are the app's texts, the
  /// first that sets a field wins: `PayriffPaymentView.strings`, then
  /// `PayriffConfig.strings`.
  const PayriffCardStrings(
    this.language, {
    this.overrides = const <PayriffStrings>[],
  });

  /// The language.
  final PayriffLanguage language;

  /// The app's texts, in order of precedence.
  final List<PayriffStrings> overrides;

  Map<String, Map<String, String>> get _table =>
      payriffCardStringTable[language.value.toLowerCase()]!;

  /// `<section>.<key>`: the first override that is not blank; for an
  /// error line with an [errorCode], then the first `errorMessages` entry
  /// for it that is not blank (CONTRACT §18.6); else the built-in text in
  /// [language].
  String _text(String section, String key, {PayriffErrorCode? errorCode}) {
    for (final PayriffStrings strings in overrides) {
      final String? text = usableText(
        cardStringOverride(strings, section, key),
      );
      if (text != null) return text;
    }
    if (errorCode != null) {
      final String? message = _errorMessage(errorCode);
      if (message != null) return message;
    }
    return _table[section]![key]!;
  }

  /// The first `errorMessages` entry for [code] that is not blank.
  String? _errorMessage(PayriffErrorCode code) {
    for (final PayriffStrings strings in overrides) {
      final String? text = usableText(strings.errorMessages[code]);
      if (text != null) return text;
    }
    return null;
  }

  /// The field's label.
  String label(PayriffCardField field) => _text('label', field.value);

  /// The field's placeholder.
  String placeholder(PayriffCardField field) =>
      _text('placeholder', field.value);

  /// The label above the card box of the grouped layout: "Card
  /// information".
  String get cardInformation => _text('group', 'cardInformation');

  /// The payment view's button title, followed by the amount: "Pay".
  String get pay => _text('view', 'pay');

  /// The payment view's line under the badges: "Proceed securely by PCI
  /// DSS".
  String get secure => _text('view', 'secure');

  /// The payment view's footer, for example "Powered by Payriff". The view
  /// shows the logo in place of "Payriff" ([poweredByParts]).
  String get poweredBy => _text('view', 'poweredBy');

  /// The payment view's error line for an order that loaded but cannot be
  /// paid by card: "This order cannot be paid by card". Without a
  /// `notPayable` text, `errorMessages[ORDER_NOT_PAYABLE]` is used.
  String get notPayable =>
      _text('view', 'notPayable', errorCode: PayriffErrorCode.orderNotPayable);

  /// The payment view's error line on a device where card payments are
  /// refused (CONTRACT §16.16): "Card payments aren't available on this
  /// device for security reasons". Without a `deviceNotSupported` text,
  /// `errorMessages[DEVICE_COMPROMISED]` is used.
  String get deviceNotSupported => _text(
    'view',
    'deviceNotSupported',
    errorCode: PayriffErrorCode.deviceCompromised,
  );

  /// The payment view's divider between the Apple Pay or Google Pay button
  /// and the card form (CONTRACT §17.9): "Or pay by card".
  String get orPayByCard => _text('view', 'orPayByCard');

  /// [poweredBy] split for the logo (CONTRACT §16.14, §18.6): the text
  /// before and after it.
  ({String before, String after}) get poweredByParts =>
      poweredByPartsOf(poweredBy);

  /// The message for [code] on [field]. An error without its own message
  /// uses the field's `invalid` message.
  String error(PayriffCardField field, PayriffCardFieldErrorCode code) {
    final Map<String, String> messages = _table[field.value]!;
    return _text(
      field.value,
      messages.containsKey(code.value) ? code.value : 'invalid',
    );
  }

  /// The text of an on-screen error line for [error] (CONTRACT §18.6): the
  /// first override's `errorMessages` entry for its code that is not blank,
  /// else [PayriffError.message].
  String errorLine(PayriffError error) =>
      _errorMessage(error.code) ?? error.message;
}
