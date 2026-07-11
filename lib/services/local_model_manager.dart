import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/local_model.dart';
import 'kokoro_tts_model_service.dart';
import 'model_download_transport.dart';
import 'note_read_aloud_service.dart';
import 'realtime_dictation_preferences_service.dart';
import 'realtime_dictation_service.dart';
import 'speech_model_service.dart';
import 'speech_denoiser_model_service.dart';
import 'speech_transcription_service.dart';
import 'speaker_diarization_model_service.dart';
import 'streaming_speech_model_service.dart';
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
  static const imageUnderstandingId = 'image-understanding-local';

  static const catalog = <LocalModelDefinition>[
    LocalModelDefinition(
      id: senseVoiceId,
      name: 'SenseVoice Small INT8',
      summary: '音频转写与实时听写结束精修',
      description: '适合普通话、粤语和中英混合录音；也可在实时听写结束后补充标点并规范数字。',
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
    LocalModelDefinition(
      id: imageUnderstandingId,
      name: '本地图片理解',
      summary: '图片描述、内容分类与检索',
      description: '为后续本地图片理解能力预留，目前尚未选择正式模型。',
      category: LocalModelCategory.vision,
      availability: LocalModelAvailability.planned,
      task: LocalModelTask.imageUnderstanding,
      engine: '待定',
      version: '规划中',
      source: '待评估',
      license: '待评估',
    ),
  ];

  final _speechModels = SpeechModelService.instance;
  final _streamingModels = StreamingSpeechModelService.instance;
  final _voiceActivityModels = VoiceActivityModelService.instance;
  final _speechDenoiserModels = SpeechDenoiserModelService.instance;
  final _speakerDiarizationModels = SpeakerDiarizationModelService.instance;
  final _kokoroTtsModels = KokoroTtsModelService.instance;
  final _dictationPreferences = RealtimeDictationPreferencesService.instance;
  final Map<String, LocalModelInstallation> _installations = {};
  final Map<String, ModelTransferState> _transfers = {};
  bool _initialized = false;
  bool _importPickerBusy = false;
  int _initializationGeneration = 0;
  String _selectedLiveDictationModelId = streamingChineseId;

  List<LocalModelDefinition> get models => catalog;
  bool get initialized => _initialized;
  String get selectedLiveDictationModelId => _selectedLiveDictationModelId;
  LocalModelDefinition modelOf(String id) => _definition(id);
  LocalModelInstallation installationOf(String id) =>
      _installations[id] ?? const LocalModelInstallation();
  ModelTransferState? transferOf(String id) => _transfers[id];

  int get installedCount => catalog.where((model) {
    return model.availability == LocalModelAvailability.builtIn ||
        installationOf(model.id).installed;
  }).length;

  int get installedSizeBytes => _installations.values.fold(
    0,
    (sum, installation) => sum + installation.installedSizeBytes,
  );

  Future<void> initialize({bool force = false}) async {
    if (_initialized && !force) return;
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
    if (generation != _initializationGeneration) return;
    _selectedLiveDictationModelId = selectedLiveDictationModelId;
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

  Future<void> _selectIfNoUsableLiveModel(String installedModelId) async {
    final selected = await _streamingModels.inspect();
    if (!selected.installed) {
      await _streamingModels.selectModel(installedModelId);
      _selectedLiveDictationModelId = installedModelId;
    }
  }

  LocalModelDefinition _definition(String id) =>
      catalog.firstWhere((model) => model.id == id);

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
