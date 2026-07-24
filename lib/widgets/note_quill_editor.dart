import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../app.dart';
import '../editor/note_editor_controller.dart';
import '../l10n/l10n.dart';
import '../models/note.dart';
import '../models/note_document.dart';
import '../services/note_audio_playback_service.dart';
import 'app_popup_menu.dart';
import 'note_attachment_title_sheet.dart';
import 'note_external_image_drop.dart';

typedef NoteAssetImageProvider = ImageProvider? Function(NoteAsset asset);
typedef NoteAssetPathResolver = String? Function(NoteAsset asset);
typedef NoteImageAssetAction = Future<void> Function(NoteAsset asset);

quill.DefaultStyles _paperQuillStyles() {
  const codeTextStyle = TextStyle(
    color: AppColors.ink,
    fontFamily: 'monospace',
    fontFamilyFallback: ['Noto Sans Mono CJK SC', 'sans-serif'],
    fontSize: 14,
    height: 1.5,
    letterSpacing: .05,
  );
  return quill.DefaultStyles(
    code: quill.DefaultTextBlockStyle(
      codeTextStyle,
      quill.HorizontalSpacing.zero,
      const quill.VerticalSpacing(10, 10),
      const quill.VerticalSpacing(1, 1),
      BoxDecoration(
        color: AppColors.paperSecondary,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
    ),
    inlineCode: quill.InlineCodeStyle(
      style: codeTextStyle.copyWith(
        color: AppColors.mechanicalBlue,
        fontSize: 13.5,
        height: 1.35,
      ),
      backgroundColor: AppColors.accentSoft,
      radius: const Radius.circular(3),
    ),
    link: const TextStyle(
      color: AppColors.mechanicalBlue,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.mechanicalBlue,
    ),
  );
}

final class NoteQuillEditor extends StatefulWidget {
  const NoteQuillEditor({
    required this.controller,
    this.focusNode,
    this.scrollController,
    this.resolveImage,
    this.resolveAssetPath,
    this.audioPlayback,
    this.onOpenAsset,
    this.onCopyImage,
    this.onEditImage,
    this.onViewImageOriginal,
    this.onShowImageDetails,
    this.onDropImages,
    this.readOnly = false,
    this.placeholder = '开始记录…',
    super.key,
  });

  final NoteEditorController controller;
  final FocusNode? focusNode;
  final ScrollController? scrollController;
  final NoteAssetImageProvider? resolveImage;
  final NoteAssetPathResolver? resolveAssetPath;
  final NoteAudioPlaybackDriver? audioPlayback;
  final ValueChanged<NoteAsset>? onOpenAsset;
  final NoteImageAssetAction? onCopyImage;
  final NoteImageAssetAction? onEditImage;
  final NoteImageAssetAction? onViewImageOriginal;
  final NoteImageAssetAction? onShowImageDetails;
  final NoteExternalImageDropHandler? onDropImages;
  final bool readOnly;
  final String placeholder;

  @override
  State<NoteQuillEditor> createState() => _NoteQuillEditorState();
}

/// A non-interactive projection that uses the same Quill and embed layout as
/// the editor. It is intended for paper-card previews where document order and
/// block positioning must remain faithful without creating editable fields.
final class NoteRichDocumentPreview extends StatefulWidget {
  const NoteRichDocumentPreview({
    required this.note,
    this.resolveImage,
    this.resolveAssetPath,
    super.key,
  });

  final Note note;
  final NoteAssetImageProvider? resolveImage;
  final NoteAssetPathResolver? resolveAssetPath;

  @override
  State<NoteRichDocumentPreview> createState() =>
      _NoteRichDocumentPreviewState();
}

final class _NoteRichDocumentPreviewState
    extends State<NoteRichDocumentPreview> {
  late NoteEditorController _controller;

  @override
  void initState() {
    super.initState();
    _controller = _createController();
  }

  @override
  void didUpdateWidget(covariant NoteRichDocumentPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note.revision == widget.note.revision &&
        oldWidget.note.document.toJsonString() ==
            widget.note.document.toJsonString() &&
        oldWidget.note.assets == widget.note.assets) {
      return;
    }
    final previous = _controller;
    _controller = _createController();
    previous.dispose();
  }

  NoteEditorController _createController() {
    final controller = NoteEditorController(
      document: widget.note.document,
      assets: widget.note.assets,
    );
    controller.quillController.readOnly = true;
    return controller;
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: quill.QuillEditor.basic(
      controller: _controller.quillController,
      config: quill.QuillEditorConfig(
        customStyles: _paperQuillStyles(),
        scrollable: false,
        autoFocus: false,
        showCursor: false,
        enableInteractiveSelection: false,
        enableSelectionToolbar: false,
        padding: EdgeInsets.zero,
        embedBuilders: [
          _NoteAssetEmbedBuilder(
            session: _controller,
            resolveImage: widget.resolveImage,
            resolveAssetPath: widget.resolveAssetPath,
            audioPlayback: null,
            onOpenAsset: null,
            selectedAssetId: null,
            onAssetInteraction: _ignoreInteraction,
            onSelectAsset: _ignoreAttachment,
            onToggleAssetSelection: _ignoreAttachment,
            onAssetDragStarted: _ignoreDragStart,
            onAssetDragUpdate: _ignoreOffset,
            onAssetDragEnded: _ignoreInteraction,
          ),
          const _NoteDividerEmbedBuilder(
            onInteraction: _ignoreInteraction,
            onToggleActions: _ignoreOffsetIndex,
          ),
          const _NoteTableEmbedBuilder(
            onInteraction: _ignoreInteraction,
            onToggleActions: _ignoreOffsetIndex,
          ),
        ],
      ),
    ),
  );

  static void _ignoreInteraction() {}

  static void _ignoreAttachment(NoteAttachmentId _) {}

  static void _ignoreDragStart(_NoteAssetDragData _) {}

  static void _ignoreOffset(Offset _) {}

  static void _ignoreOffsetIndex(int _) {}

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

final class _NoteQuillEditorState extends State<NoteQuillEditor> {
  final _quillEditorKey = GlobalKey<quill.QuillEditorState>();
  final _editorStackKey = GlobalKey();
  late final ScrollController _fallbackScrollController;
  NoteAttachmentId? _activeAssetId;
  ({NoteEmbedKind kind, int offset})? _activeBlock;
  _NoteAssetDragData? _draggingAsset;
  int? _dropOffset;
  double? _dropIndicatorY;
  var _externalImageDragActive = false;

  ScrollController get _effectiveScrollController =>
      widget.scrollController ?? _fallbackScrollController;

  @override
  void initState() {
    super.initState();
    _fallbackScrollController = ScrollController();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final focusNode = widget.focusNode;
    final scrollController = _effectiveScrollController;
    final resolveImage = widget.resolveImage;
    final resolveAssetPath = widget.resolveAssetPath;
    final audioPlayback = widget.audioPlayback;
    final onOpenAsset = widget.onOpenAsset;
    final onCopyImage = widget.onCopyImage;
    final onEditImage = widget.onEditImage;
    final onViewImageOriginal = widget.onViewImageOriginal;
    final onShowImageDetails = widget.onShowImageDetails;
    final readOnly = widget.readOnly;
    final placeholder = widget.placeholder;
    controller.quillController.readOnly = readOnly;
    void dismissEditorFocus() {
      final editorFocus = focusNode;
      if (editorFocus != null) {
        editorFocus.unfocus(disposition: UnfocusDisposition.scope);
      } else {
        FocusManager.instance.primaryFocus?.unfocus();
      }
    }

    bool handleAssetTap(
      Offset globalPosition,
      TextPosition Function(Offset offset) getPosition, {
      required bool toggleImageSelection,
    }) {
      final position = getPosition(globalPosition);
      if (!controller.isBlockEmbedAtOffset(position.offset)) {
        if (_activeAssetId != null || _activeBlock != null) {
          setState(() {
            _activeAssetId = null;
            _activeBlock = null;
          });
        }
        return false;
      }
      dismissEditorFocus();
      if (toggleImageSelection) {
        final asset = controller.attachmentAtOffset(position.offset);
        if (asset?.kind == NoteAssetKind.image) {
          if (readOnly) {
            if (asset != null) onOpenAsset?.call(asset);
          } else {
            setState(() {
              _activeBlock = null;
              _activeAssetId = _activeAssetId == asset!.id ? null : asset.id;
            });
          }
        }
      }
      return true;
    }

    final activeAsset = _activeAssetId == null
        ? null
        : controller.asset(_activeAssetId!);
    final activeImage = activeAsset?.kind == NoteAssetKind.image
        ? activeAsset
        : null;
    final activeBlock = _activeBlock;
    final showsContextActions = activeImage != null || activeBlock != null;
    final editor = quill.QuillEditor.basic(
      key: _quillEditorKey,
      controller: controller.quillController,
      focusNode: focusNode,
      scrollController: scrollController,
      config: quill.QuillEditorConfig(
        customStyles: _paperQuillStyles(),
        expands: true,
        scrollable: true,
        readOnlyMouseCursor: SystemMouseCursors.text,
        padding: EdgeInsets.fromLTRB(
          24,
          18,
          24,
          showsContextActions ? 104 : 48,
        ),
        placeholder: placeholder,
        enableInteractiveSelection: true,
        enableSelectionToolbar: true,
        textInputAction: TextInputAction.newline,
        onTapDown: (details, getPosition) => handleAssetTap(
          details.globalPosition,
          getPosition,
          toggleImageSelection: false,
        ),
        onTapUp: (details, getPosition) => handleAssetTap(
          details.globalPosition,
          getPosition,
          toggleImageSelection: true,
        ),
        embedBuilders: [
          _NoteAssetEmbedBuilder(
            session: controller,
            resolveImage: resolveImage,
            resolveAssetPath: resolveAssetPath,
            audioPlayback: audioPlayback,
            onOpenAsset: onOpenAsset,
            selectedAssetId: _activeAssetId,
            onAssetInteraction: dismissEditorFocus,
            onSelectAsset: (id) {
              if (_activeAssetId == id && _activeBlock == null) return;
              setState(() {
                _activeBlock = null;
                _activeAssetId = id;
              });
            },
            onToggleAssetSelection: (id) => setState(() {
              _activeBlock = null;
              _activeAssetId = _activeAssetId == id ? null : id;
            }),
            onAssetDragStarted: _startAssetDrag,
            onAssetDragUpdate: _updateDropLocation,
            onAssetDragEnded: _finishAssetDrag,
          ),
          _NoteDividerEmbedBuilder(
            onInteraction: dismissEditorFocus,
            onToggleActions: (offset) =>
                _toggleBlockActions(NoteEmbedKind.divider, offset),
          ),
          _NoteTableEmbedBuilder(
            onInteraction: dismissEditorFocus,
            onToggleActions: (offset) =>
                _toggleBlockActions(NoteEmbedKind.table, offset),
          ),
        ],
      ),
    );
    final editorDropTarget = DragTarget<_NoteAssetDragData>(
      onWillAcceptWithDetails: (_) => !readOnly,
      onLeave: (_) => _clearDropLocation(),
      onAcceptWithDetails: (details) {
        final targetOffset = _dropOffset;
        if (targetOffset != null) {
          controller.moveAssetEmbed(
            attachmentId: details.data.attachmentId,
            sourceOffset: details.data.sourceOffset,
            targetOffset: targetOffset,
          );
        }
        _finishAssetDrag();
      },
      builder: (context, _, _) => Stack(
        key: _editorStackKey,
        fit: StackFit.expand,
        children: [
          editor,
          if ((_draggingAsset != null || _externalImageDragActive) &&
              _dropIndicatorY != null)
            Positioned(
              key: const Key('note-asset-drop-indicator'),
              top: _dropIndicatorY! - 2,
              left: 24,
              right: 24,
              child: const IgnorePointer(child: _AssetDropIndicator()),
            ),
          if (_externalImageDragActive)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const Key('note-external-image-drop-overlay'),
                  decoration: BoxDecoration(
                    color: AppColors.accentSoft.withValues(alpha: .16),
                    border: Border.all(
                      color: AppColors.mechanicalBlue.withValues(alpha: .62),
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: const BoxDecoration(
                        color: AppColors.paperSecondary,
                        border: Border(
                          left: BorderSide(color: AppColors.mechanicalBlue),
                          right: BorderSide(color: AppColors.line),
                          top: BorderSide(color: AppColors.line),
                          bottom: BorderSide(color: AppColors.line),
                        ),
                      ),
                      child: Text(
                        context.l10n.releaseToInsertImages,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: AppColors.mechanicalBlue,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (!readOnly &&
              activeImage != null &&
              activeImage.kind == NoteAssetKind.image)
            Positioned(
              left: 24,
              right: 24,
              bottom: 12,
              child: _ImageActionBar(
                key: ValueKey('note-image-actions-${activeImage.id.value}'),
                asset: activeImage,
                onViewOriginal: onViewImageOriginal == null
                    ? null
                    : () => onViewImageOriginal(activeImage),
                onCopy: onCopyImage == null
                    ? null
                    : () => onCopyImage(activeImage),
                onEdit: onEditImage == null
                    ? null
                    : () => onEditImage(activeImage),
                onShowDetails: onShowImageDetails == null
                    ? null
                    : () => onShowImageDetails(activeImage),
                onRemove: () {
                  controller.removeAsset(activeImage.id);
                  setState(() => _activeAssetId = null);
                },
              ),
            ),
          if (!readOnly && activeBlock != null)
            Positioned(
              left: 24,
              right: 24,
              bottom: 12,
              child: _BlockActionBar(
                key: ValueKey(
                  'note-block-actions-${activeBlock.kind.name}-'
                  '${activeBlock.offset}',
                ),
                kind: activeBlock.kind,
                onRemove: () {
                  controller.removeEmbedAt(activeBlock.offset);
                  setState(() => _activeBlock = null);
                },
              ),
            ),
        ],
      ),
    );
    final onDropImages = widget.onDropImages;
    if (readOnly || onDropImages == null) return editorDropTarget;
    return NoteExternalImageDropRegion(
      enabled: !readOnly,
      captureDocumentOffset: _captureExternalDropOffset,
      onDropImages: onDropImages,
      onDropActiveChanged: _setExternalImageDragActive,
      child: editorDropTarget,
    );
  }

  void _toggleBlockActions(NoteEmbedKind kind, int offset) {
    setState(() {
      _activeAssetId = null;
      final active = _activeBlock;
      _activeBlock = active?.kind == kind && active?.offset == offset
          ? null
          : (kind: kind, offset: offset);
    });
  }

  void _startAssetDrag(_NoteAssetDragData data) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _activeAssetId = null;
      _activeBlock = null;
      _draggingAsset = data;
      _dropOffset = null;
      _dropIndicatorY = null;
    });
  }

  void _finishAssetDrag() {
    if (!mounted ||
        (_draggingAsset == null &&
            _dropOffset == null &&
            _dropIndicatorY == null)) {
      return;
    }
    setState(() {
      _draggingAsset = null;
      _dropOffset = null;
      _dropIndicatorY = null;
    });
  }

  void _clearDropLocation() {
    if (!mounted || (_dropOffset == null && _dropIndicatorY == null)) return;
    setState(() {
      _dropOffset = null;
      _dropIndicatorY = null;
    });
  }

  int? _captureExternalDropOffset(Offset globalOffset) {
    final stackBox =
        _editorStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null ||
        !stackBox.paintBounds.contains(stackBox.globalToLocal(globalOffset))) {
      _clearDropLocation();
      return null;
    }
    _updateDropLocation(globalOffset);
    final dropOffset = _dropOffset;
    if (dropOffset != null) return dropOffset;
    final selection = widget.controller.quillController.selection;
    final fallbackOffset = selection.extentOffset < 0
        ? 0
        : selection.extentOffset;
    return widget.controller.blockDropOffsetFor(
      fallbackOffset,
      afterLine: true,
    );
  }

  void _setExternalImageDragActive(bool active) {
    if (!mounted || _externalImageDragActive == active) return;
    setState(() {
      _externalImageDragActive = active;
      if (!active && _draggingAsset == null) {
        _dropOffset = null;
        _dropIndicatorY = null;
      }
    });
  }

  void _updateDropLocation(Offset globalOffset) {
    final editorState = _quillEditorKey.currentState;
    final rawEditorState = editorState?.editableTextKey.currentState;
    final stackBox =
        _editorStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (rawEditorState == null || stackBox == null || !mounted) return;
    final stackLocal = stackBox.globalToLocal(globalOffset);
    if (!stackBox.paintBounds.contains(stackLocal)) {
      _clearDropLocation();
      return;
    }
    final renderEditor = rawEditorState.renderEditor;
    final position = renderEditor.getPositionForOffset(globalOffset);
    final caret = renderEditor.getLocalRectForCaret(position);
    final localDrag = renderEditor.globalToLocal(globalOffset);
    final afterLine = localDrag.dy >= caret.center.dy;
    final targetOffset = widget.controller.blockDropOffsetFor(
      position.offset,
      afterLine: afterLine,
    );
    final indicatorGlobal = renderEditor.localToGlobal(
      Offset(caret.left, afterLine ? caret.bottom : caret.top),
    );
    final indicatorY = stackBox
        .globalToLocal(indicatorGlobal)
        .dy
        .clamp(6.0, stackBox.size.height - 6.0);
    _autoScrollForDrag(globalOffset, stackBox);
    if (_dropOffset == targetOffset &&
        _dropIndicatorY != null &&
        (_dropIndicatorY! - indicatorY).abs() < .5) {
      return;
    }
    setState(() {
      _dropOffset = targetOffset;
      _dropIndicatorY = indicatorY;
    });
  }

  void _autoScrollForDrag(Offset globalOffset, RenderBox stackBox) {
    final scrollController = _effectiveScrollController;
    if (!scrollController.hasClients) return;
    final local = stackBox.globalToLocal(globalOffset);
    const edge = 72.0;
    final delta = local.dy < edge
        ? -18.0
        : local.dy > stackBox.size.height - edge
        ? 18.0
        : 0.0;
    if (delta == 0) return;
    final position = scrollController.position;
    scrollController.jumpTo(
      (scrollController.offset + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  @override
  void dispose() {
    _fallbackScrollController.dispose();
    super.dispose();
  }
}

final class NoteQuillToolbar extends StatelessWidget {
  const NoteQuillToolbar({
    required this.controller,
    this.onOpenAssistant,
    this.onInsertImage,
    this.onRecordAudio,
    this.onDone,
    this.assistantTooltip = 'AI 创作',
    this.imageTooltip = '插入图片',
    this.recordTooltip = '录音',
    this.dividerTooltip = '插入分隔线',
    this.doneLabel,
    super.key,
  });

  final NoteEditorController controller;
  final VoidCallback? onOpenAssistant;
  final VoidCallback? onInsertImage;
  final VoidCallback? onRecordAudio;
  final VoidCallback? onDone;
  final String assistantTooltip;
  final String imageTooltip;
  final String recordTooltip;
  final String dividerTooltip;
  final String? doneLabel;

  @override
  Widget build(BuildContext context) {
    final quillController = controller.quillController;
    const baseOptions = quill.QuillToolbarBaseButtonOptions(
      iconTheme: quill.QuillIconTheme(
        iconButtonUnselectedData: quill.IconButtonData(
          color: AppColors.muted,
          iconSize: 21,
          padding: EdgeInsets.all(10),
          constraints: BoxConstraints(minWidth: 44, minHeight: 44),
        ),
        iconButtonSelectedData: quill.IconButtonData(
          color: AppColors.accent,
          iconSize: 21,
          padding: EdgeInsets.all(10),
          constraints: BoxConstraints(minWidth: 44, minHeight: 44),
          style: ButtonStyle(
            backgroundColor: WidgetStatePropertyAll(AppColors.accentSoft),
          ),
        ),
      ),
    );

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.paperSecondary,
        border: Border(top: BorderSide(color: AppColors.line)),
        boxShadow: [
          BoxShadow(
            color: Color(0x10263847),
            blurRadius: 12,
            offset: Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  key: const Key('quill-toolbar-scroll-view'),
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    key: const Key('quill-toolbar-actions'),
                    children: [
                      if (onOpenAssistant != null)
                        _NoteToolbarActionButton(
                          key: const Key('quill-open-inline-assistant'),
                          tooltip: assistantTooltip,
                          onPressed: onOpenAssistant!,
                          icon: Icons.auto_awesome_rounded,
                        ),
                      if (onInsertImage != null)
                        _NoteToolbarActionButton(
                          key: const Key('quill-insert-image'),
                          tooltip: imageTooltip,
                          onPressed: onInsertImage!,
                          icon: Icons.image_outlined,
                        ),
                      if (onRecordAudio != null)
                        _NoteToolbarActionButton(
                          key: const Key('quill-record-audio'),
                          tooltip: recordTooltip,
                          onPressed: onRecordAudio!,
                          icon: Icons.graphic_eq_rounded,
                        ),
                      quill.QuillToolbarHistoryButton(
                        key: const Key('quill-toolbar-undo'),
                        controller: quillController,
                        isUndo: true,
                        baseOptions: baseOptions,
                      ),
                      quill.QuillToolbarHistoryButton(
                        key: const Key('quill-toolbar-redo'),
                        controller: quillController,
                        isUndo: false,
                        baseOptions: baseOptions,
                      ),
                      quill.QuillToolbarToggleStyleButton(
                        key: const Key('quill-toolbar-bold'),
                        controller: quillController,
                        attribute: quill.Attribute.bold,
                        baseOptions: baseOptions,
                      ),
                      quill.QuillToolbarToggleCheckListButton(
                        key: const Key('quill-toolbar-checklist'),
                        controller: quillController,
                        baseOptions: baseOptions,
                      ),
                      quill.QuillToolbarToggleStyleButton(
                        key: const Key('quill-toolbar-bullets'),
                        controller: quillController,
                        attribute: quill.Attribute.ul,
                        baseOptions: baseOptions,
                      ),
                      quill.QuillToolbarToggleStyleButton(
                        key: const Key('quill-toolbar-numbered-list'),
                        controller: quillController,
                        attribute: quill.Attribute.ol,
                        baseOptions: baseOptions,
                      ),
                      quill.QuillToolbarToggleStyleButton(
                        key: const Key('quill-toolbar-quote'),
                        controller: quillController,
                        attribute: quill.Attribute.blockQuote,
                        baseOptions: baseOptions,
                      ),
                      quill.QuillToolbarToggleStyleButton(
                        key: const Key('quill-toolbar-italic'),
                        controller: quillController,
                        attribute: quill.Attribute.italic,
                        baseOptions: baseOptions,
                      ),
                      quill.QuillToolbarToggleStyleButton(
                        key: const Key('quill-toolbar-underline'),
                        controller: quillController,
                        attribute: quill.Attribute.underline,
                        baseOptions: baseOptions,
                      ),
                      quill.QuillToolbarSelectHeaderStyleDropdownButton(
                        key: const Key('quill-toolbar-heading'),
                        controller: quillController,
                        baseOptions: baseOptions,
                      ),
                      quill.QuillToolbarLinkStyleButton(
                        key: const Key('quill-toolbar-link'),
                        controller: quillController,
                        baseOptions: baseOptions,
                      ),
                      _NoteToolbarActionButton(
                        key: const Key('quill-toolbar-divider'),
                        tooltip: dividerTooltip,
                        onPressed: controller.insertDivider,
                        icon: Icons.horizontal_rule_rounded,
                      ),
                      quill.QuillToolbarClearFormatButton(
                        key: const Key('quill-toolbar-clear-format'),
                        controller: quillController,
                        baseOptions: baseOptions,
                      ),
                    ],
                  ),
                ),
              ),
              if (doneLabel case final label?)
                _NoteToolbarDoneButton(label: label, onPressed: onDone),
            ],
          ),
        ),
      ),
    );
  }
}

