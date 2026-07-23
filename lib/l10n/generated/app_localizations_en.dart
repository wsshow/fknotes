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

  @override
  String get localStorageInitializationFailed =>
      'Local storage could not be initialized';

  @override
  String get home => 'Home';

  @override
  String get library => 'Library';

  @override
  String get data => 'Data';

  @override
  String get createNew => 'New';

  @override
  String get undo => 'Undo';

  @override
  String get cancel => 'Cancel';

  @override
  String get close => 'Close';

  @override
  String get deletePermanently => 'Delete permanently';

  @override
  String get deletePermanentlyQuestion => 'Delete permanently?';

  @override
  String get deletePermanentlyDescription =>
      'The note and its files cannot be recovered.';

  @override
  String get discardNote => 'Discard note';

  @override
  String get discardNoteQuestion => 'Discard this note?';

  @override
  String get discardNoteDescription =>
      'Unsaved content and newly added attachments will be deleted and cannot be recovered.';

  @override
  String get noteDeleteFailed => 'Couldn\'t delete the note. Try again later.';

  @override
  String get captureMoment => 'Capture';

  @override
  String get capturePrivacyHint => 'Saved offline and kept private';

  @override
  String get note => 'Note';

  @override
  String get photo => 'Camera';

  @override
  String get image => 'Image';

  @override
  String get record => 'Record';

  @override
  String get audio => 'Audio';

  @override
  String get video => 'Video';

  @override
  String get file => 'File';

  @override
  String get voiceNote => 'Voice note';

  @override
  String importFailed(String type) {
    return 'Couldn\'t import $type';
  }

  @override
  String get recentlyUpdated => 'Recently updated';

  @override
  String get more => 'More';

  @override
  String get startWithIdea => 'Start with an idea';

  @override
  String get createNoteEmptyHint =>
      'Tap New. Your content stays safely on this device.';

  @override
  String get localAssistant => 'Local Assistant';

  @override
  String get searchLocalKnowledge => 'Search local knowledge';

  @override
  String get searchNotes => 'Search notes';

  @override
  String get savedOnlyOnDevice => 'Stored only on this device';

  @override
  String get allNotes => 'All notes';

  @override
  String noteCountShort(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count notes',
      one: '1 note',
    );
    return '$_temp0';
  }

  @override
  String attachmentCountShort(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count attachments',
      one: '1 attachment',
    );
    return '$_temp0';
  }

  @override
  String createType(String type) {
    return 'New $type';
  }

  @override
  String itemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String get search => 'Search';

  @override
  String get sort => 'Sort';

  @override
  String get creationTime => 'Date created';

  @override
  String get title => 'Title';

  @override
  String get fileSize => 'File size';

  @override
  String get all => 'All';

  @override
  String get emptyActive => 'No notes yet';

  @override
  String get clear => 'Empty';

  @override
  String get allTypes => 'All types';

  @override
  String get unavailable => 'Unavailable';

  @override
  String get localData => 'Local data';

  @override
  String get localDataSubtitle =>
      'Stored on this device by default. Sync is always your choice.';

  @override
  String get localFirst => 'Local first';

  @override
  String get offlineSecure => 'Offline and secure';

  @override
  String get totalItems => 'Items';

  @override
  String get attachments => 'Attachments';

  @override
  String get userDataUsage => 'User data';

  @override
  String get preferences => 'Preferences';

  @override
  String get unifiedStorage => 'Storage';

  @override
  String get cloudSync => 'Cloud sync';

  @override
  String get cloudSyncSubtitle => 'Manually sync user data with S3 or WebDAV';

  @override
  String get localModels => 'Local models';

  @override
  String get localModelsSubtitle =>
      'Review active models and manage them by capability';

  @override
  String get backupAndMigration => 'Backup and migration';

  @override
  String get exportCompleteBackup => 'Export full backup';

  @override
  String get exportCompleteBackupSubtitle =>
      'Keep multiple versions to share or save in a chosen location';

  @override
  String get restoreFromBackup => 'Restore from backup';

  @override
  String get restoreFromBackupSubtitle =>
      'Restore from backup history or an external file after verification';

  @override
  String get backupScopeDescription =>
      'Includes structured notes and their body attachments only. Chats, models, caches, app lock, and cloud accounts are excluded.';

  @override
  String get createNewBackup => 'Create a new backup';

  @override
  String get backupName => 'Backup name';

  @override
  String get backupNameHint => 'Optional, for example: Before migration';

  @override
  String get backupDescription => 'Backup description';

  @override
  String get backupDescriptionHint =>
      'Optional notes about what matters in this version';

  @override
  String get createBackup => 'Create backup';

  @override
  String get creatingBackup => 'Verifying and creating backup…';

  @override
  String get backupSavedDefault =>
      'Saved to the default FKNotes backup location';

  @override
  String get backupHistory => 'Backup history';

  @override
  String get backupHistorySubtitle =>
      'Keep multiple versions in the default location to share, save elsewhere, or restore';

  @override
  String get noBackupHistory => 'No local backups yet';

  @override
  String get backupStoredLocally => 'Default FKNotes location';

  @override
  String get saveBackupCopy => 'Save a copy…';

  @override
  String get backupCopySaved => 'Backup copy saved';

  @override
  String get backupDetails => 'Backup details';

  @override
  String backupDateAndSize(String date, String size) {
    return '$date · $size';
  }

  @override
  String get backupCreatedAt => 'Created';

  @override
  String get backupFileName => 'File name';

  @override
  String get backupFormat => 'Format version';

  @override
  String get backupVerificationCode => 'File checksum (SHA-256)';

  @override
  String get backupContentFingerprint => 'Content fingerprint';

  @override
  String get deleteBackup => 'Delete backup';

  @override
  String get deleteBackupQuestion => 'Delete this backup?';

  @override
  String get deleteBackupDescription =>
      'Only this version in the default backup location will be removed. Current notes are not affected.';

  @override
  String get backupDeleted => 'Backup deleted';

  @override
  String get restoreWarning =>
      'Restoring replaces current notes, chats, and attachments. Create a fresh backup first if needed.';

  @override
  String get chooseExternalBackup => 'Choose a backup from elsewhere';

  @override
  String get restoreBackupAction => 'Restore this backup';

  @override
  String get restoringBackup => 'Verifying and restoring backup…';

  @override
  String get organizationAndSecurity => 'Organization and security';

  @override
  String get appLock => 'App lock';

  @override
  String appLockEnabledSubtitle(String timeout) {
    return 'On · Lock $timeout after leaving the app';
  }

  @override
  String get appLockDisabledSubtitle => 'Use device biometrics or screen lock';

  @override
  String get lockImmediately => 'immediately';

  @override
  String get lockAfterOneMinute => 'after 1 minute';

  @override
  String get lockAfterFiveMinutes => 'after 5 minutes';

  @override
  String get lockAfterFifteenMinutes => 'after 15 minutes';

  @override
  String contentCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String get about => 'About';

  @override
  String get loadingVersion => 'Loading version information…';

  @override
  String versionNumber(String version) {
    return 'Version $version';
  }

  @override
  String versionNumberWithBuild(String version, String build) {
    return 'Version $version ($build)';
  }

  @override
  String buildTime(String time) {
    return 'Built $time';
  }

  @override
  String get buildTimeUnrecorded => 'Build time unavailable';

  @override
  String get footerTagline => 'FKNotes · Local first, sync on your terms';

  @override
  String get backupExported => 'Backup handed off to the system';

  @override
  String exportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get restoreCompleteBackupQuestion => 'Restore full backup?';

  @override
  String get restoreCompleteBackupDescription =>
      'Current content will be replaced by the backup. Exporting the current data first is recommended.';

  @override
  String get chooseBackup => 'Choose backup';

  @override
  String get backupRestored => 'Backup restored safely';

  @override
  String restoreFailed(String error) {
    return 'Restore failed: $error';
  }

  @override
  String get localModelsPageTitle => 'Local models';

  @override
  String get modelsInUse => 'In use';

  @override
  String get noModelsInUse => 'No local models are currently configured';

  @override
  String get modelConfiguration => 'Manage by category';

  @override
  String activeModelCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count models in use',
      one: '1 model in use',
    );
    return '$_temp0';
  }

  @override
  String activeModelsUsage(String size) {
    return 'Local models use $size';
  }

  @override
  String get installedModels => 'Installed';

  @override
  String get availableModels => 'Available';

  @override
  String installedModelsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count models installed',
      one: '1 model installed',
    );
    return '$_temp0';
  }

  @override
  String get noInstalledModelsInCategory =>
      'No models in this category are installed';

  @override
  String get noAvailableModelsInCategory =>
      'No other models are currently available';

  @override
  String get speechModelsDescription =>
      'Manage live dictation, recording transcription, speech processing, and text-to-speech separately.';

  @override
  String get visionModelsDescription =>
      'Manage OCR and dedicated vision features. Chat image understanding is provided by image-capable language models.';

  @override
  String get liveDictationSettingsDescription =>
      'Manage the dictation model, hotwords, refinement, and live denoising';

  @override
  String get modelDownloadsAndStorage => 'Downloads and storage';

  @override
  String get modelDownloadsAndStorageDescription =>
      'Download sources, background tasks, and model storage';

  @override
  String get localAssistantUsage => 'Local Assistant';

  @override
  String get liveDictationUsage => 'Live dictation';

  @override
  String get audioTranscriptionUsage => 'Transcription';

  @override
  String get voiceActivityUsage => 'Voice detection';

  @override
  String get speechEnhancementUsage => 'Live denoising';

  @override
  String get textRecognitionUsage => 'Text recognition';

  @override
  String get modelPrivacyHint =>
      'Models connect only when you download them and are excluded from note backups. User data is uploaded only during manual cloud sync.';

  @override
  String get languageModels => 'Language models';

  @override
  String get languageModelsDescription =>
      'Download and choose the model used by Local Assistant. The default context is 4096 tokens.';

  @override
  String get discoverMnnModels => 'Discover local models';

  @override
  String get discoverMnnModelsDescription =>
      'Browse public models synchronized from the taobao-mnn and litert-community Collections. You decide whether to verify and add them.';

  @override
  String get browseModels => 'Browse models';

  @override
  String get refreshCatalog => 'Refresh catalog';

  @override
  String get syncingModelCatalog => 'Syncing model catalog…';

  @override
  String modelCatalogSyncFailed(String error) {
    return 'Couldn\'t refresh the model catalog: $error';
  }

  @override
  String get modelCatalogRefreshTimeout => 'Model catalog refresh timed out';

  @override
  String get modelCatalogRefreshTimeoutDescription =>
      'The model service did not respond in time. Retry or switch the model network source.';

  @override
  String get modelCatalogOffline => 'Couldn\'t connect to the model service';

  @override
  String get modelCatalogOfflineDescription =>
      'Check your connection or try another model network source.';

  @override
  String get modelCatalogServiceUnavailable =>
      'Model service is temporarily unavailable';

  @override
  String get modelCatalogServiceUnavailableDescription =>
      'The service isn\'t responding normally. Try again later.';

  @override
  String get modelCatalogAuthorizationRequired =>
      'Some models require access approval';

  @override
  String get modelCatalogAuthorizationRequiredDescription =>
      'This catalog contains models whose license must be accepted on Hugging Face before use.';

  @override
  String get modelCatalogInvalidResponse =>
      'The model catalog can\'t be read right now';

  @override
  String get modelCatalogInvalidResponseDescription =>
      'The service returned unrecognized data. Try again later.';

  @override
  String get modelCatalogCompatibilityUnavailable =>
      'Model compatibility can\'t be checked right now';

  @override
  String get modelNetworkSourceSettings => 'Switch network source';

  @override
  String get cachedCatalogInUse =>
      'Showing the last successfully synchronized catalog';

  @override
  String get searchMnnModels => 'Search local models';

  @override
  String get noMnnModelsFound => 'No matching local models';

  @override
  String get officialMnnCollection => 'Official taobao-mnn Collection';

  @override
  String get officialLiteRtCollection => 'Official litert-community Collection';

  @override
  String downloadCount(int count) {
    return '$count downloads';
  }

  @override
  String get modelEngine => 'Inference engine';

  @override
  String get collection => 'Collection';

  @override
  String get downloads => 'Downloads';

  @override
  String get modelPackageNotVerified => 'Model package not verified';

  @override
  String get modelPackageVerificationDescription =>
      'Verification reads repository metadata, the pinned revision, and file manifest. It does not download the full model or guarantee that this device can run it.';

  @override
  String get verifyModelPackage => 'Verify model package';

  @override
  String get verifyingModelPackage => 'Verifying model package…';

  @override
  String get reverifyModelPackage => 'Verify model package again';

  @override
  String get modelPackageUnsupported =>
      'This repository is not a supported model package';

  @override
  String get modelPackageUnsupportedDescription =>
      'Its format, public access status, or required files do not meet the current engine requirements.';

  @override
  String get checkingModelCompatibility => 'Checking model compatibility…';

  @override
  String get modelCompatibilityPassed =>
      'MNN file and configuration checks passed';

  @override
  String get liteRtCompatibilityPassed =>
      'LiteRT-LM file, pinned revision, and checksum checks passed';

  @override
  String modelCompatibilityFailed(String error) {
    return 'This model can\'t be added: $error';
  }

  @override
  String get pinnedCommit => 'Pinned commit';

  @override
  String get modelFileCount => 'Model files';

  @override
  String get modelFile => 'Model file';

  @override
  String fileCountValue(int count) {
    return '$count files';
  }

  @override
  String get modelCapabilities => 'Capabilities';

  @override
  String get textGenerationCapability => 'Text generation';

  @override
  String get imageInputCapability => 'Image input';

  @override
  String get audioInputCapability => 'Audio input';

  @override
  String get reasoningCapability => 'Reasoning';

  @override
  String get toolCallingCapability => 'Tool calling';

  @override
  String get addAndDownloadModel => 'Add and download';

  @override
  String get addToLanguageModels => 'Add to language models';

  @override
  String get modelAddedToManager => 'Model added to Local models';

  @override
  String get recommendedModelsAlreadyListed =>
      'FKNotes recommended models are already shown on the previous page.';

  @override
  String remoteMnnModelSummary(String collection) {
    return 'Official model from $collection';
  }

  @override
  String get remoteMnnModelDescription =>
      'Synchronized from taobao-mnn Collections. The repository revision and every model file are verified before installation.';

  @override
  String get liveDictationSettings => 'Live dictation settings';

  @override
  String get speechModels => 'Speech models';

  @override
  String get visionModels => 'Vision models';

  @override
  String get modelDownloadSource => 'Model download source';

  @override
  String get downloadSourceSecurityDescription =>
      'Every mode safely falls back when its preferred endpoint is unavailable. Pinned revisions and SHA-256 checks still verify every model.';

  @override
  String get downloadSourceSaveFailed =>
      'Couldn\'t save the download source setting';

  @override
  String get downloadSourceAutomatic => 'Automatic';

  @override
  String get downloadSourceOfficialFirst => 'Prefer official sources';

  @override
  String get downloadSourceMainlandFirst => 'Prefer regional mirrors';

  @override
  String get downloadSourceAutomaticDescription =>
      'Use device region and successful connections to adapt';

  @override
  String get downloadSourceOfficialDescription =>
      'Prefer official Hugging Face or GitHub endpoints';

  @override
  String get downloadSourceMainlandDescription =>
      'Prefer regional mirrors or ModelScope endpoints';

  @override
  String downloadSourceEffective(String source) {
    return 'Automatic · Prefer $source';
  }

  @override
  String get officialSource => 'official sources';

  @override
  String get mainlandMirror => 'regional mirrors';

  @override
  String lastUsedSource(String source) {
    return 'Last used: $source';
  }

  @override
  String get continueModelDownloadQuestion => 'Continue model download?';

  @override
  String get downloadModelQuestion => 'Download model?';

  @override
  String modelDownloadDescription(String name, String size) {
    return '$name\nAbout $size remains. Wi-Fi is recommended.\n\nYou can leave this page during the download. Progress is kept if interrupted.';
  }

  @override
  String modelMemoryRecommendation(String memory) {
    return 'At least $memory of device memory is recommended. The model may fail to load or be stopped by the system when memory is low.';
  }

  @override
  String get ttsStorageRecommendation =>
      'Keep about 600 MB of free storage available for extraction and installation.';

  @override
  String get startDownload => 'Download';

  @override
  String removeModelQuestion(String name) {
    return 'Remove $name?';
  }

  @override
  String removeModelDescription(String size) {
    return 'This frees about $size. Content already generated by the model is not deleted.';
  }

  @override
  String get removeModel => 'Remove model';

  @override
  String hotwordsSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hotwords',
      one: '1 hotword',
    );
    return 'Saved $_temp0';
  }

  @override
  String get hotwordsDisabled => 'Live dictation hotwords disabled';

  @override
  String get settingsSaveFailed =>
      'Couldn\'t save settings. Check available storage.';

  @override
  String get purpose => 'Purpose';

  @override
  String get engine => 'Engine';

  @override
  String get supportedLanguages => 'Languages';

  @override
  String get version => 'Version';

  @override
  String get recommendedMemory => 'Recommended memory';

  @override
  String memoryAndAbove(String memory) {
    return '$memory or more';
  }

  @override
  String get source => 'Source';

  @override
  String get license => 'License';

  @override
  String get saveFailedStorage => 'Couldn\'t save. Check available storage.';

  @override
  String get liveDictationHotwords => 'Live dictation hotwords';

  @override
  String get hotwordsDescription =>
      'Enter one name, product, or technical term per line. Leave empty to disable. Changes apply to the next dictation session.';

  @override
  String get hotwordsHint => 'FKNotes\nSherpa ONNX\nProduct name';

  @override
  String get hotwordsList => 'Hotwords';

  @override
  String get boostStrength => 'Boost strength';

  @override
  String get hotwordsStrengthWarning =>
      'A high value may mistake similar-sounding words for hotwords. Start with 2.0.';

  @override
  String get saving => 'Saving…';

  @override
  String get save => 'Save';

  @override
  String get finalRefinement => 'Final refinement';

  @override
  String get finalRefinementDescription =>
      'Run a second SenseVoice pass and replace text only when quality checks pass (off by default)';

  @override
  String get liveNoiseSuppression => 'Live noise suppression';

  @override
  String get liveNoiseSuppressionDescription =>
      'Reduce background noise before streaming recognition';

  @override
  String get installDenoiserFirst =>
      'Install the DPDFNet live denoiser below first';

  @override
  String get hotwordBoost => 'Hotword boost';

  @override
  String hotwordSummary(int count, String strength) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hotwords',
      one: '1 hotword',
    );
    return '$_temp0 · Strength $strength';
  }

  @override
  String get hotwordBoostDescription =>
      'Prioritize names, brands, and technical terms';

  @override
  String installedModelCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count models available',
      one: '1 model available',
    );
    return '$_temp0';
  }

  @override
  String optionalModelsUsage(String size) {
    return 'Optional models use $size';
  }

  @override
  String get recommended => 'Recommended';

  @override
  String get modelTransfers => 'Downloads and resumable models';

  @override
  String get modelTransfersDescription =>
      'Review models that are transferring, need attention, or have saved download progress. Completed models leave this list automatically.';

  @override
  String modelTransferSectionCount(int count) {
    return 'Downloads and resumable models ($count)';
  }

  @override
  String modelTransferSummary(int active, int resumable) {
    return '$active running · $resumable ready to resume';
  }

  @override
  String get noModelTransfers =>
      'No models are transferring or waiting to resume';

  @override
  String get otherModels => 'Other models';

  @override
  String get currentDictation => 'Current dictation';

  @override
  String get currentAssistant => 'Current assistant';

  @override
  String get modelDetails => 'Model details';

  @override
  String memoryBadge(String memory) {
    return '$memory+ memory';
  }

  @override
  String get pleaseWait => 'Please wait';

  @override
  String get modelDownloadFailed => 'Model download failed';

  @override
  String get bundledWithApp => 'Bundled';

  @override
  String get comingSoon => 'Coming soon';

  @override
  String get installed => 'Installed';

  @override
  String get useForDictation => 'Use for dictation';

  @override
  String get useForAssistant => 'Use for assistant';

  @override
  String get remove => 'Remove';

  @override
  String get importFromFile => 'Import from file';

  @override
  String get continueDownload => 'Continue';

  @override
  String get download => 'Download';

  @override
  String get pauseDownload => 'Pause';

  @override
  String get cancelingDownload => 'Pausing and keeping downloaded data…';

  @override
  String downloadedResumable(String amount) {
    return '$amount downloaded · Ready to resume';
  }

  @override
  String get moreActions => 'More actions';

  @override
  String get discardPartialDownload => 'Delete downloaded data';

  @override
  String discardPartialDownloadQuestion(String name) {
    return 'Delete download progress for $name?';
  }

  @override
  String discardPartialDownloadDescription(String size) {
    return 'This removes the downloaded $size. The next download will start from the beginning.';
  }

  @override
  String get discardPartialDownloadFailed =>
      'Could not delete the downloaded data. Try again later.';

  @override
  String connectingDownloadSource(String source) {
    return 'Connecting to $source';
  }

  @override
  String downloadedInstalling(String size) {
    return 'Downloaded $size · Finishing installation';
  }

  @override
  String downloadedWaitingInstall(String size) {
    return 'Downloaded $size · Waiting to install';
  }

  @override
  String get preparingLocalModelImport => 'Preparing local model files…';

  @override
  String estimatedRemainingCompact(String time) {
    return '$time left';
  }

  @override
  String get modelDownloadTransfer => 'Model download';

  @override
  String get localModelImportTransfer => 'Local file import';

  @override
  String get thirdPartyMainlandMirror => 'Third-party regional mirror';

  @override
  String get githubOfficialSource => 'Official GitHub source';

  @override
  String get modelScopeSource => 'ModelScope';

  @override
  String get backgroundTasks => 'Background tasks';

  @override
  String get tasksAndActivity => 'Tasks & activity';

  @override
  String get backgroundTasksPageDescription =>
      'Review operations in progress and issues that need your attention.';

  @override
  String get runningTasks => 'In progress';

  @override
  String get tasksNeedingAttention => 'Needs attention';

  @override
  String get clearFailedTasks => 'Clear records';

  @override
  String get clearFailedTasksQuestion => 'Clear failed task records?';

  @override
  String get clearFailedTasksDescription =>
      'This removes failed records and their temporary files. It will not interrupt running tasks or affect saved content.';

  @override
  String get stopTask => 'Stop';

  @override
  String get modelTask => 'Models & downloads';

  @override
  String get attachmentTask => 'Attachment import';

  @override
  String get transcriptionTask => 'Audio processing';

  @override
  String get localInferenceTask => 'Local inference';

  @override
  String backgroundTaskCount(int count) {
    return 'Background tasks · $count';
  }

  @override
  String get noBackgroundTasks => 'No tasks are running or need attention';

  @override
  String backgroundTaskSummary(int active, int failed) {
    return '$active running · $failed need attention';
  }

  @override
  String get allTasksComplete => 'All tasks are complete';

  @override
  String taskActionFailed(String error) {
    return 'Task action failed: $error';
  }

  @override
  String taskProgress(String title) {
    return 'Progress for $title';
  }

  @override
  String get audioTranscription => 'Audio transcription';

  @override
  String get liveDictation => 'Live dictation';

  @override
  String get readAloud => 'Read aloud';

  @override
  String get localInferenceInUse => 'Using local inference resources';

  @override
  String get connectingModelSource => 'Connecting to download source';

  @override
  String get downloadingModel => 'Downloading model';

  @override
  String get importingModel => 'Importing model';

  @override
  String get waitingToInstall => 'Waiting to install';

  @override
  String get verifyingAndInstalling => 'Verifying and installing';

  @override
  String get canceling => 'Canceling';

  @override
  String get completed => 'Completed';

  @override
  String get failed => 'Failed';

  @override
  String get canceled => 'Canceled';

  @override
  String get modelTaskFailed => 'Model task failed';

  @override
  String get importingAttachment => 'Importing attachment';

  @override
  String get savingToNote => 'Saving to note';

  @override
  String get attachmentImportFailed => 'Attachment import failed';

  @override
  String get transcriptionFailed => 'Transcription failed';

  @override
  String get preparingTranscription => 'Preparing transcription';

  @override
  String get decodingAudio => 'Decoding audio';

  @override
  String get identifyingSpeakers => 'Identifying speakers';

  @override
  String get recognizingSpeech => 'Recognizing speech';

  @override
  String get savingTranscript => 'Saving transcript';

  @override
  String get systemAuthentication => 'Use system authentication';

  @override
  String get systemAuthenticationDescription =>
      'Unlock with the biometrics or screen lock already configured on this device. FKNotes never reads or stores biometric data.';

  @override
  String get enableAppLock => 'Enable app lock';

  @override
  String get appLockEnabledDescription =>
      'Verify your device identity when opening FKNotes';

  @override
  String get appLockDisabledDescription =>
      'Off by default and does not change existing data';

  @override
  String get autoLockAfterLeaving => 'Lock after leaving the app';

  @override
  String get lockNow => 'Lock now';

  @override
  String get appLockLimitDescription =>
      'App lock prevents others from viewing content on an unlocked device. It does not encrypt the database, attachments, or exported backups.';

  @override
  String get privacyProtection => 'Privacy protection';

  @override
  String get systemAuthenticationPrivacyFooter =>
      'System authentication · Local content stays private';

  @override
  String get waitingForSystemAuthentication =>
      'Waiting for system authentication';

  @override
  String get preparingAppLock => 'Preparing App lock';

  @override
  String get waitingForSystemVerification => 'Waiting for system verification';

  @override
  String get appLocked => 'App locked';

  @override
  String get loadingLocalSecuritySettings => 'Loading local security settings';

  @override
  String get completeSystemAuthentication =>
      'Complete authentication in the system prompt';

  @override
  String get unlockAppDescription =>
      'Verify your device identity to continue using FKNotes';

  @override
  String get authenticateAndUnlock => 'Authenticate and unlock';

  @override
  String get contentHidden => 'Content hidden';

  @override
  String get authenticateToContinue =>
      'Verify your device identity to continue';

  @override
  String get authenticateToEnableAppLock =>
      'Verify your device identity to enable App lock';

  @override
  String get authenticateToDisableAppLock =>
      'Verify your device identity to disable App lock';

  @override
  String get useDevicePassword => 'Use device passcode';

  @override
  String get authenticationCanceled => 'Authentication canceled';

  @override
  String get authenticationFailedRetry => 'Authentication failed. Try again.';

  @override
  String get authenticationTemporarilyUnavailable =>
      'System authentication is temporarily unavailable. Try again later.';

  @override
  String get authenticationCredentialsRequired =>
      'Set up a screen lock, fingerprint, or face unlock in system settings first.';

  @override
  String get authenticationUnavailable =>
      'System authentication is not available on this device.';

  @override
  String get authenticationLockedOut =>
      'Too many attempts. Use your device passcode or try again later.';

  @override
  String get authenticationInProgress =>
      'System authentication is already in progress.';

  @override
  String get authenticationUiUnavailable =>
      'The system authentication prompt is temporarily unavailable.';

  @override
  String get appLockSaveFailed =>
      'Couldn\'t save App lock settings. Check available storage.';

  @override
  String get autoLockSaveFailed =>
      'Couldn\'t save the auto-lock timeout. Check available storage.';

  @override
  String get back => 'Back';

  @override
  String get syncMethod => 'Sync method';

  @override
  String get saveConfiguration => 'Save configuration';

  @override
  String get testConnection => 'Test connection';

  @override
  String get syncing => 'Syncing…';

  @override
  String get syncNow => 'Sync now';

  @override
  String get manualSyncForegroundHint =>
      'Keep FKNotes in the foreground while syncing. A cloud connection is made only after you tap Sync now.';

  @override
  String get serverAddress => 'Server address';

  @override
  String get username => 'Username';

  @override
  String get passwordOrAppPassword => 'Password or app password';

  @override
  String get remoteDirectory => 'Remote folder';

  @override
  String get objectPrefix => 'Object prefix';

  @override
  String get pathStyleAddress => 'Path-style addressing';

  @override
  String get pathStyleDescription =>
      'Usually required by MinIO and many S3-compatible services';

  @override
  String get hide => 'Hide';

  @override
  String get show => 'Show';

  @override
  String get cloudConfigurationSaved =>
      'Cloud sync configuration saved on this device';

  @override
  String get connectionSuccessful =>
      'Connection successful with read and write access';

  @override
  String get syncConflictDetected => 'Sync conflict detected';

  @override
  String syncConflictDescription(String date) {
    return 'Both local and cloud data may have changed.\n\nCloud version: $date\nChoose which copy to keep. The other copy will be overwritten.';
  }

  @override
  String get notNow => 'Not now';

  @override
  String get useCloudVersion => 'Use cloud';

  @override
  String get keepLocalVersion => 'Keep local';

  @override
  String get syncedLocalToCloud => 'Local data synced to the cloud';

  @override
  String get updatedFromCloud => 'Local data updated from the cloud';

  @override
  String get cloudAlreadyUpToDate => 'Local and cloud data are already in sync';

  @override
  String get syncConflictUnresolved => 'Sync conflict remains unresolved';

  @override
  String get httpsCertificateFailed =>
      'HTTPS certificate validation failed. Check the server certificate.';

  @override
  String get cloudConnectionFailed =>
      'Couldn\'t connect. Check the network and server address.';

  @override
  String get cloudConnectionTimeout => 'Cloud connection timed out';

  @override
  String get manualUserDataSync => 'Manual user data sync only';

  @override
  String get syncScopeDescription =>
      'Includes notes, chats, and attachments. Excludes models, caches, App lock, and cloud account configuration.';

  @override
  String get cloudEncryptionWarning =>
      'Cloud archives are not additionally encrypted. Use HTTPS and a trusted storage provider.';

  @override
  String lastSyncedAt(String date) {
    return 'Last synced: $date';
  }

  @override
  String get cut => 'Cut';

  @override
  String get copy => 'Copy';

  @override
  String get paste => 'Paste';

  @override
  String get selectAll => 'Select all';

  @override
  String get share => 'Share';

  @override
  String get invalidExternalLink =>
      'This link is invalid or uses an unsupported protocol.';

  @override
  String get openExternalLinkQuestion => 'Open external link?';

  @override
  String externalLinkWarning(String destination) {
    return '$destination\n\nThis link will be handled by another app and may take you away from FKNotes.';
  }

  @override
  String get continueOpening => 'Continue';

  @override
  String get noExternalLinkHandler =>
      'No app on this device can open this link.';

  @override
  String get externalLinkOpenFailed => 'Couldn\'t open this link.';

  @override
  String remoteImageBlocked(String label) {
    return 'External image not loaded: $label';
  }

  @override
  String mathFormulaSemantics(String formula) {
    return 'Math formula: $formula';
  }

  @override
  String get assistantPrivacyDescription =>
      'Tell AI what you want to do. Note content is processed only on this device.';

  @override
  String get processingScope => 'Scope';

  @override
  String get scopeSelection => 'Selected text';

  @override
  String get scopeCurrentBlock => 'Current paragraph';

  @override
  String get scopeFullNote => 'Entire note';

  @override
  String get chatWithThisNote => 'Chat with this note';

  @override
  String get chatWithThisNoteDescription =>
      'Use the selected scope as context for follow-up questions';

  @override
  String get linkedNote => 'Linked note';

  @override
  String get noteSources => 'Note sources';

  @override
  String openSourceNote(String title) {
    return 'Open source note: $title';
  }

  @override
  String get sourceNoteUnavailable => 'This source note no longer exists.';

  @override
  String get referenceNotes => 'Reference library notes';

  @override
  String get referenceNotesDescription =>
      'Choose multiple notes as sources for your next message';

  @override
  String get recentNotes => 'Recent notes';

  @override
  String selectedNoteCount(int count) {
    return '$count selected';
  }

  @override
  String noteReferenceLimit(int count) {
    return 'You can reference up to $count notes at a time.';
  }

  @override
  String get noMatchingNotes => 'No matching notes found';

  @override
  String get addSelectedNotes => 'Reference selected notes';

  @override
  String get removeNoteReference => 'Remove note reference';

  @override
  String get pendingNoteSources => 'Next message will reference';

  @override
  String get assistantProposedAction => 'Note action awaiting confirmation';

  @override
  String get toolCreateNote => 'Create a new note';

  @override
  String get toolAppendNote => 'Append to note';

  @override
  String get toolReplaceNote => 'Replace note body';

  @override
  String get reviewToolAction => 'Preview and confirm';

  @override
  String get toolActionCompleted => 'Completed';

  @override
  String get toolActionConfirmationNotice =>
      'This changes a local note. Nothing is written until you confirm.';

  @override
  String get toolTargetNote => 'Target note';

  @override
  String get toolCurrentContent => 'Current content';

  @override
  String get toolProposedContent => 'Proposed content';

  @override
  String get confirmCreateNote => 'Create note';

  @override
  String get confirmAppendNote => 'Append';

  @override
  String get confirmReplaceNote => 'Replace';

  @override
  String get toolActionSucceeded => 'Note action completed';

  @override
  String get toolActionTargetMissing =>
      'The target note was not found. It may have been deleted.';

  @override
  String toolActionFailed(String error) {
    return 'Note action failed: $error';
  }

  @override
  String get toolProposalFallback =>
      'I prepared a note action. Preview and confirm it before anything is changed.';

  @override
  String toolSearchNoResults(String query) {
    return 'No notes matched “$query”. Say that none were found and do not search again.';
  }

  @override
  String toolSearchResultsReady(String query) {
    return 'FKNotes returned note search results for “$query”. Answer the original question using these sources and do not search again.';
  }

  @override
  String get toolSearchRetryBlocked =>
      'The model did not use the search results. Try rephrasing your request.';

  @override
  String get writeReplyToNote => 'Write to note';

  @override
  String get writeReplyToNoteDescription =>
      'Preview the reply and confirm where it should go';

  @override
  String get confirmWriteToNote => 'Write to note';

  @override
  String get replyWrittenToNote => 'Reply written to the note';

  @override
  String get replyWriteToNoteFailed =>
      'The note changed. Return to it and try again.';

  @override
  String get assistantChatResultHeading => 'Local assistant reply';

  @override
  String get chatNoteEmpty => 'Add some note content before starting a chat.';

  @override
  String get assistantCustomHint =>
      'For example: Turn these ideas into a concise email…';

  @override
  String get writeWithAi => 'Write with AI';

  @override
  String get inlineAssistantHint => 'Describe what you want AI to write…';

  @override
  String get inlineAssistantInsertAtCursor => 'Insert at cursor';

  @override
  String get inlineAssistantReplaceSelection => 'Replace selection';

  @override
  String get inlineAssistantWriting => 'Writing into your note…';

  @override
  String get inlineAssistantLoading => 'Preparing the local model…';

  @override
  String get inlineAssistantWritten => 'Content added to your note';

  @override
  String get inlineAssistantContinue => 'Keep creating';

  @override
  String get inlineAssistantContinueWriting => 'Continue this passage';

  @override
  String get inlineAssistantMakeList => 'Organize as a list';

  @override
  String get inlineAssistantExpandIdea => 'Expand this idea';

  @override
  String get startGenerating => 'Generate';

  @override
  String get quickActions => 'Quick actions';

  @override
  String get assistantSummarize => 'Summarize note';

  @override
  String get assistantSummarizeDescription =>
      'Extract the main conclusion and key points';

  @override
  String get assistantExtractTodos => 'Extract tasks';

  @override
  String get assistantExtractTodosDescription => 'Find clear, actionable tasks';

  @override
  String get assistantPolish => 'Improve writing';

  @override
  String get assistantPolishDescription =>
      'Improve clarity while preserving facts and structure';

  @override
  String get assistantCustomAction => 'Custom instruction';

  @override
  String get assistantNoOutput => 'The model didn\'t generate any content.';

  @override
  String get stopGenerating => 'Stop';

  @override
  String get regenerate => 'Generate again';

  @override
  String get chooseGeneratedContentPlacement =>
      'Choose how to use the generated content';

  @override
  String get placementReplace => 'Replace original';

  @override
  String get placementInsertBelow => 'Insert below paragraph';

  @override
  String get placementAppend => 'Append to note';

  @override
  String get useCurrentContent => 'Use current content';

  @override
  String get useGeneratedContent => 'Use generated content';

  @override
  String get generatedContentCopied => 'Generated content copied';

  @override
  String get loadingLocalModel => 'Loading local model…';

  @override
  String get generatingOnDevice => 'Generating on device…';

  @override
  String get generationCompleted => 'Generation complete. Review before using.';

  @override
  String get generationLimitReached =>
      'Output limit reached. Review the result.';

  @override
  String get generationStoppedUsable =>
      'Generation stopped. You can copy or insert the current result.';

  @override
  String get generationTimedOutUsable =>
      'Generation timed out. Retry or copy the current result.';

  @override
  String get generationIncomplete => 'Local generation didn\'t finish.';

  @override
  String get retry => 'Retry';

  @override
  String get maybeLater => 'Maybe later';

  @override
  String get readNoteAloud => 'Read note aloud';

  @override
  String get offlineReadAloudModelRequired =>
      'Offline read-aloud model required';

  @override
  String get readAloudModelDownloadDescription =>
      'Kokoro Chinese-English INT8 requires an initial 140.2 MB download. Afterward, note read-aloud works entirely offline.';

  @override
  String get manageModels => 'Manage models';

  @override
  String get noteReadAloudFailed => 'Couldn\'t read this note aloud.';

  @override
  String get liveDictationIncomplete => 'Live dictation didn\'t finish.';

  @override
  String get unsavedDraftFound => 'Unsaved draft found';

  @override
  String get unsavedDraftDescription =>
      'The last editing session may have ended unexpectedly. Restore content that wasn\'t saved to the note?';

  @override
  String get discardDraft => 'Discard';

  @override
  String get restore => 'Restore';

  @override
  String get liveSpeechModelRequired => 'Live speech model required';

  @override
  String liveSpeechModelDownloadDescription(String model, String size) {
    return 'The selected model is $model. Its first use requires about $size. After downloading, dictation works entirely offline.';
  }

  @override
  String get placeCursorInText => 'Place the cursor in a text area first.';

  @override
  String get liveDictationStartFailed => 'Couldn\'t start live dictation.';

  @override
  String get localLanguageModelRequired => 'Local language model required';

  @override
  String localLanguageModelDownloadDescription(String model, String size) {
    return 'The selected model is $model. Its first use requires about $size. After downloading, note content is processed only on this device.';
  }

  @override
  String get assistantReplacedContent => 'Original content replaced';

  @override
  String get assistantInsertedBelow => 'Inserted below the current paragraph';

  @override
  String get assistantAppended => 'Appended to the end of the note';

  @override
  String get noteChangedRetryAssistant =>
      'The note changed. Start the AI action again.';

  @override
  String assistantLaunchFailed(String error) {
    return 'Couldn\'t start the local assistant: $error';
  }

  @override
  String autosaveFailed(String error) {
    return 'Autosave failed: $error';
  }

  @override
  String get addToNote => 'Add to note';

  @override
  String get camera => 'Camera';

  @override
  String attachmentImportTypeFailed(String type) {
    return 'Couldn\'t import $type.';
  }

  @override
  String get editNote => 'Edit note';

  @override
  String get newNote => 'New note';

  @override
  String get autosaveEnabled => 'Autosave is on';

  @override
  String get autosavePending => 'Autosaving shortly';

  @override
  String get autosaving => 'Autosaving…';

  @override
  String get autosavedLocally => 'Autosaved on this device';

  @override
  String get autosaveFailedShort => 'Autosave failed';

  @override
  String get savingEllipsis => 'Saving…';

  @override
  String get localDraft => 'Local draft';

  @override
  String get savedLocally => 'Saved on device';

  @override
  String characterCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count characters',
      one: '1 character',
    );
    return '$_temp0';
  }

  @override
  String get stopReadAloud => 'Stop read-aloud';

  @override
  String get moreNoteActions => 'More note actions';

  @override
  String get unpin => 'Unpin';

  @override
  String get pin => 'Pin';

  @override
  String get addTags => 'Add tags';

  @override
  String get tags => 'Tags';

  @override
  String get noteContent => 'Note content';

  @override
  String attachmentItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count attachments',
      one: '1 attachment',
    );
    return '$_temp0';
  }

  @override
  String get noteDescriptionHint => 'Add context, ideas, or a summary…';

  @override
  String get noteStartHint => 'Start writing…';

  @override
  String get addMediaOrFile => 'Add an image, recording, or file';

  @override
  String get editTags => 'Edit tags';

  @override
  String get tagsDescription =>
      'Separate tags with commas. Duplicates are merged automatically.';

  @override
  String get tagsHint => 'For example: Work, Ideas, Read later';

  @override
  String get stopLiveDictation => 'Stop live dictation';

  @override
  String get liveVoiceInput => 'Live voice input';

  @override
  String get redo => 'Redo';

  @override
  String get bold => 'Bold';

  @override
  String get italic => 'Italic';

  @override
  String get underline => 'Underline';

  @override
  String get addLink => 'Add link';

  @override
  String get editLink => 'Edit link';

  @override
  String get linkPrivacyDescription =>
      'The link is saved in Markdown. FKNotes will still ask before opening it.';

  @override
  String get linkAddress => 'Link address';

  @override
  String get removeLink => 'Remove link';

  @override
  String get organizingLastSentence => 'Finishing the last sentence…';

  @override
  String get liveDictationFailed => 'Live dictation failed.';

  @override
  String get listening => 'Listening…';

  @override
  String liveDictationElapsed(String time) {
    return 'Live dictation  $time';
  }

  @override
  String get localVoiceInput => 'On-device voice input';

  @override
  String get cancelDictation => 'Cancel dictation';

  @override
  String get finishDictation => 'Finish dictation';

  @override
  String get paragraph => 'Paragraph';

  @override
  String get paragraphStyle => 'Paragraph style';

  @override
  String headingLevel(int level) {
    return 'Heading $level';
  }

  @override
  String get quote => 'Quote';

  @override
  String get codeBlock => 'Code block';

  @override
  String get divider => 'Divider';

  @override
  String get listsAndIndentation => 'Lists and indentation';

  @override
  String get todoItem => 'To-do item';

  @override
  String get bulletList => 'Bulleted list';

  @override
  String get numberedList => 'Numbered list';

  @override
  String get decreaseIndent => 'Decrease indent';

  @override
  String get increaseIndent => 'Increase indent';

  @override
  String get moreFormatting => 'More formatting';

  @override
  String get strikethrough => 'Strikethrough';

  @override
  String get inlineCode => 'Inline code';

  @override
  String get generatingThumbnail => 'Generating thumbnail…';

  @override
  String importingBytes(String bytes) {
    return 'Importing · $bytes';
  }

  @override
  String importingPercent(int percent, String bytes) {
    return 'Importing $percent% · $bytes';
  }

  @override
  String get importCompleteSaving => 'Import complete. Saving to note…';

  @override
  String get importFailedRetry => 'Import failed. Try again.';

  @override
  String get importCanceled => 'Import canceled';

  @override
  String get cancelImport => 'Cancel import';

  @override
  String chooseTypeAgain(String type) {
    return 'Choose $type again';
  }

  @override
  String get adjustAttachment => 'Reorder attachment';

  @override
  String get moveUp => 'Move up';

  @override
  String get moveDown => 'Move down';

  @override
  String get referenceInBody => 'Reference in note';

  @override
  String importFailedDetail(String error) {
    return 'Import failed · $error';
  }

  @override
  String get assistantSummaryHeading => 'Local assistant summary';

  @override
  String get assistantTodosHeading => 'Local assistant tasks';

  @override
  String get assistantPolishedHeading => 'Local assistant revision';

  @override
  String get assistantGeneratedHeading => 'AI-generated content';

  @override
  String attachmentReference(String path) {
    return 'Attachment reference: $path';
  }

  @override
  String get markdownTable => 'Markdown table';

  @override
  String tableDimensions(int columns, int rows) {
    return '$columns columns · $rows rows';
  }

  @override
  String get deleteTable => 'Delete table';

  @override
  String get editTable => 'Edit table';

  @override
  String get invalidMarkdownTable =>
      'The table syntax is incomplete. Check the Markdown source first.';

  @override
  String get attachmentRemoved => 'Attachment removed';

  @override
  String get brokenAttachmentReference =>
      'This reference is no longer valid. You can remove it.';

  @override
  String attachmentReferenceDescription(String type, String size) {
    return '$type · $size · Tap to preview';
  }

  @override
  String get removeReference => 'Remove reference';

  @override
  String tableEditorDescription(int columns, int rows) {
    return '$columns columns · $rows rows · Swipe horizontally to view all columns';
  }

  @override
  String get addColumn => 'Add column';

  @override
  String get addRow => 'Add row';

  @override
  String deleteRow(int row) {
    return 'Delete row $row';
  }

  @override
  String get saveTable => 'Save table';

  @override
  String get tableHeader => 'Header';

  @override
  String get deleteColumn => 'Delete column';

  @override
  String get cellAlignment => 'Cell alignment';

  @override
  String get alignLeft => 'Align left';

  @override
  String get alignCenter => 'Center';

  @override
  String get alignRight => 'Align right';

  @override
  String get content => 'Content';

  @override
  String get untitled => 'Untitled';

  @override
  String todayAt(String time) {
    return 'Today $time';
  }

  @override
  String yesterdayAt(String time) {
    return 'Yesterday $time';
  }

  @override
  String get quickNoteTile => 'Quick\nnote';

  @override
  String get edit => 'Edit';

  @override
  String mixedAttachmentMetadata(int count) {
    return 'Mixed · $count items';
  }

  @override
  String imageAttachmentMetadata(int count) {
    return 'Images · $count';
  }

  @override
  String audioAttachmentMetadata(int count) {
    return 'Recordings · $count';
  }

  @override
  String videoAttachmentMetadata(int count) {
    return 'Videos · $count';
  }

  @override
  String fileAttachmentMetadata(int count) {
    return 'Files · $count';
  }

  @override
  String get localLanguageModel => 'Local language model';

  @override
  String get conversationHistory => 'Chat history';

  @override
  String get personaManagement => 'Personas';

  @override
  String get moreConversationActions => 'More chat actions';

  @override
  String get newConversation => 'New chat';

  @override
  String get deleteCurrentConversation => 'Delete current chat';

  @override
  String get jumpToBottom => 'Jump to bottom';

  @override
  String get generalAssistant => 'General assistant';

  @override
  String get textOnlyRuntimeImageWarning =>
      'The current local runtime supports text only. Images remain in the composer; remove them or wait for a multimodal runtime.';

  @override
  String get imageConversation => 'Image chat';

  @override
  String chatModelDownloadDescription(String model, String size) {
    return 'The selected model is $model. Its first use requires about $size. Chat content is processed only on this device.';
  }

  @override
  String get imageKeptUnsupportedModel =>
      'The image remains in the composer. The current model can\'t understand images; switch to a compatible model.';

  @override
  String get voiceInputBusyElsewhere =>
      'Another page is using live voice input.';

  @override
  String get voiceInputFailed => 'Voice input failed.';

  @override
  String get deleteCurrentConversationQuestion => 'Delete current chat?';

  @override
  String get deleteConversationDescription =>
      'The messages and persona selection in this chat can\'t be recovered.';

  @override
  String chatSaveFailed(String error) {
    return 'Couldn\'t save chat history: $error';
  }

  @override
  String get today => 'Today';

  @override
  String get yesterday => 'Yesterday';

  @override
  String get installedState => 'Installed';

  @override
  String get notInstalledState => 'Not installed';

  @override
  String get modelRuntimeStandby => 'Standby';

  @override
  String get modelRuntimeStandbyDetail =>
      'The model starts automatically when you send a message and is released after 2 minutes of inactivity to save memory.';

  @override
  String get modelRuntimeStarting => 'Starting';

  @override
  String get modelRuntimeStartingDetail =>
      'Starting the local model. The first launch may take a moment.';

  @override
  String modelRuntimeStartingBackend(String backend) {
    return 'Starting $backend';
  }

  @override
  String modelRuntimeSwitchingBackend(String backend) {
    return 'Loading $backend';
  }

  @override
  String modelRuntimeRetryingBackend(String backend) {
    return 'Retrying on $backend';
  }

  @override
  String get modelRuntimeReleasing => 'Releasing';

  @override
  String get modelRuntimeReleasingDetail =>
      'Releasing memory used by the local model.';

  @override
  String get modelRuntimeFailed => 'Start failed';

  @override
  String get modelRuntimeFailedDetail =>
      'The local model could not start. Sending a message will retry automatically.';

  @override
  String get modelRuntimeUnavailable => 'Unavailable';

  @override
  String get modelRuntimeUnavailableDetail =>
      'This device cannot currently run the local model.';

  @override
  String get modelRuntimeGpu => 'GPU';

  @override
  String get modelRuntimeCpu => 'CPU';

  @override
  String modelRuntimeBackendDetail(String backend) {
    return 'Current runtime backend: $backend';
  }

  @override
  String dictationExecutionProvider(String provider) {
    return 'Live speech provider: $provider';
  }

  @override
  String get dictationExecutionProviderFallback =>
      'Hardware acceleration is unavailable. Live speech fell back to CPU.';

  @override
  String get chatEmptyTitle => 'What would you like to explore?';

  @override
  String get chatEmptyDescription =>
      'Ask anything. Messages and persona settings remain on this device.';

  @override
  String get chatSuggestionPriorities =>
      'Help me identify today\'s three most important priorities';

  @override
  String get chatSuggestionExplain =>
      'Explain a complex idea in plain language';

  @override
  String get chatSuggestionDevelopIdea => 'Help me develop a new idea';

  @override
  String get yourImageMessage => 'Your image message';

  @override
  String get yourMessage => 'Your message';

  @override
  String get aiReplying => 'AI is replying';

  @override
  String get aiReply => 'AI reply';

  @override
  String get stopped => 'Stopped';

  @override
  String get copyReply => 'Copy reply';

  @override
  String get replyCopied => 'Reply copied';

  @override
  String get generating => 'Generating…';

  @override
  String get assistantPreparingModel => 'Preparing the local model…';

  @override
  String assistantStartingBackend(String backend) {
    return 'Starting $backend…';
  }

  @override
  String assistantSwitchingBackend(String previousBackend, String backend) {
    return '$previousBackend failed to start. Loading the $backend model…';
  }

  @override
  String assistantRetryingBackend(String backend) {
    return 'The $backend model is ready. Processing this message again…';
  }

  @override
  String get assistantThinking => 'Thinking…';

  @override
  String get assistantUsingNoteTools => 'Working with your notes…';

  @override
  String assistantSearchingNotes(String query) {
    return 'Searching notes for “$query”…';
  }

  @override
  String get assistantComposingWithNotes =>
      'Composing an answer from your notes…';

  @override
  String get modelDoesNotSupportImages =>
      'The current model can\'t understand images. Switch models before sending.';

  @override
  String get takePhoto => 'Take photo';

  @override
  String get takePhotoUnsupported => 'Take photo (current model unsupported)';

  @override
  String get dictating => 'Listening…';

  @override
  String get messageOrVoiceHint => 'Message or use voice…';

  @override
  String get stopGeneration => 'Stop generation';

  @override
  String get finishVoiceInput => 'Finish voice input';

  @override
  String get send => 'Send';

  @override
  String get voiceInput => 'Voice input';

  @override
  String get addImage => 'Add image';

  @override
  String get addImageUnsupported => 'Add image (current model unsupported)';

  @override
  String get preparingOfflineSpeech => 'Preparing offline speech recognition…';

  @override
  String get dictationTapMicToFinish =>
      'Listening. Tap the microphone to finish.';

  @override
  String get previewImage => 'Preview image';

  @override
  String get removeImage => 'Remove image';

  @override
  String get addMoreImages => 'Add more images';

  @override
  String previewImageNumber(int index) {
    return 'Preview image $index';
  }

  @override
  String get closePreview => 'Close preview';

  @override
  String get imageCannotOpen => 'Couldn\'t open image';

  @override
  String get dismissMessage => 'Dismiss message';

  @override
  String get readAgain => 'Read again';

  @override
  String get switchPersona => 'Switch persona';

  @override
  String get manage => 'Manage';

  @override
  String get noSavedConversations => 'No saved chats';

  @override
  String conversationMessageCount(int count, String time) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages',
      one: '1 message',
    );
    return '$_temp0 · $time';
  }

  @override
  String personaDeleteQuestion(String name) {
    return 'Delete “$name”?';
  }

  @override
  String get personaDeleteDescription =>
      'Chats using this persona will switch to General assistant. Chat history won\'t be deleted.';

  @override
  String get createPersona => 'New persona';

  @override
  String get reload => 'Reload';

  @override
  String get personaManagementDescription =>
      'Personas define the identity, tone, and rules used by the local model. Switch at any time while chatting. All settings remain on this device.';

  @override
  String get builtIn => 'Built in';

  @override
  String get current => 'Current';

  @override
  String get personaDescriptionMissing => 'No description';

  @override
  String get personaActions => 'Persona actions';

  @override
  String get editPersona => 'Edit persona';

  @override
  String get deletePersona => 'Delete persona';

  @override
  String get personaInstructionDescription =>
      'The name appears in the persona switcher. The system prompt is sent as the highest-priority local instruction with every request.';

  @override
  String get personaName => 'Persona name';

  @override
  String get shortDescriptionOptional => 'Short description (optional)';

  @override
  String get systemPrompt => 'System prompt';

  @override
  String get systemPromptHint =>
      'For example: You are a patient English conversation coach…';

  @override
  String get savePersona => 'Save persona';

  @override
  String get microphonePermissionRequired => 'Microphone permission required';

  @override
  String get microphonePermissionDescription =>
      'Recordings are saved only on this device. Allow microphone access before starting.';

  @override
  String get openSettings => 'Open settings';

  @override
  String recordingStartFailed(String error) {
    return 'Couldn\'t start recording: $error';
  }

  @override
  String voiceNoteDefaultTitle(String date, String time) {
    return 'Voice note $date $time';
  }

  @override
  String recordingSaveFailed(String error) {
    return 'Couldn\'t save recording: $error';
  }

  @override
  String get discardRecordingQuestion => 'Discard this recording?';

  @override
  String get discardRecordingDescription =>
      'The unsaved recording will be deleted.';

  @override
  String get continueEditing => 'Continue editing';

  @override
  String get discard => 'Discard';

  @override
  String get deviceOnly => 'On device';

  @override
  String get recordIdea => 'Record an idea';

  @override
  String get recordingPrivacyDescription =>
      'Recordings stay on this device by default and are uploaded only during manual cloud sync. Add tags and notes after saving.';

  @override
  String get preparingMicrophone => 'Preparing microphone…';

  @override
  String get startRecording => 'Start recording';

  @override
  String get paused => 'Paused';

  @override
  String get recording => 'Recording';

  @override
  String get resume => 'Resume';

  @override
  String get pause => 'Pause';

  @override
  String get recordAgain => 'Record again';

  @override
  String get saveVoiceNote => 'Save voice note';

  @override
  String get editTranscript => 'Edit transcript';

  @override
  String get transcriptLocalOnlyDescription =>
      'Only the local transcript is changed. The original recording remains unchanged.';

  @override
  String get transcriptHint => 'Enter transcript';

  @override
  String transcriptCharacterCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count characters',
      one: '1 character',
    );
    return '$_temp0';
  }

  @override
  String get preparingModel => 'Preparing model';

  @override
  String get recognizedTextCopied => 'Recognized text copied';

  @override
  String ocrFailedDetail(String error) {
    return 'OCR failed: $error';
  }

  @override
  String get noClearTextRecognized => 'No clear text recognized';

  @override
  String get importOfflineSpeechModel => 'Import offline speech model';

  @override
  String get importSpeechModelDescription =>
      'From the extracted SenseVoice Small INT8 model directory, select both the ONNX model and tokens.txt.\n\nThe model is about 228 MB, stays on this device, and is excluded from note backups.';

  @override
  String get chooseFiles => 'Choose files';

  @override
  String get importingOfflineModel => 'Importing offline model';

  @override
  String get offlineSpeechModelImported => 'Offline speech model imported';

  @override
  String modelImportFailed(String error) {
    return 'Model import failed: $error';
  }

  @override
  String get downloadOfflineSpeechModelQuestion =>
      'Download offline speech model?';

  @override
  String get downloadSpeechModelDescription =>
      'About 228 MB will be downloaded from ModelScope. Wi-Fi is recommended.\n\nDownloading the model uses the network. Notes and audio are uploaded only during manual cloud sync. Interrupted downloads can resume.';

  @override
  String get downloadingFromModelScope => 'Downloading from ModelScope';

  @override
  String get offlineSpeechModelDownloaded => 'Offline speech model downloaded';

  @override
  String get downloadPausedResumable =>
      'Download paused. It will resume next time.';

  @override
  String modelDownloadFailedDetail(String error) {
    return 'Model download failed: $error';
  }

  @override
  String get finishingInstallation => 'Finishing installation';

  @override
  String importedAmount(String amount) {
    return 'Imported $amount';
  }

  @override
  String downloadedAmount(String amount) {
    return 'Downloaded $amount';
  }

  @override
  String amountFinishingInstall(String amount) {
    return '$amount · Finishing installation';
  }

  @override
  String get speedTesting => 'Testing speed…';

  @override
  String get waitForTranscription =>
      'Wait for the current transcription to finish.';

  @override
  String get removeOfflineModelQuestion => 'Remove offline model?';

  @override
  String get removeOfflineModelDescription =>
      'This frees about 228 MB. Saved transcripts won\'t be deleted.';

  @override
  String get speakerModelRequired => 'Speaker diarization model required';

  @override
  String get speakerModelDownloadDescription =>
      'First use requires an approximately 44.4 MB local-model download. Segmentation and transcription then run entirely on device.';

  @override
  String get speakerCount => 'Number of speakers';

  @override
  String get speakerCountDescription =>
      'Recordings up to 30 minutes are supported. A more accurate speaker count usually produces more stable separation.';

  @override
  String get estimateAutomatically => 'Estimate automatically';

  @override
  String get estimateAutomaticallyDescription =>
      'Best when the number of speakers is unknown';

  @override
  String speakerCountOption(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count speakers',
      one: '1 speaker',
    );
    return '$_temp0';
  }

  @override
  String get transcriptCopied => 'Transcript copied';

  @override
  String get openWithAnotherApp => 'Open with another app';

  @override
  String get editInformation => 'Edit information';

  @override
  String get preview => 'Preview';

  @override
  String get recognizedText => 'Recognized text';

  @override
  String get transcript => 'Transcript';

  @override
  String get information => 'Information';

  @override
  String get textInImage => 'Text in image';

  @override
  String get copyAll => 'Copy all';

  @override
  String get recognizeAgain => 'Recognize again';

  @override
  String get recognizeText => 'Recognize text';

  @override
  String get noRecognizedText => 'No recognized text';

  @override
  String get ocrOnDemandDescription =>
      'Run on-device text recognition on this image when needed';

  @override
  String get recognizing => 'Recognizing…';

  @override
  String get audioTranscript => 'Audio transcript';

  @override
  String get editText => 'Edit text';

  @override
  String get audioStaysOnDevice =>
      'Processed entirely on device. Audio never leaves this device.';

  @override
  String get offlineSpeechModelRequired => 'Offline speech model required';

  @override
  String get offlineModelBackupDescription =>
      'The model is stored separately on this device and doesn\'t increase backup size.';

  @override
  String get downloadAbout228Mb => 'Download about 228 MB';

  @override
  String get backgroundTranscriptionHint =>
      'You can leave this page and continue using notes';

  @override
  String get transcriptionIncomplete => 'Transcription didn\'t finish';

  @override
  String get tryAgainLater => 'Try again later';

  @override
  String get transcribeAgain => 'Transcribe again';

  @override
  String get transcriptionCanceled => 'Transcription canceled';

  @override
  String get recordingUnaffected => 'The recording wasn\'t changed';

  @override
  String get noTranscript => 'No transcript';

  @override
  String get transcriptionOnDemandDescription =>
      'Start on-device recognition only when needed; recordings aren\'t processed automatically.';

  @override
  String get transcribeOnDevice => 'Transcribe on device';

  @override
  String get speakerDiarizedTranscription => 'Transcribe with speakers';

  @override
  String get speakerDiarizedTranscriptionModelRequired =>
      'Transcribe with speakers · 44.4 MB model required';

  @override
  String manageModelSize(String size) {
    return 'Manage model · $size';
  }

  @override
  String get importFromFiles => 'Import from files';

  @override
  String get viewAllModels => 'View all models';

  @override
  String get preparingLocalTranscription => 'Preparing on-device transcription';

  @override
  String get readingAudio => 'Reading audio';

  @override
  String get separatingSpeakers => 'Separating speakers';

  @override
  String get recognizingOnDevice => 'Recognizing on device';

  @override
  String get savingTranscriptText => 'Saving transcript';

  @override
  String get processing => 'Processing';

  @override
  String get noteInformation => 'Note information';

  @override
  String get renameAttachment => 'Rename';

  @override
  String get editAttachmentTitle => 'Edit attachment title';

  @override
  String get attachmentTitle => 'Attachment title';

  @override
  String get attachmentTitleHint => 'Enter the title shown in this note';

  @override
  String get attachmentTitleDescription =>
      'This only changes the title shown in the note. The original file name and file contents stay unchanged.';

  @override
  String get restoreOriginalFileName => 'Restore original file name';

  @override
  String get type => 'Type';

  @override
  String get created => 'Created';

  @override
  String get updated => 'Updated';

  @override
  String get fileInformation => 'File information';

  @override
  String get fileName => 'File name';

  @override
  String get size => 'Size';

  @override
  String get duration => 'Duration';

  @override
  String get saveStatus => 'Save status';

  @override
  String get fileMissing => 'File missing';

  @override
  String get savedInUnifiedDirectory => 'Saved in unified directory';

  @override
  String get description => 'Description';

  @override
  String get originalFileMissing => 'Original file missing';

  @override
  String get missingFileDescription =>
      'Keep the note information or delete it permanently.';

  @override
  String get openWithLocalApp => 'Open with local app';

  @override
  String get coverSettings => 'Cover settings';

  @override
  String get noteCover => 'Cover';

  @override
  String get coverSettingsDescription =>
      'Choose how this note appears on Home and in the Library.';

  @override
  String get coverAutomatic => 'Automatic';

  @override
  String get coverAutomaticDescription =>
      'Prefer an image or video from the note, otherwise use a type cover';

  @override
  String get coverType => 'Type cover';

  @override
  String get coverTypeDescription =>
      'Use a consistent note, image, audio, video, or file icon';

  @override
  String get hideCover => 'Hide cover';

  @override
  String get hideCoverDescription =>
      'Show only the title, preview, and modified time';

  @override
  String get chooseAttachmentCover => 'Choose from note attachments';

  @override
  String get setAsCover => 'Set as cover';

  @override
  String get currentCover => 'Current cover';

  @override
  String get shareNoteAsImage => 'Share as images';

  @override
  String get noteHasNoShareableContent =>
      'This note has no content to share yet';

  @override
  String get createShareImage => 'Create share images';

  @override
  String get shareImageStyle => 'Style';

  @override
  String get shareImageCanvas => 'Canvas';

  @override
  String get shareImageRatio => 'Image ratio';

  @override
  String get shareImageContent => 'Content';

  @override
  String get shareImageLayout => 'Layout';

  @override
  String get shareTemplateLetter => 'A Letter from FKNotes';

  @override
  String get shareTemplatePlain => 'Plain Paper';

  @override
  String get shareTemplateNight => 'Night Reading';

  @override
  String get shareTemplateEditorial => 'Editorial';

  @override
  String get shareTemplateNewspaper => 'Morning Press';

  @override
  String get shareTemplateManuscript => 'Grid Manuscript';

  @override
  String get shareTemplateBotanical => 'Botanical';

  @override
  String get shareTemplateBlueprint => 'Blueprint';

  @override
  String get shareTemplateAmber => 'Amber';

  @override
  String get shareTemplateFilm => 'Film Strip';

  @override
  String get shareTemplatePostcard => 'Postcard';

  @override
  String get shareTemplateGallery => 'Gallery Label';

  @override
  String get shareTemplateNeon => 'Neon';

  @override
  String get shareTemplateTide => 'Tides';

  @override
  String get shareTemplateVermilion => 'Vermilion';

  @override
  String get shareRatioSquare => '1:1 · Square card';

  @override
  String get shareRatioFourFive => '4:5 · Social portrait';

  @override
  String get shareRatioThreeFour => '3:4 · Note card';

  @override
  String get shareRatioNineSixteen => '9:16 · Full screen';

  @override
  String get shareRatioSixteenNine => '16:9 · Landscape';

  @override
  String get shareRatioA4 => 'A4 · Document';

  @override
  String get shareRatioLong => 'Long image · One adaptive canvas';

  @override
  String get shareLongImageHint =>
      'The canvas grows with the content and exports as one image';

  @override
  String get shareRatioCustom => 'Custom size';

  @override
  String get portraitOrientation => 'Portrait';

  @override
  String get landscapeOrientation => 'Landscape';

  @override
  String get shareImageWidth => 'Width';

  @override
  String get shareImageHeight => 'Height';

  @override
  String get shareImageQuality => 'Quality';

  @override
  String get shareQualityStandard => 'Standard · 1080 px short edge';

  @override
  String get shareQualityHigh => 'High · 1440 px short edge';

  @override
  String get shareQualityUltra => 'Ultra · 2160 px short edge';

  @override
  String get includeNoteTitle => 'Show title';

  @override
  String get includeNoteDate => 'Show date';

  @override
  String get includeNoteTags => 'Show tags';

  @override
  String get includeNoteImages => 'Show images';

  @override
  String get includeNoteAttachments => 'Show attachments';

  @override
  String get noteShareSource => 'Created with FKNotes · 非空笔记';

  @override
  String get noteShareSourceAlwaysIncluded =>
      'The source is kept on every shared image';

  @override
  String get shareDensityComfortable => 'Comfortable';

  @override
  String get shareDensityStandard => 'Standard';

  @override
  String get shareDensityCompact => 'Compact';

  @override
  String get noteShareUntitled => 'A note';

  @override
  String get generateAndShare => 'Generate and share';

  @override
  String get previousPage => 'Previous page';

  @override
  String get nextPage => 'Next page';

  @override
  String shareImagePageIndicator(int current, int total) {
    return 'Page $current of $total';
  }

  @override
  String shareImageOutputSummary(int count, int width, int height) {
    return 'Creates $count PNG images at $width × $height';
  }

  @override
  String generatingShareImageProgress(int current, int total) {
    return 'Generating image $current of $total';
  }

  @override
  String shareNoteImageTitle(String title) {
    return 'Share note: $title';
  }

  @override
  String get shareImageGenerationFailed =>
      'Couldn\'t create the share images. Try another canvas or quality setting.';
}
