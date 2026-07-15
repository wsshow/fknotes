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
import '../widgets/app_feedback.dart';
import '../widgets/empty_state.dart';

class BackgroundTasksPage extends StatefulWidget {
  final NoteProvider provider;
  final Future<void> Function(BackgroundTaskItem item)? taskActionOverride;

  const BackgroundTasksPage({
    super.key,
    required this.provider,
    this.taskActionOverride,
  });

  @override
  State<BackgroundTasksPage> createState() => _BackgroundTasksPageState();
}

class _BackgroundTasksPageState extends State<BackgroundTasksPage> {
  final _center = BackgroundTaskCenter.instance;
  final Set<String> _busyTaskKeys = {};
  bool _clearingFailed = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(context.l10n.backgroundTasks)),
      body: SafeArea(
        top: false,
        child: AnimatedBuilder(
          animation: _center,
          builder: (context, _) {
            final running = _center.items
                .where((item) => item.state == BackgroundTaskState.running)
                .toList(growable: false);
            final failed = _center.items
                .where((item) => item.state == BackgroundTaskState.failed)
                .toList(growable: false);
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              children: [
                Text(
                  context.l10n.backgroundTasksPageDescription,
                  style: const TextStyle(color: AppColors.muted, height: 1.5),
                ),
                const SizedBox(height: 18),
                _TaskSummaryCard(
                  runningCount: running.length,
                  failedCount: failed.length,
                ),
                if (running.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  _TaskSectionHeader(
                    title: context.l10n.runningTasks,
                    count: running.length,
                  ),
                  const SizedBox(height: 12),
                  for (var index = 0; index < running.length; index++) ...[
                    _TaskCard(
                      key: ValueKey(
                        'background-task-${_taskKey(running[index])}',
                      ),
                      item: running[index],
                      busy: _busyTaskKeys.contains(_taskKey(running[index])),
                      onAction: () => _handleAction(running[index]),
                    ),
                    if (index != running.length - 1) const SizedBox(height: 10),
                  ],
                ],
                if (failed.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  _TaskSectionHeader(
                    title: context.l10n.tasksNeedingAttention,
                    count: failed.length,
                    action: TextButton.icon(
                      key: const Key('clear-failed-background-tasks'),
                      onPressed: _clearingFailed
                          ? null
                          : () => _confirmClearFailed(failed),
                      icon: _clearingFailed
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cleaning_services_outlined),
                      label: Text(context.l10n.clearFailedTasks),
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (var index = 0; index < failed.length; index++) ...[
                    _TaskCard(
                      key: ValueKey(
                        'background-task-${_taskKey(failed[index])}',
                      ),
                      item: failed[index],
                      busy: _busyTaskKeys.contains(_taskKey(failed[index])),
                      onAction: () => _handleAction(failed[index]),
                    ),
                    if (index != failed.length - 1) const SizedBox(height: 10),
                  ],
                ],
                if (running.isEmpty && failed.isEmpty) ...[
                  const SizedBox(height: 42),
                  EmptyState(
                    icon: Icons.task_alt_rounded,
                    message: context.l10n.allTasksComplete,
                    description: context.l10n.noBackgroundTasks,
                    alignment: Alignment.topCenter,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _handleAction(BackgroundTaskItem item) async {
    final key = _taskKey(item);
    if (_busyTaskKeys.contains(key)) return;
    setState(() => _busyTaskKeys.add(key));
    try {
      await _performAction(item);
    } catch (error) {
      if (mounted) {
        AppFeedback.error(context, context.l10n.taskActionFailed('$error'));
      }
    } finally {
      if (mounted) setState(() => _busyTaskKeys.remove(key));
    }
  }

  Future<void> _confirmClearFailed(List<BackgroundTaskItem> items) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.clearFailedTasksQuestion),
        content: Text(context.l10n.clearFailedTasksDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            key: const Key('confirm-clear-failed-background-tasks'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.clearFailedTasks),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearingFailed = true);
    Object? firstError;
    for (final item in items) {
      try {
        await _performAction(item);
      } catch (error) {
        firstError ??= error;
      }
    }
    if (!mounted) return;
    setState(() => _clearingFailed = false);
    if (firstError != null) {
      AppFeedback.error(context, context.l10n.taskActionFailed('$firstError'));
    }
  }

  Future<void> _performAction(BackgroundTaskItem item) async {
    final taskActionOverride = widget.taskActionOverride;
    if (taskActionOverride != null) {
      await taskActionOverride(item);
      return;
    }
    switch (item.kind) {
      case BackgroundTaskKind.model:
        if (item.state == BackgroundTaskState.running) {
          LocalModelManager.instance.cancel(item.id);
        } else {
          LocalModelManager.instance.dismissTransfer(item.id);
        }
      case BackgroundTaskKind.attachment:
        await widget.provider.removeAttachmentImport(item.id);
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
  }

  static String _taskKey(BackgroundTaskItem item) =>
      '${item.kind.name}:${item.id}';
}

class _TaskSummaryCard extends StatelessWidget {
  final int runningCount;
  final int failedCount;

  const _TaskSummaryCard({
    required this.runningCount,
    required this.failedCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TaskSummaryStat(
              icon: Icons.sync_rounded,
              value: runningCount,
              label: context.l10n.runningTasks,
              color: AppColors.moss,
              background: AppColors.softGreen,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              key: const Key('background-task-summary-divider'),
              width: 1,
              height: 36,
              color: AppColors.line,
            ),
          ),
          Expanded(
            child: _TaskSummaryStat(
              iconKey: const Key('background-task-failed-summary-icon'),
              icon: Icons.error_outline_rounded,
              value: failedCount,
              label: context.l10n.tasksNeedingAttention,
              color: failedCount > 0 ? AppColors.coral : AppColors.muted,
              background: failedCount > 0
                  ? AppColors.softCoral
                  : AppColors.softBlue,
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskSummaryStat extends StatelessWidget {
  final Key? iconKey;
  final IconData icon;
  final int value;
  final String label;
  final Color color;
  final Color background;

  const _TaskSummaryStat({
    this.iconKey,
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          key: iconKey,
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: background, shape: BoxShape.circle),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(width: 11),
        Flexible(
          fit: FlexFit.loose,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '$value',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TaskSectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final Widget? action;

  const _TaskSectionHeader({
    required this.title,
    required this.count,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.softBlue,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (action != null) ...[const SizedBox(width: 6), action!],
      ],
    );
  }
}

class _TaskCard extends StatelessWidget {
  final BackgroundTaskItem item;
  final bool busy;
  final VoidCallback onAction;

  const _TaskCard({
    super.key,
    required this.item,
    required this.busy,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final failed = item.state == BackgroundTaskState.failed;
    final title = _localizedTaskTitle(context.l10n, item);
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: failed ? AppColors.softCoral : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: failed ? AppColors.coral : AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: failed ? AppColors.surface : AppColors.softGreen,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  failed ? Icons.error_outline_rounded : _kindIcon(item.kind),
                  size: 20,
                  color: failed ? AppColors.coral : AppColors.moss,
                ),
              ),
              const SizedBox(width: 11),
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
                    const SizedBox(height: 2),
                    Text(
                      _localizedTaskKind(context.l10n, item.kind),
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: !busy && (item.cancelable || failed)
                    ? onAction
                    : null,
                child: busy
                    ? const SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        failed
                            ? context.l10n.remove
                            : item.kind == BackgroundTaskKind.inference
                            ? context.l10n.stopTask
                            : context.l10n.cancel,
                      ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Text(
            _localizedTaskDescription(context.l10n, item.description),
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          if (item.progress != null && !failed) ...[
            const SizedBox(height: 11),
            Semantics(
              label: context.l10n.taskProgress(title),
              value: '${(item.progress! * 100).round()}%',
              liveRegion: true,
              child: LinearProgressIndicator(value: item.progress),
            ),
            const SizedBox(height: 5),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${(item.progress! * 100).round()}%',
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
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

String _localizedTaskKind(AppLocalizations l10n, BackgroundTaskKind kind) =>
    switch (kind) {
      BackgroundTaskKind.model => l10n.modelTask,
      BackgroundTaskKind.attachment => l10n.attachmentTask,
      BackgroundTaskKind.transcription => l10n.transcriptionTask,
      BackgroundTaskKind.inference => l10n.localInferenceTask,
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
