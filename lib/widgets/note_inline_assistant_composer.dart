import 'package:flutter/material.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import 'editor_context_menu.dart';

final class NoteInlineAssistantComposer extends StatelessWidget {
  const NoteInlineAssistantComposer({
    required this.controller,
    required this.focusNode,
    required this.loading,
    required this.generating,
    required this.hasResult,
    required this.replacesSelection,
    required this.error,
    required this.onSubmit,
    required this.onStop,
    required this.onRetry,
    required this.onUndo,
    required this.onContinue,
    required this.onClose,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool loading;
  final bool generating;
  final bool hasResult;
  final bool replacesSelection;
  final String? error;
  final ValueChanged<String> onSubmit;
  final VoidCallback onStop;
  final VoidCallback onRetry;
  final VoidCallback onUndo;
  final VoidCallback onContinue;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Material(
    key: const Key('quill-inline-assistant'),
    color: AppColors.canvas,
    child: SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.line)),
          boxShadow: [
            BoxShadow(
              color: Color(0x12202A35),
              blurRadius: 22,
              offset: Offset(0, -7),
            ),
          ],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _content(context),
        ),
      ),
    ),
  );

  Widget _content(BuildContext context) {
    if (loading || generating) {
      return _GenerationStatus(
        key: const ValueKey('generating'),
        label: loading
            ? context.l10n.inlineAssistantLoading
            : context.l10n.inlineAssistantWriting,
        onStop: onStop,
      );
    }
    if (error != null) {
      return _ResultStatus(
        key: const ValueKey('error'),
        icon: Icons.error_outline_rounded,
        iconColor: AppColors.warning,
        label: error!,
        primaryLabel: context.l10n.retry,
        primaryIcon: Icons.refresh_rounded,
        onPrimary: onRetry,
        secondaryLabel: context.l10n.close,
        onSecondary: onClose,
      );
    }
    if (hasResult) {
      return _ResultStatus(
        key: const ValueKey('complete'),
        icon: Icons.auto_awesome_rounded,
        iconColor: AppColors.accent,
        label: context.l10n.inlineAssistantWritten,
        primaryLabel: context.l10n.inlineAssistantContinue,
        primaryIcon: Icons.arrow_forward_rounded,
        onPrimary: onContinue,
        secondaryLabel: context.l10n.undo,
        onSecondary: onUndo,
      );
    }
    return _PromptComposer(
      key: const ValueKey('prompt'),
      controller: controller,
      focusNode: focusNode,
      replacesSelection: replacesSelection,
      onSubmit: onSubmit,
      onClose: onClose,
    );
  }
}

final class _PromptComposer extends StatelessWidget {
  const _PromptComposer({
    required this.controller,
    required this.focusNode,
    required this.replacesSelection,
    required this.onSubmit,
    required this.onClose,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool replacesSelection;
  final ValueChanged<String> onSubmit;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: AppColors.accent,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.writeWithAi,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  replacesSelection
                      ? context.l10n.inlineAssistantReplaceSelection
                      : context.l10n.inlineAssistantInsertAtCursor,
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('close-inline-assistant'),
            tooltip: context.l10n.close,
            onPressed: onClose,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 19),
          ),
        ],
      ),
      const SizedBox(height: 10),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _SuggestionChip(
              label: context.l10n.inlineAssistantContinueWriting,
              onPressed: onSubmit,
            ),
            const SizedBox(width: 7),
            _SuggestionChip(
              label: context.l10n.inlineAssistantMakeList,
              onPressed: onSubmit,
            ),
            const SizedBox(width: 7),
            _SuggestionChip(
              label: context.l10n.inlineAssistantExpandIdea,
              onPressed: onSubmit,
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.line),
            boxShadow: AppShadows.low,
          ),
          padding: const EdgeInsets.fromLTRB(14, 3, 6, 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  key: const Key('quill-inline-assistant-input'),
                  controller: controller,
                  focusNode: focusNode,
                  contextMenuBuilder: buildAppEditableTextContextMenu,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 2000,
                  buildCounter:
                      (
                        _, {
                        required currentLength,
                        required isFocused,
                        maxLength,
                      }) => null,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: context.l10n.inlineAssistantHint,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                key: const Key('submit-inline-assistant'),
                tooltip: context.l10n.startGenerating,
                onPressed: value.text.trim().isEmpty
                    ? null
                    : () => onSubmit(value.text.trim()),
                style: IconButton.styleFrom(
                  fixedSize: const Size.square(42),
                  backgroundColor: AppColors.accent,
                  disabledBackgroundColor: AppColors.surfaceMuted,
                ),
                icon: const Icon(Icons.arrow_upward_rounded, size: 20),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

final class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onPressed});

  final String label;
  final ValueChanged<String> onPressed;

  @override
  Widget build(BuildContext context) => ActionChip(
    label: Text(label),
    avatar: const Icon(Icons.north_east_rounded, size: 14),
    onPressed: () => onPressed(label),
    backgroundColor: AppColors.surface,
    side: const BorderSide(color: AppColors.line),
    labelStyle: const TextStyle(
      color: AppColors.muted,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    ),
    visualDensity: VisualDensity.compact,
  );
}

final class _GenerationStatus extends StatelessWidget {
  const _GenerationStatus({
    required this.label,
    required this.onStop,
    super.key,
  });

  final String label;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: AppColors.line),
      boxShadow: AppShadows.low,
    ),
    child: Row(
      children: [
        const SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        TextButton.icon(
          key: const Key('stop-inline-assistant'),
          onPressed: onStop,
          icon: const Icon(Icons.stop_rounded, size: 18),
          label: Text(context.l10n.stopGenerating),
        ),
      ],
    ),
  );
}

final class _ResultStatus extends StatelessWidget {
  const _ResultStatus({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
    super.key,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(15, 12, 10, 10),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: AppColors.line),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: onSecondary, child: Text(secondaryLabel)),
            const SizedBox(width: 4),
            FilledButton.icon(
              key: const Key('continue-inline-assistant'),
              onPressed: onPrimary,
              icon: Icon(primaryIcon, size: 17),
              label: Text(primaryLabel),
            ),
          ],
        ),
      ],
    ),
  );
}
