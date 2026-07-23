import 'package:flutter/foundation.dart';

import '../debug/app_diagnostics.dart';
import 'local_inference_coordinator.dart';
import 'local_model_manager.dart';
import 'speech_transcription_service.dart';

enum BackgroundTaskKind { model, transcription, inference }

enum BackgroundTaskState { running, failed }

class BackgroundTaskItem {
  final String id;
  final BackgroundTaskKind kind;
  final BackgroundTaskState state;
  final String title;
  final String description;
  final double? progress;
  final bool cancelable;
  final String? resourceType;

  const BackgroundTaskItem({
    required this.id,
    required this.kind,
    required this.state,
    required this.title,
    required this.description,
    this.progress,
    this.cancelable = false,
    this.resourceType,
  });
}

class BackgroundTaskCenter extends ChangeNotifier {
  BackgroundTaskCenter._() {
    _models.addListener(_changed);
    _transcriptions.addListener(_changed);
    _inference.addListener(_changed);
  }

  static final BackgroundTaskCenter instance = BackgroundTaskCenter._();

  final _models = LocalModelManager.instance;
  final _transcriptions = SpeechTranscriptionService.instance;
  final _inference = LocalInferenceCoordinator.instance;
  final Map<String, BackgroundTaskState> _debugStates = {};

  List<BackgroundTaskItem> get items {
    final result = <BackgroundTaskItem>[];
    for (final transfer in _models.transfers) {
      if (!transfer.isRunning &&
          transfer.status != ModelTransferStatus.failed) {
        continue;
      }
      final model = _models.modelOf(transfer.modelId);
      result.add(
        BackgroundTaskItem(
          id: transfer.modelId,
          kind: BackgroundTaskKind.model,
          state: transfer.status == ModelTransferStatus.failed
              ? BackgroundTaskState.failed
              : BackgroundTaskState.running,
          title: model.name,
          description: transfer.status == ModelTransferStatus.failed
              ? transfer.errorMessage ?? '模型任务失败'
              : _modelStatusLabel(transfer.status),
          progress: transfer.totalBytes > 0 ? transfer.progress : null,
          cancelable: transfer.isRunning && transfer.cancelable,
        ),
      );
    }
    for (final job in _transcriptions.jobs) {
      if (!job.isRunning && job.status != TranscriptionStatus.failed) continue;
      result.add(
        BackgroundTaskItem(
          id: job.filePath,
          kind: BackgroundTaskKind.transcription,
          state: job.status == TranscriptionStatus.failed
              ? BackgroundTaskState.failed
              : BackgroundTaskState.running,
          title: '音频转写',
          description: job.status == TranscriptionStatus.failed
              ? job.errorMessage ?? '转写失败'
              : _transcriptionStatusLabel(job.status),
          progress: job.isRunning ? job.progress : null,
          cancelable: job.isRunning,
        ),
      );
    }
    final activity = _inference.activity;
    if (activity != null &&
        activity.type != LocalInferenceTaskType.transcription) {
      result.add(
        BackgroundTaskItem(
          id: activity.ownerId,
          kind: BackgroundTaskKind.inference,
          state: BackgroundTaskState.running,
          title: activity.type.label,
          description: '正在使用本地推理资源',
          cancelable: true,
          resourceType: activity.type.name,
        ),
      );
    }
    result.sort((left, right) {
      if (left.state == right.state) return left.title.compareTo(right.title);
      return left.state == BackgroundTaskState.running ? -1 : 1;
    });
    return result;
  }

  int get activeCount =>
      items.where((item) => item.state == BackgroundTaskState.running).length;

  int get failedCount =>
      items.where((item) => item.state == BackgroundTaskState.failed).length;

  void _changed() {
    if (kDebugMode) _recordStateChanges();
    notifyListeners();
  }

  void _recordStateChanges() {
    final current = <String, BackgroundTaskState>{};
    for (final item in items) {
      final key = '${item.kind.name}:${item.id.hashCode}';
      current[key] = item.state;
      final previous = _debugStates[key];
      if (previous == item.state) continue;
      AppDiagnostics.instance.record(
        item.state == BackgroundTaskState.failed
            ? AppLogLevel.error
            : AppLogLevel.info,
        AppLogCategory.backgroundTask,
        item.state == BackgroundTaskState.failed
            ? 'background_task_failed'
            : 'background_task_started',
        data: {
          'taskKey': key,
          'kind': item.kind.name,
          'cancelable': item.cancelable,
          'resourceType': item.resourceType,
        },
      );
    }
    for (final entry in _debugStates.entries) {
      if (current.containsKey(entry.key)) continue;
      AppDiagnostics.info(
        AppLogCategory.backgroundTask,
        'background_task_removed',
        data: {'taskKey': entry.key, 'previousState': entry.value.name},
      );
    }
    _debugStates
      ..clear()
      ..addAll(current);
  }

  static String _modelStatusLabel(ModelTransferStatus status) =>
      switch (status) {
        ModelTransferStatus.connecting => '正在连接下载源',
        ModelTransferStatus.downloading => '正在下载模型',
        ModelTransferStatus.importing => '正在导入模型',
        ModelTransferStatus.waitingToInstall => '等待安装资源',
        ModelTransferStatus.verifying => '正在校验并安装',
        ModelTransferStatus.canceling => '正在取消',
        ModelTransferStatus.completed => '已完成',
        ModelTransferStatus.failed => '失败',
        ModelTransferStatus.canceled => '已取消',
      };

  static String _transcriptionStatusLabel(TranscriptionStatus status) =>
      switch (status) {
        TranscriptionStatus.preparing => '正在准备转写',
        TranscriptionStatus.decoding => '正在解码音频',
        TranscriptionStatus.diarizing => '正在区分说话人',
        TranscriptionStatus.recognizing => '正在识别语音',
        TranscriptionStatus.saving => '正在保存转写',
        TranscriptionStatus.completed => '已完成',
        TranscriptionStatus.failed => '失败',
        TranscriptionStatus.canceled => '已取消',
      };
}
