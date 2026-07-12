import 'package:flutter/material.dart';

import '../app.dart';

/// The editor keeps this zero-width boundary inside block fields so mobile
/// keyboards can report backspace at the start of an otherwise empty block.
/// It must never become part of a user's copied or cut text.
const editorBlockBoundary = '\u200B';

Widget buildEditorContextMenu(
  BuildContext context,
  EditableTextState editableTextState, {
  Future<void> Function()? onPaste,
}) {
  const supported = {
    ContextMenuButtonType.cut,
    ContextMenuButtonType.copy,
    ContextMenuButtonType.paste,
    ContextMenuButtonType.selectAll,
  };
  final items = editableTextState.contextMenuButtonItems
      .where((item) => supported.contains(item.type))
      .toList(growable: false);
  if (items.isEmpty) return const SizedBox.shrink();

  final anchors = editableTextState.contextMenuAnchors;
  return TextSelectionToolbar(
    anchorAbove: anchors.primaryAnchor,
    anchorBelow: anchors.secondaryAnchor ?? anchors.primaryAnchor,
    toolbarBuilder: (context, child) => Material(
      color: AppColors.surface,
      elevation: 5,
      shadowColor: AppColors.ink.withValues(alpha: .12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    ),
    children: [
      for (final item in items)
        _EditorContextMenuButton(
          type: item.type,
          onPressed: item.onPressed == null
              ? null
              : () {
                  _excludeBlockBoundary(editableTextState);
                  if (item.type == ContextMenuButtonType.paste &&
                      onPaste != null) {
                    ContextMenuController.removeAny();
                    onPaste();
                    return;
                  }
                  item.onPressed!.call();
                },
        ),
    ],
  );
}

void _excludeBlockBoundary(EditableTextState editableTextState) {
  final controller = editableTextState.widget.controller;
  final value = controller.value;
  final selection = value.selection;
  if (!value.text.startsWith(editorBlockBoundary) || !selection.isValid) {
    return;
  }
  final base = selection.baseOffset < editorBlockBoundary.length
      ? editorBlockBoundary.length
      : selection.baseOffset;
  final extent = selection.extentOffset < editorBlockBoundary.length
      ? editorBlockBoundary.length
      : selection.extentOffset;
  if (base == selection.baseOffset && extent == selection.extentOffset) return;
  controller.selection = selection.copyWith(
    baseOffset: base,
    extentOffset: extent,
  );
}

class _EditorContextMenuButton extends StatelessWidget {
  final ContextMenuButtonType type;
  final VoidCallback? onPressed;

  const _EditorContextMenuButton({required this.type, this.onPressed});

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      foregroundColor: AppColors.ink,
      disabledForegroundColor: AppColors.muted,
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      shape: const RoundedRectangleBorder(),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    ),
    icon: Icon(_icon, size: 18),
    label: Text(_label),
  );

  String get _label => switch (type) {
    ContextMenuButtonType.cut => '剪切',
    ContextMenuButtonType.copy => '复制',
    ContextMenuButtonType.paste => '粘贴',
    ContextMenuButtonType.selectAll => '全选',
    _ => '',
  };

  IconData get _icon => switch (type) {
    ContextMenuButtonType.cut => Icons.content_cut_rounded,
    ContextMenuButtonType.copy => Icons.content_copy_rounded,
    ContextMenuButtonType.paste => Icons.content_paste_rounded,
    ContextMenuButtonType.selectAll => Icons.select_all_rounded,
    _ => Icons.more_horiz_rounded,
  };
}
