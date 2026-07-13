import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/local_model.dart';
import '../models/taobao_mnn_model.dart';
import 'kokoro_tts_model_service.dart';
import 'language_model_service.dart';
import 'local_assistant_service.dart';
import 'model_download_transport.dart';
import 'note_read_aloud_service.dart';
import 'realtime_dictation_preferences_service.dart';
import 'realtime_dictation_service.dart';
import 'speech_model_service.dart';
import 'speech_denoiser_model_service.dart';
import 'speech_transcription_service.dart';
import 'speaker_diarization_model_service.dart';
import 'streaming_speech_model_service.dart';
import 'taobao_mnn_catalog_service.dart';
import 'voice_activity_model_service.dart';

enum ModelTransferStatus {
  connecting,
  downloading,
  importing,
  waitingToInstall,
  verifying,
  canceling,
  completed,
  failed,
  canceled,
}

class ModelTransferState {
  final String modelId;
  ModelTransferStatus status;
  int transferredBytes;
  int totalBytes;
  double bytesPerSecond;
  String? errorMessage;
  String sourceLabel;
  final bool cancelable;
  bool cancelRequested;
  DateTime? _speedSampleAt;
  int _speedSampleBytes;

  ModelTransferState({
    required this.modelId,
    required this.status,
    this.transferredBytes = 0,
    this.totalBytes = 0,
    this.bytesPerSecond = 0,
    this.errorMessage,
    this.sourceLabel = '',
    this.cancelable = true,
    this.cancelRequested = false,
  }) : _speedSampleBytes = transferredBytes;

  bool get isRunning => switch (status) {
    ModelTransferStatus.connecting ||
    ModelTransferStatus.downloading ||
    ModelTransferStatus.importing ||
    ModelTransferStatus.waitingToInstall ||
    ModelTransferStatus.verifying ||
    ModelTransferStatus.canceling => true,
    _ => false,
  };

  double get progress =>
      totalBytes <= 0 ? 0 : (transferredBytes / totalBytes).clamp(0.0, 1.0);

  void updateProgress(SpeechModelImportProgress progress) {
    final now = DateTime.now();
    if (!progress.verifying &&
        !progress.waitingForInstall &&
        !progress.connecting) {
      final previous = _speedSampleAt;
      if (previous == null) {
        _speedSampleAt = now;
        _speedSampleBytes = progress.copiedBytes;
      } else {
        final elapsed = now.difference(previous).inMilliseconds;
        final bytes = progress.copiedBytes - _speedSampleBytes;
        if (elapsed >= 350 && bytes >= 0) {
          final instant = bytes * 1000 / elapsed;
          bytesPerSecond = bytesPerSecond == 0
              ? instant
              : bytesPerSecond * .65 + instant * .35;
          _speedSampleAt = now;
          _speedSampleBytes = progress.copiedBytes;
        }
      }
    }
    transferredBytes = progress.copiedBytes;
    totalBytes = progress.totalBytes;
    if (progress.sourceLabel.isNotEmpty) sourceLabel = progress.sourceLabel;
    if (status == ModelTransferStatus.canceling) return;
    if (progress.waitingForInstall) {
      status = ModelTransferStatus.waitingToInstall;
    } else if (progress.verifying) {
      status = ModelTransferStatus.verifying;
    } else if (progress.connecting) {
      status = ModelTransferStatus.connecting;
      bytesPerSecond = 0;
      _speedSampleAt = null;
      _speedSampleBytes = transferredBytes;
    } else if (status == ModelTransferStatus.connecting) {
      status = ModelTransferStatus.downloading;
    }
  }
}

class LocalModelManager extends ChangeNotifier {
  LocalModelManager._();
  static final LocalModelManager instance = LocalModelManager._();

  static const senseVoiceId = SpeechModelService.modelId;
  static const streamingChineseId = StreamingSpeechModelService.modelId;
  static const streamingBilingualId =
      StreamingSpeechModelService.bilingualModelId;
  static const voiceActivityId = VoiceActivityModelService.modelId;
  static const speechDenoiserId = SpeechDenoiserModelService.modelId;
  static const speakerDiarizationId = SpeakerDiarizationModelService.modelId;
  static const kokoroTtsId = KokoroTtsModelService.modelId;
  static const mlKitChineseOcrId = 'mlkit-text-recognition-chinese';
  static const miniCpm5Id = LanguageModelService.miniCpm5Id;
  static const qwen35Id = LanguageModelService.qwen35Id;
  static const qwen3Vl4BId = LanguageModelService.qwen3Vl4BId;
  static const qwen3Vl8BId = LanguageModelService.qwen3Vl8BId;
  static const miniCpmV4Id = LanguageModelService.miniCpmV4Id;
  static const gemma4E2BId = LanguageModelService.gemma4E2BId;
  static const gemma4E4BId = LanguageModelService.gemma4E4BId;

