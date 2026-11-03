import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../config.dart';

/// CONTRACT §3.1 and §19.3: maps a locale tag such as `az-AZ`, `ru_RU`,
/// `ar-SA` or `en-US` to a [PayriffLanguage], using the primary language
/// subtag. A language the SDK does not have falls back to English, and to
/// Arabic in [PayriffRegion.sa].
PayriffLanguage languageForLocaleTag(
  String localeTag, {
  PayriffRegion region = PayriffRegion.az,
}) {
  final int separator = localeTag.indexOf(RegExp('[-_]'));
  final String primary =
      (separator < 0 ? localeTag : localeTag.substring(0, separator))
          .toLowerCase();
  return switch (primary) {
    'az' => PayriffLanguage.az,
    'ru' => PayriffLanguage.ru,
    'en' => PayriffLanguage.en,
    'ar' => PayriffLanguage.ar,
    _ => region == PayriffRegion.sa ? PayriffLanguage.ar : PayriffLanguage.en,
  };
}

/// The language of the device's primary locale, for [region] (CONTRACT
/// §19.3).
PayriffLanguage deviceLanguage({PayriffRegion region = PayriffRegion.az}) =>
    languageForLocaleTag(_deviceLocale().toLanguageTag(), region: region);

/// The language of the SDK's screens: [explicit] (the widget's), else
/// `PayriffConfig.language`, else the device language in the configured
/// region.
PayriffLanguage effectiveLanguage(
  PayriffLanguage? explicit,
  PayriffConfig? config,
) =>
    explicit ??
    config?.language ??
    deviceLanguage(region: config?.region ?? PayriffRegion.az);

/// The layout direction of the SDK's views (CONTRACT §18.7, §19.3): right to
/// left when the host's is, or when [language] is Arabic.
TextDirection viewTextDirection(
  BuildContext context,
  PayriffLanguage language,
) => language == PayriffLanguage.ar
    ? TextDirection.rtl
    : Directionality.maybeOf(context) ?? TextDirection.ltr;

ui.Locale _deviceLocale() {
  try {
    // The binding's dispatcher, when the app has one (tests can override it).
    return WidgetsBinding.instance.platformDispatcher.locale;
  } on Object {
    // No binding yet, for example retrieveOrder before runApp.
    return ui.PlatformDispatcher.instance.locale;
  }
}
