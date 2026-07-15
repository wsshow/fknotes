import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../debug/debug_console_launcher.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n.dart';
import '../models/note_entry.dart';
import '../providers/app_lock_controller.dart';
import '../providers/app_locale_controller.dart';
import '../providers/note_provider.dart';
import '../services/app_build_metadata.dart';
import '../services/app_lock_preferences_service.dart';
import '../services/background_task_center.dart';
import '../services/file_storage_service.dart';
import '../widgets/app_feedback.dart';
import '../widgets/empty_state.dart';
import '../widgets/app_popup_menu.dart';
import '../widgets/brand_mark.dart';
import '../widgets/note_card.dart';
import '../widgets/navigation_icons.dart';
import 'background_tasks_page.dart';
import 'local_chat_page.dart';
import 'note_editor_page.dart';
import 'model_management_page.dart';
import 'app_lock_settings_page.dart';
import 'backup_export_page.dart';
import 'backup_restore_page.dart';
import 'cloud_sync_page.dart';
import 'language_settings_page.dart';
import 'record_audio_page.dart';
import 'search_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  void _selectTab(int index) {
    AppFeedback.dismiss(context);
    if (_tab == index) return;
    setState(() => _tab = index);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NoteProvider>(
      builder: (context, provider, _) => Scaffold(
        extendBody: true,
        body: IndexedStack(
          index: _tab,
          children: [
            _OverviewTab(
              provider: provider,
              onSearch: _openSearch,
              onOpenAssistant: _openAssistant,
              onOpenLibrary: () => _selectTab(1),
              onCreateText: _createTextNote,
              onPickImage: _pickImage,
              onRecordAudio: _openRecorder,
              onPickDocument: _pickDocument,
              noteBuilder: _buildCard,
            ),
            _LibraryTab(
              provider: provider,
              onSearch: _openSearch,
              noteBuilder: _buildCard,
            ),
            _DataTab(provider: provider),
          ],
        ),
        floatingActionButton: _tab == 2
            ? null
            : FloatingActionButton.extended(
                key: const ValueKey('new-note'),
                heroTag: null,
                onPressed: _showCaptureSheet,
                icon: const Icon(Icons.add_rounded),
                label: Text(
                  context.l10n.createNew,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewPaddingOf(context).bottom,
            ),
            child: NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (index) {
                _selectTab(index);
                if (index == 0 && provider.scope != NoteScope.active) {
                  provider.setScope(NoteScope.active);
                }
              },
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.home_outlined),
                  selectedIcon: const Icon(Icons.home_outlined),
                  label: context.l10n.home,
                ),
                NavigationDestination(
                  icon: const LibrarySpinesIcon(),
                  selectedIcon: const LibrarySpinesIcon(),
                  label: context.l10n.library,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.pie_chart_outline_rounded),
                  selectedIcon: const Icon(Icons.pie_chart_outline_rounded),
                  label: context.l10n.data,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(NoteEntry entry, {bool compact = false}) {
    final provider = context.read<NoteProvider>();
    return NoteCard(
      entry: entry,
      compact: compact,
      onTap: () => _openEntry(entry),
      onEdit: entry.isDeleted ? null : () => _editEntry(entry),
      onFavorite: entry.isDeleted ? null : () => provider.toggleFavorite(entry),
      onPin: entry.isDeleted || entry.isArchived
          ? null
          : () => provider.togglePinned(entry),
      onArchive: entry.isDeleted ? null : () => provider.toggleArchived(entry),
      onRestore: entry.isDeleted ? () => provider.restore(entry) : null,
      onDelete: () =>
          entry.isDeleted ? _deleteForever(entry) : _moveToTrash(entry),
    );
  }

  Future<void> _openEntry(NoteEntry entry) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NoteEditorPage(existingEntry: entry)),
    );
  }

  Future<void> _editEntry(NoteEntry entry) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NoteEditorPage(existingEntry: entry)),
    );
  }

  void _openSearch() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const SearchPage()),
  );

  void _openAssistant() => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => LocalChatPage(
        onOpenNote: (source) => NoteEditorPage.openById(context, source.noteId),
      ),
    ),
  );

  Future<void> _moveToTrash(NoteEntry entry) async {
    final provider = context.read<NoteProvider>();
    await provider.moveToTrash(entry);
    if (!mounted) return;
    AppFeedback.action(
      context,
      context.l10n.movedToTrash,
      actionLabel: context.l10n.undo,
      onAction: () => provider.restore(entry),
    );
  }

  Future<void> _deleteForever(NoteEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.deletePermanentlyQuestion),
        content: Text(context.l10n.deletePermanentlyDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.deletePermanently),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<NoteProvider>().deletePermanently(entry);
    }
  }

  void _showCaptureSheet() {
    final l10n = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.captureMoment,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.capturePrivacyHint,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  final textScale = MediaQuery.textScalerOf(context).scale(1);
                  final columns = constraints.maxWidth < 330 || textScale > 1.6
                      ? 3
                      : 4;
                  const spacing = 10.0;
                  final itemWidth =
                      (constraints.maxWidth - spacing * (columns - 1)) /
                      columns;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: 16,
                    children: [
                      _CaptureAction(
                        Icons.edit_note_rounded,
                        l10n.note,
                        AppColors.moss,
                        () => _afterSheetClose(sheetContext, _createTextNote),
                        width: itemWidth,
                      ),
                      _CaptureAction(
                        Icons.camera_alt_rounded,
                        l10n.photo,
                        const Color(0xFF9B654E),
                        () => _afterSheetClose(sheetContext, _takePhoto),
                        width: itemWidth,
                      ),
                      _CaptureAction(
                        Icons.image_rounded,
                        l10n.image,
                        const Color(0xFF9B654E),
                        () => _afterSheetClose(sheetContext, _pickImage),
                        width: itemWidth,
                      ),
                      _CaptureAction(
                        Icons.mic_rounded,
                        l10n.record,
                        const Color(0xFFA66742),
                        () => _afterSheetClose(sheetContext, _openRecorder),
                        width: itemWidth,
                      ),
                      _CaptureAction(
                        Icons.audio_file_rounded,
                        l10n.audio,
                        const Color(0xFFA66742),
                        () => _afterSheetClose(sheetContext, _pickAudio),
                        width: itemWidth,
                      ),
                      _CaptureAction(
                        Icons.video_file_rounded,
                        l10n.video,
                        const Color(0xFFA94F46),
                        () => _afterSheetClose(sheetContext, _pickVideo),
                        width: itemWidth,
                      ),
                      _CaptureAction(
                        Icons.upload_file_rounded,
                        l10n.file,
                        const Color(0xFF986047),
                        () => _afterSheetClose(sheetContext, _pickDocument),
                        width: itemWidth,
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _afterSheetClose(BuildContext sheetContext, VoidCallback action) {
    Navigator.pop(sheetContext);
    Future<void>.delayed(const Duration(milliseconds: 260), action);
  }

  void _createTextNote() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const NoteEditorPage()),
  );

  Future<void> _openRecorder() async {
    final attachment = await Navigator.push<NoteAttachment>(
      context,
      MaterialPageRoute(
        builder: (_) => const RecordAudioPage(returnAttachment: true),
      ),
    );
    if (!mounted) return;
    if (attachment != null) {
      await _createNoteWithAttachments(context.l10n.voiceNote, [attachment]);
    }
  }

  Future<void> _pickImage() async {
    await _startAttachmentImport(NoteType.image);
  }

  Future<void> _takePhoto() async {
    await _startAttachmentImport(NoteType.image, camera: true);
  }

  Future<void> _pickVideo() => _startAttachmentImport(NoteType.video);

  Future<void> _pickAudio() => _startAttachmentImport(NoteType.audio);

  Future<void> _pickDocument() => _startAttachmentImport(NoteType.document);

  Future<void> _startAttachmentImport(
    NoteType type, {
    bool camera = false,
  }) async {
    try {
      final provider = context.read<NoteProvider>();
      final jobs = await provider.startAttachmentImport(type, camera: camera);
      if (jobs.isEmpty || !mounted || jobs.first.noteId == null) return;
      final entry = provider.getEntryById(jobs.first.noteId!);
      if (entry == null) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NoteEditorPage(
            existingEntry: entry,
            initialImportJobIds: jobs.map((job) => job.id).toList(),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error is PlatformException
          ? error.message ??
                context.l10n.importFailed(_noteTypeLabel(context.l10n, type))
          : error.toString();
      AppFeedback.error(context, message);
    }
  }

  Future<void> _createNoteWithAttachments(
    String title,
    List<NoteAttachment> attachments,
  ) async {
    if (attachments.isEmpty || !mounted) return;
    final provider = context.read<NoteProvider>();
    final now = DateTime.now();
    final id = await provider.addEntry(
      NoteEntry(
        type: attachments.first.type,
        title: title,
        attachments: attachments,
        createdAt: now,
        updatedAt: now,
      ),
    );
    if (!mounted) return;
    final entry = provider.getEntryById(id);
    if (entry != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => NoteEditorPage(existingEntry: entry)),
      );
    }
  }
}

