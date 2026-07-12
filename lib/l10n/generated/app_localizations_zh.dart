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
}
