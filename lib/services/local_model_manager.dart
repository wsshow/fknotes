import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/local_model.dart';
import 'realtime_dictation_service.dart';
import 'speech_model_service.dart';
import 'speech_transcription_service.dart';
import 'streaming_speech_model_service.dart';

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
      version: '2023-02-23 INT8',
      source: 'ModelScope · sherpa-onnx-asr-models',
      license: 'Apache-2.0',
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
  final Map<String, LocalModelInstallation> _installations = {};
  final Map<String, ModelTransferState> _transfers = {};
  bool _initialized = false;

  List<LocalModelDefinition> get models => catalog;
  bool get initialized => _initialized;
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
      _streamingModels.inspect(),
      _streamingModels.partialDownloadBytes(),
    ]);
    final speech = results[0] as SpeechModelInfo;
    final partial = results[1] as int;
    final streaming = results[2] as StreamingSpeechModelInfo;
    final streamingPartial = results[3] as int;
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
      } else if (modelId == streamingChineseId) {
        await _streamingModels.downloadFromModelScope(
          shouldCancel: () => transfer.cancelRequested,
          onProgress: progress,
        );
      } else {
        return;
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
    if (modelId != senseVoiceId && modelId != streamingChineseId) return;
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
      } else {
        imported = await _streamingModels.pickAndImport(onProgress: progress);
      }
      if (imported == null) {
        _transfers.remove(modelId);
      } else {
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
    } else if (modelId == streamingChineseId) {
      if (RealtimeDictationService.instance.isActive) {
        throw StateError('请先结束正在进行的实时听写');
      }
      await _streamingModels.remove();
    } else {
      return;
    }
    _transfers.remove(modelId);
    await initialize(force: true);
  }

  LocalModelDefinition _definition(String id) =>
      catalog.firstWhere((model) => model.id == id);

  String _friendlyError(Object error) => error.toString().replaceFirst(
    RegExp(r'^(StateError|Exception|FormatException):\s*'),
    '',
  );
}