typedef NoteBuilder = Widget Function(NoteEntry entry, {bool compact});

class _OverviewTab extends StatelessWidget {
  final NoteProvider provider;
  final VoidCallback onSearch;
  final VoidCallback onOpenAssistant;
  final VoidCallback onOpenLibrary;
  final VoidCallback onCreateText;
  final VoidCallback onPickImage;
  final VoidCallback onRecordAudio;
  final VoidCallback onPickDocument;
  final NoteBuilder noteBuilder;

  const _OverviewTab({
    required this.provider,
    required this.onSearch,
    required this.onOpenAssistant,
    required this.onOpenLibrary,
    required this.onCreateText,
    required this.onPickImage,
    required this.onRecordAudio,
    required this.onPickDocument,
    required this.noteBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final entries = provider.recentlyUpdatedEntries;
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: provider.loadEntries,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              sliver: SliverList.list(
                children: [
                  _BrandHeader(onAssistant: onOpenAssistant),
                  const SizedBox(height: 22),
                  _SearchButton(onTap: onSearch),
                  const SizedBox(height: 28),
                  _LocalHero(provider: provider),
                  const SizedBox(height: 18),
                  _QuickActions(
                    onCreateText: onCreateText,
                    onPickImage: onPickImage,
                    onRecordAudio: onRecordAudio,
                    onPickDocument: onPickDocument,
                  ),
                  const SizedBox(height: 30),
                  _SectionHeader(
                    title: context.l10n.recentlyUpdated,
                    action: entries.isEmpty ? null : context.l10n.more,
                    onTap: onOpenLibrary,
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
            if (provider.isLoading && entries.isEmpty)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (entries.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverToBoxAdapter(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.auto_awesome_rounded,
                          color: AppColors.moss,
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.l10n.startWithIdea,
                                style: const TextStyle(
                                  fontFamily: 'serif',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                context.l10n.createNoteEmptyHint,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList.separated(
                  itemCount: entries.take(5).length,
                  itemBuilder: (_, index) =>
                      noteBuilder(entries[index], compact: true),
                  separatorBuilder: (_, _) => const Divider(height: 1),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 150)),
          ],
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  final VoidCallback onAssistant;
  const _BrandHeader({required this.onAssistant});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      const BrandMark(size: 48),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.appTitle,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: .2,
              ),
            ),
            Text(
              context.l10n.appTagline,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      IconButton.filledTonal(
        key: const Key('open-local-chat'),
        tooltip: context.l10n.localAssistant,
        onPressed: onAssistant,
        style: IconButton.styleFrom(
          backgroundColor: AppColors.softGreen,
          foregroundColor: AppColors.moss,
        ),
        icon: const Icon(Icons.auto_awesome_rounded),
      ),
    ],
  );
}

class _SearchButton extends StatelessWidget {
  final VoidCallback onTap;
  const _SearchButton({required this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: context.l10n.searchLocalKnowledge,
    onTap: onTap,
    excludeSemantics: true,
    child: Material(
      color: AppColors.softAmber,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, color: AppColors.muted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.l10n.searchNotes,
                  style: const TextStyle(color: AppColors.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _LocalHero extends StatelessWidget {
  final NoteProvider provider;
  const _LocalHero({required this.provider});
  @override
  Widget build(BuildContext context) {
    final adaptiveStats =
        MediaQuery.sizeOf(context).width < 380 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.4;
    final localOnly = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.verified_user_outlined,
          size: 17,
          color: AppColors.moss,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            context.l10n.savedOnlyOnDevice,
            maxLines: 2,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.allNotes,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 18),
        if (adaptiveStats)
          Wrap(
            spacing: 24,
            runSpacing: 14,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _OverviewStat(
                '${provider.activeEntries.length}',
                context.l10n.noteCountShort(provider.activeEntries.length),
                labelIncludesValue: true,
              ),
              _OverviewStat(
                '${provider.attachmentCount}',
                context.l10n.attachmentCountShort(provider.attachmentCount),
                labelIncludesValue: true,
              ),
              localOnly,
            ],
          )
        else
          IntrinsicHeight(
            child: Row(
              children: [
                _OverviewStat(
                  '${provider.activeEntries.length}',
                  context.l10n.noteCountShort(provider.activeEntries.length),
                  labelIncludesValue: true,
                ),
                const VerticalDivider(width: 28),
                _OverviewStat(
                  '${provider.attachmentCount}',
                  context.l10n.attachmentCountShort(provider.attachmentCount),
                  labelIncludesValue: true,
                ),
                const VerticalDivider(width: 28),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.verified_user_outlined,
                          size: 17,
                          color: AppColors.moss,
                        ),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            context.l10n.savedOnlyOnDevice,
                            maxLines: 2,
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 20),
        const Divider(),
      ],
    );
  }
}

class _OverviewStat extends StatelessWidget {
  final String value;
  final String label;
  final bool labelIncludesValue;
  const _OverviewStat(
    this.value,
    this.label, {
    this.labelIncludesValue = false,
  });

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(
        value,
        style: const TextStyle(
          color: AppColors.moss,
          fontFamily: 'serif',
          fontSize: 28,
          height: 1,
          fontWeight: FontWeight.w500,
        ),
      ),
      const SizedBox(width: 5),
      Text(
        labelIncludesValue ? label.replaceFirst(value, '').trim() : label,
        style: const TextStyle(
          color: AppColors.muted,
          fontSize: 12,
          height: 1.35,
        ),
      ),
    ],
  );
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onTap;
  const _SectionHeader({required this.title, this.action, this.onTap});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      if (action != null)
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.only(left: 12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                action!,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right_rounded, size: 17),
            ],
          ),
        ),
    ],
  );
}

