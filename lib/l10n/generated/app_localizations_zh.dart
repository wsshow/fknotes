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
  String get localModelsSubtitle => '下载、导入和移除设备端识别模型';

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
  String get modelPrivacyHint => '模型只在用户下载时联网，且不会进入笔记备份；用户数据仅在手动云同步时上传。';

  @override
  String get languageModels => '语言模型';

  @override
  String get languageModelsDescription => '由用户下载并选择本地助手使用的模型，默认上下文为 4096。';

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
}
