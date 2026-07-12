import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import '../models/local_llm.dart';
import '../services/local_assistant_service.dart';
import '../services/local_llm/local_llm_output_filter.dart';
import '../services/note_assistant_prompt_builder.dart';
import 'app_feedback.dart';
import 'app_popup_menu.dart';
import 'editor_context_menu.dart';
import 'fk_markdown_view.dart';

bool canInsertNoteAssistantOutput({
  required String output,
  required LocalLlmFinishReason? finishReason,
}) =>
    output.trim().isNotEmpty &&
    (finishReason == LocalLlmFinishReason.completed ||
        finishReason == LocalLlmFinishReason.maxTokens ||
        finishReason == LocalLlmFinishReason.canceled);

Future<NoteAssistantInvocation?> showNoteAssistantTaskSheet(
  BuildContext context, {
  Set<NoteAssistantScope> availableScopes = const {NoteAssistantScope.fullNote},
  NoteAssistantScope initialScope = NoteAssistantScope.fullNote,
}) {
  assert(availableScopes.isNotEmpty);
  return showModalBottomSheet<NoteAssistantInvocation>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _NoteAssistantTaskSheet(
      availableScopes: Set.unmodifiable(availableScopes),
      initialScope: availableScopes.contains(initialScope)
          ? initialScope
          : availableScopes.first,
    ),
  );
}

class _NoteAssistantTaskSheet extends StatefulWidget {
  final Set<NoteAssistantScope> availableScopes;
  final NoteAssistantScope initialScope;

  const _NoteAssistantTaskSheet({
    required this.availableScopes,
    required this.initialScope,
  });

  @override
  State<_NoteAssistantTaskSheet> createState() =>
      _NoteAssistantTaskSheetState();
}

class _NoteAssistantTaskSheetState extends State<_NoteAssistantTaskSheet> {
  final _controller = TextEditingController();
  late NoteAssistantScope _scope;

