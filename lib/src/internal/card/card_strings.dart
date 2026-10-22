import '../../card/card_types.dart';
import '../../config.dart';

/// The card form and payment view copy from `vectors/card_strings.json`:
/// language code, then section (`number`, `expiry`, `cvv`, `holder`,
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
        },
      },
    };

/// The word in `view.poweredBy` that the payment view replaces with the
/// Payriff logo.
const String payriffWordmark = 'Payriff';

/// The card form and payment view copy in one language.
final class PayriffCardStrings {
  /// Creates the copy for [language].
  const PayriffCardStrings(this.language);

  /// The language.
  final PayriffLanguage language;

  Map<String, Map<String, String>> get _table =>
      payriffCardStringTable[language.value.toLowerCase()]!;

  /// The field's label.
  String label(PayriffCardField field) => _table['label']![field.value]!;

  /// The field's placeholder.
  String placeholder(PayriffCardField field) =>
      _table['placeholder']![field.value]!;

  /// The label above the card box of the grouped layout: "Card
  /// information".
  String get cardInformation => _table['group']!['cardInformation']!;

  /// The payment view's button title, followed by the amount: "Pay".
  String get pay => _table['view']!['pay']!;

  /// The payment view's line under the badges: "Proceed securely by PCI
  /// DSS".
  String get secure => _table['view']!['secure']!;

  /// The payment view's footer, for example "Powered by Payriff". The view
  /// shows the logo in place of "Payriff" ([poweredByParts]).
  String get poweredBy => _table['view']!['poweredBy']!;

  /// The payment view's error line for an order that loaded but cannot be
  /// paid by card: "This order cannot be paid by card".
  String get notPayable => _table['view']!['notPayable']!;

  /// [poweredBy] split at "Payriff" (CONTRACT §16.14): the text before and
  /// after it, where the logo goes. `null` when the copy has no "Payriff".
  ({String before, String after})? get poweredByParts {
    final String text = poweredBy;
    final int at = text.indexOf(payriffWordmark);
    if (at < 0) return null;
    return (
      before: text.substring(0, at),
      after: text.substring(at + payriffWordmark.length),
    );
  }

  /// The message for [code] on [field]. An error without its own message
  /// uses the field's `invalid` message.
  String error(PayriffCardField field, PayriffCardFieldErrorCode code) {
    final Map<String, String> messages = _table[field.value]!;
    return messages[code.value] ?? messages['invalid']!;
  }
}
