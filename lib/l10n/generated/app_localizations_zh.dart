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

  @override
  String get localStorageInitializationFailed => '本地存储初始化失败';

  @override
  String get home => '主页';

  @override
  String get library => '资料库';

  @override
  String get data => '数据';

  @override
  String get createNew => '新建';

  @override
  String get undo => '撤销';

  @override
  String get cancel => '取消';

  @override
  String get deletePermanently => '永久删除';

  @override
  String get deletePermanentlyQuestion => '永久删除？';

  @override
  String get deletePermanentlyDescription => '笔记和关联文件将无法恢复。';

  @override
  String get movedToTrash => '已移到回收站';

  @override
  String get captureMoment => '捕捉此刻';

  @override
  String get capturePrivacyHint => '离线保存，你的内容只属于你';

  @override
  String get note => '笔记';

  @override
  String get photo => '拍照';

  @override
  String get image => '图片';

  @override
  String get record => '录音';

  @override
  String get audio => '音频';

  @override
  String get video => '视频';

  @override
  String get file => '文件';

  @override
  String get voiceNote => '语音笔记';

  @override
  String importFailed(String type) {
    return '$type导入失败';
  }

  @override
  String get recentlyUpdated => '最近更新';

  @override
  String get more => '更多';

  @override
  String get startWithIdea => '从一个念头开始';

  @override
  String get createNoteEmptyHint => '点击“新建”，内容会安全留在本机。';

  @override
  String get localAssistant => '本地助手';

  @override
  String get searchLocalKnowledge => '搜索本地知识库';

  @override
  String get searchNotes => '搜索笔记';

  @override
  String get savedOnlyOnDevice => '仅保存在本机';

  @override
  String get allNotes => '所有笔记';

  @override
  String noteCountShort(int count) {
    return '$count 条笔记';
  }

  @override
  String attachmentCountShort(int count) {
    return '$count 个附件';
  }

  @override
  String createType(String type) {
    return '新建$type';
  }

  @override
  String itemCount(int count) {
    return '$count 个条目';
  }

  @override
  String get search => '搜索';

  @override
  String get emptyTrash => '清空回收站';

  @override
  String get sort => '排序';

  @override
  String get creationTime => '创建时间';

  @override
  String get title => '标题';

  @override
  String get fileSize => '文件大小';

  @override
  String get all => '全部';

  @override
  String get favorites => '收藏';

  @override
  String get archive => '归档';

  @override
  String get trash => '回收站';

  @override
  String get emptyActive => '当前筛选下没有内容';

  @override
  String get emptyFavorites => '收藏的内容会出现在这里';

  @override
  String get emptyArchive => '归档箱是空的';

  @override
  String get emptyTrashDescription => '回收站是空的';

  @override
  String get emptyTrashQuestion => '清空回收站？';

  @override
  String emptyTrashConfirmation(int count) {
    return '将永久删除 $count 条内容和关联文件。';
  }

  @override
  String get clear => '清空';

  @override
  String get allTypes => '所有类型';

  @override
  String get unavailable => '暂不可用';

  @override
  String get localData => '本地数据';

  @override
  String get localDataSubtitle => '默认只保存在本机；是否同步完全由你决定。';

  @override
  String get localFirst => '本地优先';

  @override
  String get offlineSecure => '离线安全';

  @override
  String get totalItems => '总条目';

  @override
  String get attachments => '附件';

  @override
  String get userDataUsage => '资料占用';

  @override
  String get preferences => '偏好设置';

  @override
  String get unifiedStorage => '统一存储';

  @override
  String get cloudSync => '云同步';

  @override
  String get cloudSyncSubtitle => '手动同步用户数据，支持 S3 和 WebDAV';

  @override
  String get privateAppStorage => '应用私有存储';

  @override
  String get privateAppStorageSubtitle => '笔记、聊天、附件和缩略图均安全保存在本机';

  @override
  String get localModels => '本地模型';

  @override
  String get localModelsSubtitle => '查看正在使用的模型并按能力分类管理';

  @override
  String get backupAndMigration => '备份与迁移';

  @override
  String get exportCompleteBackup => '导出完整备份';

  @override
  String get exportCompleteBackupSubtitle => '通过系统面板保存，包含所有笔记和附件';

  @override
  String get restoreFromBackup => '从备份恢复';

  @override
  String get restoreFromBackupSubtitle => '恢复前会进行完整性检查';

  @override
  String get organizationAndSecurity => '整理与安全';

  @override
  String get appLock => '应用锁';

  @override
  String appLockEnabledSubtitle(String timeout) {
    return '已开启 · 离开应用 $timeout锁定';
  }

  @override
  String get appLockDisabledSubtitle => '使用系统指纹、人脸或锁屏密码';

  @override
  String get lockImmediately => '立即';

  @override
  String get lockAfterOneMinute => '1 分钟后';

  @override
  String get lockAfterFiveMinutes => '5 分钟后';

  @override
  String get lockAfterFifteenMinutes => '15 分钟后';

  @override
  String contentCount(int count) {
    return '$count 条内容';
  }

  @override
  String get about => '关于';

  @override
  String get loadingVersion => '正在读取版本信息…';

  @override
  String versionNumber(String version) {
    return '版本号 $version';
  }

  @override
  String versionNumberWithBuild(String version, String build) {
    return '版本号 $version ($build)';
  }

  @override
  String buildTime(String time) {
    return '构建时间 $time';
  }

  @override
  String get buildTimeUnrecorded => '构建时间 未记录';

  @override
  String get footerTagline => 'FKNotes · 本地优先，同步由你掌控';

  @override
  String get backupExported => '备份已交给系统保存';

  @override
  String exportFailed(String error) {
    return '导出失败：$error';
  }

  @override
  String get restoreCompleteBackupQuestion => '恢复完整备份？';

  @override
  String get restoreCompleteBackupDescription => '当前内容将被备份中的内容替换。建议先导出一份当前数据。';

  @override
  String get chooseBackup => '选择备份';

  @override
  String get backupRestored => '备份已安全恢复';

  @override
  String restoreFailed(String error) {
    return '恢复失败：$error';
  }

  @override
  String get localModelsPageTitle => '本地模型';

  @override
  String get modelsInUse => '正在使用';

  @override
  String get noModelsInUse => '尚未配置正在使用的本地模型';

  @override
  String get modelConfiguration => '分类管理';

  @override
  String activeModelCount(int count) {
    return '正在使用 $count 个模型';
  }

  @override
  String activeModelsUsage(String size) {
    return '本地模型占用 $size';
  }

  @override
  String get installedModels => '已安装';

  @override
  String get availableModels => '可获取';

  @override
  String installedModelsCount(int count) {
    return '已安装 $count 个模型';
  }

  @override
  String get noInstalledModelsInCategory => '这一分类还没有已安装的模型';

  @override
  String get noAvailableModelsInCategory => '当前没有其他可获取的模型';

  @override
  String get speechModelsDescription => '分别管理实时听写、录音转写、语音处理与语音合成模型。';

  @override
  String get visionModelsDescription => '管理 OCR 与专用视觉能力；聊天图片理解由支持图片的语言模型提供。';

  @override
  String get liveDictationSettingsDescription => '管理当前听写模型、热词、精修和实时降噪';

  @override
  String get modelDownloadsAndStorage => '下载与存储';

  @override
  String get modelDownloadsAndStorageDescription => '下载源、后台任务和模型文件占用';

  @override
  String get localAssistantUsage => '本地助手';

  @override
  String get liveDictationUsage => '实时听写';

  @override
  String get audioTranscriptionUsage => '录音转写';

  @override
  String get voiceActivityUsage => '语音检测';

  @override
  String get speechEnhancementUsage => '实时降噪';

  @override
  String get textRecognitionUsage => '文字识别';

  @override
  String get modelPrivacyHint => '模型只在用户下载时联网，且不会进入笔记备份；用户数据仅在手动云同步时上传。';

  @override
  String get languageModels => '语言模型';

  @override
  String get languageModelsDescription => '由用户下载并选择本地助手使用的模型，默认上下文为 4096。';

  @override
  String get discoverMnnModels => '发现本地模型';

  @override
  String get discoverMnnModelsDescription =>
      '浏览从 taobao-mnn 与 litert-community Collections 同步并通过兼容性筛选的公开模型。';

  @override
  String get browseModels => '浏览模型';

  @override
  String get refreshCatalog => '刷新目录';

  @override
  String get syncingModelCatalog => '正在同步模型目录…';

  @override
  String modelCatalogSyncFailed(String error) {
    return '无法刷新模型目录：$error';
  }

  @override
  String get modelCatalogRefreshTimeout => '模型目录刷新超时';

  @override
  String get modelCatalogRefreshTimeoutDescription =>
      '当前网络未能及时连接模型服务。你可以重试或切换模型网络源。';

  @override
  String get modelCatalogOffline => '无法连接模型服务';

  @override
  String get modelCatalogOfflineDescription => '请检查网络连接，或尝试切换模型网络源。';

  @override
  String get modelCatalogServiceUnavailable => '模型服务暂时不可用';

  @override
  String get modelCatalogServiceUnavailableDescription => '服务当前没有正常响应，请稍后重试。';

  @override
  String get modelCatalogAuthorizationRequired => '部分模型需要访问授权';

  @override
  String get modelCatalogAuthorizationRequiredDescription =>
      '当前目录包含需要在 Hugging Face 接受许可后才能访问的模型。';

  @override
  String get modelCatalogInvalidResponse => '模型目录暂时无法读取';

  @override
  String get modelCatalogInvalidResponseDescription => '服务返回了无法识别的数据，请稍后重试。';

  @override
  String get modelCatalogCompatibilityUnavailable => '暂时无法检查模型兼容性';

  @override
  String get modelNetworkSourceSettings => '切换网络源';

  @override
  String get cachedCatalogInUse => '正在显示上次成功同步的目录';

  @override
  String get searchMnnModels => '搜索本地模型';

  @override
  String get noMnnModelsFound => '没有匹配的本地模型';

  @override
  String get officialMnnCollection => 'taobao-mnn 官方 Collection';

  @override
  String get officialLiteRtCollection => 'litert-community 官方 Collection';

  @override
  String downloadCount(int count) {
    return '$count 次下载';
  }

  @override
  String get checkingModelCompatibility => '正在检查模型兼容性…';

  @override
  String get modelCompatibilityPassed => 'MNN 文件与运行配置检查通过';

  @override
  String get liteRtCompatibilityPassed => 'LiteRT-LM 文件、固定版本与校验值检查通过';

  @override
  String modelCompatibilityFailed(String error) {
    return '无法添加该模型：$error';
  }

  @override
  String get pinnedCommit => '固定 commit';

  @override
  String get modelFileCount => '模型文件';

  @override
  String get modelFile => '模型文件';

  @override
  String fileCountValue(int count) {
    return '$count 个文件';
  }

  @override
  String get modelCapabilities => '模型能力';

  @override
  String get textGenerationCapability => '文本生成';

  @override
  String get imageInputCapability => '图片输入';

  @override
  String get audioInputCapability => '音频输入';

  @override
  String get reasoningCapability => '思考推理';

  @override
  String get toolCallingCapability => '工具调用';

  @override
  String get addAndDownloadModel => '添加并下载';

  @override
  String get modelAddedToManager => '模型已添加到本地模型';

  @override
  String get recommendedModelsAlreadyListed => 'FKNotes 推荐模型已在上一页中显示。';

  @override
  String remoteMnnModelSummary(String collection) {
    return '来自 $collection 的官方模型';
  }

  @override
  String get remoteMnnModelDescription =>
      '从 taobao-mnn Collections 同步；安装前会校验仓库版本和每个模型文件。';

  @override
  String get liveDictationSettings => '实时听写设置';

  @override
  String get speechModels => '语音模型';

  @override
  String get visionModels => '视觉模型';

  @override
  String get modelDownloadSource => '模型下载源';

  @override
  String get downloadSourceSecurityDescription =>
      '所有模式都会在首选节点不可用时安全回退；模型仍通过固定版本和 SHA-256 校验。';

  @override
  String get downloadSourceSaveFailed => '下载源设置保存失败';

  @override
  String get downloadSourceAutomatic => '自动选择';

  @override
  String get downloadSourceOfficialFirst => '优先官方源';

  @override
  String get downloadSourceMainlandFirst => '优先国内镜像';

  @override
  String get downloadSourceAutomaticDescription => '结合设备区域和实际连接结果动态选择';

  @override
  String get downloadSourceOfficialDescription =>
      '优先 Hugging Face 或 GitHub 官方节点';

  @override
  String get downloadSourceMainlandDescription => '优先国内镜像或 ModelScope 节点';

  @override
  String downloadSourceEffective(String source) {
    return '自动选择 · $source优先';
  }

  @override
  String get officialSource => '官方源';

  @override
  String get mainlandMirror => '国内镜像';

  @override
  String lastUsedSource(String source) {
    return '最近使用：$source';
  }

  @override
  String get continueModelDownloadQuestion => '继续下载模型？';

  @override
  String get downloadModelQuestion => '下载模型？';

  @override
  String modelDownloadDescription(String name, String size) {
    return '$name\n还需下载约 $size，建议使用 Wi-Fi。\n\n下载中可离开此页面；中断后会保留进度。';
  }

  @override
  String modelMemoryRecommendation(String memory) {
    return '建议设备至少具备 $memory 运行内存；内存不足可能加载失败或被系统终止。';
  }

  @override
  String get ttsStorageRecommendation => '解压安装时请预留约 600 MB 可用空间。';

  @override
  String get startDownload => '开始下载';

  @override
  String removeModelQuestion(String name) {
    return '移除 $name？';
  }

  @override
  String removeModelDescription(String size) {
    return '将释放约 $size 空间。已经生成的笔记内容不会被删除。';
  }

  @override
  String get removeModel => '移除模型';

  @override
  String hotwordsSaved(int count) {
    return '已保存 $count 个热词';
  }

  @override
  String get hotwordsDisabled => '已关闭实时听写热词';

  @override
  String get settingsSaveFailed => '设置保存失败，请检查设备存储空间';

  @override
  String get purpose => '用途';

  @override
  String get engine => '引擎';

  @override
  String get supportedLanguages => '语言';

  @override
  String get version => '版本';

  @override
  String get recommendedMemory => '建议内存';

  @override
  String memoryAndAbove(String memory) {
    return '$memory 及以上';
  }

  @override
  String get source => '来源';

  @override
  String get license => '许可';

  @override
  String get saveFailedStorage => '保存失败，请检查设备存储空间';

  @override
  String get liveDictationHotwords => '实时听写热词';

  @override
  String get hotwordsDescription => '每行输入一个人名、产品名或专业术语；留空即关闭。热词从下一次听写开始生效。';

  @override
  String get hotwordsHint => '非空笔记\nFKNotes\nsherpa onnx';

  @override
  String get hotwordsList => '热词列表';

  @override
  String get boostStrength => '增强强度';

  @override
  String get hotwordsStrengthWarning => '过高的强度可能把发音相近的普通词误判为热词，建议先使用 2.0。';

  @override
  String get saving => '保存中…';

  @override
  String get save => '保存';

  @override
  String get finalRefinement => '结束后精修';

  @override
  String get finalRefinementDescription =>
      '使用 SenseVoice 二次识别，仅在质量检查通过时替换（默认关闭）';

  @override
  String get liveNoiseSuppression => '实时降噪';

  @override
  String get liveNoiseSuppressionDescription => '先抑制环境噪声，再送入流式识别';

  @override
  String get installDenoiserFirst => '请先安装下方的 DPDFNet 实时降噪模型';

  @override
  String get hotwordBoost => '热词增强';

  @override
  String hotwordSummary(int count, String strength) {
    return '$count 个热词 · 强度 $strength';
  }

  @override
  String get hotwordBoostDescription => '优先识别人名、品牌与专业术语';

  @override
  String installedModelCount(int count) {
    return '$count 个模型可用';
  }

  @override
  String optionalModelsUsage(String size) {
    return '可选模型占用 $size';
  }

  @override
  String get recommended => '推荐';

  @override
  String get currentDictation => '当前听写';

  @override
  String get currentAssistant => '当前助手';

  @override
  String get modelDetails => '模型详情';

  @override
  String memoryBadge(String memory) {
    return '$memory+ 内存';
  }

  @override
  String get pleaseWait => '请稍候';

  @override
  String get modelDownloadFailed => '模型下载失败';

  @override
  String get bundledWithApp => '随应用提供';

  @override
  String get comingSoon => '即将支持';

  @override
  String get installed => '已安装';

  @override
  String get useForDictation => '用于听写';

  @override
  String get useForAssistant => '用于助手';

  @override
  String get remove => '移除';

  @override
  String get importFromFile => '从文件导入';

  @override
  String get continueDownload => '继续下载';

  @override
  String get download => '下载';

  @override
  String get cancelingDownload => '正在取消并保留已下载内容…';

  @override
  String connectingDownloadSource(String source) {
    return '正在连接下载节点$source';
  }

  @override
  String downloadedInstalling(String size) {
    return '已下载 $size · 正在完成安装';
  }

  @override
  String downloadedWaitingInstall(String size) {
    return '已下载 $size · 等待安装';
  }

  @override
  String get importedVerb => '已导入';

  @override
  String get downloadedVerb => '已下载';

  @override
  String get waitingFirstPacket => '等待首个数据包…';

  @override
  String get thirdPartyMainlandMirror => '第三方国内镜像';

  @override
  String get githubOfficialSource => 'GitHub 官方源';

  @override
  String get modelScopeSource => 'ModelScope 魔搭';

  @override
  String get backgroundTasks => '后台任务';

  @override
  String backgroundTaskCount(int count) {
    return '后台任务 · $count 项';
  }

  @override
  String get noBackgroundTasks => '当前没有正在运行或需要处理的任务';

  @override
  String backgroundTaskSummary(int active, int failed) {
    return '$active 项进行中 · $failed 项需要处理';
  }

  @override
  String get allTasksComplete => '所有任务均已完成';

  @override
  String taskActionFailed(String error) {
    return '任务操作失败：$error';
  }

  @override
  String taskProgress(String title) {
    return '$title进度';
  }

  @override
  String get audioTranscription => '音频转写';

  @override
  String get liveDictation => '实时听写';

  @override
  String get readAloud => '朗读';

  @override
  String get localInferenceInUse => '正在使用本地推理资源';

  @override
  String get connectingModelSource => '正在连接下载源';

  @override
  String get downloadingModel => '正在下载模型';

  @override
  String get importingModel => '正在导入模型';

  @override
  String get waitingToInstall => '等待安装资源';

  @override
  String get verifyingAndInstalling => '正在校验并安装';

  @override
  String get canceling => '正在取消';

  @override
  String get completed => '已完成';

  @override
  String get failed => '失败';

  @override
  String get canceled => '已取消';

  @override
  String get modelTaskFailed => '模型任务失败';

  @override
  String get importingAttachment => '正在导入附件';

  @override
  String get savingToNote => '正在保存到笔记';

  @override
  String get attachmentImportFailed => '附件导入失败';

  @override
  String get transcriptionFailed => '转写失败';

  @override
  String get preparingTranscription => '正在准备转写';

  @override
  String get decodingAudio => '正在解码音频';

  @override
  String get identifyingSpeakers => '正在区分说话人';

  @override
  String get recognizingSpeech => '正在识别语音';

  @override
  String get savingTranscript => '正在保存转写';

  @override
  String get systemAuthentication => '使用系统身份验证';

  @override
  String get systemAuthenticationDescription =>
      '通过设备已有的指纹、人脸识别或锁屏密码解锁。FKNotes 不会读取或保存你的生物特征。';

  @override
  String get enableAppLock => '启用应用锁';

  @override
  String get appLockEnabledDescription => '打开应用时会验证设备身份';

  @override
  String get appLockDisabledDescription => '默认关闭，不影响现有数据';

  @override
  String get autoLockAfterLeaving => '离开应用后自动锁定';

  @override
  String get lockNow => '立即锁定';

  @override
  String get appLockLimitDescription =>
      '应用锁用于阻止他人在已解锁设备上直接查看内容，不会加密数据库、附件或已经导出的备份。';

  @override
  String get privacyProtection => '隐私保护';

  @override
  String get systemAuthenticationPrivacyFooter => '系统身份验证 · 本地内容保持私密';

  @override
  String get waitingForSystemAuthentication => '正在等待系统身份验证';

  @override
  String get preparingAppLock => '正在准备应用锁';

  @override
  String get waitingForSystemVerification => '等待系统验证';

  @override
  String get appLocked => '应用已锁定';

  @override
  String get loadingLocalSecuritySettings => '正在载入本地安全设置';

  @override
  String get completeSystemAuthentication => '请在系统弹窗中完成身份验证';

  @override
  String get unlockAppDescription => '验证设备身份后继续使用非空笔记';

  @override
  String get authenticateAndUnlock => '验证并解锁';

  @override
  String get contentHidden => '内容已隐藏';

  @override
  String get authenticateToContinue => '验证设备身份以继续';

  @override
  String get authenticateToEnableAppLock => '验证设备身份以开启应用锁';

  @override
  String get authenticateToDisableAppLock => '验证设备身份以关闭应用锁';

  @override
  String get useDevicePassword => '使用设备密码';

  @override
  String get authenticationCanceled => '认证已取消';

  @override
  String get authenticationFailedRetry => '身份验证失败，请重试';

  @override
  String get authenticationTemporarilyUnavailable => '暂时无法调用系统身份验证，请稍后重试';

  @override
  String get authenticationCredentialsRequired => '请先在系统设置中配置锁屏密码、指纹或人脸识别';

  @override
  String get authenticationUnavailable => '当前设备无法使用系统身份验证';

  @override
  String get authenticationLockedOut => '尝试次数过多，请使用设备密码或稍后重试';

  @override
  String get authenticationInProgress => '系统身份验证正在进行';

  @override
  String get authenticationUiUnavailable => '暂时无法显示系统身份验证界面';

  @override
  String get appLockSaveFailed => '应用锁设置保存失败，请检查设备存储空间';

  @override
  String get autoLockSaveFailed => '自动锁定时间保存失败，请检查设备存储空间';

  @override
  String get back => '返回';

  @override
  String get syncMethod => '同步方式';

  @override
  String get saveConfiguration => '保存配置';

  @override
  String get testConnection => '测试连接';

  @override
  String get syncing => '正在同步…';

  @override
  String get syncNow => '立即同步';

  @override
  String get manualSyncForegroundHint => '同步期间请保持应用在前台。只有手动点击“立即同步”才会连接云端。';

  @override
  String get serverAddress => '服务器地址';

  @override
  String get username => '用户名';

  @override
  String get passwordOrAppPassword => '密码或应用专用密码';

  @override
  String get remoteDirectory => '远程目录';

  @override
  String get objectPrefix => '对象前缀';

  @override
  String get pathStyleAddress => 'Path-style 地址';

  @override
  String get pathStyleDescription => 'MinIO、多数兼容 S3 的对象存储通常需要开启';

  @override
  String get hide => '隐藏';

  @override
  String get show => '显示';

  @override
  String get cloudConfigurationSaved => '云同步配置已保存在本机';

  @override
  String get connectionSuccessful => '连接成功，云端读写权限正常';

  @override
  String get syncConflictDetected => '检测到同步冲突';

  @override
  String syncConflictDescription(String date) {
    return '本机数据与云端数据都可能有变更。\n\n云端版本：$date\n请选择要保留的一份；另一份将被覆盖。';
  }

  @override
  String get notNow => '暂不处理';

  @override
  String get useCloudVersion => '使用云端';

  @override
  String get keepLocalVersion => '保留本机';

  @override
  String get syncedLocalToCloud => '本机数据已同步到云端';

  @override
  String get updatedFromCloud => '已使用云端数据更新本机';

  @override
  String get cloudAlreadyUpToDate => '本机与云端数据已经一致';

  @override
  String get syncConflictUnresolved => '同步冲突尚未处理';

  @override
  String get httpsCertificateFailed => 'HTTPS 证书验证失败，请检查服务器证书';

  @override
  String get cloudConnectionFailed => '无法连接云端，请检查网络和服务器地址';

  @override
  String get cloudConnectionTimeout => '连接云端超时';

  @override
  String get manualUserDataSync => '仅手动同步用户数据';

  @override
  String get syncScopeDescription => '包含笔记、聊天和附件；不包含模型、缓存、应用锁和云端账号配置。';

  @override
  String get cloudEncryptionWarning => '云端归档不额外加密，请使用 HTTPS 与可信存储。';

  @override
  String lastSyncedAt(String date) {
    return '上次同步：$date';
  }

  @override
  String get cut => '剪切';

  @override
  String get copy => '复制';

  @override
  String get paste => '粘贴';

  @override
  String get selectAll => '全选';

  @override
  String get share => '分享';

  @override
  String get invalidExternalLink => '这个链接地址无效或使用了不受支持的协议';

  @override
  String get openExternalLinkQuestion => '打开外部链接？';

  @override
  String externalLinkWarning(String destination) {
    return '$destination\n\n链接将交给系统中的其他应用处理，可能离开 FKNotes。';
  }

  @override
  String get continueOpening => '继续打开';

  @override
  String get noExternalLinkHandler => '系统中没有可以打开这个链接的应用';

  @override
  String get externalLinkOpenFailed => '无法打开这个链接';

  @override
  String remoteImageBlocked(String label) {
    return '未加载外部图片：$label';
  }

  @override
  String mathFormulaSemantics(String formula) {
    return '数学公式：$formula';
  }

  @override
  String get assistantPrivacyDescription => '直接告诉 AI 你想做什么。笔记内容只在设备上处理。';

  @override
  String get processingScope => '处理范围';

  @override
  String get scopeSelection => '选中文字';

  @override
  String get scopeCurrentBlock => '当前段落';

  @override
  String get scopeFullNote => '整篇笔记';

  @override
  String get assistantCustomHint => '例如：把这些想法整理成一封简洁的英文邮件…';

  @override
  String get startGenerating => '开始生成';

  @override
  String get quickActions => '快捷操作';

  @override
  String get assistantSummarize => '总结笔记';

  @override
  String get assistantSummarizeDescription => '提炼核心结论与关键要点';

  @override
  String get assistantExtractTodos => '提取待办';

  @override
  String get assistantExtractTodosDescription => '找出明确、可执行的事项';

  @override
  String get assistantPolish => '润色内容';

  @override
  String get assistantPolishDescription => '保留事实与结构，改善表达';

  @override
  String get assistantCustomAction => '自定义指令';

  @override
  String get assistantNoOutput => '模型没有生成内容';

  @override
  String get stopGenerating => '停止生成';

  @override
  String get regenerate => '重新生成';

  @override
  String get chooseGeneratedContentPlacement => '选择如何使用生成内容';

  @override
  String get placementReplace => '替换原内容';

  @override
  String get placementInsertBelow => '插入到段落下方';

  @override
  String get placementAppend => '追加到笔记末尾';

  @override
  String get useCurrentContent => '使用当前内容';

  @override
  String get useGeneratedContent => '使用生成内容';

  @override
  String get generatedContentCopied => '已复制生成内容';

  @override
  String get loadingLocalModel => '正在加载本地模型…';

  @override
  String get generatingOnDevice => '正在设备上生成…';

  @override
  String get generationCompleted => '生成完成，请检查后使用';

  @override
  String get generationLimitReached => '已达到输出上限，请检查结果';

  @override
  String get generationStoppedUsable => '生成已停止，可复制或插入当前内容';

  @override
  String get generationTimedOutUsable => '生成超时，可重试或复制当前内容';

  @override
  String get generationIncomplete => '本地生成未完成';

  @override
  String get retry => '重试';

  @override
  String get maybeLater => '稍后再说';

  @override
  String get readNoteAloud => '朗读笔记';

  @override
  String get offlineReadAloudModelRequired => '需要离线朗读模型';

  @override
  String get readAloudModelDownloadDescription =>
      'Kokoro 中英双语 INT8 首次使用需下载约 140.2 MB。下载后，笔记朗读全程断网可用。';

  @override
  String get manageModels => '管理模型';

  @override
  String get noteReadAloudFailed => '无法朗读这篇笔记';

  @override
  String get liveDictationIncomplete => '实时听写没有完成';

  @override
  String get unsavedDraftFound => '发现未保存的草稿';

  @override
  String get unsavedDraftDescription => '上次编辑可能意外中断。要恢复尚未写入笔记的内容吗？';

  @override
  String get discardDraft => '放弃草稿';

  @override
  String get restore => '恢复';

  @override
  String get liveSpeechModelRequired => '需要实时语音模型';

  @override
  String liveSpeechModelDownloadDescription(String model, String size) {
    return '当前选择的是$model，首次使用需下载约 $size。下载完成后，听写全程断网可用。';
  }

  @override
  String get placeCursorInText => '请先将光标放在文字区域';

  @override
  String get liveDictationStartFailed => '无法开始实时听写';

  @override
  String get localLanguageModelRequired => '需要本地语言模型';

  @override
  String localLanguageModelDownloadDescription(String model, String size) {
    return '当前选择的是 $model，首次使用需下载约 $size。下载完成后，笔记内容只在本机处理。';
  }

  @override
  String get assistantReplacedContent => '已替换原内容';

  @override
  String get assistantInsertedBelow => '已插入到当前段落下方';

  @override
  String get assistantAppended => '已追加到笔记末尾';

  @override
  String get noteChangedRetryAssistant => '笔记内容已经变化，请重新发起 AI 操作';

  @override
  String assistantLaunchFailed(String error) {
    return '无法启动本地助手：$error';
  }

  @override
  String autosaveFailed(String error) {
    return '自动保存失败：$error';
  }

  @override
  String get addToNote => '添加到笔记';

  @override
  String get camera => '拍照';

  @override
  String attachmentImportTypeFailed(String type) {
    return '$type导入失败';
  }

  @override
  String get editNote => '编辑笔记';

  @override
  String get newNote => '新笔记';

  @override
  String get savingEllipsis => '正在保存…';

  @override
  String get localDraft => '本地草稿';

  @override
  String get savedLocally => '已保存在本机';

  @override
  String characterCount(int count) {
    return '$count 字';
  }

  @override
  String get stopReadAloud => '停止朗读';

  @override
  String get moreNoteActions => '更多笔记操作';

  @override
  String get removeFavorite => '取消收藏';

  @override
  String get addFavorite => '收藏';

  @override
  String get unpin => '取消置顶';

  @override
  String get pin => '置顶';

  @override
  String get addTags => '添加标签';

  @override
  String get tags => '标签';

  @override
  String get noteContent => '笔记内容';

  @override
  String attachmentItemCount(int count) {
    return '$count 项附件';
  }

  @override
  String get noteDescriptionHint => '添加说明、想法或摘要…';

  @override
  String get noteStartHint => '开始记录…';

  @override
  String get addMediaOrFile => '添加图片、录音或文件';

  @override
  String get editTags => '编辑标签';

  @override
  String get tagsDescription => '使用逗号分隔多个标签，重复标签会自动合并。';

  @override
  String get tagsHint => '例如：工作, 灵感, 稍后阅读';

  @override
  String get stopLiveDictation => '停止实时听写';

  @override
  String get liveVoiceInput => '实时语音输入';

  @override
  String get redo => '重做';

  @override
  String get bold => '加粗';

  @override
  String get italic => '斜体';

  @override
  String get underline => '下划线';

  @override
  String get addLink => '添加链接';

  @override
  String get editLink => '编辑链接';

  @override
  String get linkPrivacyDescription =>
      '链接会保存在 Markdown 中；打开前仍会由 FKNotes 进行隐私确认。';

  @override
  String get linkAddress => '链接地址';

  @override
  String get removeLink => '移除链接';

  @override
  String get organizingLastSentence => '正在整理最后一句…';

  @override
  String get liveDictationFailed => '实时听写失败';

  @override
  String get listening => '正在聆听…';

  @override
  String liveDictationElapsed(String time) {
    return '实时听写  $time';
  }

  @override
  String get localVoiceInput => '本地语音输入';

  @override
  String get cancelDictation => '取消听写';

  @override
  String get finishDictation => '完成听写';

  @override
  String get paragraph => '正文';

  @override
  String get paragraphStyle => '段落样式';

  @override
  String headingLevel(int level) {
    return '标题 $level';
  }

  @override
  String get quote => '引用';

  @override
  String get codeBlock => '代码块';

  @override
  String get divider => '分割线';

  @override
  String get listsAndIndentation => '列表与缩进';

  @override
  String get todoItem => '待办事项';

  @override
  String get bulletList => '无序列表';

  @override
  String get numberedList => '有序列表';

  @override
  String get decreaseIndent => '减少缩进';

  @override
  String get increaseIndent => '增加缩进';

  @override
  String get moreFormatting => '更多格式';

  @override
  String get strikethrough => '删除线';

  @override
  String get inlineCode => '行内代码';

  @override
  String get generatingThumbnail => '正在生成缩略图…';

  @override
  String importingBytes(String bytes) {
    return '正在导入 · $bytes';
  }

  @override
  String importingPercent(int percent, String bytes) {
    return '正在导入 $percent% · $bytes';
  }

  @override
  String get importCompleteSaving => '导入完成，正在保存到笔记…';

  @override
  String get importFailedRetry => '导入失败，请重试';

  @override
  String get importCanceled => '导入已取消';

  @override
  String get cancelImport => '取消导入';

  @override
  String chooseTypeAgain(String type) {
    return '重新选择$type';
  }

  @override
  String get adjustAttachment => '调整附件';

  @override
  String get moveUp => '上移';

  @override
  String get moveDown => '下移';

  @override
  String get referenceInBody => '引用到正文';

  @override
  String importFailedDetail(String error) {
    return '导入失败 · $error';
  }

  @override
  String get assistantSummaryHeading => '本地助手摘要';

  @override
  String get assistantTodosHeading => '本地助手待办';

  @override
  String get assistantPolishedHeading => '本地助手润色稿';

  @override
  String get assistantGeneratedHeading => 'AI 生成内容';

  @override
  String attachmentReference(String path) {
    return '附件引用：$path';
  }

  @override
  String get markdownTable => 'Markdown 表格';

  @override
  String tableDimensions(int columns, int rows) {
    return '$columns 列 · $rows 行';
  }

  @override
  String get deleteTable => '删除表格';

  @override
  String get editTable => '编辑表格';

  @override
  String get invalidMarkdownTable => '表格语法不完整，请先检查 Markdown 原文';

  @override
  String get attachmentRemoved => '附件已移除';

  @override
  String get brokenAttachmentReference => '这个引用已失效，可以移除引用';

  @override
  String attachmentReferenceDescription(String type, String size) {
    return '$type · $size · 点击预览';
  }

  @override
  String get removeReference => '移除引用';

  @override
  String tableEditorDescription(int columns, int rows) {
    return '$columns 列 · $rows 行 · 左右滑动查看全部列';
  }

  @override
  String get addColumn => '添加列';

  @override
  String get addRow => '添加行';

  @override
  String deleteRow(int row) {
    return '删除第 $row 行';
  }

  @override
  String get saveTable => '保存表格';

  @override
  String get tableHeader => '表头';

  @override
  String get deleteColumn => '删除列';

  @override
  String get cellAlignment => '单元格对齐方式';

  @override
  String get alignLeft => '左对齐';

  @override
  String get alignCenter => '居中';

  @override
  String get alignRight => '右对齐';

  @override
  String get content => '内容';

  @override
  String get untitled => '无标题';

  @override
  String todayAt(String time) {
    return '今天 $time';
  }

  @override
  String yesterdayAt(String time) {
    return '昨天 $time';
  }

  @override
  String get quickNoteTile => '随\n笔';

  @override
  String get removeFromArchive => '移出归档';

  @override
  String get edit => '编辑';

  @override
  String get moveToTrash => '移到回收站';

  @override
  String mixedAttachmentMetadata(int count) {
    return '混合 · $count 项';
  }

  @override
  String imageAttachmentMetadata(int count) {
    return '图片 · $count 张';
  }

  @override
  String audioAttachmentMetadata(int count) {
    return '录音 · $count 段';
  }

  @override
  String videoAttachmentMetadata(int count) {
    return '视频 · $count 个';
  }

  @override
  String fileAttachmentMetadata(int count) {
    return '文件 · $count 个';
  }

  @override
  String get localLanguageModel => '本地语言模型';

  @override
  String get conversationHistory => '对话记录';

  @override
  String get personaManagement => '角色管理';

  @override
  String get moreConversationActions => '更多对话操作';

  @override
  String get newConversation => '新对话';

  @override
  String get deleteCurrentConversation => '删除当前对话';

  @override
  String get jumpToBottom => '回到底部';

  @override
  String get generalAssistant => '通用助手';

  @override
  String get textOnlyRuntimeImageWarning =>
      '当前本地运行时仅支持文字输入；图片已经保留在输入区，请移除或等待多模态运行时';

  @override
  String get imageConversation => '图片对话';

  @override
  String chatModelDownloadDescription(String model, String size) {
    return '当前选择的是 $model，首次使用需下载约 $size。聊天内容只在本机处理。';
  }

  @override
  String get imageKeptUnsupportedModel => '图片已保留在输入区；当前模型不支持图片理解，请切换到支持图片的模型';

  @override
  String get voiceInputBusyElsewhere => '其他页面正在使用实时语音输入';

  @override
  String get voiceInputFailed => '语音输入失败';

  @override
  String get deleteCurrentConversationQuestion => '删除当前对话？';

  @override
  String get deleteConversationDescription => '聊天内容和这个会话的角色设定将无法恢复。';

  @override
  String chatSaveFailed(String error) {
    return '无法保存聊天记录：$error';
  }

  @override
  String get today => '今天';

  @override
  String get yesterday => '昨天';

  @override
  String get installedState => '已安装';

  @override
  String get notInstalledState => '未安装';

  @override
  String get chatEmptyTitle => '你想聊什么？';

  @override
  String get chatEmptyDescription => '自由输入任何内容。消息和角色设定只保存在本机。';

  @override
  String get chatSuggestionPriorities => '帮我梳理今天最重要的三件事';

  @override
  String get chatSuggestionExplain => '用通俗的话解释一个复杂概念';

  @override
  String get chatSuggestionDevelopIdea => '和我一起完善一个新想法';

  @override
  String get yourImageMessage => '你的图片消息';

  @override
  String get yourMessage => '你的消息';

  @override
  String get aiReplying => 'AI 正在回复';

  @override
  String get aiReply => 'AI 回复';

  @override
  String get stopped => '已停止';

  @override
  String get copyReply => '复制回答';

  @override
  String get replyCopied => '已复制回答';

  @override
  String get generating => '正在生成…';

  @override
  String get modelDoesNotSupportImages => '当前模型不支持图片理解，请切换模型后发送';

  @override
  String get takePhoto => '拍照';

  @override
  String get takePhotoUnsupported => '拍照（当前模型不支持图片）';

  @override
  String get dictating => '正在听写…';

  @override
  String get messageOrVoiceHint => '发消息或使用语音…';

  @override
  String get stopGeneration => '停止生成';

  @override
  String get finishVoiceInput => '完成语音输入';

  @override
  String get send => '发送';

  @override
  String get voiceInput => '语音输入';

  @override
  String get addImage => '添加图片';

  @override
  String get addImageUnsupported => '添加图片（当前模型不支持）';

  @override
  String get preparingOfflineSpeech => '正在准备离线语音识别…';

  @override
  String get dictationTapMicToFinish => '正在听写，点击麦克风完成';

  @override
  String get previewImage => '预览图片';

  @override
  String get removeImage => '移除图片';

  @override
  String get addMoreImages => '继续添加图片';

  @override
  String previewImageNumber(int index) {
    return '预览图片 $index';
  }

  @override
  String get closePreview => '关闭预览';

  @override
  String get imageCannotOpen => '图片无法打开';

  @override
  String get dismissMessage => '关闭提示';

  @override
  String get readAgain => '重新读取';

  @override
  String get switchPersona => '切换角色';

  @override
  String get manage => '管理';

  @override
  String get noSavedConversations => '还没有保存的对话';

  @override
  String conversationMessageCount(int count, String time) {
    return '$count 条消息 · $time';
  }

  @override
  String personaDeleteQuestion(String name) {
    return '删除“$name”？';
  }

  @override
  String get personaDeleteDescription => '使用这个角色的对话会切换回通用助手，聊天记录不会删除。';

  @override
  String get createPersona => '新建角色';

  @override
  String get reload => '重新加载';

  @override
  String get personaManagementDescription =>
      '角色决定本地模型回答问题时采用的身份、语气和规则。你可以在聊天中随时切换，所有设定只保存在本机。';

  @override
  String get builtIn => '内置';

  @override
  String get current => '当前';

  @override
  String get personaDescriptionMissing => '未填写角色说明';

  @override
  String get personaActions => '角色操作';

  @override
  String get editPersona => '编辑角色';

  @override
  String get deletePersona => '删除角色';

  @override
  String get personaInstructionDescription =>
      '角色名称用于切换；系统提示词会在每次请求中作为最高优先级的本地指令。';

  @override
  String get personaName => '角色名称';

  @override
  String get shortDescriptionOptional => '简短说明（可选）';

  @override
  String get systemPrompt => '系统提示词';

  @override
  String get systemPromptHint => '例如：你是一位耐心的英语口语教练……';

  @override
  String get savePersona => '保存角色';

  @override
  String get microphonePermissionRequired => '需要麦克风权限';

  @override
  String get microphonePermissionDescription => '录音只会保存在本机。请允许麦克风权限后再开始。';

  @override
  String get openSettings => '前往设置';

  @override
  String recordingStartFailed(String error) {
    return '无法开始录音：$error';
  }

  @override
  String voiceNoteDefaultTitle(String date, String time) {
    return '语音笔记 $date $time';
  }

  @override
  String recordingSaveFailed(String error) {
    return '保存失败：$error';
  }

  @override
  String get discardRecordingQuestion => '放弃这段录音？';

  @override
  String get discardRecordingDescription => '还没有保存的录音将被删除。';

  @override
  String get continueEditing => '继续编辑';

  @override
  String get discard => '放弃';

  @override
  String get deviceOnly => '仅本机';

  @override
  String get recordIdea => '记录一段想法';

  @override
  String get recordingPrivacyDescription =>
      '录音默认只保存在本机；仅手动云同步时才会上传。保存后可以继续添加标签和说明。';

  @override
  String get preparingMicrophone => '正在准备麦克风…';

  @override
  String get startRecording => '开始录音';

  @override
  String get paused => '已暂停';

  @override
  String get recording => '正在录音';

  @override
  String get resume => '继续';

  @override
  String get pause => '暂停';

  @override
  String get recordAgain => '重录';

  @override
  String get saveVoiceNote => '保存语音笔记';

  @override
  String get editTranscript => '编辑转写文字';

  @override
  String get transcriptLocalOnlyDescription => '仅修改本地转写文字，原始录音不会改变';

  @override
  String get transcriptHint => '输入转写文字';

  @override
  String transcriptCharacterCount(int count) {
    return '$count 字';
  }

  @override
  String get preparingModel => '正在准备模型';

  @override
  String get recognizedTextCopied => '识别文字已复制';

  @override
  String ocrFailedDetail(String error) {
    return 'OCR 识别失败：$error';
  }

  @override
  String get noClearTextRecognized => '未识别到清晰文字';

  @override
  String get importOfflineSpeechModel => '导入离线识别模型';

  @override
  String get importSpeechModelDescription =>
      '请从解压后的 SenseVoice Small INT8 模型目录中，同时选择 ONNX 模型和 tokens.txt。\n\n模型约 228 MB，只保存在本机，不会进入笔记备份。';

  @override
  String get chooseFiles => '选择文件';

  @override
  String get importingOfflineModel => '正在导入离线模型';

  @override
  String get offlineSpeechModelImported => '离线语音识别模型已导入';

  @override
  String modelImportFailed(String error) {
    return '模型导入失败：$error';
  }

  @override
  String get downloadOfflineSpeechModelQuestion => '下载离线识别模型？';

  @override
  String get downloadSpeechModelDescription =>
      '将从 ModelScope 魔搭社区下载约 228 MB，建议使用 Wi-Fi。\n\n模型下载会联网；笔记和音频只会在你手动云同步时上传。中断后可继续下载。';

  @override
  String get downloadingFromModelScope => '正在从 ModelScope 下载';

  @override
  String get offlineSpeechModelDownloaded => '离线语音识别模型下载完成';

  @override
  String get downloadPausedResumable => '已暂停下载，下次会从断点继续';

  @override
  String modelDownloadFailedDetail(String error) {
    return '模型下载失败：$error';
  }

  @override
  String get finishingInstallation => '正在完成安装';

  @override
  String importedAmount(String amount) {
    return '已导入 $amount';
  }

  @override
  String downloadedAmount(String amount) {
    return '已下载 $amount';
  }

  @override
  String amountFinishingInstall(String amount) {
    return '$amount · 正在完成安装';
  }

  @override
  String get speedTesting => '正在测速…';

  @override
  String get waitForTranscription => '请先等待正在进行的转写结束';

  @override
  String get removeOfflineModelQuestion => '移除离线模型？';

  @override
  String get removeOfflineModelDescription => '将释放约 228 MB 空间。已经保存的转写文字不会被删除。';

  @override
  String get speakerModelRequired => '需要说话人分离模型';

  @override
  String get speakerModelDownloadDescription =>
      '首次使用需在本地模型中下载约 44.4 MB。模型安装后，分段和转写都完全在设备上完成。';

  @override
  String get speakerCount => '说话人数量';

  @override
  String get speakerCountDescription => '当前支持最长 30 分钟的录音；人数越准确，分离结果通常越稳定。';

  @override
  String get estimateAutomatically => '自动估算';

  @override
  String get estimateAutomaticallyDescription => '适合不确定人数的录音';

  @override
  String speakerCountOption(int count) {
    return '$count 位说话人';
  }

  @override
  String get transcriptCopied => '转写文字已复制';

  @override
  String get openWithAnotherApp => '用其他应用打开';

  @override
  String get editInformation => '编辑信息';

  @override
  String get preview => '预览';

  @override
  String get recognizedText => '识别文字';

  @override
  String get transcript => '转写文字';

  @override
  String get information => '信息';

  @override
  String get textInImage => '图片中的文字';

  @override
  String get copyAll => '复制全部';

  @override
  String get recognizeAgain => '重新识别';

  @override
  String get recognizeText => '识别文字';

  @override
  String get noRecognizedText => '暂无识别文字';

  @override
  String get ocrOnDemandDescription => '需要时可对这张图片进行本地文字识别';

  @override
  String get recognizing => '正在识别…';

  @override
  String get audioTranscript => '录音转写';

  @override
  String get editText => '编辑文字';

  @override
  String get audioStaysOnDevice => '完全在本机处理，音频不会离开设备';

  @override
  String get offlineSpeechModelRequired => '需要离线识别模型';

  @override
  String get offlineModelBackupDescription => '模型独立保存在本机，不增加笔记备份大小';

  @override
  String get downloadAbout228Mb => '在线下载约 228 MB';

  @override
  String get backgroundTranscriptionHint => '可以离开此页面继续使用笔记';

  @override
  String get transcriptionIncomplete => '转写没有完成';

  @override
  String get tryAgainLater => '请稍后重试';

  @override
  String get transcribeAgain => '重新转写';

  @override
  String get transcriptionCanceled => '已取消转写';

  @override
  String get recordingUnaffected => '录音文件没有受到影响';

  @override
  String get noTranscript => '暂无转写文字';

  @override
  String get transcriptionOnDemandDescription => '需要时再启动本地识别，不会自动处理录音';

  @override
  String get transcribeOnDevice => '本地转写';

  @override
  String get speakerDiarizedTranscription => '区分说话人转写';

  @override
  String get speakerDiarizedTranscriptionModelRequired =>
      '区分说话人转写 · 需 44.4 MB 模型';

  @override
  String manageModelSize(String size) {
    return '管理模型 · $size';
  }

  @override
  String get importFromFiles => '从文件导入';

  @override
  String get viewAllModels => '查看全部模型';

  @override
  String get preparingLocalTranscription => '正在准备本地转写';

  @override
  String get readingAudio => '正在读取音频';

  @override
  String get separatingSpeakers => '正在区分说话人';

  @override
  String get recognizingOnDevice => '正在本地识别';

  @override
  String get savingTranscriptText => '正在保存转写文字';

  @override
  String get processing => '正在处理';

  @override
  String get noteInformation => '笔记信息';

  @override
  String get type => '类型';

  @override
  String get created => '创建';

  @override
  String get updated => '更新';

  @override
  String get fileInformation => '文件信息';

  @override
  String get fileName => '文件名';

  @override
  String get size => '大小';

  @override
  String get duration => '时长';

  @override
  String get saveStatus => '保存状态';

  @override
  String get fileMissing => '文件不存在';

  @override
  String get savedInUnifiedDirectory => '已保存在统一目录';

  @override
  String get description => '说明';

  @override
  String get originalFileMissing => '原文件不存在';

  @override
  String get missingFileDescription => '可以保留笔记信息或将它移到回收站';

  @override
  String get openWithLocalApp => '用本地应用打开';
}