class _QuickActions extends StatelessWidget {
  final VoidCallback onCreateText;
  final VoidCallback onPickImage;
  final VoidCallback onRecordAudio;
  final VoidCallback onPickDocument;

  const _QuickActions({
    required this.onCreateText,
    required this.onPickImage,
    required this.onRecordAudio,
    required this.onPickDocument,
  });

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 78),
    child: IntrinsicHeight(
      child: Row(
        children: [
          Expanded(
            child: _QuickAction(
              icon: Icons.notes_rounded,
              label: context.l10n.note,
              onTap: onCreateText,
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _QuickAction(
              icon: Icons.image_outlined,
              label: context.l10n.image,
              onTap: onPickImage,
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _QuickAction(
              icon: Icons.mic_none_rounded,
              label: context.l10n.record,
              onTap: onRecordAudio,
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _QuickAction(
              icon: Icons.description_outlined,
              label: context.l10n.file,
              onTap: onPickDocument,
            ),
          ),
        ],
      ),
    ),
  );
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: context.l10n.createType(label),
    onTap: onTap,
    excludeSemantics: true,
    child: Material(
      color: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.ink, size: 25),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'serif',
                  fontSize: 13,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _LibraryTab extends StatelessWidget {
  final NoteProvider provider;
  final VoidCallback onSearch;
  final NoteBuilder noteBuilder;
  const _LibraryTab({
    required this.provider,
    required this.onSearch,
    required this.noteBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final entries = provider.entries;
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _scopeTitle(context.l10n, provider.scope),
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: -.4,
                            ),
                      ),
                      Text(
                        context.l10n.itemCount(entries.length),
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: onSearch,
                  icon: const Icon(Icons.search_rounded),
                  tooltip: context.l10n.search,
                ),
                if (provider.scope == NoteScope.trash &&
                    provider.trashCount > 0)
                  IconButton(
                    tooltip: context.l10n.emptyTrash,
                    onPressed: () => _confirmEmptyTrash(context),
                    icon: const Icon(Icons.delete_sweep_outlined),
                  ),
                AppAnchoredMenuButton<NoteSort>(
                  tooltip: context.l10n.sort,
                  icon: const Icon(Icons.swap_vert_rounded),
                  onSelected: provider.setSort,
                  actions: [
                    AppMenuAction(
                      value: NoteSort.updated,
                      icon: Icons.update_rounded,
                      label: context.l10n.recentlyUpdated,
                      selected: provider.sort == NoteSort.updated,
                    ),
                    AppMenuAction(
                      value: NoteSort.created,
                      icon: Icons.schedule_rounded,
                      label: context.l10n.creationTime,
                      selected: provider.sort == NoteSort.created,
                    ),
                    AppMenuAction(
                      value: NoteSort.title,
                      icon: Icons.sort_by_alpha_rounded,
                      label: context.l10n.title,
                      selected: provider.sort == NoteSort.title,
                    ),
                    AppMenuAction(
                      value: NoteSort.size,
                      icon: Icons.data_usage_rounded,
                      label: context.l10n.fileSize,
                      selected: provider.sort == NoteSort.size,
                    ),
                  ],
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 46),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _ScopeChip(
                    context.l10n.all,
                    provider.scope == NoteScope.active,
                    () => provider.setScope(NoteScope.active),
                  ),
                  _ScopeChip(
                    context.l10n.favorites,
                    provider.scope == NoteScope.favorites,
                    () => provider.setScope(NoteScope.favorites),
                  ),
                  _ScopeChip(
                    context.l10n.archive,
                    provider.scope == NoteScope.archived,
                    () => provider.setScope(NoteScope.archived),
                  ),
                  _ScopeChip(
                    context.l10n.trash,
                    provider.scope == NoteScope.trash,
                    () => provider.setScope(NoteScope.trash),
                  ),
                ],
              ),
            ),
          ),
          if (provider.scope == NoteScope.active ||
              provider.scope == NoteScope.favorites)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _TypeChip(null, provider),
                    for (final type in NoteType.values)
                      _TypeChip(type, provider),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 6),
          Expanded(
            child: provider.isLoading && entries.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : entries.isEmpty
                ? EmptyState(
                    icon: _scopeIcon(provider.scope),
                    message: _emptyMessage(context.l10n, provider.scope),
                    alignment: const Alignment(0, -0.32),
                  )
                : RefreshIndicator(
                    onRefresh: provider.loadEntries,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 150),
                      itemCount: entries.length,
                      itemBuilder: (_, index) => noteBuilder(entries[index]),
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  static String _scopeTitle(AppLocalizations l10n, NoteScope scope) =>
      switch (scope) {
        NoteScope.active => l10n.library,
        NoteScope.favorites => l10n.favorites,
        NoteScope.archived => l10n.archive,
        NoteScope.trash => l10n.trash,
      };
  static IconData _scopeIcon(NoteScope scope) => switch (scope) {
    NoteScope.active => Icons.folder_open_rounded,
    NoteScope.favorites => Icons.star_outline_rounded,
    NoteScope.archived => Icons.archive_outlined,
    NoteScope.trash => Icons.delete_outline_rounded,
  };
  static String _emptyMessage(AppLocalizations l10n, NoteScope scope) =>
      switch (scope) {
        NoteScope.active => l10n.emptyActive,
        NoteScope.favorites => l10n.emptyFavorites,
        NoteScope.archived => l10n.emptyArchive,
        NoteScope.trash => l10n.emptyTrashDescription,
      };

  Future<void> _confirmEmptyTrash(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.emptyTrashQuestion),
        content: Text(context.l10n.emptyTrashConfirmation(provider.trashCount)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.clear),
          ),
        ],
      ),
    );
    if (ok == true) await provider.emptyTrash();
  }
}

