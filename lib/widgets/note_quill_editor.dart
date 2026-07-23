import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../app.dart';
import '../editor/note_editor_controller.dart';
import '../l10n/l10n.dart';
import '../models/note.dart';
import '../models/note_document.dart';
import '../services/note_audio_playback_service.dart';
import 'app_popup_menu.dart';

typedef NoteAssetImageProvider = ImageProvider? Function(NoteAsset asset);
typedef NoteAssetPathResolver = String? Function(NoteAsset asset);
typedef NoteImageAssetAction = Future<void> Function(NoteAsset asset);

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
    this.onShowImageDetails,
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
  final NoteImageAssetAction? onShowImageDetails;
  final bool readOnly;
  final String placeholder;

  @override
  State<NoteQuillEditor> createState() => _NoteQuillEditorState();
}

final class _NoteQuillEditorState extends State<NoteQuillEditor> {
  NoteAttachmentId? _activeImageId;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final focusNode = widget.focusNode;
    final scrollController = widget.scrollController;
    final resolveImage = widget.resolveImage;
    final resolveAssetPath = widget.resolveAssetPath;
    final audioPlayback = widget.audioPlayback;
    final onOpenAsset = widget.onOpenAsset;
    final onCopyImage = widget.onCopyImage;
    final onEditImage = widget.onEditImage;
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
      TextPosition Function(Offset offset) getPosition,
    ) {
      final position = getPosition(globalPosition);
      if (!controller.isAttachmentEmbedAtOffset(position.offset)) {
        if (_activeImageId != null) {
          setState(() => _activeImageId = null);
        }
        return false;
      }
      dismissEditorFocus();
      return true;
    }

    final activeImage = _activeImageId == null
        ? null
        : controller.asset(_activeImageId!);
    final editor = quill.QuillEditor.basic(
      controller: controller.quillController,
      focusNode: focusNode,
      scrollController: scrollController,
      config: quill.QuillEditorConfig(
        expands: true,
        scrollable: true,
        readOnlyMouseCursor: SystemMouseCursors.text,
        padding: EdgeInsets.fromLTRB(
          24,
          18,
          24,
          activeImage == null ? 48 : 104,
        ),
        placeholder: placeholder,
        enableInteractiveSelection: true,
        enableSelectionToolbar: true,
        textInputAction: TextInputAction.newline,
        onTapDown: (details, getPosition) =>
            handleAssetTap(details.globalPosition, getPosition),
        onTapUp: (details, getPosition) =>
            handleAssetTap(details.globalPosition, getPosition),
        embedBuilders: [
          _NoteAssetEmbedBuilder(
            session: controller,
            resolveImage: resolveImage,
            resolveAssetPath: resolveAssetPath,
            audioPlayback: audioPlayback,
            onOpenAsset: onOpenAsset,
            onAssetInteraction: dismissEditorFocus,
            onToggleImageActions: (id) => setState(
              () => _activeImageId = _activeImageId == id ? null : id,
            ),
          ),
          _NoteDividerEmbedBuilder(session: controller),
        ],
      ),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        editor,
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
                setState(() => _activeImageId = null);
              },
            ),
          ),
      ],
    );
  }
}

final class NoteQuillToolbar extends StatelessWidget {
  const NoteQuillToolbar({
    required this.controller,
    this.onOpenAssistant,
    this.onInsertImage,
    this.onRecordAudio,
    this.assistantTooltip = 'AI 创作',
    this.imageTooltip = '插入图片',
    this.recordTooltip = '录音',
    this.dividerTooltip = '插入分隔线',
    super.key,
  });

  final NoteEditorController controller;
  final VoidCallback? onOpenAssistant;
  final VoidCallback? onInsertImage;
  final VoidCallback? onRecordAudio;
  final String assistantTooltip;
  final String imageTooltip;
  final String recordTooltip;
  final String dividerTooltip;

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
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Color(0x0F202124),
            blurRadius: 18,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
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
      ),
    );
  }
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

final class _NoteAssetEmbedBuilder extends quill.EmbedBuilder {
  const _NoteAssetEmbedBuilder({
    required this.session,
    required this.resolveImage,
    required this.resolveAssetPath,
    required this.audioPlayback,
    required this.onOpenAsset,
    required this.onAssetInteraction,
    required this.onToggleImageActions,
  });