final class _NoteToolbarDoneButton extends StatelessWidget {
  const _NoteToolbarDoneButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox(
        height: 28,
        child: VerticalDivider(width: 9, thickness: 1, color: AppColors.line),
      ),
      SizedBox(
        height: 44,
        child: TextButton(
          key: const Key('quill-toolbar-done'),
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.mechanicalBlue,
            disabledForegroundColor: AppColors.muted,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 44),
            shape: const RoundedRectangleBorder(),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    ],
  );
}

final class _NoteToolbarActionButton extends StatelessWidget {
  const _NoteToolbarActionButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    super.key,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    color: AppColors.muted,
    iconSize: 21,
    padding: const EdgeInsets.all(10),
    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    icon: Icon(icon),
  );
}

final class _NoteAssetDragData {
  const _NoteAssetDragData({
    required this.attachmentId,
    required this.sourceOffset,
  });

  final NoteAttachmentId attachmentId;
  final int sourceOffset;
}

final class _NoteAssetEmbedBuilder extends quill.EmbedBuilder {
  const _NoteAssetEmbedBuilder({
    required this.session,
    required this.resolveImage,
    required this.resolveAssetPath,
    required this.audioPlayback,
    required this.onOpenAsset,
    required this.selectedAssetId,
    required this.onAssetInteraction,
    required this.onSelectAsset,
    required this.onToggleAssetSelection,
    required this.onAssetDragStarted,
    required this.onAssetDragUpdate,
    required this.onAssetDragEnded,
  });

