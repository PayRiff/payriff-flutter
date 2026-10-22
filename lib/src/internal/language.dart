import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../config.dart';

/// CONTRACT §3.1: maps a locale tag such as `az-AZ`, `ru_RU` or `en-US` to a
/// [PayriffLanguage], using the primary language subtag and falling back to
/// English.
PayriffLanguage languageForLocaleTag(String localeTag) {
  final int separator = localeTag.indexOf(RegExp('[-_]'));
  final String primary =
      (separator < 0 ? localeTag : localeTag.substring(0, separator))
          .toLowerCase();
  return switch (primary) {
    'az' => PayriffLanguage.az,
    'ru' => PayriffLanguage.ru,
    _ => PayriffLanguage.en,
  };
}

/// The language of the device's primary locale.
PayriffLanguage deviceLanguage() =>
    languageForLocaleTag(_deviceLocale().toLanguageTag());

ui.Locale _deviceLocale() {
  try {
    // The binding's dispatcher, when the app has one (tests can override it).
    return WidgetsBinding.instance.platformDispatcher.locale;
  } on Object {
    // No binding yet, for example retrieveOrder before runApp.
    return ui.PlatformDispatcher.instance.locale;
  }
}