  static const catalog = <LocalModelDefinition>[
    LocalModelDefinition(
      id: miniCpm5Id,
      name: 'MiniCPM5 1B INT4',
      summary: '轻量、快速的本地笔记助手',
      description: '适合摘要、标题、标签、改写和待办提取；支持中英文、思考模式与工具调用。',
      category: LocalModelCategory.language,
      availability: LocalModelAvailability.downloadable,
      task: LocalModelTask.textGeneration,
      downloadSizeBytes: LanguageModelService.miniCpm5DownloadSizeBytes,
      languages: ['中文', '英语'],
      engine: 'MNN 3.6 · INT4',
      version: 'MiniCPM5 1B · 2026-05',
      source: 'OpenBMB / taobao-mnn · Hugging Face 多源下载',
      license: 'Apache-2.0',
      recommendedMemoryBytes: 4 * 1024 * 1024 * 1024,
    ),
    LocalModelDefinition(
      id: qwen35Id,
      name: 'Qwen3.5 2B INT4',
      summary: '轻量通用图文助手（图片能力实验性）',
      description: '适合中文写作、复杂摘要、中英文整理和笔记问答；可处理图片，但精细视觉任务建议改用专用视觉模型。',
      category: LocalModelCategory.language,
      availability: LocalModelAvailability.downloadable,
      task: LocalModelTask.textGeneration,
      downloadSizeBytes: LanguageModelService.qwen35DownloadSizeBytes,
      languages: ['中文', '英语', '多语言', '图片'],
      engine: 'MNN 3.6 · INT4',
      version: 'Qwen3.5 2B · 2026-03',
      source: 'Qwen / taobao-mnn · Hugging Face 多源下载',
      license: 'Apache-2.0',
      recommendedMemoryBytes: 6 * 1024 * 1024 * 1024,
    ),
    LocalModelDefinition(
      id: qwen3Vl4BId,
      name: 'Qwen3-VL 4B Instruct INT4',
      summary: '均衡的多语言图文理解模型',
      description: '适合图片问答、中文 OCR、文档与图表理解，以及质量要求更高的写作和知识整理。',
      category: LocalModelCategory.language,
      availability: LocalModelAvailability.downloadable,
      task: LocalModelTask.textGeneration,
      downloadSizeBytes: LanguageModelService.qwen3Vl4BDownloadSizeBytes,
      languages: ['中文', '英语', '多语言', '图片'],
      engine: 'MNN 3.6 · INT4',
      version: 'Qwen3-VL 4B Instruct',
      source: 'Qwen / taobao-mnn · Hugging Face 多源下载',
      license: 'Apache-2.0',
      recommended: true,
      recommendedMemoryBytes: 8 * 1024 * 1024 * 1024,
    ),
    LocalModelDefinition(
      id: qwen3Vl8BId,
      name: 'Qwen3-VL 8B Instruct INT4',
      summary: '更强的多语言图文理解模型',
      description: '面向复杂图片、长文档、图表、OCR 和高质量内容生成；模型较大，适合高内存旗舰设备。',
      category: LocalModelCategory.language,
      availability: LocalModelAvailability.downloadable,
      task: LocalModelTask.textGeneration,
      downloadSizeBytes: LanguageModelService.qwen3Vl8BDownloadSizeBytes,
      languages: ['中文', '英语', '多语言', '图片'],
      engine: 'MNN 3.6 · INT4',
      version: 'Qwen3-VL 8B Instruct',
      source: 'Qwen / taobao-mnn · Hugging Face 多源下载',
      license: 'Apache-2.0',
      recommendedMemoryBytes: 12 * 1024 * 1024 * 1024,
    ),
    LocalModelDefinition(
      id: miniCpmV4Id,
      name: 'MiniCPM-V 4 INT4',
      summary: '移动端优化的中文视觉模型',
      description: '偏重中文 OCR、截图、文档和高分辨率图片理解，在模型体积与视觉能力之间取得平衡。',
      category: LocalModelCategory.language,
      availability: LocalModelAvailability.downloadable,
      task: LocalModelTask.textGeneration,
      downloadSizeBytes: LanguageModelService.miniCpmV4DownloadSizeBytes,
      languages: ['中文', '英语', '图片'],
      engine: 'MNN 3.6 · INT4',
      version: 'MiniCPM-V 4',
      source: 'OpenBMB / taobao-mnn · Hugging Face 多源下载',
      license: 'Apache-2.0',
      recommended: true,
      recommendedMemoryBytes: 8 * 1024 * 1024 * 1024,
    ),
    LocalModelDefinition(
      id: gemma4E2BId,
      name: 'Gemma 4 E2B IT INT4',
      summary: '支持图像与音频的端侧推理模型',
      description: '支持推理、图片理解和 WAV 音频理解，兼顾多语言、代码与内容生成，适合较新的高端设备。',
      category: LocalModelCategory.language,
      availability: LocalModelAvailability.downloadable,
      task: LocalModelTask.textGeneration,
      downloadSizeBytes: LanguageModelService.gemma4E2BDownloadSizeBytes,
      languages: ['多语言', '图片', '音频'],
      engine: 'MNN 3.6 · INT4 · PLE',
      version: 'Gemma 4 E2B IT',
      source: 'Google / taobao-mnn · Hugging Face 多源下载',
      license: 'Apache-2.0',
      recommendedMemoryBytes: 8 * 1024 * 1024 * 1024,
    ),
    LocalModelDefinition(
      id: gemma4E4BId,
      name: 'Gemma 4 E4B IT INT4',
      summary: '更强的图像、音频与推理模型',
      description: '面向更复杂的推理、代码、多语言图文和音频理解；资源占用较高，适合 12 GB 以上内存设备。',
      category: LocalModelCategory.language,
      availability: LocalModelAvailability.downloadable,
      task: LocalModelTask.textGeneration,
      downloadSizeBytes: LanguageModelService.gemma4E4BDownloadSizeBytes,
      languages: ['多语言', '图片', '音频'],
      engine: 'MNN 3.6 · INT4 · PLE',
      version: 'Gemma 4 E4B IT',
      source: 'Google / taobao-mnn · Hugging Face 多源下载',
      license: 'Apache-2.0',
      recommendedMemoryBytes: 12 * 1024 * 1024 * 1024,
    ),
    LocalModelDefinition(
      id: senseVoiceId,
      name: 'SenseVoice Small INT8',
      summary: '音频转写与实时听写结束精修',
      description: '适合普通话、粤语和中英混合录音；也可作为实时听写的可选第二遍识别模型。',
      category: LocalModelCategory.speech,
      availability: LocalModelAvailability.downloadable,
      task: LocalModelTask.audioTranscription,
      downloadSizeBytes: SpeechModelService.downloadSizeBytes,
      languages: ['普通话', '粤语', '英语', '日语', '韩语'],
      engine: 'sherpa-onnx',
      version: '2024-07-17 INT8',
      source: 'ModelScope · gomodels/sherpa',
      license: 'FunASR Model License',
      recommended: true,
    ),
    LocalModelDefinition(
      id: streamingChineseId,
      name: 'Streaming Zipformer 中文',
      summary: '边说边出字的实时语音输入',
      description: '面向笔记编辑器实时听写，语音在设备端边录边识别，不需要上传音频。',
      category: LocalModelCategory.speech,
      availability: LocalModelAvailability.downloadable,
      task: LocalModelTask.liveDictation,
      downloadSizeBytes: StreamingSpeechModelService.downloadSizeBytes,
      languages: ['普通话'],
      engine: 'sherpa-onnx',
      version: '2025-06-30 INT8',
      source: 'Hugging Face 官方仓库 · hf-mirror 国内镜像',
      license: 'Apache-2.0',
    ),
    LocalModelDefinition(
      id: streamingBilingualId,
      name: 'Streaming Zipformer 中英双语',
      summary: '中英文混合实时语音输入',
      description: '适合一句话内自然切换中文和英文的实时听写，全部识别均在设备端完成。',
      category: LocalModelCategory.speech,
      availability: LocalModelAvailability.downloadable,
      task: LocalModelTask.liveDictation,
      downloadSizeBytes: StreamingSpeechModelService.bilingualDownloadSizeBytes,
      languages: ['普通话', '英语'],
      engine: 'sherpa-onnx',
      version: '2023-02-20 INT8',
      source: 'Hugging Face 官方仓库 · hf-mirror 国内镜像',
      license: 'Apache-2.0',
    ),
    LocalModelDefinition(
      id: voiceActivityId,
      name: 'Silero VAD INT8',
      summary: '检测人声并跳过长录音中的静音',
      description: '作为音频转写基础组件，在设备端定位有效语音片段，减少静音带来的耗时和误识别。',
      category: LocalModelCategory.speech,
      availability: LocalModelAvailability.downloadable,
      task: LocalModelTask.voiceActivityDetection,
      downloadSizeBytes: VoiceActivityModelService.downloadSizeBytes,
      languages: ['与语言无关'],
      engine: 'sherpa-onnx · Silero VAD',
      version: 'INT8 · 16 kHz',
      source: 'k2-fsa 官方模型 · GitHub 官方源',
      license: 'MIT',
      recommended: true,
    ),
    LocalModelDefinition(
      id: speechDenoiserId,
      name: 'DPDFNet 实时降噪',
      summary: '降低环境噪声后再进行实时听写',
      description:
          '面向 16 kHz 单声道语音的因果流式降噪模型，采用最低资源的 Baseline 版本，适合移动端 ASR 前处理。',
      category: LocalModelCategory.speech,
      availability: LocalModelAvailability.downloadable,
      task: LocalModelTask.speechEnhancement,
      downloadSizeBytes: SpeechDenoiserModelService.downloadSizeBytes,
      languages: ['与语言无关'],
      engine: 'sherpa-onnx · DPDFNet',
      version: 'Baseline · 16 kHz',
      source: 'k2-fsa 官方模型 · 国内镜像优先 / GitHub 兜底',
      license: 'Apache-2.0',
      recommended: true,
    ),
    LocalModelDefinition(
      id: speakerDiarizationId,
      name: 'Pyannote + 3D-Speaker',
      summary: '在录音转写中区分不同说话人',
      description:
          '使用 Pyannote INT8 定位说话区间，再用中文 3D-Speaker 嵌入模型聚类；支持自动估算或指定 2–8 位说话人。',
      category: LocalModelCategory.speech,
      availability: LocalModelAvailability.downloadable,
      task: LocalModelTask.speakerDiarization,
      downloadSizeBytes: SpeakerDiarizationModelService.downloadSizeBytes,
      languages: ['与语言无关', '中文优化'],
      engine: 'sherpa-onnx · Pyannote · 3D-Speaker',
      version: 'Segmentation 3.0 INT8 · ERes2Net 16 kHz',
      source: 'k2-fsa 官方模型 · 国内镜像与 GitHub 分文件下载',
      license: 'MIT · Apache-2.0',
      recommended: true,
    ),
    LocalModelDefinition(
      id: kokoroTtsId,
      name: 'Kokoro 中英双语 INT8',
      summary: '离线朗读中文与英文笔记',
      description: '支持中英文混合文本、103 个音色和 24 kHz 音频；当前默认使用中文女声音色。',
      category: LocalModelCategory.speech,
      availability: LocalModelAvailability.downloadable,
      task: LocalModelTask.textToSpeech,
      downloadSizeBytes: KokoroTtsModelService.downloadSizeBytes,
      languages: ['中文', '英语'],
      engine: 'sherpa-onnx · Kokoro',
      version: 'v1.1 INT8',
      source: 'k2-fsa 官方模型 · GitHub 官方源',
      license: 'Apache-2.0',
      recommended: true,
    ),
    LocalModelDefinition(
      id: mlKitChineseOcrId,
      name: 'ML Kit 中文文字识别',
      summary: '图片中的中文与拉丁文字 OCR',
      description: '随应用安装并完全在设备端运行，当前不能单独移除。',
      category: LocalModelCategory.vision,
      availability: LocalModelAvailability.builtIn,
      task: LocalModelTask.textRecognition,
      languages: ['中文', '英文'],
      engine: 'Google ML Kit',
      version: '内置组件',
      source: '随应用提供',
      license: 'Google ML Kit Terms',
    ),
  ];