  final NoteEditorController session;
  final NoteAssetImageProvider? resolveImage;
  final NoteAssetPathResolver? resolveAssetPath;
  final NoteAudioPlaybackDriver? audioPlayback;
  final ValueChanged<NoteAsset>? onOpenAsset;
  final NoteAttachmentId? selectedAssetId;
  final VoidCallback onAssetInteraction;
  final ValueChanged<NoteAttachmentId> onSelectAsset;
  final ValueChanged<NoteAttachmentId> onToggleAssetSelection;
  final ValueChanged<_NoteAssetDragData> onAssetDragStarted;
  final ValueChanged<Offset> onAssetDragUpdate;
  final VoidCallback onAssetDragEnded;

  @override
  String get key => NoteEmbed.attachmentType;

  @override
  String toPlainText(quill.Embed node) {
    final embed = NoteEmbed.parse(node.value.toJson());
    final asset = session.asset(embed.attachmentId!);
    return asset == null ? '【附件】' : '【${asset.displayTitle}】';
  }

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final embed = NoteEmbed.parse(embedContext.node.value.toJson());
    final asset = session.asset(embed.attachmentId!);
    if (asset == null) {
      return const _MissingAssetCard();
    }
    final imageProvider = asset.kind == NoteAssetKind.image
        ? resolveImage?.call(asset)
        : null;
    final Widget block;
    if (asset.kind == NoteAssetKind.image) {
      block = _ImageAssetBlock(
        key: ValueKey('note-asset-${asset.id.value}'),
        asset: asset,
        provider: imageProvider,
        readOnly: embedContext.readOnly,
        selected: selectedAssetId == asset.id,
        onInteraction: onAssetInteraction,
        onToggleSelection: () => onToggleAssetSelection(asset.id),
        onOpen: onOpenAsset == null ? null : () => onOpenAsset!(asset),
      );
    } else if (asset.kind == NoteAssetKind.audio) {
      block = _AudioAssetBlock(
        key: ValueKey('note-asset-${asset.id.value}'),
        asset: asset,
        filePath: resolveAssetPath?.call(asset),
        playback: audioPlayback,
        readOnly: embedContext.readOnly,
        selected: selectedAssetId == asset.id,
        onInteraction: onAssetInteraction,
        onSelect: () => onSelectAsset(asset.id),
        onToggleSelection: () => onToggleAssetSelection(asset.id),
        onRename: (displayName) =>
            session.updateAsset(asset.copyWith(displayName: displayName)),
        onRemove: () {
          if (audioPlayback?.activeAssetId == asset.id.value) {
            unawaited(audioPlayback?.stop());
          }
          session.removeEmbedAt(embedContext.node.documentOffset);
        },
      );
    } else {
      return _FileAssetBlock(
        key: ValueKey('note-asset-${asset.id.value}'),
        asset: asset,
        readOnly: embedContext.readOnly,
        selected: selectedAssetId == asset.id,
        onInteraction: () {
          onAssetInteraction();
          onToggleAssetSelection(asset.id);
        },
        onOpen: onOpenAsset == null ? null : () => onOpenAsset!(asset),
        onRemove: () => session.removeEmbedAt(embedContext.node.documentOffset),
      );
    }

