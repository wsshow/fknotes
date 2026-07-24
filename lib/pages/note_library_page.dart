import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import '../models/note.dart';
import '../providers/note_library_controller.dart';
import '../services/file_storage_service.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_popup_menu.dart';
import '../widgets/note_delta_preview.dart';
import '../widgets/note_quill_editor.dart';
import '../widgets/quiet_paper.dart';
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
    this.onSelectionModeChanged,
    super.key,
  });

  final NoteLibraryController? controller;
  final NoteLibraryEditorBuilder? editorBuilder;
  final NoteLibraryImageResolver? resolveImage;
  final VoidCallback? onOpenAssistant;
  final VoidCallback? onOpenData;
  final ValueChanged<bool>? onSelectionModeChanged;

  @override
  State<NoteLibraryPage> createState() => _NoteLibraryPageState();
}

final class _NoteLibraryPageState extends State<NoteLibraryPage> {
  late final NoteLibraryController _controller;
  late final bool _ownsController;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode(debugLabel: 'note-library-search');
  final _activeNoteMenuLink = LayerLink();
  late final PageController _pageController;
  final Set<NoteId> _selectedNoteIds = {};
  Timer? _searchTimer;
  NoteId? _searchOriginNoteId;
  var _selectionBusy = false;
  var _currentIndex = 0;
  var _searchExpanded = false;
  var _searchPullDistance = 0.0;

  bool get _selectionMode => _selectedNoteIds.isNotEmpty;

