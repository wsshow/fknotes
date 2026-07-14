import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'非空笔记'**
  String get appTitle;

  /// No description provided for @appBrandName.
  ///
  /// In zh, this message translates to:
  /// **'FKNotes'**
  String get appBrandName;

  /// No description provided for @appTagline.
  ///
  /// In zh, this message translates to:
  /// **'本地优先 · 私密可靠'**
  String get appTagline;

  /// No description provided for @language.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get language;

  /// No description provided for @languageDescription.
  ///
  /// In zh, this message translates to:
  /// **'界面语言，可跟随系统或单独设置'**
  String get languageDescription;

  /// No description provided for @languageSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get languageSystem;

  /// No description provided for @languageSimplifiedChinese.
  ///
  /// In zh, this message translates to:
  /// **'简体中文'**
  String get languageSimplifiedChinese;

  /// No description provided for @languageEnglish.
  ///
  /// In zh, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @chooseLanguage.
  ///
  /// In zh, this message translates to:
  /// **'选择语言'**
  String get chooseLanguage;

  /// No description provided for @languageSystemDescription.
  ///
  /// In zh, this message translates to:
  /// **'使用设备为 FKNotes 选择的语言'**
  String get languageSystemDescription;

  /// No description provided for @languageSimplifiedChineseDescription.
  ///
  /// In zh, this message translates to:
  /// **'使用简体中文界面'**
  String get languageSimplifiedChineseDescription;

  /// No description provided for @languageEnglishDescription.
  ///
  /// In zh, this message translates to:
  /// **'Use the English interface'**
  String get languageEnglishDescription;

  /// No description provided for @languageSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'语言设置保存失败'**
  String get languageSaveFailed;

  /// No description provided for @localStorageInitializationFailed.
  ///
  /// In zh, this message translates to:
  /// **'本地存储初始化失败'**
  String get localStorageInitializationFailed;

  /// No description provided for @home.
  ///
  /// In zh, this message translates to:
  /// **'主页'**
  String get home;

  /// No description provided for @library.
  ///
  /// In zh, this message translates to:
  /// **'资料库'**
  String get library;

  /// No description provided for @data.
  ///
  /// In zh, this message translates to:
  /// **'数据'**
  String get data;

  /// No description provided for @createNew.
  ///
  /// In zh, this message translates to:
  /// **'新建'**
  String get createNew;

  /// No description provided for @undo.
  ///
  /// In zh, this message translates to:
  /// **'撤销'**
  String get undo;

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @deletePermanently.
  ///
  /// In zh, this message translates to:
  /// **'永久删除'**
  String get deletePermanently;

  /// No description provided for @deletePermanentlyQuestion.
  ///
  /// In zh, this message translates to:
  /// **'永久删除？'**
  String get deletePermanentlyQuestion;

  /// No description provided for @deletePermanentlyDescription.
  ///
  /// In zh, this message translates to:
  /// **'笔记和关联文件将无法恢复。'**
  String get deletePermanentlyDescription;

  /// No description provided for @movedToTrash.
  ///
  /// In zh, this message translates to:
  /// **'已移到回收站'**
  String get movedToTrash;

  /// No description provided for @captureMoment.
  ///
  /// In zh, this message translates to:
  /// **'捕捉此刻'**
  String get captureMoment;

  /// No description provided for @capturePrivacyHint.
  ///
  /// In zh, this message translates to:
  /// **'离线保存，你的内容只属于你'**
  String get capturePrivacyHint;

  /// No description provided for @note.
  ///
  /// In zh, this message translates to:
  /// **'笔记'**
  String get note;

  /// No description provided for @photo.
  ///
  /// In zh, this message translates to:
  /// **'拍照'**
  String get photo;

  /// No description provided for @image.
  ///
  /// In zh, this message translates to:
  /// **'图片'**
  String get image;

  /// No description provided for @record.
  ///
  /// In zh, this message translates to:
  /// **'录音'**
  String get record;

  /// No description provided for @audio.
  ///
  /// In zh, this message translates to:
  /// **'音频'**
  String get audio;

  /// No description provided for @video.
  ///
  /// In zh, this message translates to:
  /// **'视频'**
  String get video;

  /// No description provided for @file.
  ///
  /// In zh, this message translates to:
  /// **'文件'**
  String get file;

  /// No description provided for @voiceNote.
  ///
  /// In zh, this message translates to:
  /// **'语音笔记'**
  String get voiceNote;

  /// No description provided for @importFailed.
  ///
  /// In zh, this message translates to:
  /// **'{type}导入失败'**
  String importFailed(String type);

  /// No description provided for @recentlyUpdated.
  ///
  /// In zh, this message translates to:
  /// **'最近更新'**
  String get recentlyUpdated;

  /// No description provided for @more.
  ///
  /// In zh, this message translates to:
  /// **'更多'**
  String get more;

  /// No description provided for @startWithIdea.
  ///
  /// In zh, this message translates to:
  /// **'从一个念头开始'**
  String get startWithIdea;

  /// No description provided for @createNoteEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'点击“新建”，内容会安全留在本机。'**
  String get createNoteEmptyHint;

  /// No description provided for @localAssistant.
  ///
  /// In zh, this message translates to:
  /// **'本地助手'**
  String get localAssistant;

  /// No description provided for @searchLocalKnowledge.
  ///
  /// In zh, this message translates to:
  /// **'搜索本地知识库'**
  String get searchLocalKnowledge;

  /// No description provided for @searchNotes.
  ///
  /// In zh, this message translates to:
  /// **'搜索笔记'**
  String get searchNotes;

  /// No description provided for @savedOnlyOnDevice.
  ///
  /// In zh, this message translates to:
  /// **'仅保存在本机'**
  String get savedOnlyOnDevice;

  /// No description provided for @allNotes.
  ///
  /// In zh, this message translates to:
  /// **'所有笔记'**
  String get allNotes;

  /// No description provided for @noteCountShort.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条笔记'**
  String noteCountShort(int count);

  /// No description provided for @attachmentCountShort.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个附件'**
  String attachmentCountShort(int count);

  /// No description provided for @createType.
  ///
  /// In zh, this message translates to:
  /// **'新建{type}'**
  String createType(String type);

  /// No description provided for @itemCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个条目'**
  String itemCount(int count);

  /// No description provided for @search.
  ///
  /// In zh, this message translates to:
  /// **'搜索'**
  String get search;

  /// No description provided for @emptyTrash.
  ///
  /// In zh, this message translates to:
  /// **'清空回收站'**
  String get emptyTrash;

  /// No description provided for @sort.
  ///
  /// In zh, this message translates to:
  /// **'排序'**
  String get sort;

  /// No description provided for @creationTime.
  ///
  /// In zh, this message translates to:
  /// **'创建时间'**
  String get creationTime;

  /// No description provided for @title.
  ///
  /// In zh, this message translates to:
  /// **'标题'**
  String get title;

  /// No description provided for @fileSize.
  ///
  /// In zh, this message translates to:
  /// **'文件大小'**
  String get fileSize;

  /// No description provided for @all.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get all;

  /// No description provided for @favorites.
  ///
  /// In zh, this message translates to:
  /// **'收藏'**
  String get favorites;

  /// No description provided for @archive.
  ///
  /// In zh, this message translates to:
  /// **'归档'**
  String get archive;

  /// No description provided for @trash.
  ///
  /// In zh, this message translates to:
  /// **'回收站'**
  String get trash;

  /// No description provided for @emptyActive.
  ///
  /// In zh, this message translates to:
  /// **'当前筛选下没有内容'**
  String get emptyActive;

  /// No description provided for @emptyFavorites.
  ///
  /// In zh, this message translates to:
  /// **'收藏的内容会出现在这里'**
  String get emptyFavorites;

  /// No description provided for @emptyArchive.
  ///
  /// In zh, this message translates to:
  /// **'归档箱是空的'**
  String get emptyArchive;

  /// No description provided for @emptyTrashDescription.
  ///
  /// In zh, this message translates to:
  /// **'回收站是空的'**
  String get emptyTrashDescription;

  /// No description provided for @emptyTrashQuestion.
  ///
  /// In zh, this message translates to:
  /// **'清空回收站？'**
  String get emptyTrashQuestion;

  /// No description provided for @emptyTrashConfirmation.
  ///
  /// In zh, this message translates to:
  /// **'将永久删除 {count} 条内容和关联文件。'**
  String emptyTrashConfirmation(int count);

  /// No description provided for @clear.
  ///
  /// In zh, this message translates to:
  /// **'清空'**
  String get clear;

  /// No description provided for @allTypes.
  ///
  /// In zh, this message translates to:
  /// **'所有类型'**
  String get allTypes;

  /// No description provided for @unavailable.
  ///
  /// In zh, this message translates to:
  /// **'暂不可用'**
  String get unavailable;

  /// No description provided for @localData.
  ///
  /// In zh, this message translates to:
  /// **'本地数据'**
  String get localData;

  /// No description provided for @localDataSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'默认只保存在本机；是否同步完全由你决定。'**
  String get localDataSubtitle;

  /// No description provided for @localFirst.
  ///
  /// In zh, this message translates to:
  /// **'本地优先'**
  String get localFirst;

  /// No description provided for @offlineSecure.
  ///
  /// In zh, this message translates to:
  /// **'离线安全'**
  String get offlineSecure;

  /// No description provided for @totalItems.
  ///
  /// In zh, this message translates to:
  /// **'总条目'**
  String get totalItems;

  /// No description provided for @attachments.
  ///
  /// In zh, this message translates to:
  /// **'附件'**
  String get attachments;

  /// No description provided for @userDataUsage.
  ///
  /// In zh, this message translates to:
  /// **'资料占用'**
  String get userDataUsage;

  /// No description provided for @preferences.
  ///
  /// In zh, this message translates to:
  /// **'偏好设置'**
  String get preferences;

  /// No description provided for @unifiedStorage.
  ///
  /// In zh, this message translates to:
  /// **'统一存储'**
  String get unifiedStorage;

  /// No description provided for @cloudSync.
  ///
  /// In zh, this message translates to:
  /// **'云同步'**
  String get cloudSync;

  /// No description provided for @cloudSyncSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'手动同步用户数据，支持 S3 和 WebDAV'**
  String get cloudSyncSubtitle;

  /// No description provided for @privateAppStorage.
  ///
  /// In zh, this message translates to:
  /// **'应用私有存储'**
  String get privateAppStorage;

  /// No description provided for @privateAppStorageSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'笔记、聊天、附件和缩略图均安全保存在本机'**
  String get privateAppStorageSubtitle;

  /// No description provided for @localModels.
  ///
  /// In zh, this message translates to:
  /// **'本地模型'**
  String get localModels;

  /// No description provided for @localModelsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'查看正在使用的模型并按能力分类管理'**
  String get localModelsSubtitle;

  /// No description provided for @backupAndMigration.
  ///
  /// In zh, this message translates to:
  /// **'备份与迁移'**
  String get backupAndMigration;

  /// No description provided for @exportCompleteBackup.
  ///
  /// In zh, this message translates to:
  /// **'导出完整备份'**
  String get exportCompleteBackup;

  /// No description provided for @exportCompleteBackupSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'通过系统面板保存，包含所有笔记和附件'**
  String get exportCompleteBackupSubtitle;

  /// No description provided for @restoreFromBackup.
  ///
  /// In zh, this message translates to:
  /// **'从备份恢复'**
  String get restoreFromBackup;

  /// No description provided for @restoreFromBackupSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'恢复前会进行完整性检查'**
  String get restoreFromBackupSubtitle;

  /// No description provided for @organizationAndSecurity.
  ///
  /// In zh, this message translates to:
  /// **'整理与安全'**
  String get organizationAndSecurity;

  /// No description provided for @appLock.
  ///
  /// In zh, this message translates to:
  /// **'应用锁'**
  String get appLock;

  /// No description provided for @appLockEnabledSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'已开启 · 离开应用 {timeout}锁定'**
  String appLockEnabledSubtitle(String timeout);

  /// No description provided for @appLockDisabledSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'使用系统指纹、人脸或锁屏密码'**
  String get appLockDisabledSubtitle;

  /// No description provided for @lockImmediately.
  ///
  /// In zh, this message translates to:
  /// **'立即'**
  String get lockImmediately;

  /// No description provided for @lockAfterOneMinute.
  ///
  /// In zh, this message translates to:
  /// **'1 分钟后'**
  String get lockAfterOneMinute;

  /// No description provided for @lockAfterFiveMinutes.
  ///
  /// In zh, this message translates to:
  /// **'5 分钟后'**
  String get lockAfterFiveMinutes;

  /// No description provided for @lockAfterFifteenMinutes.
  ///
  /// In zh, this message translates to:
  /// **'15 分钟后'**
  String get lockAfterFifteenMinutes;

  /// No description provided for @contentCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条内容'**
  String contentCount(int count);

  /// No description provided for @about.
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get about;

  /// No description provided for @loadingVersion.
  ///
  /// In zh, this message translates to:
  /// **'正在读取版本信息…'**
  String get loadingVersion;

  /// No description provided for @versionNumber.
  ///
  /// In zh, this message translates to:
  /// **'版本号 {version}'**
  String versionNumber(String version);

  /// No description provided for @versionNumberWithBuild.
  ///
  /// In zh, this message translates to:
  /// **'版本号 {version} ({build})'**
  String versionNumberWithBuild(String version, String build);

  /// No description provided for @buildTime.
  ///
  /// In zh, this message translates to:
  /// **'构建时间 {time}'**
  String buildTime(String time);

  /// No description provided for @buildTimeUnrecorded.
  ///
  /// In zh, this message translates to:
  /// **'构建时间 未记录'**
  String get buildTimeUnrecorded;

  /// No description provided for @footerTagline.
  ///
  /// In zh, this message translates to:
  /// **'FKNotes · 本地优先，同步由你掌控'**
  String get footerTagline;

  /// No description provided for @backupExported.
  ///
  /// In zh, this message translates to:
  /// **'备份已交给系统保存'**
  String get backupExported;

  /// No description provided for @exportFailed.
  ///
  /// In zh, this message translates to:
  /// **'导出失败：{error}'**
  String exportFailed(String error);

  /// No description provided for @restoreCompleteBackupQuestion.
  ///
  /// In zh, this message translates to:
  /// **'恢复完整备份？'**
  String get restoreCompleteBackupQuestion;

  /// No description provided for @restoreCompleteBackupDescription.
  ///
  /// In zh, this message translates to:
  /// **'当前内容将被备份中的内容替换。建议先导出一份当前数据。'**
  String get restoreCompleteBackupDescription;

  /// No description provided for @chooseBackup.
  ///
  /// In zh, this message translates to:
  /// **'选择备份'**
  String get chooseBackup;

  /// No description provided for @backupRestored.
  ///
  /// In zh, this message translates to:
  /// **'备份已安全恢复'**
  String get backupRestored;

  /// No description provided for @restoreFailed.
  ///
  /// In zh, this message translates to:
  /// **'恢复失败：{error}'**
  String restoreFailed(String error);

  /// No description provided for @localModelsPageTitle.
  ///
  /// In zh, this message translates to:
  /// **'本地模型'**
  String get localModelsPageTitle;

  /// No description provided for @modelsInUse.
  ///
  /// In zh, this message translates to:
  /// **'正在使用'**
  String get modelsInUse;

  /// No description provided for @noModelsInUse.
  ///
  /// In zh, this message translates to:
  /// **'尚未配置正在使用的本地模型'**
  String get noModelsInUse;

  /// No description provided for @modelConfiguration.
  ///
  /// In zh, this message translates to:
  /// **'分类管理'**
  String get modelConfiguration;

  /// No description provided for @activeModelCount.
  ///
  /// In zh, this message translates to:
  /// **'正在使用 {count} 个模型'**
  String activeModelCount(int count);

  /// No description provided for @activeModelsUsage.
  ///
  /// In zh, this message translates to:
  /// **'本地模型占用 {size}'**
  String activeModelsUsage(String size);

  /// No description provided for @installedModels.
  ///
  /// In zh, this message translates to:
  /// **'已安装'**
  String get installedModels;

  /// No description provided for @availableModels.
  ///
  /// In zh, this message translates to:
  /// **'可获取'**
  String get availableModels;

  /// No description provided for @installedModelsCount.
  ///
  /// In zh, this message translates to:
  /// **'已安装 {count} 个模型'**
  String installedModelsCount(int count);

  /// No description provided for @noInstalledModelsInCategory.
  ///
  /// In zh, this message translates to:
  /// **'这一分类还没有已安装的模型'**
  String get noInstalledModelsInCategory;

  /// No description provided for @noAvailableModelsInCategory.
  ///
  /// In zh, this message translates to:
  /// **'当前没有其他可获取的模型'**
  String get noAvailableModelsInCategory;

  /// No description provided for @speechModelsDescription.
  ///
  /// In zh, this message translates to:
  /// **'分别管理实时听写、录音转写、语音处理与语音合成模型。'**
  String get speechModelsDescription;

  /// No description provided for @visionModelsDescription.
  ///
  /// In zh, this message translates to:
  /// **'管理 OCR 与专用视觉能力；聊天图片理解由支持图片的语言模型提供。'**
  String get visionModelsDescription;

  /// No description provided for @liveDictationSettingsDescription.
  ///
  /// In zh, this message translates to:
  /// **'管理当前听写模型、热词、精修和实时降噪'**
  String get liveDictationSettingsDescription;

  /// No description provided for @modelDownloadsAndStorage.
  ///
  /// In zh, this message translates to:
  /// **'下载与存储'**
  String get modelDownloadsAndStorage;

  /// No description provided for @modelDownloadsAndStorageDescription.
  ///
  /// In zh, this message translates to:
  /// **'下载源、后台任务和模型文件占用'**
  String get modelDownloadsAndStorageDescription;

  /// No description provided for @localAssistantUsage.
  ///
  /// In zh, this message translates to:
  /// **'本地助手'**
  String get localAssistantUsage;

  /// No description provided for @liveDictationUsage.
  ///
  /// In zh, this message translates to:
  /// **'实时听写'**
  String get liveDictationUsage;

  /// No description provided for @audioTranscriptionUsage.
  ///
  /// In zh, this message translates to:
  /// **'录音转写'**
  String get audioTranscriptionUsage;

  /// No description provided for @voiceActivityUsage.
  ///
  /// In zh, this message translates to:
  /// **'语音检测'**
  String get voiceActivityUsage;

  /// No description provided for @speechEnhancementUsage.
  ///
  /// In zh, this message translates to:
  /// **'实时降噪'**
  String get speechEnhancementUsage;

  /// No description provided for @textRecognitionUsage.
  ///
  /// In zh, this message translates to:
  /// **'文字识别'**
  String get textRecognitionUsage;

  /// No description provided for @modelPrivacyHint.
  ///
  /// In zh, this message translates to:
  /// **'模型只在用户下载时联网，且不会进入笔记备份；用户数据仅在手动云同步时上传。'**
  String get modelPrivacyHint;

  /// No description provided for @languageModels.
  ///
  /// In zh, this message translates to:
  /// **'语言模型'**
  String get languageModels;

  /// No description provided for @languageModelsDescription.
  ///
  /// In zh, this message translates to:
  /// **'由用户下载并选择本地助手使用的模型，默认上下文为 4096。'**
  String get languageModelsDescription;

  /// No description provided for @discoverMnnModels.
  ///
  /// In zh, this message translates to:
  /// **'发现本地模型'**
  String get discoverMnnModels;

  /// No description provided for @discoverMnnModelsDescription.
  ///
  /// In zh, this message translates to:
  /// **'浏览从 taobao-mnn 与 litert-community Collections 同步的公开模型；是否校验和添加由你决定。'**
  String get discoverMnnModelsDescription;

  /// No description provided for @browseModels.
  ///
  /// In zh, this message translates to:
  /// **'浏览模型'**
  String get browseModels;

  /// No description provided for @refreshCatalog.
  ///
  /// In zh, this message translates to:
  /// **'刷新目录'**
  String get refreshCatalog;

  /// No description provided for @syncingModelCatalog.
  ///
  /// In zh, this message translates to:
  /// **'正在同步模型目录…'**
  String get syncingModelCatalog;

  /// No description provided for @modelCatalogSyncFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法刷新模型目录：{error}'**
  String modelCatalogSyncFailed(String error);

  /// No description provided for @modelCatalogRefreshTimeout.
  ///
  /// In zh, this message translates to:
  /// **'模型目录刷新超时'**
  String get modelCatalogRefreshTimeout;

  /// No description provided for @modelCatalogRefreshTimeoutDescription.
  ///
  /// In zh, this message translates to:
  /// **'当前网络未能及时连接模型服务。你可以重试或切换模型网络源。'**
  String get modelCatalogRefreshTimeoutDescription;

  /// No description provided for @modelCatalogOffline.
  ///
  /// In zh, this message translates to:
  /// **'无法连接模型服务'**
  String get modelCatalogOffline;

  /// No description provided for @modelCatalogOfflineDescription.
  ///
  /// In zh, this message translates to:
  /// **'请检查网络连接，或尝试切换模型网络源。'**
  String get modelCatalogOfflineDescription;

  /// No description provided for @modelCatalogServiceUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'模型服务暂时不可用'**
  String get modelCatalogServiceUnavailable;

  /// No description provided for @modelCatalogServiceUnavailableDescription.
  ///
  /// In zh, this message translates to:
  /// **'服务当前没有正常响应，请稍后重试。'**
  String get modelCatalogServiceUnavailableDescription;

  /// No description provided for @modelCatalogAuthorizationRequired.
  ///
  /// In zh, this message translates to:
  /// **'部分模型需要访问授权'**
  String get modelCatalogAuthorizationRequired;

  /// No description provided for @modelCatalogAuthorizationRequiredDescription.
  ///
  /// In zh, this message translates to:
  /// **'当前目录包含需要在 Hugging Face 接受许可后才能访问的模型。'**
  String get modelCatalogAuthorizationRequiredDescription;

  /// No description provided for @modelCatalogInvalidResponse.
  ///
  /// In zh, this message translates to:
  /// **'模型目录暂时无法读取'**
  String get modelCatalogInvalidResponse;

  /// No description provided for @modelCatalogInvalidResponseDescription.
  ///
  /// In zh, this message translates to:
  /// **'服务返回了无法识别的数据，请稍后重试。'**
  String get modelCatalogInvalidResponseDescription;

  /// No description provided for @modelCatalogCompatibilityUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'暂时无法检查模型兼容性'**
  String get modelCatalogCompatibilityUnavailable;

  /// No description provided for @modelNetworkSourceSettings.
  ///
  /// In zh, this message translates to:
  /// **'切换网络源'**
  String get modelNetworkSourceSettings;

  /// No description provided for @cachedCatalogInUse.
  ///
  /// In zh, this message translates to:
  /// **'正在显示上次成功同步的目录'**
  String get cachedCatalogInUse;

  /// No description provided for @searchMnnModels.
  ///
  /// In zh, this message translates to:
  /// **'搜索本地模型'**
  String get searchMnnModels;

  /// No description provided for @noMnnModelsFound.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的本地模型'**
  String get noMnnModelsFound;

  /// No description provided for @officialMnnCollection.
  ///
  /// In zh, this message translates to:
  /// **'taobao-mnn 官方 Collection'**
  String get officialMnnCollection;

  /// No description provided for @officialLiteRtCollection.
  ///
  /// In zh, this message translates to:
  /// **'litert-community 官方 Collection'**
  String get officialLiteRtCollection;

  /// No description provided for @downloadCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 次下载'**
  String downloadCount(int count);

  /// No description provided for @modelEngine.
  ///
  /// In zh, this message translates to:
  /// **'推理引擎'**
  String get modelEngine;

  /// No description provided for @collection.
  ///
  /// In zh, this message translates to:
  /// **'模型集合'**
  String get collection;

  /// No description provided for @downloads.
  ///
  /// In zh, this message translates to:
  /// **'下载热度'**
  String get downloads;

  /// No description provided for @modelPackageNotVerified.
  ///
  /// In zh, this message translates to:
  /// **'模型包尚未校验'**
  String get modelPackageNotVerified;

  /// No description provided for @modelPackageVerificationDescription.
  ///
  /// In zh, this message translates to:
  /// **'校验会联网读取仓库元数据、固定版本和文件清单，不会下载完整模型，也不代表当前设备一定能运行。'**
  String get modelPackageVerificationDescription;

  /// No description provided for @verifyModelPackage.
  ///
  /// In zh, this message translates to:
  /// **'校验模型包'**
  String get verifyModelPackage;

  /// No description provided for @verifyingModelPackage.
  ///
  /// In zh, this message translates to:
  /// **'正在校验模型包…'**
  String get verifyingModelPackage;

  /// No description provided for @reverifyModelPackage.
  ///
  /// In zh, this message translates to:
  /// **'重新校验模型包'**
  String get reverifyModelPackage;

  /// No description provided for @modelPackageUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'该仓库不是受支持的模型包'**
  String get modelPackageUnsupported;

  /// No description provided for @modelPackageUnsupportedDescription.
  ///
  /// In zh, this message translates to:
  /// **'仓库格式、公开访问状态或必要文件不符合当前引擎要求。'**
  String get modelPackageUnsupportedDescription;

  /// No description provided for @checkingModelCompatibility.
  ///
  /// In zh, this message translates to:
  /// **'正在检查模型兼容性…'**
  String get checkingModelCompatibility;

  /// No description provided for @modelCompatibilityPassed.
  ///
  /// In zh, this message translates to:
  /// **'MNN 文件与运行配置检查通过'**
  String get modelCompatibilityPassed;

  /// No description provided for @liteRtCompatibilityPassed.
  ///
  /// In zh, this message translates to:
  /// **'LiteRT-LM 文件、固定版本与校验值检查通过'**
  String get liteRtCompatibilityPassed;

  /// No description provided for @modelCompatibilityFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法添加该模型：{error}'**
  String modelCompatibilityFailed(String error);

  /// No description provided for @pinnedCommit.
  ///
  /// In zh, this message translates to:
  /// **'固定 commit'**
  String get pinnedCommit;

  /// No description provided for @modelFileCount.
  ///
  /// In zh, this message translates to:
  /// **'模型文件'**
  String get modelFileCount;

  /// No description provided for @modelFile.
  ///
  /// In zh, this message translates to:
  /// **'模型文件'**
  String get modelFile;

  /// No description provided for @fileCountValue.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个文件'**
  String fileCountValue(int count);

  /// No description provided for @modelCapabilities.
  ///
  /// In zh, this message translates to:
  /// **'模型能力'**
  String get modelCapabilities;

  /// No description provided for @textGenerationCapability.
  ///
  /// In zh, this message translates to:
  /// **'文本生成'**
  String get textGenerationCapability;

  /// No description provided for @imageInputCapability.
  ///
  /// In zh, this message translates to:
  /// **'图片输入'**
  String get imageInputCapability;

  /// No description provided for @audioInputCapability.
  ///
  /// In zh, this message translates to:
  /// **'音频输入'**
  String get audioInputCapability;

  /// No description provided for @reasoningCapability.
  ///
  /// In zh, this message translates to:
  /// **'思考推理'**
  String get reasoningCapability;

  /// No description provided for @toolCallingCapability.
  ///
  /// In zh, this message translates to:
  /// **'工具调用'**
  String get toolCallingCapability;

  /// No description provided for @addAndDownloadModel.
  ///
  /// In zh, this message translates to:
  /// **'添加并下载'**
  String get addAndDownloadModel;

  /// No description provided for @addToLanguageModels.
  ///
  /// In zh, this message translates to:
  /// **'添加到语言模型'**
  String get addToLanguageModels;

  /// No description provided for @modelAddedToManager.
  ///
  /// In zh, this message translates to:
  /// **'模型已添加到本地模型'**
  String get modelAddedToManager;

  /// No description provided for @recommendedModelsAlreadyListed.
  ///
  /// In zh, this message translates to:
  /// **'FKNotes 推荐模型已在上一页中显示。'**
  String get recommendedModelsAlreadyListed;

  /// No description provided for @remoteMnnModelSummary.
  ///
  /// In zh, this message translates to:
  /// **'来自 {collection} 的官方模型'**
  String remoteMnnModelSummary(String collection);

  /// No description provided for @remoteMnnModelDescription.
  ///
  /// In zh, this message translates to:
  /// **'从 taobao-mnn Collections 同步；安装前会校验仓库版本和每个模型文件。'**
  String get remoteMnnModelDescription;

  /// No description provided for @liveDictationSettings.
  ///
  /// In zh, this message translates to:
  /// **'实时听写设置'**
  String get liveDictationSettings;

  /// No description provided for @speechModels.
  ///
  /// In zh, this message translates to:
  /// **'语音模型'**
  String get speechModels;

  /// No description provided for @visionModels.
  ///
  /// In zh, this message translates to:
  /// **'视觉模型'**
  String get visionModels;

  /// No description provided for @modelDownloadSource.
  ///
  /// In zh, this message translates to:
  /// **'模型下载源'**
  String get modelDownloadSource;

  /// No description provided for @downloadSourceSecurityDescription.
  ///
  /// In zh, this message translates to:
  /// **'所有模式都会在首选节点不可用时安全回退；模型仍通过固定版本和 SHA-256 校验。'**
  String get downloadSourceSecurityDescription;

  /// No description provided for @downloadSourceSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'下载源设置保存失败'**
  String get downloadSourceSaveFailed;

  /// No description provided for @downloadSourceAutomatic.
  ///
  /// In zh, this message translates to:
  /// **'自动选择'**
  String get downloadSourceAutomatic;

  /// No description provided for @downloadSourceOfficialFirst.
  ///
  /// In zh, this message translates to:
  /// **'优先官方源'**
  String get downloadSourceOfficialFirst;

  /// No description provided for @downloadSourceMainlandFirst.
  ///
  /// In zh, this message translates to:
  /// **'优先国内镜像'**
  String get downloadSourceMainlandFirst;

  /// No description provided for @downloadSourceAutomaticDescription.
  ///
  /// In zh, this message translates to:
  /// **'结合设备区域和实际连接结果动态选择'**
  String get downloadSourceAutomaticDescription;

  /// No description provided for @downloadSourceOfficialDescription.
  ///
  /// In zh, this message translates to:
  /// **'优先 Hugging Face 或 GitHub 官方节点'**
  String get downloadSourceOfficialDescription;

  /// No description provided for @downloadSourceMainlandDescription.
  ///
  /// In zh, this message translates to:
  /// **'优先国内镜像或 ModelScope 节点'**
  String get downloadSourceMainlandDescription;

  /// No description provided for @downloadSourceEffective.
  ///
  /// In zh, this message translates to:
  /// **'自动选择 · {source}优先'**
  String downloadSourceEffective(String source);

  /// No description provided for @officialSource.
  ///
  /// In zh, this message translates to:
  /// **'官方源'**
  String get officialSource;

  /// No description provided for @mainlandMirror.
  ///
  /// In zh, this message translates to:
  /// **'国内镜像'**
  String get mainlandMirror;

  /// No description provided for @lastUsedSource.
  ///
  /// In zh, this message translates to:
  /// **'最近使用：{source}'**
  String lastUsedSource(String source);

  /// No description provided for @continueModelDownloadQuestion.
  ///
  /// In zh, this message translates to:
  /// **'继续下载模型？'**
  String get continueModelDownloadQuestion;

  /// No description provided for @downloadModelQuestion.
  ///
  /// In zh, this message translates to:
  /// **'下载模型？'**
  String get downloadModelQuestion;

  /// No description provided for @modelDownloadDescription.
  ///
  /// In zh, this message translates to:
  /// **'{name}\n还需下载约 {size}，建议使用 Wi-Fi。\n\n下载中可离开此页面；中断后会保留进度。'**
  String modelDownloadDescription(String name, String size);

  /// No description provided for @modelMemoryRecommendation.
  ///
  /// In zh, this message translates to:
  /// **'建议设备至少具备 {memory} 运行内存；内存不足可能加载失败或被系统终止。'**
  String modelMemoryRecommendation(String memory);

  /// No description provided for @ttsStorageRecommendation.
  ///
  /// In zh, this message translates to:
  /// **'解压安装时请预留约 600 MB 可用空间。'**
  String get ttsStorageRecommendation;

  /// No description provided for @startDownload.
  ///
  /// In zh, this message translates to:
  /// **'开始下载'**
  String get startDownload;

  /// No description provided for @removeModelQuestion.
  ///
  /// In zh, this message translates to:
  /// **'移除 {name}？'**
  String removeModelQuestion(String name);

  /// No description provided for @removeModelDescription.
  ///
  /// In zh, this message translates to:
  /// **'将释放约 {size} 空间。已经生成的笔记内容不会被删除。'**
  String removeModelDescription(String size);

  /// No description provided for @removeModel.
  ///
  /// In zh, this message translates to:
  /// **'移除模型'**
  String get removeModel;

  /// No description provided for @hotwordsSaved.
  ///
  /// In zh, this message translates to:
  /// **'已保存 {count} 个热词'**
  String hotwordsSaved(int count);

  /// No description provided for @hotwordsDisabled.
  ///
  /// In zh, this message translates to:
  /// **'已关闭实时听写热词'**
  String get hotwordsDisabled;

  /// No description provided for @settingsSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'设置保存失败，请检查设备存储空间'**
  String get settingsSaveFailed;

  /// No description provided for @purpose.
  ///
  /// In zh, this message translates to:
  /// **'用途'**
  String get purpose;

  /// No description provided for @engine.
  ///
  /// In zh, this message translates to:
  /// **'引擎'**
  String get engine;

  /// No description provided for @supportedLanguages.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get supportedLanguages;

  /// No description provided for @version.
  ///
  /// In zh, this message translates to:
  /// **'版本'**
  String get version;

  /// No description provided for @recommendedMemory.
  ///
  /// In zh, this message translates to:
  /// **'建议内存'**
  String get recommendedMemory;

  /// No description provided for @memoryAndAbove.
  ///
  /// In zh, this message translates to:
  /// **'{memory} 及以上'**
  String memoryAndAbove(String memory);

  /// No description provided for @source.
  ///
  /// In zh, this message translates to:
  /// **'来源'**
  String get source;

  /// No description provided for @license.
  ///
  /// In zh, this message translates to:
  /// **'许可'**
  String get license;

  /// No description provided for @saveFailedStorage.
  ///
  /// In zh, this message translates to:
  /// **'保存失败，请检查设备存储空间'**
  String get saveFailedStorage;

  /// No description provided for @liveDictationHotwords.
  ///
  /// In zh, this message translates to:
  /// **'实时听写热词'**
  String get liveDictationHotwords;

  /// No description provided for @hotwordsDescription.
  ///
  /// In zh, this message translates to:
  /// **'每行输入一个人名、产品名或专业术语；留空即关闭。热词从下一次听写开始生效。'**
  String get hotwordsDescription;

  /// No description provided for @hotwordsHint.
  ///
  /// In zh, this message translates to:
  /// **'非空笔记\nFKNotes\nsherpa onnx'**
  String get hotwordsHint;

  /// No description provided for @hotwordsList.
  ///
  /// In zh, this message translates to:
  /// **'热词列表'**
  String get hotwordsList;

  /// No description provided for @boostStrength.
  ///
  /// In zh, this message translates to:
  /// **'增强强度'**
  String get boostStrength;

  /// No description provided for @hotwordsStrengthWarning.
  ///
  /// In zh, this message translates to:
  /// **'过高的强度可能把发音相近的普通词误判为热词，建议先使用 2.0。'**
  String get hotwordsStrengthWarning;

  /// No description provided for @saving.
  ///
  /// In zh, this message translates to:
  /// **'保存中…'**
  String get saving;

  /// No description provided for @save.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get save;

  /// No description provided for @finalRefinement.
  ///
  /// In zh, this message translates to:
  /// **'结束后精修'**
  String get finalRefinement;

  /// No description provided for @finalRefinementDescription.
  ///
  /// In zh, this message translates to:
  /// **'使用 SenseVoice 二次识别，仅在质量检查通过时替换（默认关闭）'**
  String get finalRefinementDescription;

  /// No description provided for @liveNoiseSuppression.
  ///
  /// In zh, this message translates to:
  /// **'实时降噪'**
  String get liveNoiseSuppression;

  /// No description provided for @liveNoiseSuppressionDescription.
  ///
  /// In zh, this message translates to:
  /// **'先抑制环境噪声，再送入流式识别'**
  String get liveNoiseSuppressionDescription;

  /// No description provided for @installDenoiserFirst.
  ///
  /// In zh, this message translates to:
  /// **'请先安装下方的 DPDFNet 实时降噪模型'**
  String get installDenoiserFirst;

  /// No description provided for @hotwordBoost.
  ///
  /// In zh, this message translates to:
  /// **'热词增强'**
  String get hotwordBoost;

  /// No description provided for @hotwordSummary.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个热词 · 强度 {strength}'**
  String hotwordSummary(int count, String strength);

  /// No description provided for @hotwordBoostDescription.
  ///
  /// In zh, this message translates to:
  /// **'优先识别人名、品牌与专业术语'**
  String get hotwordBoostDescription;

  /// No description provided for @installedModelCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个模型可用'**
  String installedModelCount(int count);

  /// No description provided for @optionalModelsUsage.
  ///
  /// In zh, this message translates to:
  /// **'可选模型占用 {size}'**
  String optionalModelsUsage(String size);

  /// No description provided for @recommended.
  ///
  /// In zh, this message translates to:
  /// **'推荐'**
  String get recommended;

  /// No description provided for @modelTransfers.
  ///
  /// In zh, this message translates to:
  /// **'下载与待继续'**
  String get modelTransfers;

  /// No description provided for @modelTransfersDescription.
  ///
  /// In zh, this message translates to:
  /// **'集中查看正在传输、等待处理以及保留了下载进度的模型。已完成的模型会自动离开这里。'**
  String get modelTransfersDescription;

  /// No description provided for @modelTransferSectionCount.
  ///
  /// In zh, this message translates to:
  /// **'下载与待继续（{count}）'**
  String modelTransferSectionCount(int count);

  /// No description provided for @modelTransferSummary.
  ///
  /// In zh, this message translates to:
  /// **'{active} 项进行中 · {resumable} 项待继续'**
  String modelTransferSummary(int active, int resumable);

  /// No description provided for @noModelTransfers.
  ///
  /// In zh, this message translates to:
  /// **'当前没有正在传输或等待继续的模型'**
  String get noModelTransfers;

  /// No description provided for @otherModels.
  ///
  /// In zh, this message translates to:
  /// **'其他模型'**
  String get otherModels;

  /// No description provided for @currentDictation.
  ///
  /// In zh, this message translates to:
  /// **'当前听写'**
  String get currentDictation;

  /// No description provided for @currentAssistant.
  ///
  /// In zh, this message translates to:
  /// **'当前助手'**
  String get currentAssistant;

  /// No description provided for @modelDetails.
  ///
  /// In zh, this message translates to:
  /// **'模型详情'**
  String get modelDetails;

  /// No description provided for @memoryBadge.
  ///
  /// In zh, this message translates to:
  /// **'{memory}+ 内存'**
  String memoryBadge(String memory);

  /// No description provided for @pleaseWait.
  ///
  /// In zh, this message translates to:
  /// **'请稍候'**
  String get pleaseWait;

  /// No description provided for @modelDownloadFailed.
  ///
  /// In zh, this message translates to:
  /// **'模型下载失败'**
  String get modelDownloadFailed;

  /// No description provided for @bundledWithApp.
  ///
  /// In zh, this message translates to:
  /// **'随应用提供'**
  String get bundledWithApp;

  /// No description provided for @comingSoon.
  ///
  /// In zh, this message translates to:
  /// **'即将支持'**
  String get comingSoon;

  /// No description provided for @installed.
  ///
  /// In zh, this message translates to:
  /// **'已安装'**
  String get installed;

  /// No description provided for @useForDictation.
  ///
  /// In zh, this message translates to:
  /// **'用于听写'**
  String get useForDictation;

  /// No description provided for @useForAssistant.
  ///
  /// In zh, this message translates to:
  /// **'用于助手'**
  String get useForAssistant;

  /// No description provided for @remove.
  ///
  /// In zh, this message translates to:
  /// **'移除'**
  String get remove;

  /// No description provided for @importFromFile.
  ///
  /// In zh, this message translates to:
  /// **'从文件导入'**
  String get importFromFile;

  /// No description provided for @continueDownload.
  ///
  /// In zh, this message translates to:
  /// **'继续下载'**
  String get continueDownload;

  /// No description provided for @download.
  ///
  /// In zh, this message translates to:
  /// **'下载'**
  String get download;

  /// No description provided for @pauseDownload.
  ///
  /// In zh, this message translates to:
  /// **'暂停'**
  String get pauseDownload;

  /// No description provided for @cancelingDownload.
  ///
  /// In zh, this message translates to:
  /// **'正在暂停并保留已下载内容…'**
  String get cancelingDownload;

  /// No description provided for @downloadedResumable.
  ///
  /// In zh, this message translates to:
  /// **'已下载 {amount}，可继续'**
  String downloadedResumable(String amount);

  /// No description provided for @moreActions.
  ///
  /// In zh, this message translates to:
  /// **'更多操作'**
  String get moreActions;

  /// No description provided for @discardPartialDownload.
  ///
  /// In zh, this message translates to:
  /// **'删除已下载部分'**
  String get discardPartialDownload;

  /// No description provided for @discardPartialDownloadQuestion.
  ///
  /// In zh, this message translates to:
  /// **'删除 {name} 的下载进度？'**
  String discardPartialDownloadQuestion(String name);

  /// No description provided for @discardPartialDownloadDescription.
  ///
  /// In zh, this message translates to:
  /// **'将删除已下载的 {size}，下次需要从头下载。'**
  String discardPartialDownloadDescription(String size);

  /// No description provided for @discardPartialDownloadFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法删除已下载部分，请稍后重试'**
  String get discardPartialDownloadFailed;

  /// No description provided for @connectingDownloadSource.
  ///
  /// In zh, this message translates to:
  /// **'正在连接下载节点{source}'**
  String connectingDownloadSource(String source);

  /// No description provided for @downloadedInstalling.
  ///
  /// In zh, this message translates to:
  /// **'已下载 {size} · 正在完成安装'**
  String downloadedInstalling(String size);

  /// No description provided for @downloadedWaitingInstall.
  ///
  /// In zh, this message translates to:
  /// **'已下载 {size} · 等待安装'**
  String downloadedWaitingInstall(String size);

  /// No description provided for @preparingLocalModelImport.
  ///
  /// In zh, this message translates to:
  /// **'正在准备本地模型文件…'**
  String get preparingLocalModelImport;

  /// No description provided for @estimatedRemainingCompact.
  ///
  /// In zh, this message translates to:
  /// **'剩余 {time}'**
  String estimatedRemainingCompact(String time);

  /// No description provided for @modelDownloadTransfer.
  ///
  /// In zh, this message translates to:
  /// **'模型下载'**
  String get modelDownloadTransfer;

  /// No description provided for @localModelImportTransfer.
  ///
  /// In zh, this message translates to:
  /// **'本地文件导入'**
  String get localModelImportTransfer;

  /// No description provided for @thirdPartyMainlandMirror.
  ///
  /// In zh, this message translates to:
  /// **'第三方国内镜像'**
  String get thirdPartyMainlandMirror;

  /// No description provided for @githubOfficialSource.
  ///
  /// In zh, this message translates to:
  /// **'GitHub 官方源'**
  String get githubOfficialSource;

  /// No description provided for @modelScopeSource.
  ///
  /// In zh, this message translates to:
  /// **'ModelScope 魔搭'**
  String get modelScopeSource;

  /// No description provided for @backgroundTasks.
  ///
  /// In zh, this message translates to:
  /// **'后台任务'**
  String get backgroundTasks;

  /// No description provided for @backgroundTaskCount.
  ///
  /// In zh, this message translates to:
  /// **'后台任务 · {count} 项'**
  String backgroundTaskCount(int count);

  /// No description provided for @noBackgroundTasks.
  ///
  /// In zh, this message translates to:
  /// **'当前没有正在运行或需要处理的任务'**
  String get noBackgroundTasks;

  /// No description provided for @backgroundTaskSummary.
  ///
  /// In zh, this message translates to:
  /// **'{active} 项进行中 · {failed} 项需要处理'**
  String backgroundTaskSummary(int active, int failed);

  /// No description provided for @allTasksComplete.
  ///
  /// In zh, this message translates to:
  /// **'所有任务均已完成'**
  String get allTasksComplete;

  /// No description provided for @taskActionFailed.
  ///
  /// In zh, this message translates to:
  /// **'任务操作失败：{error}'**
  String taskActionFailed(String error);

  /// No description provided for @taskProgress.
  ///
  /// In zh, this message translates to:
  /// **'{title}进度'**
  String taskProgress(String title);

  /// No description provided for @audioTranscription.
  ///
  /// In zh, this message translates to:
  /// **'音频转写'**
  String get audioTranscription;

  /// No description provided for @liveDictation.
  ///
  /// In zh, this message translates to:
  /// **'实时听写'**
  String get liveDictation;

  /// No description provided for @readAloud.
  ///
  /// In zh, this message translates to:
  /// **'朗读'**
  String get readAloud;

  /// No description provided for @localInferenceInUse.
  ///
  /// In zh, this message translates to:
  /// **'正在使用本地推理资源'**
  String get localInferenceInUse;

  /// No description provided for @connectingModelSource.
  ///
  /// In zh, this message translates to:
  /// **'正在连接下载源'**
  String get connectingModelSource;

  /// No description provided for @downloadingModel.
  ///
  /// In zh, this message translates to:
  /// **'正在下载模型'**
  String get downloadingModel;

  /// No description provided for @importingModel.
  ///
  /// In zh, this message translates to:
  /// **'正在导入模型'**
  String get importingModel;

  /// No description provided for @waitingToInstall.
  ///
  /// In zh, this message translates to:
  /// **'等待安装资源'**
  String get waitingToInstall;

  /// No description provided for @verifyingAndInstalling.
  ///
  /// In zh, this message translates to:
  /// **'正在校验并安装'**
  String get verifyingAndInstalling;

  /// No description provided for @canceling.
  ///
  /// In zh, this message translates to:
  /// **'正在取消'**
  String get canceling;

  /// No description provided for @completed.
  ///
  /// In zh, this message translates to:
  /// **'已完成'**
  String get completed;

  /// No description provided for @failed.
  ///
  /// In zh, this message translates to:
  /// **'失败'**
  String get failed;

  /// No description provided for @canceled.
  ///
  /// In zh, this message translates to:
  /// **'已取消'**
  String get canceled;

  /// No description provided for @modelTaskFailed.
  ///
  /// In zh, this message translates to:
  /// **'模型任务失败'**
  String get modelTaskFailed;

  /// No description provided for @importingAttachment.
  ///
  /// In zh, this message translates to:
  /// **'正在导入附件'**
  String get importingAttachment;

  /// No description provided for @savingToNote.
  ///
  /// In zh, this message translates to:
  /// **'正在保存到笔记'**
  String get savingToNote;

  /// No description provided for @attachmentImportFailed.
  ///
  /// In zh, this message translates to:
  /// **'附件导入失败'**
  String get attachmentImportFailed;

  /// No description provided for @transcriptionFailed.
  ///
  /// In zh, this message translates to:
  /// **'转写失败'**
  String get transcriptionFailed;

  /// No description provided for @preparingTranscription.
  ///
  /// In zh, this message translates to:
  /// **'正在准备转写'**
  String get preparingTranscription;

  /// No description provided for @decodingAudio.
  ///
  /// In zh, this message translates to:
  /// **'正在解码音频'**
  String get decodingAudio;

  /// No description provided for @identifyingSpeakers.
  ///
  /// In zh, this message translates to:
  /// **'正在区分说话人'**
  String get identifyingSpeakers;

  /// No description provided for @recognizingSpeech.
  ///
  /// In zh, this message translates to:
  /// **'正在识别语音'**
  String get recognizingSpeech;

  /// No description provided for @savingTranscript.
  ///
  /// In zh, this message translates to:
  /// **'正在保存转写'**
  String get savingTranscript;

  /// No description provided for @systemAuthentication.
  ///
  /// In zh, this message translates to:
  /// **'使用系统身份验证'**
  String get systemAuthentication;

  /// No description provided for @systemAuthenticationDescription.
  ///
  /// In zh, this message translates to:
  /// **'通过设备已有的指纹、人脸识别或锁屏密码解锁。FKNotes 不会读取或保存你的生物特征。'**
  String get systemAuthenticationDescription;

  /// No description provided for @enableAppLock.
  ///
  /// In zh, this message translates to:
  /// **'启用应用锁'**
  String get enableAppLock;

  /// No description provided for @appLockEnabledDescription.
  ///
  /// In zh, this message translates to:
  /// **'打开应用时会验证设备身份'**
  String get appLockEnabledDescription;

  /// No description provided for @appLockDisabledDescription.
  ///
  /// In zh, this message translates to:
  /// **'默认关闭，不影响现有数据'**
  String get appLockDisabledDescription;

  /// No description provided for @autoLockAfterLeaving.
  ///
  /// In zh, this message translates to:
  /// **'离开应用后自动锁定'**
  String get autoLockAfterLeaving;

  /// No description provided for @lockNow.
  ///
  /// In zh, this message translates to:
  /// **'立即锁定'**
  String get lockNow;

  /// No description provided for @appLockLimitDescription.
  ///
  /// In zh, this message translates to:
  /// **'应用锁用于阻止他人在已解锁设备上直接查看内容，不会加密数据库、附件或已经导出的备份。'**
  String get appLockLimitDescription;

  /// No description provided for @privacyProtection.
  ///
  /// In zh, this message translates to:
  /// **'隐私保护'**
  String get privacyProtection;

  /// No description provided for @systemAuthenticationPrivacyFooter.
  ///
  /// In zh, this message translates to:
  /// **'系统身份验证 · 本地内容保持私密'**
  String get systemAuthenticationPrivacyFooter;

  /// No description provided for @waitingForSystemAuthentication.
  ///
  /// In zh, this message translates to:
  /// **'正在等待系统身份验证'**
  String get waitingForSystemAuthentication;

  /// No description provided for @preparingAppLock.
  ///
  /// In zh, this message translates to:
  /// **'正在准备应用锁'**
  String get preparingAppLock;

  /// No description provided for @waitingForSystemVerification.
  ///
  /// In zh, this message translates to:
  /// **'等待系统验证'**
  String get waitingForSystemVerification;

  /// No description provided for @appLocked.
  ///
  /// In zh, this message translates to:
  /// **'应用已锁定'**
  String get appLocked;

  /// No description provided for @loadingLocalSecuritySettings.
  ///
  /// In zh, this message translates to:
  /// **'正在载入本地安全设置'**
  String get loadingLocalSecuritySettings;

  /// No description provided for @completeSystemAuthentication.
  ///
  /// In zh, this message translates to:
  /// **'请在系统弹窗中完成身份验证'**
  String get completeSystemAuthentication;

  /// No description provided for @unlockAppDescription.
  ///
  /// In zh, this message translates to:
  /// **'验证设备身份后继续使用非空笔记'**
  String get unlockAppDescription;

  /// No description provided for @authenticateAndUnlock.
  ///
  /// In zh, this message translates to:
  /// **'验证并解锁'**
  String get authenticateAndUnlock;

  /// No description provided for @contentHidden.
  ///
  /// In zh, this message translates to:
  /// **'内容已隐藏'**
  String get contentHidden;

  /// No description provided for @authenticateToContinue.
  ///
  /// In zh, this message translates to:
  /// **'验证设备身份以继续'**
  String get authenticateToContinue;

  /// No description provided for @authenticateToEnableAppLock.
  ///
  /// In zh, this message translates to:
  /// **'验证设备身份以开启应用锁'**
  String get authenticateToEnableAppLock;

  /// No description provided for @authenticateToDisableAppLock.
  ///
  /// In zh, this message translates to:
  /// **'验证设备身份以关闭应用锁'**
  String get authenticateToDisableAppLock;

  /// No description provided for @useDevicePassword.
  ///
  /// In zh, this message translates to:
  /// **'使用设备密码'**
  String get useDevicePassword;

  /// No description provided for @authenticationCanceled.
  ///
  /// In zh, this message translates to:
  /// **'认证已取消'**
  String get authenticationCanceled;

  /// No description provided for @authenticationFailedRetry.
  ///
  /// In zh, this message translates to:
  /// **'身份验证失败，请重试'**
  String get authenticationFailedRetry;

  /// No description provided for @authenticationTemporarilyUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'暂时无法调用系统身份验证，请稍后重试'**
  String get authenticationTemporarilyUnavailable;

  /// No description provided for @authenticationCredentialsRequired.
  ///
  /// In zh, this message translates to:
  /// **'请先在系统设置中配置锁屏密码、指纹或人脸识别'**
  String get authenticationCredentialsRequired;

  /// No description provided for @authenticationUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'当前设备无法使用系统身份验证'**
  String get authenticationUnavailable;

  /// No description provided for @authenticationLockedOut.
  ///
  /// In zh, this message translates to:
  /// **'尝试次数过多，请使用设备密码或稍后重试'**
  String get authenticationLockedOut;

  /// No description provided for @authenticationInProgress.
  ///
  /// In zh, this message translates to:
  /// **'系统身份验证正在进行'**
  String get authenticationInProgress;

  /// No description provided for @authenticationUiUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'暂时无法显示系统身份验证界面'**
  String get authenticationUiUnavailable;

  /// No description provided for @appLockSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'应用锁设置保存失败，请检查设备存储空间'**
  String get appLockSaveFailed;

  /// No description provided for @autoLockSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'自动锁定时间保存失败，请检查设备存储空间'**
  String get autoLockSaveFailed;

  /// No description provided for @back.
  ///
  /// In zh, this message translates to:
  /// **'返回'**
  String get back;

  /// No description provided for @syncMethod.
  ///
  /// In zh, this message translates to:
  /// **'同步方式'**
  String get syncMethod;

  /// No description provided for @saveConfiguration.
  ///
  /// In zh, this message translates to:
  /// **'保存配置'**
  String get saveConfiguration;

  /// No description provided for @testConnection.
  ///
  /// In zh, this message translates to:
  /// **'测试连接'**
  String get testConnection;

  /// No description provided for @syncing.
  ///
  /// In zh, this message translates to:
  /// **'正在同步…'**
  String get syncing;

  /// No description provided for @syncNow.
  ///
  /// In zh, this message translates to:
  /// **'立即同步'**
  String get syncNow;

  /// No description provided for @manualSyncForegroundHint.
  ///
  /// In zh, this message translates to:
  /// **'同步期间请保持应用在前台。只有手动点击“立即同步”才会连接云端。'**
  String get manualSyncForegroundHint;

  /// No description provided for @serverAddress.
  ///
  /// In zh, this message translates to:
  /// **'服务器地址'**
  String get serverAddress;

  /// No description provided for @username.
  ///
  /// In zh, this message translates to:
  /// **'用户名'**
  String get username;

  /// No description provided for @passwordOrAppPassword.
  ///
  /// In zh, this message translates to:
  /// **'密码或应用专用密码'**
  String get passwordOrAppPassword;

  /// No description provided for @remoteDirectory.
  ///
  /// In zh, this message translates to:
  /// **'远程目录'**
  String get remoteDirectory;

  /// No description provided for @objectPrefix.
  ///
  /// In zh, this message translates to:
  /// **'对象前缀'**
  String get objectPrefix;

  /// No description provided for @pathStyleAddress.
  ///
  /// In zh, this message translates to:
  /// **'Path-style 地址'**
  String get pathStyleAddress;

  /// No description provided for @pathStyleDescription.
  ///
  /// In zh, this message translates to:
  /// **'MinIO、多数兼容 S3 的对象存储通常需要开启'**
  String get pathStyleDescription;

  /// No description provided for @hide.
  ///
  /// In zh, this message translates to:
  /// **'隐藏'**
  String get hide;

  /// No description provided for @show.
  ///
  /// In zh, this message translates to:
  /// **'显示'**
  String get show;

  /// No description provided for @cloudConfigurationSaved.
  ///
  /// In zh, this message translates to:
  /// **'云同步配置已保存在本机'**
  String get cloudConfigurationSaved;

  /// No description provided for @connectionSuccessful.
  ///
  /// In zh, this message translates to:
  /// **'连接成功，云端读写权限正常'**
  String get connectionSuccessful;

  /// No description provided for @syncConflictDetected.
  ///
  /// In zh, this message translates to:
  /// **'检测到同步冲突'**
  String get syncConflictDetected;

  /// No description provided for @syncConflictDescription.
  ///
  /// In zh, this message translates to:
  /// **'本机数据与云端数据都可能有变更。\n\n云端版本：{date}\n请选择要保留的一份；另一份将被覆盖。'**
  String syncConflictDescription(String date);

  /// No description provided for @notNow.
  ///
  /// In zh, this message translates to:
  /// **'暂不处理'**
  String get notNow;

  /// No description provided for @useCloudVersion.
  ///
  /// In zh, this message translates to:
  /// **'使用云端'**
  String get useCloudVersion;

  /// No description provided for @keepLocalVersion.
  ///
  /// In zh, this message translates to:
  /// **'保留本机'**
  String get keepLocalVersion;

  /// No description provided for @syncedLocalToCloud.
  ///
  /// In zh, this message translates to:
  /// **'本机数据已同步到云端'**
  String get syncedLocalToCloud;

  /// No description provided for @updatedFromCloud.
  ///
  /// In zh, this message translates to:
  /// **'已使用云端数据更新本机'**
  String get updatedFromCloud;

  /// No description provided for @cloudAlreadyUpToDate.
  ///
  /// In zh, this message translates to:
  /// **'本机与云端数据已经一致'**
  String get cloudAlreadyUpToDate;

  /// No description provided for @syncConflictUnresolved.
  ///
  /// In zh, this message translates to:
  /// **'同步冲突尚未处理'**
  String get syncConflictUnresolved;

  /// No description provided for @httpsCertificateFailed.
  ///
  /// In zh, this message translates to:
  /// **'HTTPS 证书验证失败，请检查服务器证书'**
  String get httpsCertificateFailed;

  /// No description provided for @cloudConnectionFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法连接云端，请检查网络和服务器地址'**
  String get cloudConnectionFailed;

  /// No description provided for @cloudConnectionTimeout.
  ///
  /// In zh, this message translates to:
  /// **'连接云端超时'**
  String get cloudConnectionTimeout;

  /// No description provided for @manualUserDataSync.
  ///
  /// In zh, this message translates to:
  /// **'仅手动同步用户数据'**
  String get manualUserDataSync;

  /// No description provided for @syncScopeDescription.
  ///
  /// In zh, this message translates to:
  /// **'包含笔记、聊天和附件；不包含模型、缓存、应用锁和云端账号配置。'**
  String get syncScopeDescription;

  /// No description provided for @cloudEncryptionWarning.
  ///
  /// In zh, this message translates to:
  /// **'云端归档不额外加密，请使用 HTTPS 与可信存储。'**
  String get cloudEncryptionWarning;

  /// No description provided for @lastSyncedAt.
  ///
  /// In zh, this message translates to:
  /// **'上次同步：{date}'**
  String lastSyncedAt(String date);

  /// No description provided for @cut.
  ///
  /// In zh, this message translates to:
  /// **'剪切'**
  String get cut;

  /// No description provided for @copy.
  ///
  /// In zh, this message translates to:
  /// **'复制'**
  String get copy;

  /// No description provided for @paste.
  ///
  /// In zh, this message translates to:
  /// **'粘贴'**
  String get paste;

  /// No description provided for @selectAll.
  ///
  /// In zh, this message translates to:
  /// **'全选'**
  String get selectAll;

  /// No description provided for @share.
  ///
  /// In zh, this message translates to:
  /// **'分享'**
  String get share;

  /// No description provided for @invalidExternalLink.
  ///
  /// In zh, this message translates to:
  /// **'这个链接地址无效或使用了不受支持的协议'**
  String get invalidExternalLink;

  /// No description provided for @openExternalLinkQuestion.
  ///
  /// In zh, this message translates to:
  /// **'打开外部链接？'**
  String get openExternalLinkQuestion;

  /// No description provided for @externalLinkWarning.
  ///
  /// In zh, this message translates to:
  /// **'{destination}\n\n链接将交给系统中的其他应用处理，可能离开 FKNotes。'**
  String externalLinkWarning(String destination);

  /// No description provided for @continueOpening.
  ///
  /// In zh, this message translates to:
  /// **'继续打开'**
  String get continueOpening;

  /// No description provided for @noExternalLinkHandler.
  ///
  /// In zh, this message translates to:
  /// **'系统中没有可以打开这个链接的应用'**
  String get noExternalLinkHandler;

  /// No description provided for @externalLinkOpenFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法打开这个链接'**
  String get externalLinkOpenFailed;

  /// No description provided for @remoteImageBlocked.
  ///
  /// In zh, this message translates to:
  /// **'未加载外部图片：{label}'**
  String remoteImageBlocked(String label);

  /// No description provided for @mathFormulaSemantics.
  ///
  /// In zh, this message translates to:
  /// **'数学公式：{formula}'**
  String mathFormulaSemantics(String formula);

  /// No description provided for @assistantPrivacyDescription.
  ///
  /// In zh, this message translates to:
  /// **'直接告诉 AI 你想做什么。笔记内容只在设备上处理。'**
  String get assistantPrivacyDescription;

  /// No description provided for @processingScope.
  ///
  /// In zh, this message translates to:
  /// **'处理范围'**
  String get processingScope;

  /// No description provided for @scopeSelection.
  ///
  /// In zh, this message translates to:
  /// **'选中文字'**
  String get scopeSelection;

  /// No description provided for @scopeCurrentBlock.
  ///
  /// In zh, this message translates to:
  /// **'当前段落'**
  String get scopeCurrentBlock;

  /// No description provided for @scopeFullNote.
  ///
  /// In zh, this message translates to:
  /// **'整篇笔记'**
  String get scopeFullNote;

  /// No description provided for @chatWithThisNote.
  ///
  /// In zh, this message translates to:
  /// **'和这篇笔记对话'**
  String get chatWithThisNote;

  /// No description provided for @chatWithThisNoteDescription.
  ///
  /// In zh, this message translates to:
  /// **'把所选范围作为上下文，连续追问和整理'**
  String get chatWithThisNoteDescription;

  /// No description provided for @linkedNote.
  ///
  /// In zh, this message translates to:
  /// **'关联笔记'**
  String get linkedNote;

  /// No description provided for @noteSources.
  ///
  /// In zh, this message translates to:
  /// **'笔记来源'**
  String get noteSources;

  /// No description provided for @writeReplyToNote.
  ///
  /// In zh, this message translates to:
  /// **'写入笔记'**
  String get writeReplyToNote;

  /// No description provided for @writeReplyToNoteDescription.
  ///
  /// In zh, this message translates to:
  /// **'预览内容并确认写入位置'**
  String get writeReplyToNoteDescription;

  /// No description provided for @confirmWriteToNote.
  ///
  /// In zh, this message translates to:
  /// **'确认写入'**
  String get confirmWriteToNote;

  /// No description provided for @replyWrittenToNote.
  ///
  /// In zh, this message translates to:
  /// **'回答已写入笔记'**
  String get replyWrittenToNote;

  /// No description provided for @replyWriteToNoteFailed.
  ///
  /// In zh, this message translates to:
  /// **'笔记内容已经变化，请返回笔记后重试'**
  String get replyWriteToNoteFailed;

  /// No description provided for @assistantChatResultHeading.
  ///
  /// In zh, this message translates to:
  /// **'本地助手回答'**
  String get assistantChatResultHeading;

  /// No description provided for @chatNoteEmpty.
  ///
  /// In zh, this message translates to:
  /// **'请先输入笔记内容，再开始对话'**
  String get chatNoteEmpty;

  /// No description provided for @assistantCustomHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：把这些想法整理成一封简洁的英文邮件…'**
  String get assistantCustomHint;

  /// No description provided for @startGenerating.
  ///
  /// In zh, this message translates to:
  /// **'开始生成'**
  String get startGenerating;

  /// No description provided for @quickActions.
  ///
  /// In zh, this message translates to:
  /// **'快捷操作'**
  String get quickActions;

  /// No description provided for @assistantSummarize.
  ///
  /// In zh, this message translates to:
  /// **'总结笔记'**
  String get assistantSummarize;

  /// No description provided for @assistantSummarizeDescription.
  ///
  /// In zh, this message translates to:
  /// **'提炼核心结论与关键要点'**
  String get assistantSummarizeDescription;

  /// No description provided for @assistantExtractTodos.
  ///
  /// In zh, this message translates to:
  /// **'提取待办'**
  String get assistantExtractTodos;

  /// No description provided for @assistantExtractTodosDescription.
  ///
  /// In zh, this message translates to:
  /// **'找出明确、可执行的事项'**
  String get assistantExtractTodosDescription;

  /// No description provided for @assistantPolish.
  ///
  /// In zh, this message translates to:
  /// **'润色内容'**
  String get assistantPolish;

  /// No description provided for @assistantPolishDescription.
  ///
  /// In zh, this message translates to:
  /// **'保留事实与结构，改善表达'**
  String get assistantPolishDescription;

  /// No description provided for @assistantCustomAction.
  ///
  /// In zh, this message translates to:
  /// **'自定义指令'**
  String get assistantCustomAction;

  /// No description provided for @assistantNoOutput.
  ///
  /// In zh, this message translates to:
  /// **'模型没有生成内容'**
  String get assistantNoOutput;

  /// No description provided for @stopGenerating.
  ///
  /// In zh, this message translates to:
  /// **'停止生成'**
  String get stopGenerating;

  /// No description provided for @regenerate.
  ///
  /// In zh, this message translates to:
  /// **'重新生成'**
  String get regenerate;

  /// No description provided for @chooseGeneratedContentPlacement.
  ///
  /// In zh, this message translates to:
  /// **'选择如何使用生成内容'**
  String get chooseGeneratedContentPlacement;

  /// No description provided for @placementReplace.
  ///
  /// In zh, this message translates to:
  /// **'替换原内容'**
  String get placementReplace;

  /// No description provided for @placementInsertBelow.
  ///
  /// In zh, this message translates to:
  /// **'插入到段落下方'**
  String get placementInsertBelow;

  /// No description provided for @placementAppend.
  ///
  /// In zh, this message translates to:
  /// **'追加到笔记末尾'**
  String get placementAppend;

  /// No description provided for @useCurrentContent.
  ///
  /// In zh, this message translates to:
  /// **'使用当前内容'**
  String get useCurrentContent;

  /// No description provided for @useGeneratedContent.
  ///
  /// In zh, this message translates to:
  /// **'使用生成内容'**
  String get useGeneratedContent;

  /// No description provided for @generatedContentCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制生成内容'**
  String get generatedContentCopied;

  /// No description provided for @loadingLocalModel.
  ///
  /// In zh, this message translates to:
  /// **'正在加载本地模型…'**
  String get loadingLocalModel;

  /// No description provided for @generatingOnDevice.
  ///
  /// In zh, this message translates to:
  /// **'正在设备上生成…'**
  String get generatingOnDevice;

  /// No description provided for @generationCompleted.
  ///
  /// In zh, this message translates to:
  /// **'生成完成，请检查后使用'**
  String get generationCompleted;

  /// No description provided for @generationLimitReached.
  ///
  /// In zh, this message translates to:
  /// **'已达到输出上限，请检查结果'**
  String get generationLimitReached;

  /// No description provided for @generationStoppedUsable.
  ///
  /// In zh, this message translates to:
  /// **'生成已停止，可复制或插入当前内容'**
  String get generationStoppedUsable;

  /// No description provided for @generationTimedOutUsable.
  ///
  /// In zh, this message translates to:
  /// **'生成超时，可重试或复制当前内容'**
  String get generationTimedOutUsable;

  /// No description provided for @generationIncomplete.
  ///
  /// In zh, this message translates to:
  /// **'本地生成未完成'**
  String get generationIncomplete;

  /// No description provided for @retry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get retry;

  /// No description provided for @maybeLater.
  ///
  /// In zh, this message translates to:
  /// **'稍后再说'**
  String get maybeLater;

  /// No description provided for @readNoteAloud.
  ///
  /// In zh, this message translates to:
  /// **'朗读笔记'**
  String get readNoteAloud;

  /// No description provided for @offlineReadAloudModelRequired.
  ///
  /// In zh, this message translates to:
  /// **'需要离线朗读模型'**
  String get offlineReadAloudModelRequired;

  /// No description provided for @readAloudModelDownloadDescription.
  ///
  /// In zh, this message translates to:
  /// **'Kokoro 中英双语 INT8 首次使用需下载约 140.2 MB。下载后，笔记朗读全程断网可用。'**
  String get readAloudModelDownloadDescription;

  /// No description provided for @manageModels.
  ///
  /// In zh, this message translates to:
  /// **'管理模型'**
  String get manageModels;

  /// No description provided for @noteReadAloudFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法朗读这篇笔记'**
  String get noteReadAloudFailed;

  /// No description provided for @liveDictationIncomplete.
  ///
  /// In zh, this message translates to:
  /// **'实时听写没有完成'**
  String get liveDictationIncomplete;

  /// No description provided for @unsavedDraftFound.
  ///
  /// In zh, this message translates to:
  /// **'发现未保存的草稿'**
  String get unsavedDraftFound;

  /// No description provided for @unsavedDraftDescription.
  ///
  /// In zh, this message translates to:
  /// **'上次编辑可能意外中断。要恢复尚未写入笔记的内容吗？'**
  String get unsavedDraftDescription;

  /// No description provided for @discardDraft.
  ///
  /// In zh, this message translates to:
  /// **'放弃草稿'**
  String get discardDraft;

  /// No description provided for @restore.
  ///
  /// In zh, this message translates to:
  /// **'恢复'**
  String get restore;

  /// No description provided for @liveSpeechModelRequired.
  ///
  /// In zh, this message translates to:
  /// **'需要实时语音模型'**
  String get liveSpeechModelRequired;

  /// No description provided for @liveSpeechModelDownloadDescription.
  ///
  /// In zh, this message translates to:
  /// **'当前选择的是{model}，首次使用需下载约 {size}。下载完成后，听写全程断网可用。'**
  String liveSpeechModelDownloadDescription(String model, String size);

  /// No description provided for @placeCursorInText.
  ///
  /// In zh, this message translates to:
  /// **'请先将光标放在文字区域'**
  String get placeCursorInText;

  /// No description provided for @liveDictationStartFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法开始实时听写'**
  String get liveDictationStartFailed;

  /// No description provided for @localLanguageModelRequired.
  ///
  /// In zh, this message translates to:
  /// **'需要本地语言模型'**
  String get localLanguageModelRequired;

  /// No description provided for @localLanguageModelDownloadDescription.
  ///
  /// In zh, this message translates to:
  /// **'当前选择的是 {model}，首次使用需下载约 {size}。下载完成后，笔记内容只在本机处理。'**
  String localLanguageModelDownloadDescription(String model, String size);

  /// No description provided for @assistantReplacedContent.
  ///
  /// In zh, this message translates to:
  /// **'已替换原内容'**
  String get assistantReplacedContent;

  /// No description provided for @assistantInsertedBelow.
  ///
  /// In zh, this message translates to:
  /// **'已插入到当前段落下方'**
  String get assistantInsertedBelow;

  /// No description provided for @assistantAppended.
  ///
  /// In zh, this message translates to:
  /// **'已追加到笔记末尾'**
  String get assistantAppended;

  /// No description provided for @noteChangedRetryAssistant.
  ///
  /// In zh, this message translates to:
  /// **'笔记内容已经变化，请重新发起 AI 操作'**
  String get noteChangedRetryAssistant;

  /// No description provided for @assistantLaunchFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法启动本地助手：{error}'**
  String assistantLaunchFailed(String error);

  /// No description provided for @autosaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'自动保存失败：{error}'**
  String autosaveFailed(String error);

  /// No description provided for @addToNote.
  ///
  /// In zh, this message translates to:
  /// **'添加到笔记'**
  String get addToNote;

  /// No description provided for @camera.
  ///
  /// In zh, this message translates to:
  /// **'拍照'**
  String get camera;

  /// No description provided for @attachmentImportTypeFailed.
  ///
  /// In zh, this message translates to:
  /// **'{type}导入失败'**
  String attachmentImportTypeFailed(String type);

  /// No description provided for @editNote.
  ///
  /// In zh, this message translates to:
  /// **'编辑笔记'**
  String get editNote;

  /// No description provided for @newNote.
  ///
  /// In zh, this message translates to:
  /// **'新笔记'**
  String get newNote;

  /// No description provided for @savingEllipsis.
  ///
  /// In zh, this message translates to:
  /// **'正在保存…'**
  String get savingEllipsis;

  /// No description provided for @localDraft.
  ///
  /// In zh, this message translates to:
  /// **'本地草稿'**
  String get localDraft;

  /// No description provided for @savedLocally.
  ///
  /// In zh, this message translates to:
  /// **'已保存在本机'**
  String get savedLocally;

  /// No description provided for @characterCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 字'**
  String characterCount(int count);

  /// No description provided for @stopReadAloud.
  ///
  /// In zh, this message translates to:
  /// **'停止朗读'**
  String get stopReadAloud;

  /// No description provided for @moreNoteActions.
  ///
  /// In zh, this message translates to:
  /// **'更多笔记操作'**
  String get moreNoteActions;

  /// No description provided for @removeFavorite.
  ///
  /// In zh, this message translates to:
  /// **'取消收藏'**
  String get removeFavorite;

  /// No description provided for @addFavorite.
  ///
  /// In zh, this message translates to:
  /// **'收藏'**
  String get addFavorite;

  /// No description provided for @unpin.
  ///
  /// In zh, this message translates to:
  /// **'取消置顶'**
  String get unpin;

  /// No description provided for @pin.
  ///
  /// In zh, this message translates to:
  /// **'置顶'**
  String get pin;

  /// No description provided for @addTags.
  ///
  /// In zh, this message translates to:
  /// **'添加标签'**
  String get addTags;

  /// No description provided for @tags.
  ///
  /// In zh, this message translates to:
  /// **'标签'**
  String get tags;

  /// No description provided for @noteContent.
  ///
  /// In zh, this message translates to:
  /// **'笔记内容'**
  String get noteContent;

  /// No description provided for @attachmentItemCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 项附件'**
  String attachmentItemCount(int count);

  /// No description provided for @noteDescriptionHint.
  ///
  /// In zh, this message translates to:
  /// **'添加说明、想法或摘要…'**
  String get noteDescriptionHint;

  /// No description provided for @noteStartHint.
  ///
  /// In zh, this message translates to:
  /// **'开始记录…'**
  String get noteStartHint;

  /// No description provided for @addMediaOrFile.
  ///
  /// In zh, this message translates to:
  /// **'添加图片、录音或文件'**
  String get addMediaOrFile;

  /// No description provided for @editTags.
  ///
  /// In zh, this message translates to:
  /// **'编辑标签'**
  String get editTags;

  /// No description provided for @tagsDescription.
  ///
  /// In zh, this message translates to:
  /// **'使用逗号分隔多个标签，重复标签会自动合并。'**
  String get tagsDescription;

  /// No description provided for @tagsHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：工作, 灵感, 稍后阅读'**
  String get tagsHint;

  /// No description provided for @stopLiveDictation.
  ///
  /// In zh, this message translates to:
  /// **'停止实时听写'**
  String get stopLiveDictation;

  /// No description provided for @liveVoiceInput.
  ///
  /// In zh, this message translates to:
  /// **'实时语音输入'**
  String get liveVoiceInput;

  /// No description provided for @redo.
  ///
  /// In zh, this message translates to:
  /// **'重做'**
  String get redo;

  /// No description provided for @bold.
  ///
  /// In zh, this message translates to:
  /// **'加粗'**
  String get bold;

  /// No description provided for @italic.
  ///
  /// In zh, this message translates to:
  /// **'斜体'**
  String get italic;

  /// No description provided for @underline.
  ///
  /// In zh, this message translates to:
  /// **'下划线'**
  String get underline;

  /// No description provided for @addLink.
  ///
  /// In zh, this message translates to:
  /// **'添加链接'**
  String get addLink;

  /// No description provided for @editLink.
  ///
  /// In zh, this message translates to:
  /// **'编辑链接'**
  String get editLink;

  /// No description provided for @linkPrivacyDescription.
  ///
  /// In zh, this message translates to:
  /// **'链接会保存在 Markdown 中；打开前仍会由 FKNotes 进行隐私确认。'**
  String get linkPrivacyDescription;

  /// No description provided for @linkAddress.
  ///
  /// In zh, this message translates to:
  /// **'链接地址'**
  String get linkAddress;

  /// No description provided for @removeLink.
  ///
  /// In zh, this message translates to:
  /// **'移除链接'**
  String get removeLink;

  /// No description provided for @organizingLastSentence.
  ///
  /// In zh, this message translates to:
  /// **'正在整理最后一句…'**
  String get organizingLastSentence;

  /// No description provided for @liveDictationFailed.
  ///
  /// In zh, this message translates to:
  /// **'实时听写失败'**
  String get liveDictationFailed;

  /// No description provided for @listening.
  ///
  /// In zh, this message translates to:
  /// **'正在聆听…'**
  String get listening;

  /// No description provided for @liveDictationElapsed.
  ///
  /// In zh, this message translates to:
  /// **'实时听写  {time}'**
  String liveDictationElapsed(String time);

  /// No description provided for @localVoiceInput.
  ///
  /// In zh, this message translates to:
  /// **'本地语音输入'**
  String get localVoiceInput;

  /// No description provided for @cancelDictation.
  ///
  /// In zh, this message translates to:
  /// **'取消听写'**
  String get cancelDictation;

  /// No description provided for @finishDictation.
  ///
  /// In zh, this message translates to:
  /// **'完成听写'**
  String get finishDictation;

  /// No description provided for @paragraph.
  ///
  /// In zh, this message translates to:
  /// **'正文'**
  String get paragraph;

  /// No description provided for @paragraphStyle.
  ///
  /// In zh, this message translates to:
  /// **'段落样式'**
  String get paragraphStyle;

  /// No description provided for @headingLevel.
  ///
  /// In zh, this message translates to:
  /// **'标题 {level}'**
  String headingLevel(int level);

  /// No description provided for @quote.
  ///
  /// In zh, this message translates to:
  /// **'引用'**
  String get quote;

  /// No description provided for @codeBlock.
  ///
  /// In zh, this message translates to:
  /// **'代码块'**
  String get codeBlock;

  /// No description provided for @divider.
  ///
  /// In zh, this message translates to:
  /// **'分割线'**
  String get divider;

  /// No description provided for @listsAndIndentation.
  ///
  /// In zh, this message translates to:
  /// **'列表与缩进'**
  String get listsAndIndentation;

  /// No description provided for @todoItem.
  ///
  /// In zh, this message translates to:
  /// **'待办事项'**
  String get todoItem;

  /// No description provided for @bulletList.
  ///
  /// In zh, this message translates to:
  /// **'无序列表'**
  String get bulletList;

  /// No description provided for @numberedList.
  ///
  /// In zh, this message translates to:
  /// **'有序列表'**
  String get numberedList;

  /// No description provided for @decreaseIndent.
  ///
  /// In zh, this message translates to:
  /// **'减少缩进'**
  String get decreaseIndent;

  /// No description provided for @increaseIndent.
  ///
  /// In zh, this message translates to:
  /// **'增加缩进'**
  String get increaseIndent;

  /// No description provided for @moreFormatting.
  ///
  /// In zh, this message translates to:
  /// **'更多格式'**
  String get moreFormatting;

  /// No description provided for @strikethrough.
  ///
  /// In zh, this message translates to:
  /// **'删除线'**
  String get strikethrough;

  /// No description provided for @inlineCode.
  ///
  /// In zh, this message translates to:
  /// **'行内代码'**
  String get inlineCode;

  /// No description provided for @generatingThumbnail.
  ///
  /// In zh, this message translates to:
  /// **'正在生成缩略图…'**
  String get generatingThumbnail;

  /// No description provided for @importingBytes.
  ///
  /// In zh, this message translates to:
  /// **'正在导入 · {bytes}'**
  String importingBytes(String bytes);

  /// No description provided for @importingPercent.
  ///
  /// In zh, this message translates to:
  /// **'正在导入 {percent}% · {bytes}'**
  String importingPercent(int percent, String bytes);

  /// No description provided for @importCompleteSaving.
  ///
  /// In zh, this message translates to:
  /// **'导入完成，正在保存到笔记…'**
  String get importCompleteSaving;

  /// No description provided for @importFailedRetry.
  ///
  /// In zh, this message translates to:
  /// **'导入失败，请重试'**
  String get importFailedRetry;

  /// No description provided for @importCanceled.
  ///
  /// In zh, this message translates to:
  /// **'导入已取消'**
  String get importCanceled;

  /// No description provided for @cancelImport.
  ///
  /// In zh, this message translates to:
  /// **'取消导入'**
  String get cancelImport;

  /// No description provided for @chooseTypeAgain.
  ///
  /// In zh, this message translates to:
  /// **'重新选择{type}'**
  String chooseTypeAgain(String type);

  /// No description provided for @adjustAttachment.
  ///
  /// In zh, this message translates to:
  /// **'调整附件'**
  String get adjustAttachment;

  /// No description provided for @moveUp.
  ///
  /// In zh, this message translates to:
  /// **'上移'**
  String get moveUp;

  /// No description provided for @moveDown.
  ///
  /// In zh, this message translates to:
  /// **'下移'**
  String get moveDown;

  /// No description provided for @referenceInBody.
  ///
  /// In zh, this message translates to:
  /// **'引用到正文'**
  String get referenceInBody;

  /// No description provided for @importFailedDetail.
  ///
  /// In zh, this message translates to:
  /// **'导入失败 · {error}'**
  String importFailedDetail(String error);

  /// No description provided for @assistantSummaryHeading.
  ///
  /// In zh, this message translates to:
  /// **'本地助手摘要'**
  String get assistantSummaryHeading;

  /// No description provided for @assistantTodosHeading.
  ///
  /// In zh, this message translates to:
  /// **'本地助手待办'**
  String get assistantTodosHeading;

  /// No description provided for @assistantPolishedHeading.
  ///
  /// In zh, this message translates to:
  /// **'本地助手润色稿'**
  String get assistantPolishedHeading;

  /// No description provided for @assistantGeneratedHeading.
  ///
  /// In zh, this message translates to:
  /// **'AI 生成内容'**
  String get assistantGeneratedHeading;

  /// No description provided for @attachmentReference.
  ///
  /// In zh, this message translates to:
  /// **'附件引用：{path}'**
  String attachmentReference(String path);

  /// No description provided for @markdownTable.
  ///
  /// In zh, this message translates to:
  /// **'Markdown 表格'**
  String get markdownTable;

  /// No description provided for @tableDimensions.
  ///
  /// In zh, this message translates to:
  /// **'{columns} 列 · {rows} 行'**
  String tableDimensions(int columns, int rows);

  /// No description provided for @deleteTable.
  ///
  /// In zh, this message translates to:
  /// **'删除表格'**
  String get deleteTable;

  /// No description provided for @editTable.
  ///
  /// In zh, this message translates to:
  /// **'编辑表格'**
  String get editTable;

  /// No description provided for @invalidMarkdownTable.
  ///
  /// In zh, this message translates to:
  /// **'表格语法不完整，请先检查 Markdown 原文'**
  String get invalidMarkdownTable;

  /// No description provided for @attachmentRemoved.
  ///
  /// In zh, this message translates to:
  /// **'附件已移除'**
  String get attachmentRemoved;

  /// No description provided for @brokenAttachmentReference.
  ///
  /// In zh, this message translates to:
  /// **'这个引用已失效，可以移除引用'**
  String get brokenAttachmentReference;

  /// No description provided for @attachmentReferenceDescription.
  ///
  /// In zh, this message translates to:
  /// **'{type} · {size} · 点击预览'**
  String attachmentReferenceDescription(String type, String size);

  /// No description provided for @removeReference.
  ///
  /// In zh, this message translates to:
  /// **'移除引用'**
  String get removeReference;

  /// No description provided for @tableEditorDescription.
  ///
  /// In zh, this message translates to:
  /// **'{columns} 列 · {rows} 行 · 左右滑动查看全部列'**
  String tableEditorDescription(int columns, int rows);

  /// No description provided for @addColumn.
  ///
  /// In zh, this message translates to:
  /// **'添加列'**
  String get addColumn;

  /// No description provided for @addRow.
  ///
  /// In zh, this message translates to:
  /// **'添加行'**
  String get addRow;

  /// No description provided for @deleteRow.
  ///
  /// In zh, this message translates to:
  /// **'删除第 {row} 行'**
  String deleteRow(int row);

  /// No description provided for @saveTable.
  ///
  /// In zh, this message translates to:
  /// **'保存表格'**
  String get saveTable;

  /// No description provided for @tableHeader.
  ///
  /// In zh, this message translates to:
  /// **'表头'**
  String get tableHeader;

  /// No description provided for @deleteColumn.
  ///
  /// In zh, this message translates to:
  /// **'删除列'**
  String get deleteColumn;

  /// No description provided for @cellAlignment.
  ///
  /// In zh, this message translates to:
  /// **'单元格对齐方式'**
  String get cellAlignment;

  /// No description provided for @alignLeft.
  ///
  /// In zh, this message translates to:
  /// **'左对齐'**
  String get alignLeft;

  /// No description provided for @alignCenter.
  ///
  /// In zh, this message translates to:
  /// **'居中'**
  String get alignCenter;

  /// No description provided for @alignRight.
  ///
  /// In zh, this message translates to:
  /// **'右对齐'**
  String get alignRight;

  /// No description provided for @content.
  ///
  /// In zh, this message translates to:
  /// **'内容'**
  String get content;

  /// No description provided for @untitled.
  ///
  /// In zh, this message translates to:
  /// **'无标题'**
  String get untitled;

  /// No description provided for @todayAt.
  ///
  /// In zh, this message translates to:
  /// **'今天 {time}'**
  String todayAt(String time);

  /// No description provided for @yesterdayAt.
  ///
  /// In zh, this message translates to:
  /// **'昨天 {time}'**
  String yesterdayAt(String time);

  /// No description provided for @quickNoteTile.
  ///
  /// In zh, this message translates to:
  /// **'随\n笔'**
  String get quickNoteTile;

  /// No description provided for @removeFromArchive.
  ///
  /// In zh, this message translates to:
  /// **'移出归档'**
  String get removeFromArchive;

  /// No description provided for @edit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get edit;

  /// No description provided for @moveToTrash.
  ///
  /// In zh, this message translates to:
  /// **'移到回收站'**
  String get moveToTrash;

  /// No description provided for @mixedAttachmentMetadata.
  ///
  /// In zh, this message translates to:
  /// **'混合 · {count} 项'**
  String mixedAttachmentMetadata(int count);

  /// No description provided for @imageAttachmentMetadata.
  ///
  /// In zh, this message translates to:
  /// **'图片 · {count} 张'**
  String imageAttachmentMetadata(int count);

  /// No description provided for @audioAttachmentMetadata.
  ///
  /// In zh, this message translates to:
  /// **'录音 · {count} 段'**
  String audioAttachmentMetadata(int count);

  /// No description provided for @videoAttachmentMetadata.
  ///
  /// In zh, this message translates to:
  /// **'视频 · {count} 个'**
  String videoAttachmentMetadata(int count);

  /// No description provided for @fileAttachmentMetadata.
  ///
  /// In zh, this message translates to:
  /// **'文件 · {count} 个'**
  String fileAttachmentMetadata(int count);

  /// No description provided for @localLanguageModel.
  ///
  /// In zh, this message translates to:
  /// **'本地语言模型'**
  String get localLanguageModel;

  /// No description provided for @conversationHistory.
  ///
  /// In zh, this message translates to:
  /// **'对话记录'**
  String get conversationHistory;

  /// No description provided for @personaManagement.
  ///
  /// In zh, this message translates to:
  /// **'角色管理'**
  String get personaManagement;

  /// No description provided for @moreConversationActions.
  ///
  /// In zh, this message translates to:
  /// **'更多对话操作'**
  String get moreConversationActions;

  /// No description provided for @newConversation.
  ///
  /// In zh, this message translates to:
  /// **'新对话'**
  String get newConversation;

  /// No description provided for @deleteCurrentConversation.
  ///
  /// In zh, this message translates to:
  /// **'删除当前对话'**
  String get deleteCurrentConversation;

  /// No description provided for @jumpToBottom.
  ///
  /// In zh, this message translates to:
  /// **'回到底部'**
  String get jumpToBottom;

  /// No description provided for @generalAssistant.
  ///
  /// In zh, this message translates to:
  /// **'通用助手'**
  String get generalAssistant;

  /// No description provided for @textOnlyRuntimeImageWarning.
  ///
  /// In zh, this message translates to:
  /// **'当前本地运行时仅支持文字输入；图片已经保留在输入区，请移除或等待多模态运行时'**
  String get textOnlyRuntimeImageWarning;

  /// No description provided for @imageConversation.
  ///
  /// In zh, this message translates to:
  /// **'图片对话'**
  String get imageConversation;

  /// No description provided for @chatModelDownloadDescription.
  ///
  /// In zh, this message translates to:
  /// **'当前选择的是 {model}，首次使用需下载约 {size}。聊天内容只在本机处理。'**
  String chatModelDownloadDescription(String model, String size);

  /// No description provided for @imageKeptUnsupportedModel.
  ///
  /// In zh, this message translates to:
  /// **'图片已保留在输入区；当前模型不支持图片理解，请切换到支持图片的模型'**
  String get imageKeptUnsupportedModel;

  /// No description provided for @voiceInputBusyElsewhere.
  ///
  /// In zh, this message translates to:
  /// **'其他页面正在使用实时语音输入'**
  String get voiceInputBusyElsewhere;

  /// No description provided for @voiceInputFailed.
  ///
  /// In zh, this message translates to:
  /// **'语音输入失败'**
  String get voiceInputFailed;

  /// No description provided for @deleteCurrentConversationQuestion.
  ///
  /// In zh, this message translates to:
  /// **'删除当前对话？'**
  String get deleteCurrentConversationQuestion;

  /// No description provided for @deleteConversationDescription.
  ///
  /// In zh, this message translates to:
  /// **'聊天内容和这个会话的角色设定将无法恢复。'**
  String get deleteConversationDescription;

  /// No description provided for @chatSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法保存聊天记录：{error}'**
  String chatSaveFailed(String error);

  /// No description provided for @today.
  ///
  /// In zh, this message translates to:
  /// **'今天'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In zh, this message translates to:
  /// **'昨天'**
  String get yesterday;

  /// No description provided for @installedState.
  ///
  /// In zh, this message translates to:
  /// **'已安装'**
  String get installedState;

  /// No description provided for @notInstalledState.
  ///
  /// In zh, this message translates to:
  /// **'未安装'**
  String get notInstalledState;

  /// No description provided for @chatEmptyTitle.
  ///
  /// In zh, this message translates to:
  /// **'你想聊什么？'**
  String get chatEmptyTitle;

  /// No description provided for @chatEmptyDescription.
  ///
  /// In zh, this message translates to:
  /// **'自由输入任何内容。消息和角色设定只保存在本机。'**
  String get chatEmptyDescription;

  /// No description provided for @chatSuggestionPriorities.
  ///
  /// In zh, this message translates to:
  /// **'帮我梳理今天最重要的三件事'**
  String get chatSuggestionPriorities;

  /// No description provided for @chatSuggestionExplain.
  ///
  /// In zh, this message translates to:
  /// **'用通俗的话解释一个复杂概念'**
  String get chatSuggestionExplain;

  /// No description provided for @chatSuggestionDevelopIdea.
  ///
  /// In zh, this message translates to:
  /// **'和我一起完善一个新想法'**
  String get chatSuggestionDevelopIdea;

  /// No description provided for @yourImageMessage.
  ///
  /// In zh, this message translates to:
  /// **'你的图片消息'**
  String get yourImageMessage;

  /// No description provided for @yourMessage.
  ///
  /// In zh, this message translates to:
  /// **'你的消息'**
  String get yourMessage;

  /// No description provided for @aiReplying.
  ///
  /// In zh, this message translates to:
  /// **'AI 正在回复'**
  String get aiReplying;

  /// No description provided for @aiReply.
  ///
  /// In zh, this message translates to:
  /// **'AI 回复'**
  String get aiReply;

  /// No description provided for @stopped.
  ///
  /// In zh, this message translates to:
  /// **'已停止'**
  String get stopped;

  /// No description provided for @copyReply.
  ///
  /// In zh, this message translates to:
  /// **'复制回答'**
  String get copyReply;

  /// No description provided for @replyCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制回答'**
  String get replyCopied;

  /// No description provided for @generating.
  ///
  /// In zh, this message translates to:
  /// **'正在生成…'**
  String get generating;

  /// No description provided for @modelDoesNotSupportImages.
  ///
  /// In zh, this message translates to:
  /// **'当前模型不支持图片理解，请切换模型后发送'**
  String get modelDoesNotSupportImages;

  /// No description provided for @takePhoto.
  ///
  /// In zh, this message translates to:
  /// **'拍照'**
  String get takePhoto;

  /// No description provided for @takePhotoUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'拍照（当前模型不支持图片）'**
  String get takePhotoUnsupported;

  /// No description provided for @dictating.
  ///
  /// In zh, this message translates to:
  /// **'正在听写…'**
  String get dictating;

  /// No description provided for @messageOrVoiceHint.
  ///
  /// In zh, this message translates to:
  /// **'发消息或使用语音…'**
  String get messageOrVoiceHint;

  /// No description provided for @stopGeneration.
  ///
  /// In zh, this message translates to:
  /// **'停止生成'**
  String get stopGeneration;

  /// No description provided for @finishVoiceInput.
  ///
  /// In zh, this message translates to:
  /// **'完成语音输入'**
  String get finishVoiceInput;

  /// No description provided for @send.
  ///
  /// In zh, this message translates to:
  /// **'发送'**
  String get send;

  /// No description provided for @voiceInput.
  ///
  /// In zh, this message translates to:
  /// **'语音输入'**
  String get voiceInput;

  /// No description provided for @addImage.
  ///
  /// In zh, this message translates to:
  /// **'添加图片'**
  String get addImage;

  /// No description provided for @addImageUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'添加图片（当前模型不支持）'**
  String get addImageUnsupported;

  /// No description provided for @preparingOfflineSpeech.
  ///
  /// In zh, this message translates to:
  /// **'正在准备离线语音识别…'**
  String get preparingOfflineSpeech;

  /// No description provided for @dictationTapMicToFinish.
  ///
  /// In zh, this message translates to:
  /// **'正在听写，点击麦克风完成'**
  String get dictationTapMicToFinish;

  /// No description provided for @previewImage.
  ///
  /// In zh, this message translates to:
  /// **'预览图片'**
  String get previewImage;

  /// No description provided for @removeImage.
  ///
  /// In zh, this message translates to:
  /// **'移除图片'**
  String get removeImage;

  /// No description provided for @addMoreImages.
  ///
  /// In zh, this message translates to:
  /// **'继续添加图片'**
  String get addMoreImages;

  /// No description provided for @previewImageNumber.
  ///
  /// In zh, this message translates to:
  /// **'预览图片 {index}'**
  String previewImageNumber(int index);

  /// No description provided for @closePreview.
  ///
  /// In zh, this message translates to:
  /// **'关闭预览'**
  String get closePreview;

  /// No description provided for @imageCannotOpen.
  ///
  /// In zh, this message translates to:
  /// **'图片无法打开'**
  String get imageCannotOpen;

  /// No description provided for @dismissMessage.
  ///
  /// In zh, this message translates to:
  /// **'关闭提示'**
  String get dismissMessage;

  /// No description provided for @readAgain.
  ///
  /// In zh, this message translates to:
  /// **'重新读取'**
  String get readAgain;

  /// No description provided for @switchPersona.
  ///
  /// In zh, this message translates to:
  /// **'切换角色'**
  String get switchPersona;

  /// No description provided for @manage.
  ///
  /// In zh, this message translates to:
  /// **'管理'**
  String get manage;

  /// No description provided for @noSavedConversations.
  ///
  /// In zh, this message translates to:
  /// **'还没有保存的对话'**
  String get noSavedConversations;

  /// No description provided for @conversationMessageCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条消息 · {time}'**
  String conversationMessageCount(int count, String time);

  /// No description provided for @personaDeleteQuestion.
  ///
  /// In zh, this message translates to:
  /// **'删除“{name}”？'**
  String personaDeleteQuestion(String name);

  /// No description provided for @personaDeleteDescription.
  ///
  /// In zh, this message translates to:
  /// **'使用这个角色的对话会切换回通用助手，聊天记录不会删除。'**
  String get personaDeleteDescription;

  /// No description provided for @createPersona.
  ///
  /// In zh, this message translates to:
  /// **'新建角色'**
  String get createPersona;

  /// No description provided for @reload.
  ///
  /// In zh, this message translates to:
  /// **'重新加载'**
  String get reload;

  /// No description provided for @personaManagementDescription.
  ///
  /// In zh, this message translates to:
  /// **'角色决定本地模型回答问题时采用的身份、语气和规则。你可以在聊天中随时切换，所有设定只保存在本机。'**
  String get personaManagementDescription;

  /// No description provided for @builtIn.
  ///
  /// In zh, this message translates to:
  /// **'内置'**
  String get builtIn;

  /// No description provided for @current.
  ///
  /// In zh, this message translates to:
  /// **'当前'**
  String get current;

  /// No description provided for @personaDescriptionMissing.
  ///
  /// In zh, this message translates to:
  /// **'未填写角色说明'**
  String get personaDescriptionMissing;

  /// No description provided for @personaActions.
  ///
  /// In zh, this message translates to:
  /// **'角色操作'**
  String get personaActions;

  /// No description provided for @editPersona.
  ///
  /// In zh, this message translates to:
  /// **'编辑角色'**
  String get editPersona;

  /// No description provided for @deletePersona.
  ///
  /// In zh, this message translates to:
  /// **'删除角色'**
  String get deletePersona;

  /// No description provided for @personaInstructionDescription.
  ///
  /// In zh, this message translates to:
  /// **'角色名称用于切换；系统提示词会在每次请求中作为最高优先级的本地指令。'**
  String get personaInstructionDescription;

  /// No description provided for @personaName.
  ///
  /// In zh, this message translates to:
  /// **'角色名称'**
  String get personaName;

  /// No description provided for @shortDescriptionOptional.
  ///
  /// In zh, this message translates to:
  /// **'简短说明（可选）'**
  String get shortDescriptionOptional;

  /// No description provided for @systemPrompt.
  ///
  /// In zh, this message translates to:
  /// **'系统提示词'**
  String get systemPrompt;

  /// No description provided for @systemPromptHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：你是一位耐心的英语口语教练……'**
  String get systemPromptHint;

  /// No description provided for @savePersona.
  ///
  /// In zh, this message translates to:
  /// **'保存角色'**
  String get savePersona;

  /// No description provided for @microphonePermissionRequired.
  ///
  /// In zh, this message translates to:
  /// **'需要麦克风权限'**
  String get microphonePermissionRequired;

  /// No description provided for @microphonePermissionDescription.
  ///
  /// In zh, this message translates to:
  /// **'录音只会保存在本机。请允许麦克风权限后再开始。'**
  String get microphonePermissionDescription;

  /// No description provided for @openSettings.
  ///
  /// In zh, this message translates to:
  /// **'前往设置'**
  String get openSettings;

  /// No description provided for @recordingStartFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法开始录音：{error}'**
  String recordingStartFailed(String error);

  /// No description provided for @voiceNoteDefaultTitle.
  ///
  /// In zh, this message translates to:
  /// **'语音笔记 {date} {time}'**
  String voiceNoteDefaultTitle(String date, String time);

  /// No description provided for @recordingSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存失败：{error}'**
  String recordingSaveFailed(String error);

  /// No description provided for @discardRecordingQuestion.
  ///
  /// In zh, this message translates to:
  /// **'放弃这段录音？'**
  String get discardRecordingQuestion;

  /// No description provided for @discardRecordingDescription.
  ///
  /// In zh, this message translates to:
  /// **'还没有保存的录音将被删除。'**
  String get discardRecordingDescription;

  /// No description provided for @continueEditing.
  ///
  /// In zh, this message translates to:
  /// **'继续编辑'**
  String get continueEditing;

  /// No description provided for @discard.
  ///
  /// In zh, this message translates to:
  /// **'放弃'**
  String get discard;

  /// No description provided for @deviceOnly.
  ///
  /// In zh, this message translates to:
  /// **'仅本机'**
  String get deviceOnly;

  /// No description provided for @recordIdea.
  ///
  /// In zh, this message translates to:
  /// **'记录一段想法'**
  String get recordIdea;

  /// No description provided for @recordingPrivacyDescription.
  ///
  /// In zh, this message translates to:
  /// **'录音默认只保存在本机；仅手动云同步时才会上传。保存后可以继续添加标签和说明。'**
  String get recordingPrivacyDescription;

  /// No description provided for @preparingMicrophone.
  ///
  /// In zh, this message translates to:
  /// **'正在准备麦克风…'**
  String get preparingMicrophone;

  /// No description provided for @startRecording.
  ///
  /// In zh, this message translates to:
  /// **'开始录音'**
  String get startRecording;

  /// No description provided for @paused.
  ///
  /// In zh, this message translates to:
  /// **'已暂停'**
  String get paused;

  /// No description provided for @recording.
  ///
  /// In zh, this message translates to:
  /// **'正在录音'**
  String get recording;

  /// No description provided for @resume.
  ///
  /// In zh, this message translates to:
  /// **'继续'**
  String get resume;

  /// No description provided for @pause.
  ///
  /// In zh, this message translates to:
  /// **'暂停'**
  String get pause;

  /// No description provided for @recordAgain.
  ///
  /// In zh, this message translates to:
  /// **'重录'**
  String get recordAgain;

  /// No description provided for @saveVoiceNote.
  ///
  /// In zh, this message translates to:
  /// **'保存语音笔记'**
  String get saveVoiceNote;

  /// No description provided for @editTranscript.
  ///
  /// In zh, this message translates to:
  /// **'编辑转写文字'**
  String get editTranscript;

  /// No description provided for @transcriptLocalOnlyDescription.
  ///
  /// In zh, this message translates to:
  /// **'仅修改本地转写文字，原始录音不会改变'**
  String get transcriptLocalOnlyDescription;

  /// No description provided for @transcriptHint.
  ///
  /// In zh, this message translates to:
  /// **'输入转写文字'**
  String get transcriptHint;

  /// No description provided for @transcriptCharacterCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 字'**
  String transcriptCharacterCount(int count);

  /// No description provided for @preparingModel.
  ///
  /// In zh, this message translates to:
  /// **'正在准备模型'**
  String get preparingModel;

  /// No description provided for @recognizedTextCopied.
  ///
  /// In zh, this message translates to:
  /// **'识别文字已复制'**
  String get recognizedTextCopied;

  /// No description provided for @ocrFailedDetail.
  ///
  /// In zh, this message translates to:
  /// **'OCR 识别失败：{error}'**
  String ocrFailedDetail(String error);

  /// No description provided for @noClearTextRecognized.
  ///
  /// In zh, this message translates to:
  /// **'未识别到清晰文字'**
  String get noClearTextRecognized;

  /// No description provided for @importOfflineSpeechModel.
  ///
  /// In zh, this message translates to:
  /// **'导入离线识别模型'**
  String get importOfflineSpeechModel;

  /// No description provided for @importSpeechModelDescription.
  ///
  /// In zh, this message translates to:
  /// **'请从解压后的 SenseVoice Small INT8 模型目录中，同时选择 ONNX 模型和 tokens.txt。\n\n模型约 228 MB，只保存在本机，不会进入笔记备份。'**
  String get importSpeechModelDescription;

  /// No description provided for @chooseFiles.
  ///
  /// In zh, this message translates to:
  /// **'选择文件'**
  String get chooseFiles;

  /// No description provided for @importingOfflineModel.
  ///
  /// In zh, this message translates to:
  /// **'正在导入离线模型'**
  String get importingOfflineModel;

  /// No description provided for @offlineSpeechModelImported.
  ///
  /// In zh, this message translates to:
  /// **'离线语音识别模型已导入'**
  String get offlineSpeechModelImported;

  /// No description provided for @modelImportFailed.
  ///
  /// In zh, this message translates to:
  /// **'模型导入失败：{error}'**
  String modelImportFailed(String error);

  /// No description provided for @downloadOfflineSpeechModelQuestion.
  ///
  /// In zh, this message translates to:
  /// **'下载离线识别模型？'**
  String get downloadOfflineSpeechModelQuestion;

  /// No description provided for @downloadSpeechModelDescription.
  ///
  /// In zh, this message translates to:
  /// **'将从 ModelScope 魔搭社区下载约 228 MB，建议使用 Wi-Fi。\n\n模型下载会联网；笔记和音频只会在你手动云同步时上传。中断后可继续下载。'**
  String get downloadSpeechModelDescription;

  /// No description provided for @downloadingFromModelScope.
  ///
  /// In zh, this message translates to:
  /// **'正在从 ModelScope 下载'**
  String get downloadingFromModelScope;

  /// No description provided for @offlineSpeechModelDownloaded.
  ///
  /// In zh, this message translates to:
  /// **'离线语音识别模型下载完成'**
  String get offlineSpeechModelDownloaded;

  /// No description provided for @downloadPausedResumable.
  ///
  /// In zh, this message translates to:
  /// **'已暂停下载，下次会从断点继续'**
  String get downloadPausedResumable;

  /// No description provided for @modelDownloadFailedDetail.
  ///
  /// In zh, this message translates to:
  /// **'模型下载失败：{error}'**
  String modelDownloadFailedDetail(String error);

  /// No description provided for @finishingInstallation.
  ///
  /// In zh, this message translates to:
  /// **'正在完成安装'**
  String get finishingInstallation;

  /// No description provided for @importedAmount.
  ///
  /// In zh, this message translates to:
  /// **'已导入 {amount}'**
  String importedAmount(String amount);

  /// No description provided for @downloadedAmount.
  ///
  /// In zh, this message translates to:
  /// **'已下载 {amount}'**
  String downloadedAmount(String amount);

  /// No description provided for @amountFinishingInstall.
  ///
  /// In zh, this message translates to:
  /// **'{amount} · 正在完成安装'**
  String amountFinishingInstall(String amount);

  /// No description provided for @speedTesting.
  ///
  /// In zh, this message translates to:
  /// **'正在测速…'**
  String get speedTesting;

  /// No description provided for @waitForTranscription.
  ///
  /// In zh, this message translates to:
  /// **'请先等待正在进行的转写结束'**
  String get waitForTranscription;

  /// No description provided for @removeOfflineModelQuestion.
  ///
  /// In zh, this message translates to:
  /// **'移除离线模型？'**
  String get removeOfflineModelQuestion;

  /// No description provided for @removeOfflineModelDescription.
  ///
  /// In zh, this message translates to:
  /// **'将释放约 228 MB 空间。已经保存的转写文字不会被删除。'**
  String get removeOfflineModelDescription;

  /// No description provided for @speakerModelRequired.
  ///
  /// In zh, this message translates to:
  /// **'需要说话人分离模型'**
  String get speakerModelRequired;

  /// No description provided for @speakerModelDownloadDescription.
  ///
  /// In zh, this message translates to:
  /// **'首次使用需在本地模型中下载约 44.4 MB。模型安装后，分段和转写都完全在设备上完成。'**
  String get speakerModelDownloadDescription;

  /// No description provided for @speakerCount.
  ///
  /// In zh, this message translates to:
  /// **'说话人数量'**
  String get speakerCount;

  /// No description provided for @speakerCountDescription.
  ///
  /// In zh, this message translates to:
  /// **'当前支持最长 30 分钟的录音；人数越准确，分离结果通常越稳定。'**
  String get speakerCountDescription;

  /// No description provided for @estimateAutomatically.
  ///
  /// In zh, this message translates to:
  /// **'自动估算'**
  String get estimateAutomatically;

  /// No description provided for @estimateAutomaticallyDescription.
  ///
  /// In zh, this message translates to:
  /// **'适合不确定人数的录音'**
  String get estimateAutomaticallyDescription;

  /// No description provided for @speakerCountOption.
  ///
  /// In zh, this message translates to:
  /// **'{count} 位说话人'**
  String speakerCountOption(int count);

  /// No description provided for @transcriptCopied.
  ///
  /// In zh, this message translates to:
  /// **'转写文字已复制'**
  String get transcriptCopied;

  /// No description provided for @openWithAnotherApp.
  ///
  /// In zh, this message translates to:
  /// **'用其他应用打开'**
  String get openWithAnotherApp;

  /// No description provided for @editInformation.
  ///
  /// In zh, this message translates to:
  /// **'编辑信息'**
  String get editInformation;

  /// No description provided for @preview.
  ///
  /// In zh, this message translates to:
  /// **'预览'**
  String get preview;

  /// No description provided for @recognizedText.
  ///
  /// In zh, this message translates to:
  /// **'识别文字'**
  String get recognizedText;

  /// No description provided for @transcript.
  ///
  /// In zh, this message translates to:
  /// **'转写文字'**
  String get transcript;

  /// No description provided for @information.
  ///
  /// In zh, this message translates to:
  /// **'信息'**
  String get information;

  /// No description provided for @textInImage.
  ///
  /// In zh, this message translates to:
  /// **'图片中的文字'**
  String get textInImage;

  /// No description provided for @copyAll.
  ///
  /// In zh, this message translates to:
  /// **'复制全部'**
  String get copyAll;

  /// No description provided for @recognizeAgain.
  ///
  /// In zh, this message translates to:
  /// **'重新识别'**
  String get recognizeAgain;

  /// No description provided for @recognizeText.
  ///
  /// In zh, this message translates to:
  /// **'识别文字'**
  String get recognizeText;

  /// No description provided for @noRecognizedText.
  ///
  /// In zh, this message translates to:
  /// **'暂无识别文字'**
  String get noRecognizedText;

  /// No description provided for @ocrOnDemandDescription.
  ///
  /// In zh, this message translates to:
  /// **'需要时可对这张图片进行本地文字识别'**
  String get ocrOnDemandDescription;

  /// No description provided for @recognizing.
  ///
  /// In zh, this message translates to:
  /// **'正在识别…'**
  String get recognizing;

  /// No description provided for @audioTranscript.
  ///
  /// In zh, this message translates to:
  /// **'录音转写'**
  String get audioTranscript;

  /// No description provided for @editText.
  ///
  /// In zh, this message translates to:
  /// **'编辑文字'**
  String get editText;

  /// No description provided for @audioStaysOnDevice.
  ///
  /// In zh, this message translates to:
  /// **'完全在本机处理，音频不会离开设备'**
  String get audioStaysOnDevice;

  /// No description provided for @offlineSpeechModelRequired.
  ///
  /// In zh, this message translates to:
  /// **'需要离线识别模型'**
  String get offlineSpeechModelRequired;

  /// No description provided for @offlineModelBackupDescription.
  ///
  /// In zh, this message translates to:
  /// **'模型独立保存在本机，不增加笔记备份大小'**
  String get offlineModelBackupDescription;

  /// No description provided for @downloadAbout228Mb.
  ///
  /// In zh, this message translates to:
  /// **'在线下载约 228 MB'**
  String get downloadAbout228Mb;

  /// No description provided for @backgroundTranscriptionHint.
  ///
  /// In zh, this message translates to:
  /// **'可以离开此页面继续使用笔记'**
  String get backgroundTranscriptionHint;

  /// No description provided for @transcriptionIncomplete.
  ///
  /// In zh, this message translates to:
  /// **'转写没有完成'**
  String get transcriptionIncomplete;

  /// No description provided for @tryAgainLater.
  ///
  /// In zh, this message translates to:
  /// **'请稍后重试'**
  String get tryAgainLater;

  /// No description provided for @transcribeAgain.
  ///
  /// In zh, this message translates to:
  /// **'重新转写'**
  String get transcribeAgain;

  /// No description provided for @transcriptionCanceled.
  ///
  /// In zh, this message translates to:
  /// **'已取消转写'**
  String get transcriptionCanceled;

  /// No description provided for @recordingUnaffected.
  ///
  /// In zh, this message translates to:
  /// **'录音文件没有受到影响'**
  String get recordingUnaffected;

  /// No description provided for @noTranscript.
  ///
  /// In zh, this message translates to:
  /// **'暂无转写文字'**
  String get noTranscript;

  /// No description provided for @transcriptionOnDemandDescription.
  ///
  /// In zh, this message translates to:
  /// **'需要时再启动本地识别，不会自动处理录音'**
  String get transcriptionOnDemandDescription;

  /// No description provided for @transcribeOnDevice.
  ///
  /// In zh, this message translates to:
  /// **'本地转写'**
  String get transcribeOnDevice;

  /// No description provided for @speakerDiarizedTranscription.
  ///
  /// In zh, this message translates to:
  /// **'区分说话人转写'**
  String get speakerDiarizedTranscription;

  /// No description provided for @speakerDiarizedTranscriptionModelRequired.
  ///
  /// In zh, this message translates to:
  /// **'区分说话人转写 · 需 44.4 MB 模型'**
  String get speakerDiarizedTranscriptionModelRequired;

  /// No description provided for @manageModelSize.
  ///
  /// In zh, this message translates to:
  /// **'管理模型 · {size}'**
  String manageModelSize(String size);

  /// No description provided for @importFromFiles.
  ///
  /// In zh, this message translates to:
  /// **'从文件导入'**
  String get importFromFiles;

  /// No description provided for @viewAllModels.
  ///
  /// In zh, this message translates to:
  /// **'查看全部模型'**
  String get viewAllModels;

  /// No description provided for @preparingLocalTranscription.
  ///
  /// In zh, this message translates to:
  /// **'正在准备本地转写'**
  String get preparingLocalTranscription;

  /// No description provided for @readingAudio.
  ///
  /// In zh, this message translates to:
  /// **'正在读取音频'**
  String get readingAudio;

  /// No description provided for @separatingSpeakers.
  ///
  /// In zh, this message translates to:
  /// **'正在区分说话人'**
  String get separatingSpeakers;

  /// No description provided for @recognizingOnDevice.
  ///
  /// In zh, this message translates to:
  /// **'正在本地识别'**
  String get recognizingOnDevice;

  /// No description provided for @savingTranscriptText.
  ///
  /// In zh, this message translates to:
  /// **'正在保存转写文字'**
  String get savingTranscriptText;

  /// No description provided for @processing.
  ///
  /// In zh, this message translates to:
  /// **'正在处理'**
  String get processing;

  /// No description provided for @noteInformation.
  ///
  /// In zh, this message translates to:
  /// **'笔记信息'**
  String get noteInformation;

  /// No description provided for @type.
  ///
  /// In zh, this message translates to:
  /// **'类型'**
  String get type;

  /// No description provided for @created.
  ///
  /// In zh, this message translates to:
  /// **'创建'**
  String get created;

  /// No description provided for @updated.
  ///
  /// In zh, this message translates to:
  /// **'更新'**
  String get updated;

  /// No description provided for @fileInformation.
  ///
  /// In zh, this message translates to:
  /// **'文件信息'**
  String get fileInformation;

  /// No description provided for @fileName.
  ///
  /// In zh, this message translates to:
  /// **'文件名'**
  String get fileName;

  /// No description provided for @size.
  ///
  /// In zh, this message translates to:
  /// **'大小'**
  String get size;

  /// No description provided for @duration.
  ///
  /// In zh, this message translates to:
  /// **'时长'**
  String get duration;

  /// No description provided for @saveStatus.
  ///
  /// In zh, this message translates to:
  /// **'保存状态'**
  String get saveStatus;

  /// No description provided for @fileMissing.
  ///
  /// In zh, this message translates to:
  /// **'文件不存在'**
  String get fileMissing;

  /// No description provided for @savedInUnifiedDirectory.
  ///
  /// In zh, this message translates to:
  /// **'已保存在统一目录'**
  String get savedInUnifiedDirectory;

  /// No description provided for @description.
  ///
  /// In zh, this message translates to:
  /// **'说明'**
  String get description;

  /// No description provided for @originalFileMissing.
  ///
  /// In zh, this message translates to:
  /// **'原文件不存在'**
  String get originalFileMissing;

  /// No description provided for @missingFileDescription.
  ///
  /// In zh, this message translates to:
  /// **'可以保留笔记信息或将它移到回收站'**
  String get missingFileDescription;

  /// No description provided for @openWithLocalApp.
  ///
  /// In zh, this message translates to:
  /// **'用本地应用打开'**
  String get openWithLocalApp;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
