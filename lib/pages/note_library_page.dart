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
  final Set<NoteId> _selectedNoteIds = {};
  Timer? _searchTimer;
  var _selectionBusy = false;

  bool get _selectionMode => _selectedNoteIds.isNotEmpty;

  List<Note> get _selectedNotes => _controller.notes
      .where((note) => _selectedNoteIds.contains(note.id))
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? NoteLibraryController();
    _controller.addListener(_onChanged);
    unawaited(_controller.initialize());
  }

  void _onChanged() {
    if (!mounted) return;
    final available = _controller.notes.map((note) => note.id).toSet();
    _selectedNoteIds.removeWhere((id) => !available.contains(id));
    setState(() {});
  }

  void _toggleSelection(Note note) {
    if (_controller.isBusy(note.id) || _selectionBusy) return;
    setState(() {
      if (!_selectedNoteIds.add(note.id)) {
        _selectedNoteIds.remove(note.id);
      }
    });
  }

  void _clearSelection() {
    if (_selectionBusy) return;
    setState(_selectedNoteIds.clear);
  }

  void _selectAll() {
    if (_selectionBusy) return;
    setState(() {
      final available = _controller.notes
          .where((note) => !_controller.isBusy(note.id))
          .map((note) => note.id);
      if (_selectedNoteIds.length == _controller.notes.length) {
        _selectedNoteIds.clear();
      } else {
        _selectedNoteIds
          ..clear()
          ..addAll(available);
      }
    });
  }

  Future<void> _setSelectedPinned() async {
    final notes = _selectedNotes;
    if (notes.isEmpty || _selectionBusy) return;
    final pinned = notes.any((note) => !note.isPinned);
    setState(() => _selectionBusy = true);
    try {
      await _runAction(() => _controller.setPinned(notes, pinned: pinned));
    } finally {
      if (mounted) setState(() => _selectionBusy = false);
    }
  }

  Future<void> _deleteSelected() async {
    final notes = _selectedNotes;
    if (notes.isEmpty || _selectionBusy) return;
    final confirmed = await _confirmPermanentDeleteMany(notes.length);
    if (confirmed != true || !mounted) return;
    setState(() => _selectionBusy = true);
    try {
      await _runAction(() => _controller.deletePermanentlyAll(notes));
      if (mounted) {
        setState(_selectedNoteIds.clear);
      }
    } finally {
      if (mounted) setState(() => _selectionBusy = false);
    }
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

  Future<bool?> _confirmPermanentDeleteMany(int count) => showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(context.l10n.deleteSelectedNotesQuestion(count)),
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

  Widget _buildHeader(BuildContext context) => _selectionMode
      ? _buildSelectionHeader(context)
      : Padding(
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
                backgroundColor: const WidgetStatePropertyAll(
                  AppColors.surfaceMuted,
                ),
                surfaceTintColor: const WidgetStatePropertyAll(
                  Colors.transparent,
                ),
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

  Widget _buildSelectionHeader(BuildContext context) {
    final notes = _selectedNotes;
    final allPinned = notes.isNotEmpty && notes.every((note) => note.isPinned);
    return Padding(
      key: const Key('delta-library-selection-header'),
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 10),
      child: Row(
        children: [
          IconButton(
            key: const Key('delta-library-exit-selection'),
            tooltip: context.l10n.close,
            onPressed: _selectionBusy ? null : _clearSelection,
            icon: const Icon(Icons.close_rounded),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              context.l10n.selectedNoteCount(notes.length),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          if (_selectionBusy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 13),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else ...[
            IconButton(
              key: const Key('delta-library-select-all'),
              tooltip: context.l10n.selectAll,
              onPressed: _selectAll,
              icon: Icon(
                _selectedNoteIds.length == _controller.notes.length
                    ? Icons.deselect_rounded
                    : Icons.select_all_rounded,
              ),
            ),
            IconButton(
              key: const Key('delta-library-pin-selected'),
              tooltip: allPinned ? context.l10n.unpin : context.l10n.pin,
              onPressed: () => unawaited(_setSelectedPinned()),
              icon: Icon(
                allPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
              ),
            ),
            IconButton(
              key: const Key('delta-library-delete-selected'),
              tooltip: context.l10n.deletePermanently,
              color: AppColors.danger,
              onPressed: () => unawaited(_deleteSelected()),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ],
      ),
    );
  }

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
            selectionMode: _selectionMode,
            selected: _selectedNoteIds.contains(note.id),
            resolveImage: widget.resolveImage ?? _resolveManagedImage,
            onTap: () =>
                _selectionMode ? _toggleSelection(note) : _openEditor(note),
            onLongPress: () => _toggleSelection(note),
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
    required this.selectionMode,
    required this.selected,
    required this.resolveImage,
    required this.onTap,
    required this.onLongPress,
    required this.onAction,
    super.key,
  });

  final Note note;
  final bool busy;
  final bool selectionMode;
  final bool selected;
  final NoteLibraryImageResolver resolveImage;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<_LibraryNoteAction> onAction;

  @override
  Widget build(BuildContext context) {
    final cover = _coverAsset;
    final provider = cover == null ? null : resolveImage(cover);
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.large),
        side: BorderSide(
          color: selected ? AppColors.accent : Colors.transparent,
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : onTap,
        onLongPress: busy ? null : onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 17, 8, 16),
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.only(right: provider == null ? 46 : 138),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: provider == null ? 0 : 78,
                  ),
                  child: _buildText(context),
                ),
              ),
              if (provider != null)
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 48,
                  child: Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.small),
                      child: Image(
                        key: ValueKey('delta-note-cover-${note.id.value}'),
                        image: provider,
                        width: 78,
                        height: 78,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: 0,
                right: 0,
                child: busy
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : selectionMode
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: AnimatedContainer(
                          key: ValueKey(
                            'delta-note-selection-${note.id.value}',
                          ),
                          duration: const Duration(milliseconds: 160),
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.accent
                                : Colors.transparent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected
                                  ? AppColors.accent
                                  : AppColors.subtle,
                              width: 1.5,
                            ),
                          ),
                          child: selected
                              ? const Icon(
                                  Icons.check_rounded,
                                  size: 16,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      )
                    : AppAnchoredMenuButton<_LibraryNoteAction>(
                        tooltip: context.l10n.moreNoteActions,
                        icon: const Icon(Icons.more_vert_rounded),
                        actions: _actions(context),
                        onSelected: onAction,
                      ),
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
      if (_hasPreviewText) ...[
        const SizedBox(height: 8),
        NoteDeltaPreview(
          note: note,
          maxLines: 3,
          includeAttachmentLabels: false,
        ),
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

  bool get _hasPreviewText => note.document.toDelta().operations.any(
    (operation) =>
        operation.data is String &&
        (operation.data as String).trim().isNotEmpty,
  );

  List<AppMenuAction<_LibraryNoteAction>> _actions(BuildContext context) => [
    AppMenuAction(
      value: _LibraryNoteAction.pin,
      icon: note.isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
      label: note.isPinned ? context.l10n.unpin : context.l10n.pin,
    ),
    AppMenuAction(
      value: _LibraryNoteAction.delete,
      icon: Icons.delete_outline_rounded,
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