  final _speechModels = SpeechModelService.instance;
  final _streamingModels = StreamingSpeechModelService.instance;
  final _voiceActivityModels = VoiceActivityModelService.instance;
  final _speechDenoiserModels = SpeechDenoiserModelService.instance;
  final _speakerDiarizationModels = SpeakerDiarizationModelService.instance;
  final _kokoroTtsModels = KokoroTtsModelService.instance;
  final _languageModels = LanguageModelService.instance;
  final _remoteCatalog = TaobaoMnnCatalogService.instance;
  final _dictationPreferences = RealtimeDictationPreferencesService.instance;
  final Map<String, LocalModelInstallation> _installations = {};
  final Map<String, ModelTransferState> _transfers = {};
  final Map<String, LocalModelDefinition> _remoteDefinitions = {};
  bool _initialized = false;
  bool _importPickerBusy = false;
  int _initializationGeneration = 0;
  String _selectedLiveDictationModelId = streamingChineseId;
  String _selectedAssistantModelId = qwen35Id;

  List<LocalModelDefinition> get models => [
    ...catalog,
    ..._remoteDefinitions.values,
  ];
  List<ModelTransferState> get transfers =>
      List.unmodifiable(_transfers.values);
  bool get initialized => _initialized;
  String get selectedLiveDictationModelId => _selectedLiveDictationModelId;
  String get selectedAssistantModelId => _selectedAssistantModelId;
  LocalModelDefinition modelOf(String id) => _definition(id);
  LocalModelInstallation installationOf(String id) =>
      _installations[id] ?? const LocalModelInstallation();
  ModelTransferState? transferOf(String id) => _transfers[id];