  List<Note> get _selectedNotes => _controller.notes
      .where((note) => _selectedNoteIds.contains(note.id))
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? NoteLibraryController();
    _pageController = PageController(viewportFraction: .42);
    _controller.addListener(_onChanged);
    unawaited(_controller.initialize());
  }

  void _onChanged() {
    if (!mounted) return;
    final wasSelectionMode = _selectionMode;
    final available = _controller.notes.map((note) => note.id).toSet();
    _selectedNoteIds.removeWhere((id) => !available.contains(id));
    final lastIndex = math.max(0, _controller.notes.length - 1);
    if (_currentIndex > lastIndex) {
      _currentIndex = lastIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pageController.hasClients) return;
        _pageController.jumpToPage(_currentIndex);
      });
    }
    setState(() {});
    _notifySelectionModeChanged(wasSelectionMode);
  }

  void _toggleSelection(Note note) {
    if (_controller.isBusy(note.id) || _selectionBusy) return;
    final wasSelectionMode = _selectionMode;
    setState(() {
      if (!_selectedNoteIds.add(note.id)) {
        _selectedNoteIds.remove(note.id);
      }
    });
    _notifySelectionModeChanged(wasSelectionMode);
  }

  void _clearSelection() {
    if (_selectionBusy) return;
    final wasSelectionMode = _selectionMode;
    setState(_selectedNoteIds.clear);
    _notifySelectionModeChanged(wasSelectionMode);
  }

  void _selectAll() {
    if (_selectionBusy) return;
    final wasSelectionMode = _selectionMode;
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
    _notifySelectionModeChanged(wasSelectionMode);
  }

  void _notifySelectionModeChanged(bool wasSelectionMode) {
    if (wasSelectionMode == _selectionMode) return;
    widget.onSelectionModeChanged?.call(_selectionMode);
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

  void _expandSearch() {
    if (_searchExpanded) return;
    if (_controller.notes.isNotEmpty &&
        _currentIndex < _controller.notes.length) {
      _searchOriginNoteId = _controller.notes[_currentIndex].id;
    }
    setState(() => _searchExpanded = true);
  }

  void _updateSearchPull(DragUpdateDetails details) {
    if (_searchExpanded) return;
    _searchPullDistance += math.max(0.0, details.primaryDelta ?? 0);
    if (_searchPullDistance >= 14) {
      _searchPullDistance = 0;
      _expandSearch();
    }
  }

  void _endSearchPull(DragEndDetails details) {
    final shouldExpand =
        !_searchExpanded &&
        (_searchPullDistance >= 8 || (details.primaryVelocity ?? 0) > 120);
    _searchPullDistance = 0;
    if (shouldExpand) _expandSearch();
  }

  Future<void> _collapseSearch() async {
    if (!_searchExpanded) return;
    _searchTimer?.cancel();
    _dismissSearchFocus();
    _searchController.clear();
    if (_controller.query.isNotEmpty) {
      await _controller.search('');
    }
    if (!mounted) return;

    final origin = _searchOriginNoteId;
    final targetIndex = origin == null
        ? _currentIndex
        : _controller.notes.indexWhere((note) => note.id == origin);
    setState(() {
      _searchExpanded = false;
      _searchOriginNoteId = null;
      if (targetIndex >= 0) _currentIndex = targetIndex;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients || targetIndex < 0) return;
      _pageController.jumpToPage(targetIndex);
    });
  }

  Future<void> _openEditor([Note? note]) async {
    _dismissSearchFocus();
    final builder =
        widget.editorBuilder ??
        (context, value) => NoteQuillEditorPage(initialNote: value);
    await Navigator.push<Note?>(
      context,
      MaterialPageRoute(builder: (context) => builder(context, note)),
    );
    if (!mounted) return;
    _dismissSearchFocus();
    await _controller.refresh();
  }

  void _dismissSearchFocus() {
    _searchFocusNode.unfocus(disposition: UnfocusDisposition.scope);
    FocusScope.of(context).unfocus(disposition: UnfocusDisposition.scope);
  }

  void _openAssistant() {
    _dismissSearchFocus();
    widget.onOpenAssistant?.call();
  }

  void _openData() {
    _dismissSearchFocus();
    widget.onOpenData?.call();
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
      child: PaperShell(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (_selectionMode) {
              return Column(
                children: [
                  _buildSelectionHeader(context),
                  Expanded(child: _buildContent(context)),
                ],
              );
            }
            final deckWidth = math.min(
              620.0,
              math.max(220.0, constraints.maxWidth - 128),
            );
            final searchWidth = _searchExpanded
                ? math.min(250.0, deckWidth * .82)
                : math.min(176.0, deckWidth * .72);
            final reduceMotion = MediaQuery.disableAnimationsOf(context);
            return Stack(
              children: [
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: 0,
                  width: 58,
                  child: BrandSpine(
                    label: widget.onOpenData == null
                        ? context.l10n.library
                        : context.l10n.appTitle,
                    itemLabel: context.l10n.itemCount(_controller.notes.length),
                  ),
                ),
                Positioned(
                  top: 66,
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: deckWidth,
                      height: constraints.maxHeight - 66,
                      child: _buildContent(context),
                    ),
                  ),
                ),
                AnimatedPositioned(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  top: 0,
                  left: (constraints.maxWidth - searchWidth) / 2,
                  width: searchWidth,
                  child: _buildSearchHandle(context),
                ),
                Positioned(
                  top: 58,
                  right: 7,
                  child: Column(
                    children: [
                      if (widget.onOpenAssistant != null) ...[
                        ToolNodeButton(
                          buttonKey: const Key('quill-home-assistant'),
                          tooltip: context.l10n.localAssistant,
                          onPressed: _openAssistant,
                          icon: Icons.auto_awesome_outlined,
                        ),
                        const SizedBox(height: 14),
                      ],
                      ToolNodeButton(
                        buttonKey: widget.onOpenData != null
                            ? const Key('delta-library-open-data')
                            : null,
                        tooltip: widget.onOpenData != null
                            ? context.l10n.localData
                            : context.l10n.retry,
                        onPressed: widget.onOpenData != null
                            ? _openData
                            : _controller.isLoading
                            ? null
                            : () => unawaited(_controller.refresh()),
                        icon: widget.onOpenData != null
                            ? Icons.tune_rounded
                            : Icons.refresh_rounded,
                      ),
                    ],
                  ),
                ),
                if (_controller.notes.isNotEmpty)
                  Positioned(
                    top: constraints.maxHeight * .34,
                    bottom: constraints.maxHeight * .27,
                    right: 2,
                    width: 51,
                    child: IndexTicks(
                      index: _currentIndex,
                      count: _controller.notes.length,
                      onDrag: _jumpToFraction,
                    ),
                  ),
                if (_controller.notes.isNotEmpty)
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: CompositedTransformFollower(
                        link: _activeNoteMenuLink,
                        showWhenUnlinked: false,
                        targetAnchor: Alignment.topRight,
                        followerAnchor: Alignment.topRight,
                        child: _buildActiveNoteMenu(context),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );

  Widget _buildSearchHandle(BuildContext context) => AnimatedSwitcher(
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 160),
    switchInCurve: Curves.easeOut,
    switchOutCurve: Curves.easeIn,
    child: _searchExpanded
        ? SearchPullHandle(
            key: const Key('delta-library-search-expanded'),
            child: SizedBox(
              height: 39,
              child: SearchBar(
                key: const Key('delta-library-search'),
                controller: _searchController,
                focusNode: _searchFocusNode,
                hintText: context.l10n.searchNotes,
                textStyle: const WidgetStatePropertyAll(
                  TextStyle(color: AppColors.ink, fontSize: 13),
                ),
                hintStyle: const WidgetStatePropertyAll(
                  TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                elevation: const WidgetStatePropertyAll(0),
                backgroundColor: const WidgetStatePropertyAll(
                  Colors.transparent,
                ),
                surfaceTintColor: const WidgetStatePropertyAll(
                  Colors.transparent,
                ),
                shape: const WidgetStatePropertyAll(StadiumBorder()),
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 3),
                ),
                leading: IconButton(
                  key: const Key('delta-library-collapse-search'),
                  tooltip: context.l10n.close,
                  onPressed: () => unawaited(_collapseSearch()),
                  icon: const Icon(
                    Icons.keyboard_arrow_up_rounded,
                    size: 20,
                    color: AppColors.mechanicalBlue,
                  ),
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
                      icon: const Icon(Icons.close_rounded, size: 18),
                    )
                  else
                    const Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: AppColors.muted,
                    ),
                ],
                onChanged: (value) {
                  _scheduleSearch(value);
                  setState(() {});
                },
              ),
            ),
          )
        : SearchPullTab(
            key: const Key('delta-library-search-pull'),
            label: context.l10n.pullToSearch,
            onTap: _expandSearch,
            onVerticalDragUpdate: _updateSearchPull,
            onVerticalDragEnd: _endSearchPull,
          ),
  );

  Widget _buildActiveNoteMenu(BuildContext context) {
    final index = math.min(
      math.max(0, _currentIndex),
      _controller.notes.length - 1,
    );
    final note = _controller.notes[index];
    return _ActiveNoteMenuControl(
      key: ValueKey('delta-active-note-menu-${note.id.value}'),
      buttonKey: ValueKey('delta-note-menu-${note.id.value}'),
      tooltip: context.l10n.moreNoteActions,
      busy: _controller.isBusy(note.id),
      actions: _libraryNoteActions(context, note),
      onSelected: (action) => unawaited(_handleAction(note, action)),
    );
  }

  Widget _buildSelectionHeader(BuildContext context) {
    final notes = _selectedNotes;
    final allPinned = notes.isNotEmpty && notes.every((note) => note.isPinned);
    return Container(
      key: const Key('delta-library-selection-header'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
      decoration: const BoxDecoration(
        color: AppColors.paperPrimary,
        border: Border(bottom: BorderSide(color: AppColors.line)),
        boxShadow: AppShadows.paperEdge,
      ),
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
                color: AppColors.terracotta,
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
      return Center(
        child: PaperSection(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              ),
              const SizedBox(width: 12),
              Text(
                context.l10n.loadingVersion,
                style: const TextStyle(color: AppColors.muted),
              ),
            ],
          ),
        ),
      );
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
        alignment: const Alignment(0, -0.48),
      );
    }
    if (!_selectionMode) return _buildRolodex(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 520 ? 3 : 2;
        const spacing = 10.0;
        final horizontalPadding = constraints.maxWidth < 300 ? 10.0 : 16.0;
        final tileWidth =
            (constraints.maxWidth -
                horizontalPadding * 2 -
                spacing * (columns - 1)) /
            columns;
        final tileHeight = (tileWidth * 1.42).clamp(158.0, 224.0);
        return RefreshIndicator(
          onRefresh: _controller.refresh,
          child: GridView.builder(
            key: const Key('delta-library-selection-grid'),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              16,
              horizontalPadding,
              widget.onOpenData == null ? 40 : 108,
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
              childAspectRatio: tileWidth / tileHeight,
            ),
            itemCount: _controller.notes.length,
            itemBuilder: (context, index) {
              final note = _controller.notes[index];
              return _DeltaNoteCard(
                key: ValueKey('delta-note-${note.id.value}'),
                note: note,
                busy: _controller.isBusy(note.id),
                selectionMode: _selectionMode,
                selected: _selectedNoteIds.contains(note.id),
                resolveImage: widget.resolveImage ?? _resolveManagedImage,
                onTap: () => _toggleSelection(note),
                onLongPress: () => _toggleSelection(note),
                onAction: (action) => unawaited(_handleAction(note, action)),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildRolodex(BuildContext context) => RefreshIndicator(
    onRefresh: _controller.refresh,
    displacement: 76,
    color: AppColors.mechanicalBlue,
    backgroundColor: AppColors.paperPrimary,
    child: PageView.builder(
      key: const Key('delta-library-rolodex'),
      controller: _pageController,
      scrollDirection: Axis.vertical,
      padEnds: true,
      allowImplicitScrolling: true,
      physics: const BouncingScrollPhysics(),
      itemCount: _controller.notes.length,
      onPageChanged: (value) {
        if (_currentIndex == value) return;
        setState(() => _currentIndex = value);
        if (!MediaQuery.disableAnimationsOf(context)) {
          unawaited(HapticFeedback.selectionClick());
        }
      },
      itemBuilder: (context, index) {
        final note = _controller.notes[index];
        final active = index == _currentIndex;
        final reduceMotion = MediaQuery.disableAnimationsOf(context);
        return _RolodexNoteSheet(
          key: ValueKey('delta-note-${note.id.value}'),
          note: note,
          active: active,
          menuLayerLink: active ? _activeNoteMenuLink : null,
          reduceMotion: reduceMotion,
          busy: _controller.isBusy(note.id),
          resolveImage: widget.resolveImage ?? _resolveManagedImage,
          onTap: () {
            if (!active) {
              if (reduceMotion) {
                _pageController.jumpToPage(index);
              } else {
                _pageController.animateToPage(
                  index,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                );
              }
              return;
            }
            unawaited(_openEditor(note));
          },
          onLongPress: () => _toggleSelection(note),
        );
      },
    ),
  );

  void _jumpToFraction(double fraction) {
    if (!_pageController.hasClients || _controller.notes.isEmpty) return;
    final target = ((math.max(0, _controller.notes.length - 1)) * fraction)
        .round();
    if (target == _currentIndex) return;
    _pageController.jumpToPage(target);
    setState(() => _currentIndex = target);
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
    _searchFocusNode.dispose();
    _pageController.dispose();
    _controller.removeListener(_onChanged);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }
}

enum _LibraryNoteAction { pin, delete }

List<AppMenuAction<_LibraryNoteAction>> _libraryNoteActions(
  BuildContext context,
  Note note,
) => [
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

final class _ActiveNoteMenuControl extends StatefulWidget {
  const _ActiveNoteMenuControl({
    required this.buttonKey,
    required this.tooltip,
    required this.busy,
    required this.actions,
    required this.onSelected,
    super.key,
  });

  final Key buttonKey;
  final String tooltip;
  final bool busy;
  final List<AppMenuAction<_LibraryNoteAction>> actions;
  final ValueChanged<_LibraryNoteAction> onSelected;

  @override
  State<_ActiveNoteMenuControl> createState() => _ActiveNoteMenuControlState();
}

final class _ActiveNoteMenuControlState extends State<_ActiveNoteMenuControl> {
  var _open = false;

  @override
  void didUpdateWidget(covariant _ActiveNoteMenuControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.busy && _open) _open = false;
  }

  void _toggle() => setState(() => _open = !_open);

  void _close() {
    if (_open) setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) => TapRegion(
    onTapOutside: (_) => _close(),
    child: SizedBox(
      width: 152,
      height: 160,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 0,
            right: 0,
            child: widget.busy
                ? const SizedBox.square(
                    dimension: 48,
                    child: Center(
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      ),
                    ),
                  )
                : IconButton(
                    key: widget.buttonKey,
                    tooltip: widget.tooltip,
                    onPressed: _toggle,
                    icon: const Icon(Icons.more_vert_rounded),
                  ),
          ),
          if (_open)
            Positioned(
              top: 52,
              right: 0,
              width: 144,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.paperPrimary,
                  border: Border.all(color: AppColors.line),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: AppShadows.floating,
                ),
                clipBehavior: Clip.antiAlias,
                child: Material(
                  color: Colors.transparent,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (
                        var index = 0;
                        index < widget.actions.length;
                        index++
                      ) ...[
                        if (index > 0)
                          const Divider(height: 1, color: AppColors.line),
                        _buildAction(widget.actions[index]),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _buildAction(AppMenuAction<_LibraryNoteAction> action) {
    final color = action.destructive ? AppColors.danger : AppColors.ink;
    return InkWell(
      onTap: action.enabled
          ? () {
              _close();
              widget.onSelected(action.value);
            }
          : null,
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: Row(
            children: [
              Icon(action.icon, size: 19, color: color),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  action.label,
                  maxLines: 1,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _RolodexNoteSheet extends StatelessWidget {
  const _RolodexNoteSheet({
    required this.note,
    required this.active,
    required this.menuLayerLink,
    required this.reduceMotion,
    required this.busy,
    required this.resolveImage,
    required this.onTap,
    required this.onLongPress,
    super.key,
  });

  final Note note;
  final bool active;
  final LayerLink? menuLayerLink;
  final bool reduceMotion;
  final bool busy;
  final NoteLibraryImageResolver resolveImage;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final sheetHeight = active
          ? math.max(188.0, constraints.maxHeight * 1.3)
          : math.min(112.0, math.max(76.0, constraints.maxHeight - 40));
      return OverflowBox(
        alignment: Alignment.center,
        minHeight: 0,
        maxHeight: active ? sheetHeight : constraints.maxHeight,
        child: Center(
          child: AnimatedContainer(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            height: sheetHeight,
            margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
            decoration: BoxDecoration(
              color: active ? AppColors.paperPrimary : AppColors.paperSecondary,
              borderRadius: BorderRadius.circular(AppRadius.small),
              border: Border.all(color: AppColors.line),
              boxShadow: active ? AppShadows.floating : AppShadows.paperEdge,
            ),
            clipBehavior: Clip.antiAlias,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: busy ? null : onTap,
                onLongPress: busy ? null : onLongPress,
                child: active ? _buildActive(context) : _buildAdjacent(context),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _buildActive(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // `active` flips while the sheet is still growing from its folded
      // height. Keep the compact composition until the animated box can
      // safely accommodate the expanded card's fixed header and footer.
      if (constraints.maxHeight < 228) {
        return _buildAdjacent(context);
      }

      final showPreview = constraints.maxHeight >= 250;
      final showTags = constraints.maxHeight >= 320;
      return Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(25, 24, 25, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (note.isPinned)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(
                            Icons.push_pin_rounded,
                            size: 16,
                            color: AppColors.terracotta,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          note.title.trim().isEmpty
                              ? context.l10n.untitled
                              : note.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontSize: 23, height: 1.28),
                        ),
                      ),
                      if (menuLayerLink != null) const SizedBox(width: 42),
                    ],
                  ),
                  const SizedBox(height: 11),
                  Container(
                    height: 1,
                    color: AppColors.mechanicalBlue.withValues(alpha: .5),
                  ),
                  if (showPreview)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: _FadedDocumentPreview(
                          documentKey: ValueKey(
                            'delta-note-document-${note.id.value}',
                          ),
                          note: note,
                          resolveImage: resolveImage,
                          fadeHeight: 72,
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (showTags && note.tags.isNotEmpty) ...[
                        Flexible(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 5,
                            children: [
                              for (final tag in note.tags.take(3))
                                PaperTag(label: tag),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(height: 1, color: AppColors.line),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          _DeltaNoteCard._friendlyTime(
                            context,
                            note.updatedAt.toLocal(),
                          ),
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
              ),
            ),
          ),
          if (menuLayerLink != null)
            Positioned(
              top: 7,
              right: 7,
              child: CompositedTransformTarget(
                link: menuLayerLink!,
                child: const SizedBox.square(dimension: 48),
              ),
            ),
        ],
      );
    },
  );

  Widget _buildAdjacent(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 14, 18, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (note.isPinned)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(
                  Icons.push_pin_rounded,
                  color: AppColors.terracotta,
                  size: 15,
                ),
              ),
            Expanded(
              child: Text(
                note.title.trim().isEmpty ? context.l10n.untitled : note.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontSize: 17),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _DeltaNoteCard._friendlyTime(context, note.updatedAt.toLocal()),
              style: const TextStyle(color: AppColors.muted, fontSize: 10),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(height: 1, color: AppColors.line),
        const SizedBox(height: 5),
        Expanded(
          child: note.contentProjection.isVisuallyEmpty
              ? const SizedBox.shrink()
              : Row(
                  key: ValueKey('folded-note-preview-${note.id.value}'),
                  children: [
                    Icon(
                      _foldedContentIcon(note),
                      size: 13,
                      color: AppColors.subtle,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: NoteDeltaPreview(
                        note: note,
                        maxLines: 1,
                        compactWhitespace: true,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 11,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    ),
  );

  static IconData _foldedContentIcon(Note note) {
    if (note.assets.any((asset) => asset.kind == NoteAssetKind.image)) {
      return Icons.image_outlined;
    }
    if (note.assets.any((asset) => asset.kind == NoteAssetKind.audio)) {
      return Icons.graphic_eq_rounded;
    }
    return Icons.subject_rounded;
  }
}

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
  Widget build(BuildContext context) => Material(
    color: AppColors.paperPrimary,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.small),
      side: BorderSide(
        color: selected ? AppColors.mechanicalBlue : AppColors.line,
        width: 1.5,
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: busy ? null : onTap,
      onLongPress: busy ? null : onLongPress,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(11, 11, 8, 10),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 27),
              child: _buildText(context),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(5),
                      child: SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : selectionMode
                  ? Padding(
                      padding: const EdgeInsets.all(3),
                      child: AnimatedContainer(
                        key: ValueKey('delta-note-selection-${note.id.value}'),
                        duration: const Duration(milliseconds: 160),
                        width: 22,
                        height: 22,
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
                                size: 15,
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
                color: AppColors.terracotta,
              ),
            ),
          Expanded(
            child: Text(
              note.title.trim().isEmpty ? context.l10n.untitled : note.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontSize: 15, height: 1.25),
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Container(height: 1, color: AppColors.line),
      const SizedBox(height: 7),
      Expanded(
        child: note.contentProjection.isVisuallyEmpty
            ? const SizedBox.shrink()
            : _FadedDocumentPreview(
                note: note,
                resolveImage: resolveImage,
                fadeHeight: 36,
              ),
      ),
      const SizedBox(height: 7),
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (note.tags.isNotEmpty) ...[
            _MiniPaperTag(label: note.tags.first),
            const SizedBox(width: 5),
          ],
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Container(height: 1, color: AppColors.line),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            DateFormat('HH:mm').format(note.updatedAt.toLocal()),
            style: const TextStyle(
              color: AppColors.subtle,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    ],
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

final class _FadedDocumentPreview extends StatefulWidget {
  const _FadedDocumentPreview({
    required this.note,
    required this.resolveImage,
    required this.fadeHeight,
    this.documentKey,
  });

  final Note note;
  final NoteLibraryImageResolver resolveImage;
  final double fadeHeight;
  final Key? documentKey;

  @override
  State<_FadedDocumentPreview> createState() => _FadedDocumentPreviewState();
}

final class _FadedDocumentPreviewState extends State<_FadedDocumentPreview> {
  final ScrollController _previewController = ScrollController();
  bool _hasOverflow = false;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverflow());

    final preview = SingleChildScrollView(
      controller: _previewController,
      physics: const NeverScrollableScrollPhysics(),
      clipBehavior: Clip.hardEdge,
      child: NoteRichDocumentPreview(
        key: widget.documentKey,
        note: widget.note,
        resolveImage: widget.resolveImage,
      ),
    );
    if (!_hasOverflow) return preview;

    return ShaderMask(
      key: const Key('note-document-preview-fade'),
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        final fadeStart = bounds.height <= 0
            ? 0.0
            : ((bounds.height - widget.fadeHeight) / bounds.height).clamp(
                0.0,
                1.0,
              );
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Colors.white, Colors.white, Colors.transparent],
          stops: [0, fadeStart, 1],
        ).createShader(bounds);
      },
      child: preview,
    );
  }

  void _syncOverflow() {
    if (!mounted || !_previewController.hasClients) return;
    final hasOverflow = _previewController.position.maxScrollExtent > 1;
    if (hasOverflow == _hasOverflow) return;
    setState(() => _hasOverflow = hasOverflow);
  }

  @override
  void dispose() {
    _previewController.dispose();
    super.dispose();
  }
}

final class _MiniPaperTag extends StatelessWidget {
  const _MiniPaperTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 56),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      border: Border.all(
        color: AppColors.mechanicalBlue.withValues(alpha: .65),
      ),
      borderRadius: BorderRadius.circular(AppRadius.pill),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: AppColors.ink,
        fontSize: 9,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

final class _LibraryMessage extends StatelessWidget {
  const _LibraryMessage({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.alignment = Alignment.center,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final Future<void> Function()? onAction;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => Align(
    alignment: alignment,
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
