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
  String get deletePermanently => 'Delete permanently';

  @override
  String get deletePermanentlyQuestion => 'Delete permanently?';

  @override
  String get deletePermanentlyDescription =>
      'The note and its files cannot be recovered.';

  @override
  String get movedToTrash => 'Moved to Trash';

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
  String get emptyTrash => 'Empty Trash';

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
  String get favorites => 'Favorites';

  @override
  String get archive => 'Archive';

  @override
  String get trash => 'Trash';

  @override
  String get emptyActive => 'No content matches this filter';

  @override
  String get emptyFavorites => 'Favorite notes will appear here';

  @override
  String get emptyArchive => 'The archive is empty';

  @override
  String get emptyTrashDescription => 'Trash is empty';

  @override
  String get emptyTrashQuestion => 'Empty Trash?';

  @override
  String emptyTrashConfirmation(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items and their files',
      one: '1 item and its files',
    );
    return 'This will permanently delete $_temp0.';
  }

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
  String get privateAppStorage => 'Private app storage';

  @override
  String get privateAppStorageSubtitle =>
      'Notes, chats, files, and thumbnails stay on this device';

  @override
  String get localModels => 'Local models';

  @override
  String get localModelsSubtitle =>
      'Download, import, and remove on-device models';

  @override
  String get backupAndMigration => 'Backup and migration';

  @override
  String get exportCompleteBackup => 'Export full backup';

  @override
  String get exportCompleteBackupSubtitle =>
      'Save all notes and files through the system share sheet';

  @override
  String get restoreFromBackup => 'Restore from backup';

  @override
  String get restoreFromBackupSubtitle =>
      'The backup is verified before restoration';

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
  String get modelPrivacyHint =>
      'Models connect only when you download them and are excluded from note backups. User data is uploaded only during manual cloud sync.';

  @override
  String get languageModels => 'Language models';

  @override
  String get languageModelsDescription =>
      'Download and choose the model used by Local Assistant. The default context is 4096 tokens.';

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
  String get cancelingDownload => 'Canceling and keeping downloaded data…';

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
  String get importedVerb => 'Imported';

  @override
  String get downloadedVerb => 'Downloaded';

  @override
  String get waitingFirstPacket => 'Waiting for the first data packet…';

  @override
  String get thirdPartyMainlandMirror => 'Third-party regional mirror';

  @override
  String get githubOfficialSource => 'Official GitHub source';

  @override
  String get modelScopeSource => 'ModelScope';

  @override
  String get backgroundTasks => 'Background tasks';

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
  String get assistantCustomHint =>
      'For example: Turn these ideas into a concise email…';

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
  String get removeFavorite => 'Remove from favorites';

  @override
  String get addFavorite => 'Add to favorites';

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
  String get removeFromArchive => 'Remove from archive';

  @override
  String get edit => 'Edit';

  @override
  String get moveToTrash => 'Move to trash';

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
}
