import 'package:flutter/material.dart';

import '../app.dart';
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
            tooltip: count == 0 ? '后台任务' : '后台任务 · $count 项',
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
                      '后台任务',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      items.isEmpty
                          ? '当前没有正在运行或需要处理的任务'
                          : '${center.activeCount} 项进行中 · ${center.failedCount} 项需要处理',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: items.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.task_alt_rounded,
                              size: 48,
                              color: AppColors.muted,
                            ),
                            SizedBox(height: 12),
                            Text(
                              '所有任务均已完成',
                              style: TextStyle(color: AppColors.muted),
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
      AppFeedback.error(context, '任务操作失败：$error');
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
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  item.description,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                if (item.progress != null && !failed) ...[
                  const SizedBox(height: 9),
                  Semantics(
                    label: '${item.title}进度',
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
            child: Text(failed ? '移除' : '取消'),
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