    if (embedContext.readOnly) return block;
    return _MovableNoteAsset(
      key: ValueKey('move-note-asset-${asset.id.value}'),
      asset: asset,
      imageProvider: imageProvider,
      data: _NoteAssetDragData(
        attachmentId: asset.id,
        sourceOffset: embedContext.node.documentOffset,
      ),
      onDragStarted: onAssetDragStarted,
      onDragUpdate: onAssetDragUpdate,
      onDragEnded: onAssetDragEnded,
      child: block,
    );
  }
}

final class _MovableNoteAsset extends StatelessWidget {
  const _MovableNoteAsset({
    required this.asset,
    required this.imageProvider,
    required this.data,
    required this.onDragStarted,
    required this.onDragUpdate,
    required this.onDragEnded,
    required this.child,
    super.key,
  });

  final NoteAsset asset;
  final ImageProvider? imageProvider;
  final _NoteAssetDragData data;
  final ValueChanged<_NoteAssetDragData> onDragStarted;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnded;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    label: asset.displayTitle,
    hint: context.l10n.moveAttachmentHint,
    child: LongPressDraggable<_NoteAssetDragData>(
      data: data,
      delay: const Duration(milliseconds: 360),
      hapticFeedbackOnStart: true,
      rootOverlay: true,
      onDragStarted: () => onDragStarted(data),
      onDragUpdate: (details) => onDragUpdate(details.globalPosition),
      onDragEnd: (_) => onDragEnded(),
      feedback: _AssetDragFeedback(
        asset: asset,
        imageProvider: imageProvider,
        width: math.min(MediaQuery.sizeOf(context).width - 48, 320),
      ),
      childWhenDragging: Opacity(opacity: .26, child: child),
      child: child,
    ),
  );
}

