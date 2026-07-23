import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../app.dart';
import '../editor/note_editor_controller.dart';
import '../models/note.dart';
import '../models/note_document.dart';

typedef NoteAssetImageProvider = ImageProvider? Function(NoteAsset asset);

final class NoteQuillEditor extends StatelessWidget {
  const NoteQuillEditor({
    required this.controller,
    this.focusNode,
    this.scrollController,
    this.resolveImage,
    this.onOpenAsset,
    this.readOnly = false,
    this.placeholder = '开始记录…',
    super.key,
  });

  final NoteEditorController controller;
  final FocusNode? focusNode;
  final ScrollController? scrollController;
  final NoteAssetImageProvider? resolveImage;
  final ValueChanged<NoteAsset>? onOpenAsset;
  final bool readOnly;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    controller.quillController.readOnly = readOnly;
    return quill.QuillEditor.basic(
      controller: controller.quillController,
      focusNode: focusNode,
      scrollController: scrollController,
      config: quill.QuillEditorConfig(
        expands: true,
        scrollable: true,
        readOnlyMouseCursor: SystemMouseCursors.text,
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 120),
        placeholder: placeholder,
        enableInteractiveSelection: true,
        enableSelectionToolbar: true,
        textInputAction: TextInputAction.newline,
        embedBuilders: [
          _NoteAssetEmbedBuilder(
            session: controller,
            resolveImage: resolveImage,
            onOpenAsset: onOpenAsset,
          ),
          _NoteDividerEmbedBuilder(session: controller),
        ],
      ),
    );
  }
}

final class NoteQuillToolbar extends StatelessWidget {
  const NoteQuillToolbar({
    required this.controller,
    this.onInsertImage,
    this.imageTooltip = '插入图片',
    this.dividerTooltip = '插入分隔线',
    super.key,
  });

  final NoteEditorController controller;
  final VoidCallback? onInsertImage;
  final String imageTooltip;
  final String dividerTooltip;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    child: SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: quill.QuillSimpleToolbar(
          controller: controller.quillController,
          config: quill.QuillSimpleToolbarConfig(
            multiRowsDisplay: false,
            toolbarSize: 46,
            showDividers: false,
            color: AppColors.surface,
            sectionDividerColor: AppColors.line,
            showFontFamily: false,
            showFontSize: false,
            showSmallButton: false,
            showLineHeightButton: false,
            showColorButton: false,
            showBackgroundColorButton: false,
            showClearFormat: true,
            showAlignmentButtons: false,
            showDirection: false,
            showSearchButton: false,
            showSubscript: false,
            showSuperscript: false,
            showIndent: true,
            showCodeBlock: true,
            showInlineCode: true,
            customButtons: [
              if (onInsertImage != null)
                quill.QuillToolbarCustomButtonOptions(
                  tooltip: imageTooltip,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  onPressed: onInsertImage,
                ),
              quill.QuillToolbarCustomButtonOptions(
                tooltip: dividerTooltip,
                icon: const Icon(Icons.horizontal_rule_rounded),
                onPressed: controller.insertDivider,
              ),
            ],
            iconTheme: const quill.QuillIconTheme(
              iconButtonUnselectedData: quill.IconButtonData(
                color: AppColors.muted,
                iconSize: 21,
                padding: EdgeInsets.all(10),
                constraints: BoxConstraints(minWidth: 44, minHeight: 44),
              ),
              iconButtonSelectedData: quill.IconButtonData(
                color: AppColors.coral,
                iconSize: 21,
                padding: EdgeInsets.all(10),
                constraints: BoxConstraints(minWidth: 44, minHeight: 44),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

final class _NoteAssetEmbedBuilder extends quill.EmbedBuilder {
  const _NoteAssetEmbedBuilder({
    required this.session,
    required this.resolveImage,
    required this.onOpenAsset,
  });

  final NoteEditorController session;
  final NoteAssetImageProvider? resolveImage;
  final ValueChanged<NoteAsset>? onOpenAsset;

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
    if (asset.kind == NoteAssetKind.image) {
      return _ImageAssetBlock(
        key: ValueKey('note-asset-${asset.id.value}'),
        asset: asset,
        provider: resolveImage?.call(asset),
        readOnly: embedContext.readOnly,
        onOpen: onOpenAsset == null ? null : () => onOpenAsset!(asset),
        onRemove: () => session.removeEmbedAt(embedContext.node.documentOffset),
      );
    }
    return _FileAssetBlock(
      key: ValueKey('note-asset-${asset.id.value}'),
      asset: asset,
      readOnly: embedContext.readOnly,
      onOpen: onOpenAsset == null ? null : () => onOpenAsset!(asset),
      onRemove: () => session.removeEmbedAt(embedContext.node.documentOffset),
    );
  }
}

final class _NoteDividerEmbedBuilder extends quill.EmbedBuilder {
  const _NoteDividerEmbedBuilder({required this.session});

  final NoteEditorController session;

  @override
  String get key => NoteEmbed.dividerType;

  @override
  String toPlainText(quill.Embed node) => '——';

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) => Stack(
    alignment: Alignment.centerRight,
    children: [
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Divider(height: 1, color: AppColors.line),
      ),
      if (!embedContext.readOnly)
        _RemoveButton(
          onPressed: () =>
              session.removeEmbedAt(embedContext.node.documentOffset),
        ),
    ],
  );
}

final class _ImageAssetBlock extends StatelessWidget {
  const _ImageAssetBlock({
    required this.asset,
    required this.provider,
    required this.readOnly,
    required this.onOpen,
    required this.onRemove,
    super.key,
  });

  final NoteAsset asset;
  final ImageProvider? provider;
  final bool readOnly;
  final VoidCallback? onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final imageProvider = provider;
    return Semantics(
      label: '图片：${asset.displayTitle}',
      button: onOpen != null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Material(
            color: AppColors.softBlue,
            child: Stack(
              alignment: Alignment.topRight,
              children: [
                InkWell(
                  onTap: onOpen,
                  child: imageProvider == null
                      ? _AssetFallback(asset: asset, minHeight: 180)
                      : Image(
                          key: ValueKey('note-image-${asset.id.value}'),
                          image: imageProvider,
                          width: double.infinity,
                          fit: BoxFit.fitWidth,
                          errorBuilder: (_, _, _) =>
                              _AssetFallback(asset: asset, minHeight: 180),
                        ),
                ),
                if (!readOnly)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: _RemoveButton(
                      key: ValueKey('remove-note-asset-${asset.id.value}'),
                      onPressed: onRemove,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _FileAssetBlock extends StatelessWidget {
  const _FileAssetBlock({
    required this.asset,
    required this.readOnly,
    required this.onOpen,
    required this.onRemove,
    super.key,
  });

  final NoteAsset asset;
  final bool readOnly;
  final VoidCallback? onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Material(
      color: AppColors.canvas,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.softCoral,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_iconFor(asset.kind), color: AppColors.coral),
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
  );

  static IconData _iconFor(NoteAssetKind kind) => switch (kind) {
    NoteAssetKind.image => Icons.image_outlined,
    NoteAssetKind.audio => Icons.graphic_eq_rounded,
    NoteAssetKind.video => Icons.play_circle_outline_rounded,
    NoteAssetKind.file => Icons.insert_drive_file_outlined,
  };
}

final class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface.withValues(alpha: .92),
    elevation: 1,
    shape: const CircleBorder(),
    child: IconButton(
      tooltip: '移除',
      onPressed: onPressed,
      icon: const Icon(Icons.close_rounded, size: 19),
      color: AppColors.ink,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
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