  void dismissTransfer(String modelId) {
    final transfer = _transfers[modelId];
    if (transfer == null || transfer.isRunning) return;
    _transfers.remove(modelId);
    notifyListeners();
  }

  int get installedCount => models.where((model) {
    return model.availability == LocalModelAvailability.builtIn ||
        installationOf(model.id).installed;
  }).length;

  int get installedSizeBytes => _installations.values.fold(
    0,
    (sum, installation) => sum + installation.installedSizeBytes,
  );

  Future<void> initialize({bool force = false}) async {
    if (_initialized && !force) return;
    await _remoteCatalog.loadCache();
    _languageModels.registerRemoteModels(_remoteCatalog.cachedDetails);
    _remoteDefinitions
      ..clear()
      ..addEntries(
        _remoteCatalog.cachedDetails
            .where(
              (model) => !_languageModels.curatedRepositories.contains(
                model.repository.toLowerCase(),
              ),
            )
            .map((model) => MapEntry(model.id, _remoteDefinition(model))),
      );
    final languageModelIds = _languageModels.modelIds;
    final generation = ++_initializationGeneration;
    final results = await Future.wait<Object>([
      _speechModels.inspect(),
      _speechModels.partialDownloadBytes(),
      _streamingModels.inspect(modelId: streamingChineseId),
      _streamingModels.partialDownloadBytes(streamingChineseId),
      _streamingModels.inspect(modelId: streamingBilingualId),
      _streamingModels.partialDownloadBytes(streamingBilingualId),
      _streamingModels.selectedModelId(),
      _voiceActivityModels.inspect(),
      _voiceActivityModels.partialDownloadBytes(),
      _speechDenoiserModels.inspect(),
      _speechDenoiserModels.partialDownloadBytes(),
      _speakerDiarizationModels.inspect(),
      _speakerDiarizationModels.partialDownloadBytes(),
      _kokoroTtsModels.inspect(),
      _kokoroTtsModels.partialDownloadBytes(),
      Future.wait<List<Object>>([
        for (final id in languageModelIds)
          Future.wait<Object>([
            _languageModels.inspect(id),
            _languageModels.partialDownloadBytes(id),
          ]),
      ]),
      _languageModels.selectedModelId(),
    ]);
    final speech = results[0] as SpeechModelInfo;
    final partial = results[1] as int;
    final streaming = results[2] as StreamingSpeechModelInfo;
    final streamingPartial = results[3] as int;
    final bilingual = results[4] as StreamingSpeechModelInfo;
    final bilingualPartial = results[5] as int;
    final selectedLiveDictationModelId = results[6] as String;
    final voiceActivity = results[7] as VoiceActivityModelInfo;
    final voiceActivityPartial = results[8] as int;
    final speechDenoiser = results[9] as SpeechDenoiserModelInfo;
    final speechDenoiserPartial = results[10] as int;
    final speakerDiarization = results[11] as SpeakerDiarizationModelInfo;
    final speakerDiarizationPartial = results[12] as int;
    final kokoroTts = results[13] as KokoroTtsModelInfo;
    final kokoroTtsPartial = results[14] as int;
    final languageResults = results[15] as List<List<Object>>;
    final selectedAssistantModelId = results[16] as String;
    if (generation != _initializationGeneration) return;
    _selectedLiveDictationModelId = selectedLiveDictationModelId;
    _selectedAssistantModelId = selectedAssistantModelId;
    _installations[senseVoiceId] = LocalModelInstallation(
      installed: speech.installed,
      installedSizeBytes: speech.sizeBytes,
      partialSizeBytes: partial,
    );
    _installations[streamingChineseId] = LocalModelInstallation(
      installed: streaming.installed,
      installedSizeBytes: streaming.sizeBytes,
      partialSizeBytes: streamingPartial,
    );
    _installations[streamingBilingualId] = LocalModelInstallation(
      installed: bilingual.installed,
      installedSizeBytes: bilingual.sizeBytes,
      partialSizeBytes: bilingualPartial,
    );
    _installations[voiceActivityId] = LocalModelInstallation(
      installed: voiceActivity.installed,
      installedSizeBytes: voiceActivity.sizeBytes,
      partialSizeBytes: voiceActivityPartial,
    );
    _installations[speechDenoiserId] = LocalModelInstallation(
      installed: speechDenoiser.installed,
      installedSizeBytes: speechDenoiser.sizeBytes,
      partialSizeBytes: speechDenoiserPartial,
    );
    _installations[speakerDiarizationId] = LocalModelInstallation(
      installed: speakerDiarization.installed,
      installedSizeBytes: speakerDiarization.sizeBytes,
      partialSizeBytes: speakerDiarizationPartial,
    );
    _installations[kokoroTtsId] = LocalModelInstallation(
      installed: kokoroTts.installed,
      installedSizeBytes: kokoroTts.sizeBytes,
      partialSizeBytes: kokoroTtsPartial,
    );
    for (var index = 0; index < languageResults.length; index++) {
      final id = languageModelIds[index];
      final info = languageResults[index][0] as LanguageModelInfo;
      final partialBytes = languageResults[index][1] as int;
      _installations[id] = LocalModelInstallation(
        installed: info.installed,
        installedSizeBytes: info.sizeBytes,
        partialSizeBytes: partialBytes,
      );
    }
    _installations[mlKitChineseOcrId] = const LocalModelInstallation(
      installed: true,
    );
    _initialized = true;
    notifyListeners();
  }

