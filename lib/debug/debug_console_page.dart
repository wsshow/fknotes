import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../app.dart';
import '../services/background_task_center.dart';
import '../services/local_inference_coordinator.dart';
import '../services/local_model_manager.dart';
import '../widgets/app_feedback.dart';
import 'app_diagnostics.dart';

class DebugConsolePage extends StatefulWidget {
  const DebugConsolePage({super.key});

  @override
  State<DebugConsolePage> createState() => _DebugConsolePageState();
}

class _DebugConsolePageState extends State<DebugConsolePage> {
  final _queryController = TextEditingController();
  final _levels = <AppLogLevel>{};
  AppLogCategory? _category;
  bool _busy = false;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  List<AppLogRecord> _records() => AppDiagnostics.instance.snapshot(
    levels: _levels,
    categories: _category == null ? null : {_category!},
    query: _queryController.text,
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('调试中心'),
          Text(
            '仅存在于 Debug 构建',
            style: TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: '导出诊断包',
          onPressed: _busy ? null : _export,
          icon: const Icon(Icons.ios_share_rounded),
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: AnimatedBuilder(
        animation: AppDiagnostics.instance.changes,
        builder: (context, _) {
          final all = AppDiagnostics.instance.snapshot();
          final records = _records();
          final errors = all
              .where((item) => item.level.index >= AppLogLevel.error.index)
              .length;
          final warnings = all
              .where((item) => item.level == AppLogLevel.warning)
              .length;
          return Column(
            children: [
              _SummaryCard(
                sessionId: AppDiagnostics.instance.sessionId,
                eventCount: all.length,
                errorCount: errors,
                warningCount: warnings,
              ),
              _buildFilters(),
              const Divider(height: 1),
              Expanded(
                child: records.isEmpty
                    ? const _EmptyLogs()
                    : ListView.separated(
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                        itemCount: records.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final record = records[records.length - 1 - index];
                          return _LogRecordCard(
                            record: record,
                            onTap: () => _showDetails(record),
                          );
                        },
                      ),
              ),
              _buildActions(records),
            ],
          );
        },
      ),
    ),
  );

  Widget _buildFilters() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
    child: Column(
      children: [
        TextField(
          controller: _queryController,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: '搜索事件、分类、错误或 Trace ID',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _queryController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: '清除搜索',
                    onPressed: () {
                      _queryController.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _levelChip('错误', AppLogLevel.error),
              _levelChip('警告', AppLogLevel.warning),
              _levelChip('信息', AppLogLevel.info),
              _levelChip('调试', AppLogLevel.debug),
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                initialValue: _category?.name ?? '__all__',
                onSelected: (value) => setState(
                  () => _category = value == '__all__'
                      ? null
                      : AppLogCategory.values.byName(value),
                ),
                itemBuilder: (context) => [
                  const PopupMenuItem(value: '__all__', child: Text('全部模块')),
                  for (final category in AppLogCategory.values)
                    PopupMenuItem(
                      value: category.name,
                      child: Text(_categoryLabel(category)),
                    ),
                ],
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: _category == null
                        ? AppColors.surface
                        : AppColors.softGreen,
                    border: Border.all(color: AppColors.line),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.tune_rounded, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        _category == null ? '全部模块' : _categoryLabel(_category!),
                      ),
                      const Icon(Icons.arrow_drop_down_rounded),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _levelChip(String label, AppLogLevel level) {
    final selected = _levels.contains(level);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (value) => setState(() {
          if (value) {
            _levels.add(level);
            if (level == AppLogLevel.error) _levels.add(AppLogLevel.fatal);
          } else {
            _levels.remove(level);
            if (level == AppLogLevel.error) _levels.remove(AppLogLevel.fatal);
          }
        }),
      ),
    );
  }

  Widget _buildActions(List<AppLogRecord> records) => Container(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
    decoration: const BoxDecoration(
      color: AppColors.surface,
      border: Border(top: BorderSide(color: AppColors.line)),
    ),
    child: Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: records.isEmpty ? null : () => _copy(records),
            icon: const Icon(Icons.copy_all_rounded),
            label: const Text('复制筛选结果'),
          ),
        ),
        const SizedBox(width: 10),
        IconButton.outlined(
          tooltip: '清空日志',
          onPressed: _busy ? null : _confirmClear,
          icon: const Icon(Icons.delete_sweep_outlined),
        ),
      ],
    ),
  );

  Future<void> _copy(List<AppLogRecord> records) async {
    final value = records
        .map((record) => jsonEncode(record.toJson()))
        .join('\n');
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) _message('已复制 ${records.length} 条脱敏日志');
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      _captureRuntimeSnapshot();
      final file = await AppDiagnostics.instance.exportBundle();
      if (file == null) throw StateError('诊断包未生成');
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(
              file.path,
              mimeType: 'application/zip',
              name: file.uri.pathSegments.last,
            ),
          ],
          title: 'FKNotes Debug 诊断包',
          subject: 'FKNotes Debug 诊断包',
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (error, stackTrace) {
      AppDiagnostics.error(
        AppLogCategory.application,
        'diagnostics_export_failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) _message('导出失败，请查看最新错误日志');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _captureRuntimeSnapshot() {
    final modelManager = LocalModelManager.instance;
    final tasks = BackgroundTaskCenter.instance;
    final activity = LocalInferenceCoordinator.instance.activity;
    AppDiagnostics.info(
      AppLogCategory.application,
      'runtime_snapshot_captured',
      data: {
        'installedModelCount': modelManager.installedCount,
        'installedModelBytes': modelManager.installedSizeBytes,
        'selectedAssistantModelId': modelManager.selectedAssistantModelId,
        'selectedLiveDictationModelId':
            modelManager.selectedLiveDictationModelId,
        'activeTaskCount': tasks.activeCount,
        'failedTaskCount': tasks.failedCount,
        'inferenceType': activity?.type.name,
        'inferenceDurationMs': activity == null
            ? null
            : DateTime.now().difference(activity.startedAt).inMilliseconds,
      },
    );
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空调试日志？'),
        content: const Text('内存和本次运行已写入的日志都会被清除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    await AppDiagnostics.instance.clear();
    if (mounted) setState(() => _busy = false);
  }

  void _showDetails(AppLogRecord record) {
    final json = const JsonEncoder.withIndent('  ').convert(record.toJson());
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: .82,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      record.event,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: '复制该事件',
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: json));
                      if (context.mounted) Navigator.pop(context);
                      if (mounted) _message('事件已复制');
                    },
                    icon: const Icon(Icons.copy_rounded),
                  ),
                ],
              ),
              Text(
                '${_levelLabel(record.level)} · '
                '${_categoryLabel(record.category)} · #${record.sequence}',
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.canvas,
                    border: Border.all(color: AppColors.line),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      json,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _message(String text) => AppFeedback.show(context, text);
}

