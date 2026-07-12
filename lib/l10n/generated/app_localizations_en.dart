// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'FKNotes';

  @override
  String get appBrandName => 'FKNotes';

  @override
  String get appTagline => 'Local first · Private by design';

  @override
  String get language => 'Language';

  @override
  String get languageDescription =>
      'Follow the device language or choose one for FKNotes';

  @override
  String get languageSystem => 'System default';

  @override
  String get languageSimplifiedChinese => '简体中文';

  @override
  String get languageEnglish => 'English';

  @override
  String get chooseLanguage => 'Choose language';

  @override
  String get languageSystemDescription =>
      'Use the language selected for FKNotes on this device';

  @override
  String get languageSimplifiedChineseDescription => '使用简体中文界面';

  @override
  String get languageEnglishDescription => 'Use the English interface';

  @override
  String get languageSaveFailed => 'Couldn\'t save the language setting';
}
