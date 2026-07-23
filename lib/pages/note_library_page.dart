import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import '../models/note.dart';
import '../providers/note_library_controller.dart';
import '../services/file_storage_service.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_popup_menu.dart';
import '../widgets/note_delta_preview.dart';
import 'note_quill_editor_page.dart';

typedef NoteLibraryEditorBuilder =
    Widget Function(BuildContext context, Note? note);

typedef NoteLibraryImageResolver = ImageProvider? Function(NoteAsset asset);

/// Standalone library for the Delta note model.
final class NoteLibraryPage extends StatefulWidget {
  const NoteLibraryPage({
    this.controller,
    this.editorBuilder,
    this.resolveImage,
    this.onOpenAssistant,
    this.onOpenData,
    super.key,
  });

  final NoteLibraryController? controller;
  final NoteLibraryEditorBuilder? editorBuilder;
  final NoteLibraryImageResolver? resolveImage;
  final VoidCallback? onOpenAssistant;
  final VoidCallback? onOpenData;

  @override
  State<NoteLibraryPage> createState() => _NoteLibraryPageState();
}

final class _NoteLibraryPageState extends State<NoteLibraryPage> {
  late final NoteLibraryController _controller;
  late final bool _ownsController;
  final _searchController = TextEditingController();
  Timer? _searchTimer;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? NoteLibraryController();
    _controller.addListener(_onChanged);
    unawaited(_controller.initialize());
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _scheduleSearch(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(
      const Duration(milliseconds: 280),
      () => unawaited(_controller.search(value)),
    );
  }

  Future<void> _openEditor([Note? note]) async {
    final builder =
        widget.editorBuilder ??
        (context, value) => NoteQuillEditorPage(initialNote: value);
    await Navigator.push<Note?>(
      context,
      MaterialPageRoute(builder: (context) => builder(context, note)),
    );
    if (mounted) await _controller.refresh();
  }

  Future<void> _runAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) {
        AppFeedback.error(context, context.l10n.toolActionFailed('$error'));
      }
    }
  }

  Future<void> _handleAction(Note note, _LibraryNoteAction action) async {
    switch (action) {
      case _LibraryNoteAction.pin:
        await _runAction(() => _controller.togglePinned(note));
      case _LibraryNoteAction.delete:
        if (await _confirmPermanentDelete(note) == true) {
          await _runAction(() => _controller.deletePermanently(note));
        }
    }
  }

  Future<bool?> _confirmPermanentDelete(Note note) => showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(context.l10n.deletePermanentlyQuestion),
      content: Text(context.l10n.deletePermanentlyDescription),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(context.l10n.deletePermanently),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    body: SafeArea(
      bottom: false,
      child: Column(
        children: [
          _buildHeader(context),
          const SizedBox(height: 14),
          Expanded(child: _buildContent(context)),
        ],
      ),
    ),
  );

  Widget _buildHeader(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.onOpenData == null
                        ? context.l10n.library
                        : context.l10n.appTitle,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.l10n.itemCount(_controller.notes.length),
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.onOpenAssistant != null) ...[
              IconButton(
                key: const Key('quill-home-assistant'),
                tooltip: context.l10n.localAssistant,
                onPressed: widget.onOpenAssistant,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  fixedSize: const Size.square(44),
                ),
                icon: const Icon(Icons.auto_awesome_outlined, size: 20),
              ),
              const SizedBox(width: 6),
            ],
            if (widget.onOpenData != null)
              IconButton(
                key: const Key('delta-library-open-data'),
                tooltip: context.l10n.localData,
                onPressed: widget.onOpenData,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  fixedSize: const Size.square(44),
                ),
                icon: const Icon(Icons.tune_rounded, size: 20),
              )
            else
              IconButton(
                tooltip: context.l10n.retry,
                onPressed: _controller.isLoading
                    ? null
                    : () => unawaited(_controller.refresh()),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  fixedSize: const Size.square(44),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 20),
              ),
          ],
        ),
        const SizedBox(height: 20),
        SearchBar(
          key: const Key('delta-library-search'),
          controller: _searchController,
          hintText: context.l10n.searchNotes,
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: const WidgetStatePropertyAll(AppColors.surfaceMuted),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.medium),
            ),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 15),
          ),
          leading: const Icon(
            Icons.search_rounded,
            size: 21,
            color: AppColors.muted,
          ),
          trailing: [
            if (_searchController.text.isNotEmpty)
              IconButton(
                tooltip: context.l10n.close,
                onPressed: () {
                  _searchController.clear();
                  _searchTimer?.cancel();
                  unawaited(_controller.search(''));
                  setState(() {});
                },
                icon: const Icon(Icons.close_rounded),
              ),
          ],
          onChanged: (value) {
            _scheduleSearch(value);
            setState(() {});
          },
        ),
      ],
    ),
  );

  Widget _buildContent(BuildContext context) {
    if (_controller.isLoading && _controller.notes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_controller.hasError && _controller.notes.isEmpty) {
      return _LibraryMessage(
        icon: Icons.cloud_off_outlined,
        message: context.l10n.toolActionFailed(context.l10n.unavailable),
        actionLabel: context.l10n.retry,
        onAction: _controller.refresh,
      );
    }
    if (_controller.notes.isEmpty) {
      return _LibraryMessage(
        icon: Icons.notes_rounded,
        message: context.l10n.emptyActive,
      );
    }
    return RefreshIndicator(
      onRefresh: _controller.refresh,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(
          20,
          2,
          20,
          widget.onOpenData == null ? 40 : 104,
        ),
        itemCount: _controller.notes.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final note = _controller.notes[index];
          return _DeltaNoteCard(
            key: ValueKey('delta-note-${note.id.value}'),
            note: note,
            busy: _controller.isBusy(note.id),
            resolveImage: widget.resolveImage ?? _resolveManagedImage,
            onTap: () => _openEditor(note),
            onAction: (action) => unawaited(_handleAction(note, action)),
          );
        },
      ),
    );
  }

  ImageProvider? _resolveManagedImage(NoteAsset asset) {
    final key = asset.previewStorageKey ?? asset.storageKey;
    try {
      final file = File(FileStorageService.instance.absolutePath(key));
      return FileImage(file);
    } on FormatException {
      return null;
    }
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    _controller.removeListener(_onChanged);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }
}

