import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../models/local_llm.dart';
import '../services/local_assistant_service.dart';
import '../services/local_llm/local_llm_output_filter.dart';
import '../services/note_assistant_prompt_builder.dart';
import 'fk_markdown_view.dart';

Future<NoteAssistantTask?> showNoteAssistantTaskSheet(BuildContext context) =>
    showModalBottomSheet<NoteAssistantTask>(
      context: context,
      builder: (context) => const _NoteAssistantTaskSheet(),
    );

class _NoteAssistantTaskSheet extends StatelessWidget {
  const _NoteAssistantTaskSheet();

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '本地助手',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            '笔记内容只在设备上处理，生成结果会先预览。',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          _TaskTile(
            task: NoteAssistantTask.summarize,
            icon: Icons.summarize_outlined,
            subtitle: '提炼核心结论与关键要点',
          ),
          _TaskTile(
            task: NoteAssistantTask.extractTodos,
            icon: Icons.checklist_rounded,
            subtitle: '找出明确、可执行的事项',
          ),
          _TaskTile(
            task: NoteAssistantTask.polish,
            icon: Icons.auto_fix_high_rounded,
            subtitle: '保留事实与结构，改善表达',
          ),
        ],
      ),
    ),
  );
}

class _TaskTile extends StatelessWidget {
  final NoteAssistantTask task;
  final IconData icon;
  final String subtitle;

  const _TaskTile({
    required this.task,
    required this.icon,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: AppColors.softGreen,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: AppColors.moss),
    ),
    title: Text(
      task.label,
      style: const TextStyle(fontWeight: FontWeight.w700),
    ),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: () => Navigator.pop(context, task),
  );
}

class NoteAssistantResultSheet extends StatefulWidget {
  final NoteAssistantTask task;
  final String title;
  final String content;

  const NoteAssistantResultSheet({
    super.key,
    required this.task,
    required this.title,
    required this.content,
  });

  @override
  State<NoteAssistantResultSheet> createState() =>
      _NoteAssistantResultSheetState();
}

class _NoteAssistantResultSheetState extends State<NoteAssistantResultSheet> {
  final _assistant = LocalAssistantService.instance;
  final _rawOutput = StringBuffer();
  String _visibleOutput = '';
  String? _error;
  LocalLlmGenerationMetrics? _metrics;
  LocalLlmFinishReason? _finishReason;
  bool _loadingModel = true;
  bool _generating = false;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    try {
      await _assistant.loadSelectedModel();
      if (!mounted) return;
      setState(() {
        _loadingModel = false;
        _generating = true;
      });
      final request = NoteAssistantPromptBuilder.build(
        task: widget.task,
        title: widget.title,
        content: widget.content,
      );
      await for (final event in _assistant.generate(request)) {
        if (!mounted) return;
        switch (event) {
          case LocalLlmTextDelta():
            _rawOutput.write(event.text);
            setState(
              () => _visibleOutput = LocalLlmOutputFilter.visibleText(
                _rawOutput.toString(),
              ),
            );
          case LocalLlmGenerationCompleted():
            setState(() {
              _visibleOutput = LocalLlmOutputFilter.visibleText(
                _rawOutput.toString(),
              ).trim();
              _metrics = event.metrics;
              _finishReason = event.reason;
              _generating = false;
              _completed =
                  event.reason == LocalLlmFinishReason.completed ||
                  event.reason == LocalLlmFinishReason.maxTokens;
            });
        }
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingModel = false;
        _generating = false;
        _error = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  @override
  void dispose() {
    if (_generating) unawaited(_assistant.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busy = _loadingModel || _generating;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .76,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.softGreen,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: AppColors.moss,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.task.label,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          _statusText,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.canvas,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: _error != null
                      ? _ErrorContent(message: _error!, onRetry: _retry)
                      : _visibleOutput.isEmpty
                      ? Center(
                          child: busy
                              ? const CircularProgressIndicator(strokeWidth: 2)
                              : const Text(
                                  '模型没有生成内容',
                                  style: TextStyle(color: AppColors.muted),
                                ),
                        )
                      : SingleChildScrollView(
                          child: FkMarkdownView(data: _visibleOutput),
                        ),
                ),
              ),
              if (_metrics != null && _metrics!.generatedTokens > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '${_metrics!.generatedTokens} tokens · '
                  '${_metrics!.decodeTokensPerSecond.toStringAsFixed(1)} tokens/s',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  if (_generating)
                    TextButton.icon(
                      onPressed: _cancel,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('停止生成'),
                    )
                  else
                    TextButton.icon(
                      onPressed: _visibleOutput.trim().isEmpty ? null : _copy,
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('复制'),
                    ),
                  if (!_generating &&
                      (_finishReason == LocalLlmFinishReason.canceled ||
                          _finishReason == LocalLlmFinishReason.timeout))
                    IconButton(
                      tooltip: '重新生成',
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _completed && _visibleOutput.trim().isNotEmpty
                        ? () => Navigator.pop(context, _visibleOutput.trim())
                        : null,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('插入笔记末尾'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _cancel() async {
    await _assistant.cancel();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _visibleOutput.trim()));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已复制生成内容')));
    }
  }

  void _retry() {
    setState(() {
      _rawOutput.clear();
      _visibleOutput = '';
      _error = null;
      _metrics = null;
      _finishReason = null;
      _loadingModel = true;
      _completed = false;
    });
    unawaited(_run());
  }

  String get _statusText {
    if (_loadingModel) return '正在加载本地模型…';
    if (_generating) return '正在设备上生成…';
    return switch (_finishReason) {
      LocalLlmFinishReason.completed => '生成完成，请检查后使用',
      LocalLlmFinishReason.maxTokens => '已达到输出上限，请检查结果',
      LocalLlmFinishReason.canceled => '生成已停止，可复制当前内容',
      LocalLlmFinishReason.timeout => '生成超时，可重试或复制当前内容',
      null => '本地生成未完成',
    };
  }
}

class _ErrorContent extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorContent({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline_rounded, color: AppColors.coral),
        const SizedBox(height: 10),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onRetry, child: const Text('重试')),
      ],
    ),
  );
}