  Future<void> download(String modelId) async {
    final definition = _definition(modelId);
    if (definition.availability != LocalModelAvailability.downloadable) return;
    if (_transfers[modelId]?.isRunning == true) return;
    final partial = installationOf(modelId).partialSizeBytes;
    final transfer = ModelTransferState(
      modelId: modelId,
      status: ModelTransferStatus.downloading,
      transferredBytes: partial,
      totalBytes: definition.downloadSizeBytes,
    );
    _transfers[modelId] = transfer;
    notifyListeners();
    try {
      void progress(SpeechModelImportProgress value) {
        transfer.updateProgress(value);
        notifyListeners();
      }

      if (modelId == senseVoiceId) {
        await _speechModels.downloadFromModelScope(
          shouldCancel: () => transfer.cancelRequested,
          onProgress: progress,
        );
      } else if (modelId == voiceActivityId) {
        await _voiceActivityModels.download(
          shouldCancel: () => transfer.cancelRequested,
          onProgress: progress,
        );
      } else if (modelId == speechDenoiserId) {
        await _speechDenoiserModels.download(
          shouldCancel: () => transfer.cancelRequested,
          onProgress: progress,
        );
      } else if (modelId == speakerDiarizationId) {
        await _speakerDiarizationModels.download(
          shouldCancel: () => transfer.cancelRequested,
          onProgress: progress,
        );
      } else if (modelId == kokoroTtsId) {
        await _kokoroTtsModels.download(
          shouldCancel: () => transfer.cancelRequested,
          onProgress: progress,
        );
      } else if (_languageModels.supports(modelId)) {
        await _languageModels.download(
          modelId,
          shouldCancel: () => transfer.cancelRequested,
          onProgress: progress,
        );
      } else if (StreamingSpeechModelService.supportedModelIds.contains(
        modelId,
      )) {
        await _streamingModels.downloadFromHuggingFaceMirror(
          modelId,
          shouldCancel: () => transfer.cancelRequested,
          onProgress: progress,
        );
      } else {
        return;
      }
      if (StreamingSpeechModelService.supportedModelIds.contains(modelId)) {
        await _selectIfNoUsableLiveModel(modelId);
      }
      if (_languageModels.supports(modelId)) {
        await _selectIfNoUsableAssistantModel(modelId);
      }
      transfer.status = ModelTransferStatus.completed;
      await initialize(force: true);
    } on ModelDownloadCanceled {
      transfer.status = ModelTransferStatus.canceled;
      await initialize(force: true);
    } catch (error) {
      transfer.status = ModelTransferStatus.failed;
      transfer.errorMessage = _friendlyError(error);
      await initialize(force: true);
    } finally {
      notifyListeners();
    }
  }