class _ScopeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ScopeChip(this.label, this.selected, this.onTap);
  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
    ),
    child: Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        pressElevation: 0,
        chipAnimationStyle: ChipAnimationStyle(
          selectAnimation: AnimationStyle.noAnimation,
        ),
        onSelected: (_) => onTap(),
      ),
    ),
  );
}

class _TypeChip extends StatelessWidget {
  final NoteType? type;
  final NoteProvider provider;
  const _TypeChip(this.type, this.provider);
  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
    ),
    child: Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(
          type == null
              ? context.l10n.allTypes
              : _noteTypeLabel(context.l10n, type!),
        ),
        avatar: type == null
            ? null
            : Icon(
                NoteCard.iconForType(type!),
                size: 16,
                color: provider.typeFilter == type
                    ? AppColors.moss
                    : AppColors.muted,
              ),
        selected: provider.typeFilter == type,
        showCheckmark: false,
        pressElevation: 0,
        chipAnimationStyle: ChipAnimationStyle(
          selectAnimation: AnimationStyle.noAnimation,
          avatarDrawerAnimation: AnimationStyle.noAnimation,
        ),
        onSelected: (_) => provider.setTypeFilter(type),
      ),
    ),
  );
}

class _DataTab extends StatefulWidget {
  final NoteProvider provider;
  const _DataTab({required this.provider});
  @override
  State<_DataTab> createState() => _DataTabState();
}