  final NoteEditorController session;
  final NoteAssetImageProvider? resolveImage;
  final NoteAssetPathResolver? resolveAssetPath;
  final NoteAudioPlaybackDriver? audioPlayback;
  final ValueChanged<NoteAsset>? onOpenAsset;
  final VoidCallback onAssetInteraction;
  final ValueChanged<NoteAttachmentId> onToggleImageActions;

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
        onInteraction: onAssetInteraction,
        onToggleActions: () => onToggleImageActions(asset.id),
        onOpen: onOpenAsset == null ? null : () => onOpenAsset!(asset),
      );
    }
    if (asset.kind == NoteAssetKind.audio) {
      return _AudioAssetBlock(
        key: ValueKey('note-asset-${asset.id.value}'),
        asset: asset,
        filePath: resolveAssetPath?.call(asset),
        playback: audioPlayback,
        readOnly: embedContext.readOnly,
        onInteraction: onAssetInteraction,
        onRename: (displayName) =>
            session.updateAsset(asset.copyWith(displayName: displayName)),
        onRemove: () {
          if (audioPlayback?.activeAssetId == asset.id.value) {
            unawaited(audioPlayback?.stop());
          }
          session.removeEmbedAt(embedContext.node.documentOffset);
        },
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

enum _AudioAssetAction { rename, remove }

final class _AudioAssetBlock extends StatelessWidget {
  const _AudioAssetBlock({
    required this.asset,
    required this.filePath,
    required this.playback,
    required this.readOnly,
    required this.onInteraction,
    required this.onRename,
    required this.onRemove,
    super.key,
  });

  final NoteAsset asset;
  final String? filePath;
  final NoteAudioPlaybackDriver? playback;
  final bool readOnly;
  final VoidCallback onInteraction;
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
        behavior: HitTestBehavior.opaque,
        onTap: onInteraction,
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
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          side: const BorderSide(color: AppColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
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
                            color: failed ? AppColors.danger : AppColors.muted,
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
                AppAnchoredMenuButton<_AudioAssetAction>(
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
                    switch (action) {
                      case _AudioAssetAction.rename:
                        unawaited(_rename(context));
                      case _AudioAssetAction.remove:
                        onRemove();
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _rename(BuildContext context) async {
    var value = asset.displayTitle;
    final result = await showDialog<_AudioRenameResult>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.editAttachmentTitle),
        content: TextFormField(
          key: const Key('audio-attachment-title'),
          initialValue: value,
          onChanged: (next) => value = next,
          autofocus: true,
          maxLength: 120,
          decoration: InputDecoration(
            labelText: context.l10n.attachmentTitle,
            hintText: context.l10n.attachmentTitleHint,
            helperText: context.l10n.attachmentTitleDescription,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, const _AudioRenameResult(null)),
            child: Text(context.l10n.restoreOriginalFileName),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _AudioRenameResult(value.trim())),
            child: Text(context.l10n.save),
          ),
        ],
      ),
    );
    if (result != null) onRename(result.displayName);
  }
}

final class _AudioRenameResult {
  const _AudioRenameResult(this.displayName);

  final String? displayName;
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
    required this.onInteraction,
    required this.onToggleActions,
    required this.onOpen,
    super.key,
  });

  final NoteAsset asset;
  final ImageProvider? provider;
  final bool readOnly;
  final VoidCallback onInteraction;
  final VoidCallback onToggleActions;
  final VoidCallback? onOpen;

  void _handleImageTap() {
    onInteraction();
    if (readOnly) {
      onOpen?.call();
      return;
    }
    onToggleActions();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '图片：${asset.displayTitle}',
      button: true,
      onTap: _handleImageTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleImageTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.medium),
            child: Material(
              color: AppColors.surfaceMuted,
              child: provider == null
                  ? _AssetFallback(asset: asset, minHeight: 180)
                  : ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 120),
                      child: Image(
                        key: ValueKey('note-image-${asset.id.value}'),
                        image: provider!,
                        width: double.infinity,
                        fit: BoxFit.fitWidth,
                        errorBuilder: (_, _, _) =>
                            _AssetFallback(asset: asset, minHeight: 180),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _ImageActionBar extends StatelessWidget {
  const _ImageActionBar({
    required this.asset,
    required this.onCopy,
    required this.onEdit,
    required this.onShowDetails,
    required this.onRemove,
    super.key,
  });

  final NoteAsset asset;
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
      color: AppColors.surfaceMuted,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
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
