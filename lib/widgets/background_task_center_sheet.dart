import 'package:flutter/material.dart';

import '../app.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n.dart';
import '../l10n/local_model_l10n.dart';
import '../providers/note_provider.dart';
import '../services/background_task_center.dart';
import '../services/local_assistant_service.dart';
import '../services/local_inference_coordinator.dart';
import '../services/local_model_manager.dart';
import '../services/note_read_aloud_service.dart';
import '../services/realtime_dictation_service.dart';
import '../services/speech_transcription_service.dart';
import 'app_feedback.dart';

class BackgroundTaskCenterButton extends StatelessWidget {
  final NoteProvider provider;

  const BackgroundTaskCenterButton({super.key, required this.provider});

  @override
  Widget build(BuildContext context) {
    final center = BackgroundTaskCenter.instance;
    return AnimatedBuilder(
      animation: center,
      builder: (context, _) {
        final count = center.items.length;
        return Badge(
          isLabelVisible: count > 0,
          label: Text('$count'),
          child: IconButton(
            key: const Key('open-background-tasks'),
            tooltip: count == 0
                ? context.l10n.backgroundTasks
                : context.l10n.backgroundTaskCount(count),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              useSafeArea: true,
              showDragHandle: true,
              isScrollControlled: true,
              builder: (_) => _BackgroundTaskSheet(provider: provider),
            ),
            icon: Icon(
              center.failedCount > 0
                  ? Icons.error_outline_rounded
                  : count > 0
                  ? Icons.sync_rounded
                  : Icons.task_alt_rounded,
            ),
          ),
        );
      },
    );
  }
}

class _BackgroundTaskSheet extends StatelessWidget {
  final NoteProvider provider;

  const _BackgroundTaskSheet({required this.provider});

  @override
  Widget build(BuildContext context) {
    final center = BackgroundTaskCenter.instance;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .7,
      child: AnimatedBuilder(
        animation: center,
        builder: (context, _) {
          final items = center.items;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.backgroundTasks,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      items.isEmpty
                          ? context.l10n.noBackgroundTasks
                          : context.l10n.backgroundTaskSummary(
                              center.activeCount,
                              center.failedCount,
                            ),
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.task_alt_rounded,
                              size: 48,
                              color: AppColors.muted,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              context.l10n.allTasksComplete,
                              style: const TextStyle(color: AppColors.muted),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, index) => _TaskCard(
                          item: items[index],
                          onAction: () => _handleAction(context, items[index]),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    BackgroundTaskItem item,
  ) async {
    try {
      switch (item.kind) {
        case BackgroundTaskKind.model:
          if (item.state == BackgroundTaskState.running) {
            LocalModelManager.instance.cancel(item.id);
          } else {
            LocalModelManager.instance.dismissTransfer(item.id);
          }
        case BackgroundTaskKind.attachment:
          await provider.removeAttachmentImport(item.id);
        case BackgroundTaskKind.transcription:
          if (item.state == BackgroundTaskState.running) {
            SpeechTranscriptionService.instance.cancel(item.id);
          } else {
            SpeechTranscriptionService.instance.dismiss(item.id);
          }
        case BackgroundTaskKind.inference:
          final type = LocalInferenceTaskType.values.firstWhere(
            (value) => value.name == item.resourceType,
          );
          switch (type) {
            case LocalInferenceTaskType.liveDictation:
              await RealtimeDictationService.instance.cancel();
            case LocalInferenceTaskType.readAloud:
              await NoteReadAloudService.instance.stop();
            case LocalInferenceTaskType.assistant:
              await LocalAssistantService.instance.unload();
            case LocalInferenceTaskType.transcription:
              break;
          }
      }
    } catch (error) {
      if (!context.mounted) return;
      AppFeedback.error(context, context.l10n.taskActionFailed('$error'));
    }
  }
}

class _TaskCard extends StatelessWidget {
  final BackgroundTaskItem item;
  final VoidCallback onAction;

  const _TaskCard({required this.item, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final failed = item.state == BackgroundTaskState.failed;
    final title = _localizedTaskTitle(context.l10n, item);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: failed ? AppColors.softCoral : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: failed ? AppColors.coral : AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            failed ? Icons.error_outline_rounded : _kindIcon(item.kind),
            color: failed ? AppColors.coral : AppColors.moss,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  _localizedTaskDescription(context.l10n, item.description),
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                if (item.progress != null && !failed) ...[
                  const SizedBox(height: 9),
                  Semantics(
                    label: context.l10n.taskProgress(title),
                    value: '${(item.progress! * 100).round()}%',
                    liveRegion: true,
                    child: LinearProgressIndicator(value: item.progress),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: item.cancelable || failed ? onAction : null,
            child: Text(failed ? context.l10n.remove : context.l10n.cancel),
          ),
        ],
      ),
    );
  }

  static IconData _kindIcon(BackgroundTaskKind kind) => switch (kind) {
    BackgroundTaskKind.model => Icons.download_rounded,
    BackgroundTaskKind.attachment => Icons.attach_file_rounded,
    BackgroundTaskKind.transcription => Icons.graphic_eq_rounded,
    BackgroundTaskKind.inference => Icons.memory_rounded,
  };
}

String _localizedTaskTitle(AppLocalizations l10n, BackgroundTaskItem item) =>
    switch (item.kind) {
      BackgroundTaskKind.model => localizedModelName(
        l10n,
        LocalModelManager.instance.modelOf(item.id),
      ),
      BackgroundTaskKind.attachment => item.title,
      BackgroundTaskKind.transcription => l10n.audioTranscription,
      BackgroundTaskKind.inference => switch (item.resourceType) {
        'liveDictation' => l10n.liveDictation,
        'readAloud' => l10n.readAloud,
        'assistant' => l10n.localAssistant,
        _ => item.title,
      },
    };

String _localizedTaskDescription(AppLocalizations l10n, String description) =>
    switch (description) {
      '正在连接下载源' => l10n.connectingModelSource,
      '正在下载模型' => l10n.downloadingModel,
      '正在导入模型' => l10n.importingModel,
      '等待安装资源' => l10n.waitingToInstall,
      '正在校验并安装' => l10n.verifyingAndInstalling,
      '正在取消' => l10n.canceling,
      '已完成' => l10n.completed,
      '失败' => l10n.failed,
      '已取消' => l10n.canceled,
      '模型任务失败' => l10n.modelTaskFailed,
      '正在导入附件' => l10n.importingAttachment,
      '正在保存到笔记' => l10n.savingToNote,
      '附件导入失败' => l10n.attachmentImportFailed,
      '转写失败' => l10n.transcriptionFailed,
      '正在准备转写' => l10n.preparingTranscription,
      '正在解码音频' => l10n.decodingAudio,
      '正在区分说话人' => l10n.identifyingSpeakers,
      '正在识别语音' => l10n.recognizingSpeech,
      '正在保存转写' => l10n.savingTranscript,
      '正在使用本地推理资源' => l10n.localInferenceInUse,
      _ => description,
    };