  Future<void> import(String modelId) async {
    if (modelId != senseVoiceId &&
        modelId != voiceActivityId &&
        modelId != speechDenoiserId &&
        modelId != speakerDiarizationId &&
        modelId != kokoroTtsId &&
        !_languageModels.supports(modelId) &&
        !StreamingSpeechModelService.supportedModelIds.contains(modelId)) {
      return;
    }
    if (_transfers[modelId]?.isRunning == true || _importPickerBusy) return;
    _importPickerBusy = true;
    final transfer = ModelTransferState(
      modelId: modelId,
      status: ModelTransferStatus.importing,
      cancelable: false,
    );
    _transfers[modelId] = transfer;
    notifyListeners();
    try {
      void progress(SpeechModelImportProgress value) {
        transfer.updateProgress(value);
        notifyListeners();
      }

      final Object? imported;
      if (modelId == senseVoiceId) {
        imported = await _speechModels.pickAndImport(onProgress: progress);
      } else if (modelId == voiceActivityId) {
        imported = await _voiceActivityModels.pickAndImport(
          onProgress: progress,
        );
      } else if (modelId == speechDenoiserId) {
        imported = await _speechDenoiserModels.pickAndImport(
          onProgress: progress,
        );
      } else if (modelId == speakerDiarizationId) {
        imported = await _speakerDiarizationModels.pickAndImport(
          onProgress: progress,
        );
      } else if (modelId == kokoroTtsId) {
        imported = await _kokoroTtsModels.pickAndImport(onProgress: progress);
      } else if (_languageModels.supports(modelId)) {
        imported = await _languageModels.pickAndImport(
          modelId,
          onProgress: progress,
        );
      } else {
        imported = await _streamingModels.pickAndImport(
          modelId,
          onProgress: progress,
        );
      }
      if (imported == null) {
        _transfers.remove(modelId);
      } else {
        if (StreamingSpeechModelService.supportedModelIds.contains(modelId)) {
          await _selectIfNoUsableLiveModel(modelId);
        }
        if (_languageModels.supports(modelId)) {
          await _selectIfNoUsableAssistantModel(modelId);
        }
        transfer.status = ModelTransferStatus.completed;
      }
      await initialize(force: true);
    } catch (error) {
      transfer.status = ModelTransferStatus.failed;
      transfer.errorMessage = _friendlyError(error);
      notifyListeners();
    } finally {
      _importPickerBusy = false;
    }
  }