final class _AssetDragFeedback extends StatelessWidget {
  const _AssetDragFeedback({
    required this.asset,
    required this.imageProvider,
    required this.width,
  });

  final NoteAsset asset;
  final ImageProvider? imageProvider;
  final double width;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: Container(
      width: width,
      constraints: const BoxConstraints(maxHeight: 190),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: AppColors.accent, width: 1.5),
        boxShadow: AppShadows.floating,
      ),
      child: asset.kind == NoteAssetKind.image
          ? imageProvider == null
                ? _AssetFallback(asset: asset, minHeight: 130)
                : Image(
                    image: imageProvider!,
                    height: 170,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        _AssetFallback(asset: asset, minHeight: 130),
                  )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              child: Row(
                children: [
                  const Icon(
                    Icons.graphic_eq_rounded,
                    color: AppColors.accent,
                    size: 27,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      asset.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    ),
  );
}

final class _AssetDropIndicator extends StatelessWidget {
  const _AssetDropIndicator();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.accent,
          shape: BoxShape.circle,
        ),
        child: SizedBox.square(dimension: 8),
      ),
      Expanded(
        child: Container(
          height: 3,
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
      const DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.accent,
          shape: BoxShape.circle,
        ),
        child: SizedBox.square(dimension: 8),
      ),
    ],
  );
}

