import 'package:flutter/material.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import '../models/local_chat.dart';
import '../models/note.dart';
import 'note_delta_preview.dart';

class LocalChatToolActionCard extends StatelessWidget {
  final LocalChatToolCall call;
  final String targetLabel;
  final VoidCallback? onReview;

  const LocalChatToolActionCard({
    super.key,
    required this.call,
    required this.targetLabel,
    required this.onReview,
  });

  @override
  Widget build(BuildContext context) {
    final completed = call.status == LocalChatToolStatus.completed;
    return Container(
      key: Key('local-chat-tool-action-${call.id}'),
      width: double.infinity,
      margin: const EdgeInsets.only(top: 9),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: completed ? AppColors.successSoft : AppColors.warningSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: completed ? AppColors.success : AppColors.line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                completed
                    ? Icons.check_circle_outline
                    : Icons.edit_note_rounded,
                size: 18,
                color: completed ? AppColors.success : AppColors.warning,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  _toolLabel(context, call.name),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            targetLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.muted, fontSize: 11),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: completed
                ? Text(
                    context.l10n.toolActionCompleted,
                    style: const TextStyle(
                      color: AppColors.success,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : TextButton(
                    key: Key('local-chat-review-tool-${call.id}'),
                    onPressed: onReview,
                    child: Text(context.l10n.reviewToolAction),
                  ),
          ),
        ],
      ),
    );
  }
}

Future<bool?> showLocalChatToolActionSheet(
  BuildContext context, {
  required LocalChatToolCall call,
  Note? target,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) => _LocalChatToolActionSheet(call: call, target: target),
);

class _LocalChatToolActionSheet extends StatelessWidget {
  final LocalChatToolCall call;
  final Note? target;

  const _LocalChatToolActionSheet({required this.call, required this.target});

  @override
  Widget build(BuildContext context) {
    final current = target?.contentProjection.plainText.trim() ?? '';
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .84,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _toolLabel(context, call.name),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.cancel,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.warningSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.verified_user_outlined,
                        size: 19,
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.l10n.toolActionConfirmationNotice,
                          style: const TextStyle(fontSize: 12, height: 1.45),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _PreviewSection(
                  label: context.l10n.toolTargetNote,
                  child: Text(
                    call.name == LocalChatToolName.createNote
                        ? (call.title?.trim().isNotEmpty == true
                              ? call.title!
                              : context.l10n.untitled)
                        : (target?.title.trim().isNotEmpty == true
                              ? target!.title
                              : context.l10n.untitled),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (call.name != LocalChatToolName.createNote) ...[
                  const SizedBox(height: 14),
                  _PreviewSection(
                    label: context.l10n.toolCurrentContent,
                    child: current.isEmpty
                        ? const Text(
                            '—',
                            style: TextStyle(color: AppColors.muted),
                          )
                        : NoteDeltaPreview(note: target!, maxLines: 12),
                  ),
                ],
                const SizedBox(height: 14),
                _PreviewSection(
                  label: context.l10n.toolProposedContent,
                  child: Text(
                    call.content?.trim() ?? '',
                    style: const TextStyle(height: 1.55),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.line)),
            ),
            child: FilledButton(
              key: const Key('local-chat-confirm-tool-action'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(_confirmLabel(context, call.name)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewSection extends StatelessWidget {
  final String label;
  final Widget child;

  const _PreviewSection({required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.canvas,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    ),
  );
}

String _toolLabel(BuildContext context, LocalChatToolName name) =>
    switch (name) {
      LocalChatToolName.searchNotes => context.l10n.searchNotes,
      LocalChatToolName.createNote => context.l10n.toolCreateNote,
      LocalChatToolName.appendNote => context.l10n.toolAppendNote,
      LocalChatToolName.replaceNote => context.l10n.toolReplaceNote,
    };

String _confirmLabel(BuildContext context, LocalChatToolName name) =>
    switch (name) {
      LocalChatToolName.createNote => context.l10n.confirmCreateNote,
      LocalChatToolName.appendNote => context.l10n.confirmAppendNote,
      LocalChatToolName.replaceNote => context.l10n.confirmReplaceNote,
      LocalChatToolName.searchNotes => context.l10n.searchNotes,
    };