  void cancel(String modelId) {
    final transfer = _transfers[modelId];
    if (transfer?.isRunning != true || transfer?.cancelable != true) return;
    transfer!.cancelRequested = true;
    transfer.status = ModelTransferStatus.canceling;
    notifyListeners();
  }

  Future<void> remove(String modelId) async {
    if (modelId == senseVoiceId) {
      if (SpeechTranscriptionService.instance.jobs.any(
        (job) => job.isRunning,
      )) {
        throw StateError('请先等待正在进行的转写结束');
      }
      if (RealtimeDictationService.instance.isActive) {
        throw StateError('请先结束正在进行的实时听写');
      }
      await _speechModels.remove();
    } else if (modelId == voiceActivityId) {
      if (SpeechTranscriptionService.instance.jobs.any(
        (job) => job.isRunning,
      )) {
        throw StateError('请先等待正在进行的转写结束');
      }
      if (RealtimeDictationService.instance.isActive) {
        throw StateError('请先结束正在进行的实时听写');
      }
      await _voiceActivityModels.remove();
    } else if (modelId == speechDenoiserId) {
      if (RealtimeDictationService.instance.isActive) {
        throw StateError('请先结束正在进行的实时听写');
      }
      await _speechDenoiserModels.remove();
      final preferences = await _dictationPreferences.load();
      if (preferences.noiseSuppressionEnabled) {
        await _dictationPreferences.save(
          hotwordsText: preferences.hotwords.join('\n'),
          hotwordsScore: preferences.hotwordsScore,
          twoPassEnabled: preferences.twoPassEnabled,
          noiseSuppressionEnabled: false,
        );
      }
    } else if (modelId == speakerDiarizationId) {
      if (SpeechTranscriptionService.instance.jobs.any(
        (job) => job.isRunning,
      )) {
        throw StateError('请先等待正在进行的转写结束');
      }
      await _speakerDiarizationModels.remove();
    } else if (modelId == kokoroTtsId) {
      if (NoteReadAloudService.instance.isActive) {
        throw StateError('请先停止正在进行的笔记朗读');
      }
      await _kokoroTtsModels.remove();
    } else if (_languageModels.supports(modelId)) {
      if (LocalAssistantService.instance.loadedModelId == modelId) {
        throw StateError('请先结束正在进行的本地助手任务并释放模型');
      }
      await _languageModels.remove(modelId);
      if (_selectedAssistantModelId == modelId) {
        String? replacement;
        for (final candidate in _languageModels.modelIds) {
          if (candidate == modelId) continue;
          if ((await _languageModels.inspect(candidate)).installed) {
            replacement = candidate;
            break;
          }
        }
        if (replacement != null) await _languageModels.selectModel(replacement);
      }
    } else if (StreamingSpeechModelService.supportedModelIds.contains(
      modelId,
    )) {
      if (RealtimeDictationService.instance.isActive) {
        throw StateError('请先结束正在进行的实时听写');
      }
      final wasSelected = _selectedLiveDictationModelId == modelId;
      await _streamingModels.remove(modelId);
      if (wasSelected) {
        String? replacement;
        for (final candidate in StreamingSpeechModelService.supportedModelIds) {
          if (candidate == modelId) continue;
          if ((await _streamingModels.inspect(modelId: candidate)).installed) {
            replacement = candidate;
            break;
          }
        }
        if (replacement == null) {
          await _streamingModels.resetSelection();
        } else {
          await _streamingModels.selectModel(replacement);
        }
      }
    } else {
      return;
    }
    _transfers.remove(modelId);
    await initialize(force: true);
  }

