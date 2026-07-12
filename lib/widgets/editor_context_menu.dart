import 'package:flutter/material.dart';

import '../app.dart';
import '../l10n/l10n.dart';

/// The block editor keeps this zero-width boundary inside block fields so
/// mobile keyboards can report backspace at the start of an otherwise empty
/// block. It must never become part of a user's copied or cut text.
const editorBlockBoundary = '\u200B';

const _supportedAppContextMenuActions = {
  ContextMenuButtonType.cut,
  ContextMenuButtonType.copy,
  ContextMenuButtonType.paste,
  ContextMenuButtonType.selectAll,
  ContextMenuButtonType.share,
};

/// FKNotes' app-wide context menu for editable and selectable text.
///
/// Filtering the framework-provided actions also prevents Android services
/// and third-party apps from injecting unrelated menu entries.
Widget buildAppEditableTextContextMenu(
  BuildContext context,
  EditableTextState editableTextState, {
  Future<void> Function()? onPaste,
}) {
  final items = editableTextState.contextMenuButtonItems
      .where((item) => _supportedAppContextMenuActions.contains(item.type))
      .toList(growable: false);
  return _buildAppTextSelectionToolbar(
    anchors: editableTextState.contextMenuAnchors,
    items: items,
    beforeAction: (type) {
      _excludeBlockBoundary(editableTextState);
      if (type != ContextMenuButtonType.paste || onPaste == null) return false;
      ContextMenuController.removeAny();
      onPaste();
      return true;
    },
  );
}

/// FKNotes' app-wide context menu for a multi-widget [SelectionArea].
Widget buildAppSelectableRegionContextMenu(
  BuildContext context,
  SelectableRegionState selectableRegionState,
) {
  final items = selectableRegionState.contextMenuButtonItems
      .where((item) => _supportedAppContextMenuActions.contains(item.type))
      .toList(growable: false);
  return _buildAppTextSelectionToolbar(
    anchors: selectableRegionState.contextMenuAnchors,
    items: items,
  );
}

Widget _buildAppTextSelectionToolbar({
  required TextSelectionToolbarAnchors anchors,
  required List<ContextMenuButtonItem> items,
  bool Function(ContextMenuButtonType type)? beforeAction,
}) {
  if (items.isEmpty) return const SizedBox.shrink();
  return TextSelectionToolbar(
    anchorAbove: anchors.primaryAnchor,
    anchorBelow: anchors.secondaryAnchor ?? anchors.primaryAnchor,
    toolbarBuilder: (context, child) => Material(
      color: AppColors.surface,
      elevation: 5,
      shadowColor: AppColors.ink.withValues(alpha: .12),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    ),
    children: [
      for (final item in items)
        _AppContextMenuButton(
          type: item.type,
          onPressed: item.onPressed == null
              ? null
              : () {
                  final handled = beforeAction?.call(item.type) ?? false;
                  if (!handled) item.onPressed!.call();
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

class _AppContextMenuButton extends StatelessWidget {
  final ContextMenuButtonType type;
  final VoidCallback? onPressed;

  const _AppContextMenuButton({required this.type, this.onPressed});

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
    label: Text(_label(context)),
  );

  String _label(BuildContext context) => switch (type) {
    ContextMenuButtonType.cut => context.l10n.cut,
    ContextMenuButtonType.copy => context.l10n.copy,
    ContextMenuButtonType.paste => context.l10n.paste,
    ContextMenuButtonType.selectAll => context.l10n.selectAll,
    ContextMenuButtonType.share => context.l10n.share,
    _ => '',
  };

  IconData get _icon => switch (type) {
    ContextMenuButtonType.cut => Icons.content_cut_rounded,
    ContextMenuButtonType.copy => Icons.content_copy_rounded,
    ContextMenuButtonType.paste => Icons.content_paste_rounded,
    ContextMenuButtonType.selectAll => Icons.select_all_rounded,
    ContextMenuButtonType.share => Icons.ios_share_rounded,
    _ => Icons.more_horiz_rounded,
  };
}