enum _AudioAssetAction { rename, remove }

final class _AssetSelectionFrame extends StatelessWidget {
  const _AssetSelectionFrame({
    required this.asset,
    required this.selected,
    required this.borderRadius,
    required this.child,
  });

  final NoteAsset asset;
  final bool selected;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!selected) return child;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              key: ValueKey('note-asset-selection-${asset.id.value}'),
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                border: Border.all(color: AppColors.accent, width: 2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

final class _AudioAssetBlock extends StatelessWidget {
  const _AudioAssetBlock({
    required this.asset,
    required this.filePath,
    required this.playback,
    required this.readOnly,
    required this.selected,
    required this.onInteraction,
    required this.onSelect,
    required this.onToggleSelection,
    required this.onRename,
    required this.onRemove,
    super.key,
  });

  final NoteAsset asset;
  final String? filePath;
  final NoteAudioPlaybackDriver? playback;
  final bool readOnly;
  final bool selected;
  final VoidCallback onInteraction;
  final VoidCallback onSelect;
  final VoidCallback onToggleSelection;
  final ValueChanged<String?> onRename;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final driver = playback;
    final content = (driver == null)
        ? _buildCard(context, null)
        : ListenableBuilder(
            listenable: driver,
            builder: (context, _) => _buildCard(context, driver),
          );
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => onInteraction(),
      child: GestureDetector(
        key: ValueKey('note-audio-selection-target-${asset.id.value}'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          onInteraction();
          onToggleSelection();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: content,
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context, NoteAudioPlaybackDriver? driver) {
    final active = driver?.activeAssetId == asset.id.value;
    final status = active ? driver!.status : NoteAudioPlaybackStatus.idle;
    final loading = status == NoteAudioPlaybackStatus.loading;
    final playing = status == NoteAudioPlaybackStatus.playing;
    final failed = status == NoteAudioPlaybackStatus.failed;
    final storedDuration = Duration(milliseconds: asset.durationMs ?? 0);
    final duration = active && driver!.duration > Duration.zero
        ? driver.duration
        : storedDuration;
    final position = active ? driver!.position : Duration.zero;
    final maximum = duration.inMilliseconds <= 0
        ? 1.0
        : duration.inMilliseconds.toDouble();
    final value = position.inMilliseconds.clamp(0, maximum.toInt()).toDouble();

    return Semantics(
      label: '${context.l10n.record}：${asset.displayTitle}',
      selected: selected,
      child: _AssetSelectionFrame(
        asset: asset,
        selected: selected,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        child: Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium),
            side: const BorderSide(color: AppColors.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 180) {
                return _buildCompactPreview(context, duration);
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
                child: Row(
                  children: [
                    IconButton(
                      key: ValueKey('play-note-audio-${asset.id.value}'),
                      tooltip: playing
                          ? context.l10n.pauseRecording
                          : context.l10n.playRecording,
                      onPressed: driver == null || filePath == null
                          ? null
                          : () {
                              onInteraction();
                              onSelect();
                              unawaited(
                                driver.toggle(
                                  assetId: asset.id.value,
                                  filePath: filePath!,
                                ),
                              );
                            },
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.accentSoft,
                        foregroundColor: AppColors.accent,
                        disabledBackgroundColor: AppColors.surfaceMuted,
                        fixedSize: const Size.square(44),
                      ),
                      icon: loading
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              playing
                                  ? Icons.pause_rounded
                                  : failed
                                  ? Icons.refresh_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            asset.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                failed
                                    ? context.l10n.recordingPlaybackFailed
                                    : _formatAudioDuration(position),
                                style: TextStyle(
                                  color: failed
                                      ? AppColors.danger
                                      : AppColors.muted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 2,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 5,
                                      disabledThumbRadius: 4,
                                    ),
                                    overlayShape: const RoundSliderOverlayShape(
                                      overlayRadius: 12,
                                    ),
                                  ),
                                  child: Slider(
                                    key: ValueKey(
                                      'note-audio-progress-${asset.id.value}',
                                    ),
                                    value: value,
                                    max: maximum,
                                    onChanged:
                                        !active ||
                                            driver == null ||
                                            duration <= Duration.zero
                                        ? null
                                        : (next) {
                                            onInteraction();
                                            onSelect();
                                            unawaited(
                                              driver.seek(
                                                assetId: asset.id.value,
                                                position: Duration(
                                                  milliseconds: next.round(),
                                                ),
                                              ),
                                            );
                                          },
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _formatAudioDuration(duration),
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (!readOnly)
                      Listener(
                        onPointerDown: (_) {
                          onInteraction();
                          onSelect();
                        },
                        child: AppAnchoredMenuButton<_AudioAssetAction>(
                          key: ValueKey('note-audio-actions-${asset.id.value}'),
                          tooltip: context.l10n.recordingActions,
                          icon: const Icon(Icons.more_vert_rounded, size: 20),
                          actions: [
                            AppMenuAction(
                              value: _AudioAssetAction.rename,
                              icon: Icons.edit_outlined,
                              label: context.l10n.renameAttachment,
                            ),
                            AppMenuAction(
                              value: _AudioAssetAction.remove,
                              icon: Icons.delete_outline_rounded,
                              label: context.l10n.remove,
                              destructive: true,
                            ),
                          ],
                          onSelected: (action) {
                            onInteraction();
                            onSelect();
                            switch (action) {
                              case _AudioAssetAction.rename:
                                unawaited(_rename(context));
                              case _AudioAssetAction.remove:
                                onRemove();
                            }
                          },
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCompactPreview(BuildContext context, Duration duration) =>
      Padding(
        key: ValueKey('compact-note-audio-${asset.id.value}'),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
        child: Row(
          children: [
            const Icon(
              Icons.graphic_eq_rounded,
              size: 18,
              color: AppColors.accent,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                asset.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (duration > Duration.zero) ...[
              const SizedBox(width: 5),
              Text(
                _formatAudioDuration(duration),
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      );

  Future<void> _rename(BuildContext context) async {
    final result = await showNoteAttachmentTitleSheet(
      context,
      initialValue: asset.displayTitle,
      fieldKey: const Key('audio-attachment-title'),
    );
    if (result != null) onRename(result.displayName);
  }
}

final class _NoteDividerEmbedBuilder extends quill.EmbedBuilder {
  const _NoteDividerEmbedBuilder({
    required this.onInteraction,
    required this.onToggleActions,
  });

  final VoidCallback onInteraction;
  final ValueChanged<int> onToggleActions;

  @override
  String get key => NoteEmbed.dividerType;

  @override
  String toPlainText(quill.Embed node) => '——';

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) =>
      Semantics(
        label: context.l10n.divider,
        button: !embedContext.readOnly,
        child: GestureDetector(
          key: ValueKey('note-divider-${embedContext.node.documentOffset}'),
          behavior: HitTestBehavior.opaque,
          onTap: embedContext.readOnly
              ? null
              : () {
                  onInteraction();
                  onToggleActions(embedContext.node.documentOffset);
                },
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Divider(height: 1, color: AppColors.line),
          ),
        ),
      );
}

final class _NoteTableEmbedBuilder extends quill.EmbedBuilder {
  const _NoteTableEmbedBuilder({
    required this.onInteraction,
    required this.onToggleActions,
  });

  final VoidCallback onInteraction;
  final ValueChanged<int> onToggleActions;

  @override
  String get key => NoteEmbed.tableType;

  @override
  String toPlainText(quill.Embed node) =>
      NoteEmbed.parse(node.value.toJson()).table!.plainText;

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final table = NoteEmbed.parse(embedContext.node.value.toJson()).table!;
    final offset = embedContext.node.documentOffset;
    return _NoteTableBlock(
      key: ValueKey('note-table-$offset'),
      table: table,
      readOnly: embedContext.readOnly,
      onTap: () {
        onInteraction();
        onToggleActions(offset);
      },
    );
  }
}

final class _NoteTableBlock extends StatelessWidget {
  const _NoteTableBlock({
    required this.table,
    required this.readOnly,
    required this.onTap,
    super.key,
  });

  final NoteTable table;
  final bool readOnly;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: context.l10n.tableDimensions(table.columnCount, table.rows.length),
    button: !readOnly,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: readOnly ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = math.max(
              constraints.maxWidth,
              table.columnCount * 116.0,
            );
            return DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.medium),
                border: Border.all(color: AppColors.line),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.medium),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: width,
                    child: Table(
                      border: const TableBorder(
                        horizontalInside: BorderSide(color: AppColors.line),
                        verticalInside: BorderSide(color: AppColors.line),
                      ),
                      children: [
                        for (
                          var rowIndex = 0;
                          rowIndex < table.rows.length;
                          rowIndex++
                        )
                          TableRow(
                            decoration: rowIndex == 0
                                ? const BoxDecoration(
                                    color: AppColors.surfaceMuted,
                                  )
                                : null,
                            children: [
                              for (
                                var columnIndex = 0;
                                columnIndex < table.columnCount;
                                columnIndex++
                              )
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  child: Text(
                                    table.rows[rowIndex][columnIndex],
                                    textAlign: switch (table
                                        .alignments[columnIndex]) {
                                      NoteTableAlignment.start =>
                                        TextAlign.start,
                                      NoteTableAlignment.center =>
                                        TextAlign.center,
                                      NoteTableAlignment.end => TextAlign.end,
                                    },
                                    style: TextStyle(
                                      color: AppColors.ink,
                                      fontSize: 14,
                                      height: 1.35,
                                      fontWeight: rowIndex == 0
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

final class _ImageAssetBlock extends StatelessWidget {
  const _ImageAssetBlock({
    required this.asset,
    required this.provider,
    required this.readOnly,
    required this.selected,
    required this.onInteraction,
    required this.onToggleSelection,
    required this.onOpen,
    super.key,
  });

  final NoteAsset asset;
  final ImageProvider? provider;
  final bool readOnly;
  final bool selected;
  final VoidCallback onInteraction;
  final VoidCallback onToggleSelection;
  final VoidCallback? onOpen;

  void _handleImageTap() {
    onInteraction();
    if (readOnly) {
      onOpen?.call();
      return;
    }
    onToggleSelection();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '图片：${asset.displayTitle}',
      button: true,
      selected: selected,
      onTap: _handleImageTap,
      child: Padding(
        key: ValueKey('note-image-selection-target-${asset.id.value}'),
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: _AssetSelectionFrame(
          asset: asset,
          selected: selected,
          borderRadius: BorderRadius.circular(4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: provider == null
                ? _AssetFallback(asset: asset, minHeight: 180)
                : _NaturalRatioImage(
                    key: ValueKey('note-image-${asset.id.value}'),
                    asset: asset,
                    provider: provider!,
                  ),
          ),
        ),
      ),
    );
  }
}

final class _NaturalRatioImage extends StatefulWidget {
  const _NaturalRatioImage({
    required this.asset,
    required this.provider,
    super.key,
  });

  final NoteAsset asset;
  final ImageProvider provider;

  @override
  State<_NaturalRatioImage> createState() => _NaturalRatioImageState();
}

final class _NaturalRatioImageState extends State<_NaturalRatioImage> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageInfo? _imageInfo;
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _NaturalRatioImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider != widget.provider) _resolve();
  }

  void _resolve() {
    final stream = widget.provider.resolve(
      createLocalImageConfiguration(context),
    );
    if (_stream?.key == stream.key) return;
    _stopListening();
    _imageInfo?.dispose();
    _imageInfo = null;
    _failed = false;
    _stream = stream;
    _listener = ImageStreamListener(
      _handleImage,
      onError: (_, _) {
        if (mounted) setState(() => _failed = true);
      },
    );
    stream.addListener(_listener!);
  }

  void _handleImage(ImageInfo info, bool synchronousCall) {
    if (!mounted) {
      info.dispose();
      return;
    }
    final previous = _imageInfo;
    setState(() {
      _imageInfo = info;
      _failed = false;
    });
    previous?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return _AssetFallback(asset: widget.asset, minHeight: 180);
    }
    final info = _imageInfo;
    if (info == null) {
      return const SizedBox(
        width: double.infinity,
        height: 180,
        child: ColoredBox(
          color: AppColors.paperSecondary,
          child: Center(
            child: Icon(Icons.photo_outlined, color: AppColors.subtle),
          ),
        ),
      );
    }
    final ratio = info.image.width / info.image.height;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return SizedBox(
          width: width,
          height: width / ratio,
          child: RawImage(
            image: info.image,
            width: width,
            height: width / ratio,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          ),
        );
      },
    );
  }

  void _stopListening() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _listener = null;
    _stream = null;
  }

  @override
  void dispose() {
    _stopListening();
    _imageInfo?.dispose();
    super.dispose();
  }
}

final class _ImageActionBar extends StatelessWidget {
  const _ImageActionBar({
    required this.asset,
    required this.onViewOriginal,
    required this.onCopy,
    required this.onEdit,
    required this.onShowDetails,
    required this.onRemove,
    super.key,
  });

  final NoteAsset asset;
  final Future<void> Function()? onViewOriginal;
  final Future<void> Function()? onCopy;
  final Future<void> Function()? onEdit;
  final Future<void> Function()? onShowDetails;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '图片操作：${asset.displayTitle}',
    container: true,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: AppColors.line),
        boxShadow: AppShadows.floating,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        child: Row(
          children: [
            _ImageActionButton(
              key: ValueKey('view-original-note-image-${asset.id.value}'),
              icon: Icons.open_in_full_rounded,
              label: context.l10n.viewOriginalImage,
              onPressed: onViewOriginal == null
                  ? null
                  : () => unawaited(onViewOriginal!()),
            ),
            _ImageActionButton(
              key: ValueKey('copy-note-image-${asset.id.value}'),
              icon: Icons.copy_rounded,
              label: context.l10n.copy,
              onPressed: onCopy == null ? null : () => unawaited(onCopy!()),
            ),
            _ImageActionButton(
              key: ValueKey('edit-note-image-${asset.id.value}'),
              icon: Icons.edit_outlined,
              label: context.l10n.edit,
              onPressed: onEdit == null ? null : () => unawaited(onEdit!()),
            ),
            _ImageActionButton(
              key: ValueKey('details-note-image-${asset.id.value}'),
              icon: Icons.info_outline_rounded,
              label: context.l10n.details,
              onPressed: onShowDetails == null
                  ? null
                  : () => unawaited(onShowDetails!()),
            ),
            _ImageActionButton(
              key: ValueKey('remove-note-asset-${asset.id.value}'),
              icon: Icons.delete_outline_rounded,
              label: context.l10n.delete,
              destructive: true,
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    ),
  );
}

final class _BlockActionBar extends StatelessWidget {
  const _BlockActionBar({
    required this.kind,
    required this.onRemove,
    super.key,
  });

  final NoteEmbedKind kind;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final table = kind == NoteEmbedKind.table;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: AppColors.line),
        boxShadow: AppShadows.floating,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 7, 8, 7),
        child: Row(
          children: [
            Icon(
              table ? Icons.table_chart_outlined : Icons.horizontal_rule,
              size: 20,
              color: AppColors.muted,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                table ? context.l10n.markdownTable : context.l10n.divider,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton.icon(
              key: ValueKey('remove-note-${kind.name}'),
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline_rounded, size: 19),
              label: Text(
                table ? context.l10n.deleteTable : context.l10n.delete,
              ),
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            ),
          ],
        ),
      ),
    );
  }
}

final class _ImageActionButton extends StatelessWidget {
  const _ImageActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.destructive = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 19,
              color: destructive ? AppColors.danger : AppColors.muted,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: destructive ? AppColors.danger : AppColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

String _formatAudioDuration(Duration value) {
  final totalSeconds = value.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

final class _FileAssetBlock extends StatelessWidget {
  const _FileAssetBlock({
    required this.asset,
    required this.readOnly,
    required this.selected,
    required this.onInteraction,
    required this.onOpen,
    required this.onRemove,
    super.key,
  });

  final NoteAsset asset;
  final bool readOnly;
  final bool selected;
  final VoidCallback onInteraction;
  final VoidCallback? onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    label: asset.displayTitle,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: _AssetSelectionFrame(
        asset: asset,
        selected: selected,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        child: Material(
          color: AppColors.surfaceMuted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              onInteraction();
              onOpen?.call();
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.small),
                    ),
                    child: Icon(
                      _iconFor(asset.kind),
                      color: AppColors.accent,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          asset.displayTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          asset.mimeType,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!readOnly) _RemoveButton(onPressed: onRemove),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  static IconData _iconFor(NoteAssetKind kind) => switch (kind) {
    NoteAssetKind.image => Icons.image_outlined,
    NoteAssetKind.audio => Icons.graphic_eq_rounded,
    NoteAssetKind.video => Icons.play_circle_outline_rounded,
    NoteAssetKind.file => Icons.insert_drive_file_outlined,
  };
}

final class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface.withValues(alpha: .92),
    shape: const CircleBorder(),
    child: IconButton(
      tooltip: '移除',
      onPressed: onPressed,
      icon: const Icon(Icons.close_rounded, size: 18),
      color: AppColors.muted,
      constraints: const BoxConstraints.tightFor(width: 38, height: 38),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.standard,
    ),
  );
}

final class _AssetFallback extends StatelessWidget {
  const _AssetFallback({required this.asset, required this.minHeight});

  final NoteAsset asset;
  final double minHeight;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(minHeight: minHeight),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.broken_image_outlined, color: AppColors.muted),
          const SizedBox(height: 8),
          Text(
            asset.displayTitle,
            style: const TextStyle(color: AppColors.muted),
          ),
        ],
      ),
    ),
  );
}

final class _MissingAssetCard extends StatelessWidget {
  const _MissingAssetCard();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 8),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.softCoral,
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
      child: Padding(
        padding: EdgeInsets.all(14),
        child: Text('附件不可用', style: TextStyle(color: AppColors.coral)),
      ),
    ),
  );
}