enum _LibraryNoteAction { pin, delete }

final class _DeltaNoteCard extends StatelessWidget {
  const _DeltaNoteCard({
    required this.note,
    required this.busy,
    required this.resolveImage,
    required this.onTap,
    required this.onAction,
    super.key,
  });

  final Note note;
  final bool busy;
  final NoteLibraryImageResolver resolveImage;
  final VoidCallback onTap;
  final ValueChanged<_LibraryNoteAction> onAction;

  @override
  Widget build(BuildContext context) {
    final cover = _coverAsset;
    final provider = cover == null ? null : resolveImage(cover);
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.large),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 17, 8, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildText(context)),
              if (provider != null) ...[
                const SizedBox(width: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.small),
                  child: Image(
                    image: provider,
                    width: 78,
                    height: 78,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ],
              const SizedBox(width: 2),
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                AppAnchoredMenuButton<_LibraryNoteAction>(
                  tooltip: context.l10n.moreNoteActions,
                  icon: const Icon(Icons.more_vert_rounded),
                  actions: _actions(context),
                  onSelected: onAction,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildText(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          if (note.isPinned)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Icon(
                Icons.push_pin_rounded,
                size: 15,
                color: AppColors.accent,
              ),
            ),
          Expanded(
            child: Text(
              note.title.trim().isEmpty ? context.l10n.untitled : note.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      ),
      if (!note.contentProjection.isVisuallyEmpty) ...[
        const SizedBox(height: 8),
        NoteDeltaPreview(note: note, maxLines: 3),
      ],
      if (note.tags.isNotEmpty) ...[
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 5,
          children: [
            for (final tag in note.tags.take(3))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  tag,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ],
      const SizedBox(height: 10),
      Text(
        _friendlyTime(context, note.updatedAt.toLocal()),
        style: const TextStyle(
          color: AppColors.subtle,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    ],
  );

  NoteAsset? get _coverAsset {
    final explicit = note.coverAttachmentId;
    if (explicit != null) {
      final asset = note.assetsById[explicit];
      if (asset?.kind == NoteAssetKind.image) return asset;
    }
    for (final asset in note.assets) {
      if (asset.kind == NoteAssetKind.image) return asset;
    }
    return null;
  }

  List<AppMenuAction<_LibraryNoteAction>> _actions(BuildContext context) => [
    AppMenuAction(
      value: _LibraryNoteAction.pin,
      icon: note.isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
      label: note.isPinned ? context.l10n.unpin : context.l10n.pin,
    ),
    AppMenuAction(
      value: _LibraryNoteAction.delete,
      icon: Icons.delete_forever_outlined,
      label: context.l10n.deletePermanently,
      destructive: true,
    ),
  ];

  static String _friendlyTime(BuildContext context, DateTime date) {
    final now = DateTime.now();
    if (DateUtils.isSameDay(now, date)) {
      return context.l10n.todayAt(DateFormat('HH:mm').format(date));
    }
    if (DateUtils.isSameDay(now.subtract(const Duration(days: 1)), date)) {
      return context.l10n.yesterdayAt(DateFormat('HH:mm').format(date));
    }
    return DateFormat.MMMd(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(date);
  }
}

final class _LibraryMessage extends StatelessWidget {
  const _LibraryMessage({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
            ),
            child: SizedBox.square(
              dimension: 64,
              child: Icon(icon, size: 27, color: AppColors.subtle),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            TextButton(
              onPressed: () => unawaited(onAction!()),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    ),
  );
}
