import 'package:flutter/widgets.dart';
import 'package:hermes_mobile/l10n/app_localizations.dart';

export 'package:hermes_mobile/l10n/app_localizations.dart';

/// Global access for non-BuildContext code (status callbacks, sync layer).
/// Updated from [MaterialApp.builder] on every rebuild.
class L10n {
  L10n._();
  static AppLocalizations? _current;

  static AppLocalizations get current =>
      _current ?? lookupAppLocalizations(const Locale('en'));

  static void bind(AppLocalizations value) {
    _current = value;
  }
}

extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Locales we ship ARBs for (plus system resolution).
const supportedAppLocales = <Locale>[
  Locale('en'),
  Locale('es'),
  Locale('fr'),
  Locale('de'),
  Locale('ja'),
  Locale('zh'),
  Locale('pt'),
  Locale('ko'),
  Locale('ar'),
];

/// Display labels for Settings language picker (in that language).
String localeDisplayName(Locale locale) {
  switch (locale.languageCode) {
    case 'en':
      return 'English';
    case 'es':
      return 'Español';
    case 'fr':
      return 'Français';
    case 'de':
      return 'Deutsch';
    case 'ja':
      return '日本語';
    case 'zh':
      return '中文';
    case 'pt':
      return 'Português';
    case 'ko':
      return '한국어';
    case 'ar':
      return 'العربية';
    default:
      return locale.languageCode;
  }
}

/// Speech / TTS language tag for the active UI locale.
String speechLocaleId(Locale locale) {
  switch (locale.languageCode) {
    case 'es':
      return 'es_ES';
    case 'fr':
      return 'fr_FR';
    case 'de':
      return 'de_DE';
    case 'ja':
      return 'ja_JP';
    case 'zh':
      return 'zh_CN';
    case 'pt':
      return 'pt_BR';
    case 'ko':
      return 'ko_KR';
    case 'ar':
      return 'ar_SA';
    case 'en':
    default:
      return 'en_US';
  }
}