class _SummaryCard extends StatelessWidget {
  final String sessionId;
  final int eventCount;
  final int errorCount;
  final int warningCount;

  const _SummaryCard({
    required this.sessionId,
    required this.eventCount,
    required this.errorCount,
    required this.warningCount,
  });

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 10, 16, 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.softGreen,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.line),
    ),
    child: Row(
      children: [
        const Icon(Icons.bug_report_outlined, color: AppColors.moss),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '会话 ${sessionId.length > 12 ? sessionId.substring(0, 12) : sessionId}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(
                '$eventCount 条事件 · $warningCount 条警告 · $errorCount 条错误',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(99),
          ),
          child: const Text(
            'LIVE',
            style: TextStyle(
              color: AppColors.moss,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );
}

class _LogRecordCard extends StatelessWidget {
  final AppLogRecord record;
  final VoidCallback onTap;

  const _LogRecordCard({required this.record, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = _levelColor(record.level);
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            record.event,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          _clock(record.timestamp),
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_levelLabel(record.level)} · '
                      '${_categoryLabel(record.category)} · '
                      '${record.elapsed.inMilliseconds} ms',
                      style: TextStyle(color: color, fontSize: 11),
                    ),
                    if (record.error != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        record.error!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyLogs extends StatelessWidget {
  const _EmptyLogs();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.manage_search_rounded, size: 48, color: AppColors.muted),
        SizedBox(height: 12),
        Text('没有符合筛选条件的日志'),
      ],
    ),
  );
}

Color _levelColor(AppLogLevel level) => switch (level) {
  AppLogLevel.debug => AppColors.muted,
  AppLogLevel.info => AppColors.moss,
  AppLogLevel.warning => const Color(0xFF9B681A),
  AppLogLevel.error || AppLogLevel.fatal => AppColors.coral,
};

String _levelLabel(AppLogLevel level) => switch (level) {
  AppLogLevel.debug => '调试',
  AppLogLevel.info => '信息',
  AppLogLevel.warning => '警告',
  AppLogLevel.error => '错误',
  AppLogLevel.fatal => '致命',
};

String _categoryLabel(AppLogCategory category) => switch (category) {
  AppLogCategory.application => '应用',
  AppLogCategory.navigation => '导航',
  AppLogCategory.storage => '存储',
  AppLogCategory.database => '数据库',
  AppLogCategory.editor => '编辑器',
  AppLogCategory.media => '媒体',
  AppLogCategory.localAssistant => '本地助手',
  AppLogCategory.inference => '推理',
  AppLogCategory.modelManagement => '模型管理',
  AppLogCategory.modelDownload => '模型下载',
  AppLogCategory.speech => '语音',
  AppLogCategory.cloudSync => '云同步',
  AppLogCategory.authentication => '应用锁',
  AppLogCategory.backgroundTask => '后台任务',
  AppLogCategory.network => '网络',
  AppLogCategory.platform => '原生平台',
};

String _clock(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}:'
    '${value.second.toString().padLeft(2, '0')}';
