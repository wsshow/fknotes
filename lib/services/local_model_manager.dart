import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/local_model.dart';
import 'realtime_dictation_service.dart';
import 'speech_model_service.dart';
import 'speech_transcription_service.dart';
import 'streaming_speech_model_service.dart';
import 'voice_activity_model_service.dart';

enum ModelTransferStatus {
  downloading,
  importing,
  verifying,
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
    this.cancelRequested = false,
  }) : _speedSampleBytes = transferredBytes;

  bool get isRunning => switch (status) {
    ModelTransferStatus.downloading ||
    ModelTransferStatus.importing ||
    ModelTransferStatus.verifying => true,
    _ => false,
  };

  double get progress =>
      totalBytes <= 0 ? 0 : (transferredBytes / totalBytes).clamp(0.0, 1.0);

  void updateProgress(SpeechModelImportProgress progress) {
    final now = DateTime.now();
    if (!progress.verifying) {
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
    if (progress.verifying) status = ModelTransferStatus.verifying;
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
  static const mlKitChineseOcrId = 'mlkit-text-recognition-chinese';
  static const imageUnderstandingId = 'image-understanding-local';

  static const catalog = <LocalModelDefinition>[
    LocalModelDefinition(
      id: senseVoiceId,
      name: 'SenseVoice Small INT8',
      summary: '录音与音频文件转写',
      description: '适合普通话、粤语和中英混合录音，支持标点与数字规范化。',
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
      source: 'k2-fsa 官方模型',
      license: 'MIT',
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
  final Map<String, LocalModelInstallation> _installations = {};
  final Map<String, ModelTransferState> _transfers = {};
  bool _initialized = false;
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
    ]);
    final speech = results[0] as SpeechModelInfo;
    final partial = results[1] as int;
    final streaming = results[2] as StreamingSpeechModelInfo;
    final streamingPartial = results[3] as int;
    final bilingual = results[4] as StreamingSpeechModelInfo;
    final bilingualPartial = results[5] as int;
    _selectedLiveDictationModelId = results[6] as String;
    final voiceActivity = results[7] as VoiceActivityModelInfo;
    final voiceActivityPartial = results[8] as int;
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
    _installations[mlKitChineseOcrId] = const LocalModelInstallation(
      installed: true,
    );
    _initialized = true;
    notifyListeners();
  }

  Future<void> download(String modelId) async {
    final definition = _definition(modelId);
    if (definition.availability != LocalModelAvailability.downloadable) return;
    if (_transfers.values.any((transfer) => transfer.isRunning)) return;
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
    } on SpeechModelDownloadCanceled {
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
        !StreamingSpeechModelService.supportedModelIds.contains(modelId)) {
      return;
    }
    if (_transfers.values.any((transfer) => transfer.isRunning)) return;
    final transfer = ModelTransferState(
      modelId: modelId,
      status: ModelTransferStatus.importing,
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
    }
  }

  void cancel(String modelId) {
    final transfer = _transfers[modelId];
    if (transfer?.isRunning != true) return;
    transfer!.cancelRequested = true;
    notifyListeners();
  }

  Future<void> remove(String modelId) async {
    if (modelId == senseVoiceId) {
      if (SpeechTranscriptionService.instance.jobs.any(
        (job) => job.isRunning,
      )) {
        throw StateError('请先等待正在进行的转写结束');
      }
      await _speechModels.remove();
    } else if (modelId == voiceActivityId) {
      if (SpeechTranscriptionService.instance.jobs.any(
        (job) => job.isRunning,
      )) {
        throw StateError('请先等待正在进行的转写结束');
      }
      await _voiceActivityModels.remove();
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

  String _friendlyError(Object error) => error.toString().replaceFirst(
    RegExp(r'^(StateError|Exception|FormatException):\s*'),
    '',
  );
}
