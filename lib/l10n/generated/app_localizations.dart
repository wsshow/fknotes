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
  /// **'下载、导入和移除设备端识别模型'**
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

  /// No description provided for @cancelingDownload.
  ///
  /// In zh, this message translates to:
  /// **'正在取消并保留已下载内容…'**
  String get cancelingDownload;

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

  /// No description provided for @importedVerb.
  ///
  /// In zh, this message translates to:
  /// **'已导入'**
  String get importedVerb;

  /// No description provided for @downloadedVerb.
  ///
  /// In zh, this message translates to:
  /// **'已下载'**
  String get downloadedVerb;

  /// No description provided for @waitingFirstPacket.
  ///
  /// In zh, this message translates to:
  /// **'等待首个数据包…'**
  String get waitingFirstPacket;

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
