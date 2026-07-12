// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '非空笔记';

  @override
  String get appBrandName => 'FKNotes';

  @override
  String get appTagline => '本地优先 · 私密可靠';

  @override
  String get language => '语言';

  @override
  String get languageDescription => '界面语言，可跟随系统或单独设置';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get languageSimplifiedChinese => '简体中文';

  @override
  String get languageEnglish => 'English';

  @override
  String get chooseLanguage => '选择语言';

  @override
  String get languageSystemDescription => '使用设备为 FKNotes 选择的语言';

  @override
  String get languageSimplifiedChineseDescription => '使用简体中文界面';

  @override
  String get languageEnglishDescription => 'Use the English interface';

  @override
  String get languageSaveFailed => '语言设置保存失败';
}
