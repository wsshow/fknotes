import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/local_model.dart';
import 'speech_model_service.dart';
import 'speech_transcription_service.dart';

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
  static const streamingChineseId = 'streaming-zipformer-zh-14m-2023-02-23';
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
      description: '面向笔记编辑器实时听写，模型接入与输入交互正在准备中。',
      category: LocalModelCategory.speech,
      availability: LocalModelAvailability.planned,
      task: LocalModelTask.liveDictation,
      downloadSizeBytes: 14 * 1024 * 1024,
      languages: ['普通话'],
      engine: 'sherpa-onnx',
      version: '计划接入',
      source: 'sherpa-onnx streaming models',
      license: '待接入时核对',
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
    final speech = await _speechModels.inspect();
    final partial = await _speechModels.partialDownloadBytes();
    _installations[senseVoiceId] = LocalModelInstallation(
      installed: speech.installed,
      installedSizeBytes: speech.sizeBytes,
      partialSizeBytes: partial,
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
    final existing = _transfers[modelId];
    if (existing?.isRunning == true) return;
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
      await _speechModels.downloadFromModelScope(
        shouldCancel: () => transfer.cancelRequested,
        onProgress: (progress) {
          transfer.updateProgress(progress);
          notifyListeners();
        },
      );
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
    if (modelId != senseVoiceId) return;
    final existing = _transfers[modelId];
    if (existing?.isRunning == true) return;
    final transfer = ModelTransferState(
      modelId: modelId,
      status: ModelTransferStatus.importing,
    );
    _transfers[modelId] = transfer;
    notifyListeners();
    try {
      final imported = await _speechModels.pickAndImport(
        onProgress: (progress) {
          transfer.updateProgress(progress);
          notifyListeners();
        },
      );
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
    if (modelId != senseVoiceId) return;
    if (SpeechTranscriptionService.instance.jobs.any((job) => job.isRunning)) {
      throw StateError('请先等待正在进行的转写结束');
    }
    await _speechModels.remove();
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