  Future<void> selectForLiveDictation(String modelId) async {
    final definition = _definition(modelId);
    if (definition.task != LocalModelTask.liveDictation) return;
    await _streamingModels.selectModel(modelId);
    _selectedLiveDictationModelId = modelId;
    notifyListeners();
  }

  Future<void> selectForAssistant(String modelId) async {
    final definition = _definition(modelId);
    if (definition.category != LocalModelCategory.language) return;
    await _languageModels.selectModel(modelId);
    _selectedAssistantModelId = modelId;
    notifyListeners();
  }

  Future<void> _selectIfNoUsableLiveModel(String installedModelId) async {
    final selected = await _streamingModels.inspect();
    if (!selected.installed) {
      await _streamingModels.selectModel(installedModelId);
      _selectedLiveDictationModelId = installedModelId;
    }
  }

  Future<void> _selectIfNoUsableAssistantModel(String installedModelId) async {
    final selectedId = await _languageModels.selectedModelId();
    final selected = await _languageModels.inspect(selectedId);
    if (!selected.installed) {
      await _languageModels.selectModel(installedModelId);
      _selectedAssistantModelId = installedModelId;
    }
  }

  Future<void> registerRemoteModel(TaobaoMnnModelSpec model) async {
    if (_languageModels.curatedRepositories.contains(
      model.repository.toLowerCase(),
    )) {
      return;
    }
    _languageModels.registerRemoteModels([model]);
    _remoteDefinitions[model.id] = _remoteDefinition(model);
    await initialize(force: true);
  }

  LocalModelDefinition _remoteDefinition(TaobaoMnnModelSpec model) =>
      LocalModelDefinition(
        id: model.id,
        name: model.name,
        summary: model.collection,
        description:
            'Official MNN model synchronized from taobao-mnn Collections.',
        category: LocalModelCategory.language,
        availability: LocalModelAvailability.downloadable,
        task: LocalModelTask.textGeneration,
        downloadSizeBytes: model.downloadSizeBytes,
        languages: model.languages,
        engine: 'MNN · taobao-mnn',
        version: model.revision.substring(0, 8),
        source: model.repository,
        license: model.license,
        recommendedMemoryBytes: model.recommendedMemoryBytes,
        remote: true,
        repository: model.repository,
        revision: model.revision,
      );

  LocalModelDefinition _definition(String id) =>
      models.firstWhere((model) => model.id == id);

  String _friendlyError(Object error) {
    if (error is TimeoutException) {
      return '下载节点连接超时，请检查网络后重试';
    }
    if (error is SocketException) {
      return '无法连接下载节点，请检查网络后重试';
    }
    if (error is HttpException) return error.message;
    return error.toString().replaceFirst(
      RegExp(r'^(StateError|Exception|FormatException):\s*'),
      '',
    );
  }
}