class _DataTabState extends State<_DataTab> {
  int? _actualSize;
  AppBuildMetadata? _appBuildMetadata;

  @override
  void initState() {
    super.initState();
    _refreshSize();
    _loadAppMetadata();
  }

  @override
  void didUpdateWidget(covariant _DataTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refreshSize();
  }

  Future<void> _refreshSize() async {
    final size = await FileStorageService.instance.userDataSize();
    if (mounted) setState(() => _actualSize = size);
  }

  Future<void> _loadAppMetadata() async {
    try {
      final metadata = await AppBuildMetadata.load();
      if (!mounted) return;
      setState(() => _appBuildMetadata = metadata);
    } catch (_) {
      if (mounted) {
        setState(
          () => _appBuildMetadata = const AppBuildMetadata(
            version: '',
            buildNumber: '',
            buildTime: null,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appLock = context.watch<AppLockController>();
    final localeController = context.watch<AppLocaleController>();
    final l10n = context.l10n;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 140),
        children: [
          Text(
            l10n.localData,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.localDataSubtitle,
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.softGreen,
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(
                          Icons.verified_user_outlined,
                          size: 19,
                          color: AppColors.moss,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              l10n.localFirst,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.ink,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            l10n.offlineSecure,
                            maxLines: 1,
                            style: const TextStyle(
                              color: AppColors.moss,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(height: 1, thickness: 1, color: AppColors.line),
                const SizedBox(height: 9),
                Row(
                  children: [
                    _DataStat(
                      '${widget.provider.allEntries.length}',
                      l10n.totalItems,
                      alignment: Alignment.centerLeft,
                    ),
                    _DataStat(
                      '${widget.provider.attachmentCount}',
                      l10n.attachments,
                    ),
                    _DataStat(
                      _formatBytes(
                        _actualSize ?? widget.provider.totalFileSize,
                      ),
                      l10n.userDataUsage,
                      alignment: Alignment.centerRight,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text(
            l10n.tasksAndActivity,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          AnimatedBuilder(
            animation: BackgroundTaskCenter.instance,
            builder: (context, _) {
              final center = BackgroundTaskCenter.instance;
              final hasTasks = center.items.isNotEmpty;
              return _SettingCard(
                children: [
                  _SettingRow(
                    key: const Key('open-background-tasks'),
                    icon: center.failedCount > 0
                        ? Icons.error_outline_rounded
                        : center.activeCount > 0
                        ? Icons.sync_rounded
                        : Icons.task_alt_rounded,
                    title: l10n.backgroundTasks,
                    subtitle: hasTasks
                        ? l10n.backgroundTaskSummary(
                            center.activeCount,
                            center.failedCount,
                          )
                        : l10n.noBackgroundTasks,
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            BackgroundTasksPage(provider: widget.provider),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 22),
          Text(
            l10n.preferences,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _SettingCard(
            children: [
              _SettingRow(
                icon: Icons.language_rounded,
                title: l10n.language,
                subtitle: _appLanguageTitle(l10n, localeController.language),
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LanguageSettingsPage(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            l10n.unifiedStorage,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _SettingCard(
            children: [
              _SettingRow(
                icon: Icons.cloud_sync_outlined,
                title: l10n.cloudSync,
                subtitle: l10n.cloudSyncSubtitle,
                onTap: _openCloudSync,
              ),
              const Divider(height: 1),
              _SettingRow(
                icon: Icons.memory_rounded,
                title: l10n.localModels,
                subtitle: l10n.localModelsSubtitle,
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ModelManagementPage(),
                    ),
                  );
                  await _refreshSize();
                },
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            l10n.backupAndMigration,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _SettingCard(
            children: [
              _SettingRow(
                icon: Icons.ios_share_rounded,
                title: l10n.exportCompleteBackup,
                subtitle: l10n.exportCompleteBackupSubtitle,
                onTap: _openBackupExport,
              ),
              const Divider(height: 1),
              _SettingRow(
                icon: Icons.settings_backup_restore_rounded,
                title: l10n.restoreFromBackup,
                subtitle: l10n.restoreFromBackupSubtitle,
                onTap: _openBackupRestore,
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            l10n.organizationAndSecurity,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _SettingCard(
            children: [
              _SettingRow(
                icon: Icons.lock_outline_rounded,
                title: l10n.appLock,
                subtitle: appLock.enabled
                    ? l10n.appLockEnabledSubtitle(
                        _appLockTimeoutLabel(l10n, appLock.timeout),
                      )
                    : l10n.appLockDisabledSubtitle,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AppLockSettingsPage(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            l10n.about,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _SettingCard(
            children: [
              _SettingRow(
                icon: Icons.info_outline_rounded,
                title: l10n.appTitle,
                subtitle: _appBuildMetadata == null
                    ? l10n.loadingVersion
                    : _buildMetadataSubtitle(l10n, _appBuildMetadata!),
                showChevron: false,
              ),
              if (kDebugMode) ...[
                const Divider(height: 1),
                _SettingRow(
                  icon: Icons.bug_report_outlined,
                  title: '调试中心 · Debug',
                  subtitle: '实时日志、异常堆栈与脱敏诊断包',
                  onTap: () => openDebugConsole(context),
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              l10n.footerTagline,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openBackupExport() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const BackupExportPage()),
    );
    await _refreshSize();
  }

  Future<void> _openCloudSync() async {
    final restored = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CloudSyncPage()),
    );
    if (restored == true) await widget.provider.loadEntries();
    await _refreshSize();
  }

  Future<void> _openBackupRestore() async {
    final restored = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const BackupRestorePage()),
    );
    if (restored == true) {
      await widget.provider.loadEntries();
      await _refreshSize();
      if (mounted) {
        AppFeedback.success(context, context.l10n.backupRestored);
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }
}

String _appLanguageTitle(AppLocalizations l10n, AppLanguage language) =>
    switch (language) {
      AppLanguage.system => l10n.languageSystem,
      AppLanguage.simplifiedChinese => l10n.languageSimplifiedChinese,
      AppLanguage.english => l10n.languageEnglish,
    };

String _noteTypeLabel(AppLocalizations l10n, NoteType type) => switch (type) {
  NoteType.text => l10n.note,
  NoteType.image => l10n.image,
  NoteType.audio => l10n.audio,
  NoteType.video => l10n.video,
  NoteType.document => l10n.file,
};

String _appLockTimeoutLabel(AppLocalizations l10n, AppLockTimeout timeout) =>
    switch (timeout) {
      AppLockTimeout.immediately => l10n.lockImmediately,
      AppLockTimeout.oneMinute => l10n.lockAfterOneMinute,
      AppLockTimeout.fiveMinutes => l10n.lockAfterFiveMinutes,
      AppLockTimeout.fifteenMinutes => l10n.lockAfterFifteenMinutes,
    };

String _buildMetadataSubtitle(
  AppLocalizations l10n,
  AppBuildMetadata metadata,
) {
  if (metadata.version.isEmpty) return l10n.unavailable;
  final version = metadata.buildNumber.isEmpty
      ? l10n.versionNumber(metadata.version)
      : l10n.versionNumberWithBuild(metadata.version, metadata.buildNumber);
  final time = metadata.buildTime == null
      ? l10n.buildTimeUnrecorded
      : l10n.buildTime(
          DateFormat.yMd(l10n.localeName).add_Hm().format(metadata.buildTime!),
        );
  return '$version\n$time';
}

class _DataStat extends StatelessWidget {
  final String value;
  final String label;
  final AlignmentGeometry alignment;
  const _DataStat(this.value, this.label, {this.alignment = Alignment.center});
  @override
  Widget build(BuildContext context) => Expanded(
    child: Align(
      alignment: alignment,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            height: 24,
            child: Text(
              value,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 3),
          SizedBox(
            height: 17,
            child: Text(
              label,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SettingCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingCard({required this.children});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.surface,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(children: children),
  );
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool showChevron;
  const _SettingRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.showChevron = true,
  });
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.softGreen,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: AppColors.moss, size: 20),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          if (showChevron)
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
        ],
      ),
    ),
  );
}

class _CaptureAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final double width;
  const _CaptureAction(
    this.icon,
    this.label,
    this.color,
    this.onTap, {
    required this.width,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Semantics(
      button: true,
      label: context.l10n.createType(label),
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: color, size: 27),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