  @override
  void initState() {
    super.initState();
    _scope = widget.initialScope;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submitCustomInstruction() {
    final instruction = _controller.text.trim();
    if (instruction.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.pop(
      context,
      NoteAssistantInvocation(
        action: NoteAssistantAction.custom(instruction),
        scope: _scope,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.localAssistant,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.assistantPrivacyDescription,
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 14),
              Text(
                context.l10n.processingScope,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final scope in NoteAssistantScope.values)
                    if (widget.availableScopes.contains(scope))
                      ChoiceChip(
                        key: Key('note-assistant-scope-${scope.name}'),
                        label: Text(_scopeLabel(context, scope)),
                        selected: _scope == scope,
                        onSelected: (_) => setState(() => _scope = scope),
                      ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('note-assistant-custom-instruction'),
                controller: _controller,
                contextMenuBuilder: buildAppEditableTextContextMenu,
                minLines: 2,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: context.l10n.assistantCustomHint,
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  key: const Key('note-assistant-submit-custom'),
                  onPressed: _controller.text.trim().isEmpty
                      ? null
                      : _submitCustomInstruction,
                  icon: const Icon(Icons.arrow_upward_rounded),
                  label: Text(context.l10n.startGenerating),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      context.l10n.quickActions,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              _TaskTile(
                task: NoteAssistantTask.summarize,
                scope: _scope,
                icon: Icons.summarize_outlined,
                subtitle: context.l10n.assistantSummarizeDescription,
              ),
              _TaskTile(
                task: NoteAssistantTask.extractTodos,
                scope: _scope,
                icon: Icons.checklist_rounded,
                subtitle: context.l10n.assistantExtractTodosDescription,
              ),
              _TaskTile(
                task: NoteAssistantTask.polish,
                scope: _scope,
                icon: Icons.auto_fix_high_rounded,
                subtitle: context.l10n.assistantPolishDescription,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  final NoteAssistantTask task;
  final NoteAssistantScope scope;
  final IconData icon;
  final String subtitle;

  const _TaskTile({
    required this.task,
    required this.scope,
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
      _taskLabel(context, task),
      style: const TextStyle(fontWeight: FontWeight.w700),
    ),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: () => Navigator.pop(
      context,
      NoteAssistantInvocation(
        action: NoteAssistantAction.preset(task),
        scope: scope,
      ),
    ),
  );
}

class NoteAssistantResultSheet extends StatefulWidget {
  final NoteAssistantAction action;
  final NoteAssistantScope scope;
  final String title;
  final String content;
  final String languageCode;
  final Set<NoteAssistantPlacement> placements;

  const NoteAssistantResultSheet({
    super.key,
    required this.action,
    required this.scope,
    required this.title,
    required this.content,
    this.languageCode = 'zh',
    required this.placements,
  }) : assert(placements.length > 0);

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
        action: widget.action,
        title: widget.title,
        content: widget.content,
        scope: widget.scope,
        languageCode: widget.languageCode,
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
                          _actionLabel(context, widget.action),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _statusText(context),
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
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
                              : Text(
                                  context.l10n.assistantNoOutput,
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                  ),
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
              OverflowBar(
                alignment: MainAxisAlignment.end,
                overflowAlignment: OverflowBarAlignment.end,
                spacing: 8,
                overflowSpacing: 8,
                children: [
                  if (_generating)
                    TextButton.icon(
                      onPressed: _cancel,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: Text(context.l10n.stopGenerating),
                    )
                  else
                    TextButton.icon(
                      onPressed: _visibleOutput.trim().isEmpty ? null : _copy,
                      icon: const Icon(Icons.copy_rounded),
                      label: Text(context.l10n.copy),
                    ),
                  if (!_generating &&
                      (_finishReason == LocalLlmFinishReason.canceled ||
                          _finishReason == LocalLlmFinishReason.timeout))
                    IconButton(
                      tooltip: context.l10n.regenerate,
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  AppAnchoredMenuButton<NoteAssistantPlacement>(
                    key: const Key('note-assistant-use-result'),
                    enabled: canInsertNoteAssistantOutput(
                      output: _visibleOutput,
                      finishReason: _finishReason,
                    ),
                    tooltip: context.l10n.chooseGeneratedContentPlacement,
                    onSelected: (placement) => Navigator.pop(
                      context,
                      NoteAssistantResult(
                        text: _visibleOutput.trim(),
                        placement: placement,
                      ),
                    ),
                    actions: [
                      for (final placement in NoteAssistantPlacement.values)
                        if (widget.placements.contains(placement))
                          AppMenuAction(
                            value: placement,
                            icon: _placementIcon(placement),
                            label: _placementLabel(context, placement),
                          ),
                    ],
                    child: IgnorePointer(
                      child: FilledButton.icon(
                        onPressed:
                            canInsertNoteAssistantOutput(
                              output: _visibleOutput,
                              finishReason: _finishReason,
                            )
                            ? () {}
                            : null,
                        icon: const Icon(Icons.check_rounded),
                        label: Text(
                          _finishReason == LocalLlmFinishReason.canceled
                              ? context.l10n.useCurrentContent
                              : context.l10n.useGeneratedContent,
                        ),
                      ),
                    ),
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
      AppFeedback.success(context, context.l10n.generatedContentCopied);
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
    });
    unawaited(_run());
  }

  String _statusText(BuildContext context) {
    if (_loadingModel) return context.l10n.loadingLocalModel;
    if (_generating) return context.l10n.generatingOnDevice;
    return switch (_finishReason) {
      LocalLlmFinishReason.completed => context.l10n.generationCompleted,
      LocalLlmFinishReason.maxTokens => context.l10n.generationLimitReached,
      LocalLlmFinishReason.canceled => context.l10n.generationStoppedUsable,
      LocalLlmFinishReason.timeout => context.l10n.generationTimedOutUsable,
      null => context.l10n.generationIncomplete,
    };
  }

  IconData _placementIcon(NoteAssistantPlacement placement) =>
      switch (placement) {
        NoteAssistantPlacement.replace => Icons.find_replace_rounded,
        NoteAssistantPlacement.insertBelow => Icons.vertical_align_bottom,
        NoteAssistantPlacement.append => Icons.playlist_add_rounded,
      };
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
        OutlinedButton(onPressed: onRetry, child: Text(context.l10n.retry)),
      ],
    ),
  );
}

String _scopeLabel(BuildContext context, NoteAssistantScope scope) =>
    switch (scope) {
      NoteAssistantScope.selection => context.l10n.scopeSelection,
      NoteAssistantScope.currentBlock => context.l10n.scopeCurrentBlock,
      NoteAssistantScope.fullNote => context.l10n.scopeFullNote,
    };

String _taskLabel(BuildContext context, NoteAssistantTask task) =>
    switch (task) {
      NoteAssistantTask.summarize => context.l10n.assistantSummarize,
      NoteAssistantTask.extractTodos => context.l10n.assistantExtractTodos,
      NoteAssistantTask.polish => context.l10n.assistantPolish,
    };

String _actionLabel(BuildContext context, NoteAssistantAction action) =>
    action.task == null
    ? context.l10n.assistantCustomAction
    : _taskLabel(context, action.task!);

String _placementLabel(
  BuildContext context,
  NoteAssistantPlacement placement,
) => switch (placement) {
  NoteAssistantPlacement.replace => context.l10n.placementReplace,
  NoteAssistantPlacement.insertBelow => context.l10n.placementInsertBelow,
  NoteAssistantPlacement.append => context.l10n.placementAppend,
};
