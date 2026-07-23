import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../debug/debug_console_launcher.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n.dart';
import '../models/local_chat.dart';
import '../models/note.dart';
import '../providers/app_lock_controller.dart';
import '../providers/app_locale_controller.dart';
import '../providers/note_library_controller.dart';
import '../services/app_build_metadata.dart';
import '../services/app_lock_preferences_service.dart';
import '../services/file_storage_service.dart';
import '../services/note_database_service.dart';
import '../widgets/app_feedback.dart';
import '../widgets/brand_mark.dart';
import '../widgets/navigation_icons.dart';
import '../widgets/note_delta_preview.dart';
import 'app_lock_settings_page.dart';
import 'backup_export_page.dart';
import 'backup_restore_page.dart';
import 'cloud_sync_page.dart';
import 'language_settings_page.dart';
import 'local_chat_page.dart';
import 'model_management_page.dart';
import 'note_library_page.dart';
import 'note_quill_editor_page.dart';

typedef NoteHomeDataSizeLoader = Future<int> Function();
typedef NoteHomeNoteLoader = Future<Note?> Function(NoteId id);
typedef NoteHomeAssistantBuilder =
    Widget Function(BuildContext context, LocalChatNoteOpener onOpenNote);

/// Primary application shell for the clean Delta note system.
///
/// It owns no compatibility provider or secondary note database. All note
/// entry points converge on [NoteQuillEditorPage].
final class QuillHomePage extends StatefulWidget {
  const QuillHomePage({
    this.recentController,
    this.libraryController,
    this.editorBuilder,
    this.assistantBuilder,
    this.noteLoader,
    this.dataSizeLoader,
    super.key,
  });

  final NoteLibraryController? recentController;
  final NoteLibraryController? libraryController;
  final NoteLibraryEditorBuilder? editorBuilder;
  final NoteHomeAssistantBuilder? assistantBuilder;
  final NoteHomeNoteLoader? noteLoader;
  final NoteHomeDataSizeLoader? dataSizeLoader;

  @override
  State<QuillHomePage> createState() => _QuillHomePageState();
}

final class _QuillHomePageState extends State<QuillHomePage> {
  late final NoteLibraryController _recentController;
  late final NoteLibraryController _libraryController;
  late final bool _ownsRecentController;
  late final bool _ownsLibraryController;
  var _tab = 0;

  @override
  void initState() {
    super.initState();
    _ownsRecentController = widget.recentController == null;
    _ownsLibraryController = widget.libraryController == null;
    _recentController = widget.recentController ?? NoteLibraryController();
    _libraryController = widget.libraryController ?? NoteLibraryController();
    _recentController.addListener(_onRecentChanged);
    unawaited(_recentController.initialize());
  }

  void _onRecentChanged() {
    if (mounted) setState(() {});
  }

  void _selectTab(int value) {
    if (_tab == value) return;
    setState(() => _tab = value);
    if (value == 0) unawaited(_recentController.refresh());
  }

  Future<void> _openEditor([Note? note]) async {
    final builder =
        widget.editorBuilder ??
        (context, value) => NoteQuillEditorPage(initialNote: value);
    await Navigator.push<Note?>(
      context,
      MaterialPageRoute(builder: (context) => builder(context, note)),
    );
    if (mounted) await _recentController.refresh();
  }

  Future<void> _openAssistant() async {
    final builder =
        widget.assistantBuilder ??
        (context, onOpenNote) => LocalChatPage(onOpenNote: onOpenNote);
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => builder(context, _openAssistantSource),
      ),
    );
    if (mounted) await _recentController.refresh();
  }

  Future<void> _openAssistantSource(LocalChatNoteContext source) async {
    final loader =
        widget.noteLoader ??
        (id) async => (await NoteDatabaseService.instance.repository).get(id);
    final note = await loader(source.noteId);
    if (!mounted) return;
    if (note == null || note.status == NoteStatus.trashed) {
      AppFeedback.error(context, context.l10n.toolActionTargetMissing);
      return;
    }
    await _openEditor(note);
  }

  Future<void> _refreshAfterRestore() async {
    await _recentController.refresh();
    if (!identical(_recentController, _libraryController)) {
      await _libraryController.refresh();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBody: true,
    body: IndexedStack(
      index: _tab,
      children: [
        _QuillOverviewTab(
          controller: _recentController,
          onCreate: _openEditor,
          onOpenNote: _openEditor,
          onOpenAssistant: _openAssistant,
          onOpenLibrary: () => _selectTab(1),
        ),
        NoteLibraryPage(
          controller: _libraryController,
          editorBuilder: widget.editorBuilder,
        ),
        _QuillDataTab(
          controller: _recentController,
          dataSizeLoader:
              widget.dataSizeLoader ?? FileStorageService.instance.userDataSize,
          onRestoreCompleted: _refreshAfterRestore,
        ),
      ],
    ),
    floatingActionButton: _tab == 0
        ? FloatingActionButton(
            key: const Key('quill-home-new-note'),
            heroTag: null,
            tooltip: context.l10n.newNote,
            onPressed: _openEditor,
            child: const Icon(Icons.add_rounded),
          )
        : null,
    bottomNavigationBar: SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.all(Radius.circular(22)),
          boxShadow: AppShadows.floating,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: _selectTab,
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.home_outlined),
                selectedIcon: const Icon(Icons.home_rounded),
                label: context.l10n.home,
              ),
              NavigationDestination(
                icon: const LibrarySpinesIcon(),
                selectedIcon: const LibrarySpinesIcon(),
                label: context.l10n.library,
              ),
              NavigationDestination(
                icon: const Icon(Icons.pie_chart_outline_rounded),
                selectedIcon: const Icon(Icons.pie_chart_rounded),
                label: context.l10n.data,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _recentController.removeListener(_onRecentChanged);
    if (_ownsRecentController) _recentController.dispose();
    if (_ownsLibraryController) _libraryController.dispose();
    super.dispose();
  }
}

final class _QuillOverviewTab extends StatelessWidget {
  const _QuillOverviewTab({
    required this.controller,
    required this.onCreate,
    required this.onOpenNote,
    required this.onOpenAssistant,
    required this.onOpenLibrary,
  });

  final NoteLibraryController controller;
  final VoidCallback onCreate;
  final ValueChanged<Note> onOpenNote;
  final VoidCallback onOpenAssistant;
  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    final recent = [...controller.notes]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: controller.refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 132),
              sliver: SliverList.list(
                children: [
                  _QuillBrandHeader(onOpenAssistant: onOpenAssistant),
                  const SizedBox(height: 26),
                  _OverviewSearch(onTap: onOpenLibrary),
                  const SizedBox(height: 30),
                  _SectionHeader(
                    title: context.l10n.recentlyUpdated,
                    actionLabel: context.l10n.library,
                    onAction: onOpenLibrary,
                  ),
                  const SizedBox(height: 12),
                  if (controller.isLoading && recent.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (recent.isEmpty)
                    _EmptyRecent(onCreate: onCreate)
                  else
                    for (final note in recent.take(5)) ...[
                      _RecentDeltaNoteCard(
                        note: note,
                        onTap: () => onOpenNote(note),
                      ),
                      const SizedBox(height: 10),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _QuillBrandHeader extends StatelessWidget {
  const _QuillBrandHeader({required this.onOpenAssistant});

  final VoidCallback onOpenAssistant;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const BrandMark(size: 36, showSurface: false),
      const SizedBox(width: 11),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.appTitle,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              context.l10n.localFirst,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      IconButton(
        key: const Key('quill-home-assistant'),
        tooltip: context.l10n.localAssistant,
        onPressed: onOpenAssistant,
        style: IconButton.styleFrom(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.ink,
          fixedSize: const Size.square(44),
        ),
        icon: const Icon(Icons.auto_awesome_outlined, size: 21),
      ),
    ],
  );
}

final class _OverviewSearch extends StatelessWidget {
  const _OverviewSearch({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceMuted,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.medium),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      key: const Key('quill-home-search'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, color: AppColors.muted, size: 21),
            const SizedBox(width: 10),
            Text(
              context.l10n.searchNotes,
              style: const TextStyle(color: AppColors.muted),
            ),
          ],
        ),
      ),
    ),
  );
}

final class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      TextButton(
        onPressed: onAction,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.muted,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(actionLabel),
            const SizedBox(width: 2),
            const Icon(Icons.arrow_forward_rounded, size: 16),
          ],
        ),
      ),
    ],
  );
}

final class _EmptyRecent extends StatelessWidget {
  const _EmptyRecent({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.large),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.note_add_outlined, size: 32, color: AppColors.subtle),
        const SizedBox(height: 10),
        Text(context.l10n.emptyActive, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        TextButton(onPressed: onCreate, child: Text(context.l10n.createNew)),
      ],
    ),
  );
}

final class _RecentDeltaNoteCard extends StatelessWidget {
  const _RecentDeltaNoteCard({required this.note, required this.onTap});

  final Note note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.large),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      key: ValueKey('quill-home-note-${note.id.value}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 17, 18, 15),
        child: Column(
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
                    note.title.trim().isEmpty
                        ? context.l10n.untitled
                        : note.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            if (!note.contentProjection.isVisuallyEmpty) ...[
              const SizedBox(height: 7),
              NoteDeltaPreview(note: note, maxLines: 2),
            ],
            const SizedBox(height: 11),
            Text(
              _recentTime(context, note.updatedAt.toLocal()),
              style: const TextStyle(
                color: AppColors.subtle,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  static String _recentTime(BuildContext context, DateTime date) {
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

final class _QuillDataTab extends StatefulWidget {
  const _QuillDataTab({
    required this.controller,
    required this.dataSizeLoader,
    required this.onRestoreCompleted,
  });

  final NoteLibraryController controller;
  final NoteHomeDataSizeLoader dataSizeLoader;
  final AsyncCallback onRestoreCompleted;

  @override
  State<_QuillDataTab> createState() => _QuillDataTabState();
}

final class _QuillDataTabState extends State<_QuillDataTab> {
  int? _dataSize;
  AppBuildMetadata? _metadata;

  @override
  void initState() {
    super.initState();
    unawaited(_loadDataSize());
    unawaited(_loadMetadata());
  }

  Future<void> _loadDataSize() async {
    int? value;
    try {
      value = await widget.dataSizeLoader();
    } catch (_) {
      value = null;
    }
    if (mounted) setState(() => _dataSize = value);
  }

  Future<void> _loadMetadata() async {
    AppBuildMetadata metadata;
    try {
      metadata = await AppBuildMetadata.load();
    } catch (_) {
      metadata = const AppBuildMetadata(
        version: '',
        buildNumber: '',
        buildTime: null,
      );
    }
    if (mounted) setState(() => _metadata = metadata);
  }

  @override
  Widget build(BuildContext context) {
    final appLock = context.watch<AppLockController>();
    final locale = context.watch<AppLocaleController>();
    final notes = widget.controller.notes;
    final attachmentCount = notes.fold<int>(
      0,
      (total, note) => total + note.assets.length,
    );
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 132),
        children: [
          Text(
            context.l10n.localData,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.localDataSubtitle,
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 24),
          _DataSummary(
            noteCount: notes.length,
            attachmentCount: attachmentCount,
            dataSize: _dataSize,
          ),
          const SizedBox(height: 22),
          _SettingsSection(
            title: context.l10n.backupAndMigration,
            children: [
              _SettingsRow(
                icon: Icons.ios_share_rounded,
                title: context.l10n.exportCompleteBackup,
                subtitle: context.l10n.exportCompleteBackupSubtitle,
                onTap: _openBackupExport,
              ),
              const Divider(height: 1),
              _SettingsRow(
                icon: Icons.settings_backup_restore_rounded,
                title: context.l10n.restoreFromBackup,
                subtitle: context.l10n.restoreFromBackupSubtitle,
                onTap: _openBackupRestore,
              ),
              const Divider(height: 1),
              _SettingsRow(
                icon: Icons.cloud_sync_outlined,
                title: context.l10n.cloudSync,
                subtitle: context.l10n.cloudSyncSubtitle,
                onTap: _openCloudSync,
              ),
            ],
          ),
          const SizedBox(height: 22),
          _SettingsSection(
            title: context.l10n.preferences,
            children: [
              _SettingsRow(
                icon: Icons.language_rounded,
                title: context.l10n.language,
                subtitle: _languageLabel(context.l10n, locale.language),
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LanguageSettingsPage(),
                  ),
                ),
              ),
              const Divider(height: 1),
              _SettingsRow(
                icon: Icons.lock_outline_rounded,
                title: context.l10n.appLock,
                subtitle: appLock.enabled
                    ? context.l10n.appLockEnabledSubtitle(
                        _lockTimeoutLabel(context.l10n, appLock.timeout),
                      )
                    : context.l10n.appLockDisabledSubtitle,
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AppLockSettingsPage(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _SettingsSection(
            title: context.l10n.unifiedStorage,
            children: [
              _SettingsRow(
                icon: Icons.memory_rounded,
                title: context.l10n.localModels,
                subtitle: context.l10n.localModelsSubtitle,
                onTap: () async {
                  await Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ModelManagementPage(),
                    ),
                  );
                  await _loadDataSize();
                },
              ),
            ],
          ),
          const SizedBox(height: 22),
          _SettingsSection(
            title: context.l10n.about,
            children: [
              _SettingsRow(
                icon: Icons.info_outline_rounded,
                title: context.l10n.appTitle,
                subtitle: _metadata == null
                    ? context.l10n.loadingVersion
                    : _buildMetadataSubtitle(context.l10n, _metadata!),
              ),
              if (kDebugMode) ...[
                const Divider(height: 1),
                _SettingsRow(
                  icon: Icons.bug_report_outlined,
                  title: '调试中心 · Debug',
                  subtitle: '实时日志、异常堆栈与脱敏诊断包',
                  onTap: () => openDebugConsole(context),
                ),
              ],
            ],
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
    await _loadDataSize();
  }

  Future<void> _openBackupRestore() async {
    final restored = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const BackupRestorePage()),
    );
    if (restored != true) return;
    await widget.onRestoreCompleted();
    await _loadDataSize();
    if (mounted) {
      AppFeedback.success(context, context.l10n.backupRestored);
    }
  }

  Future<void> _openCloudSync() async {
    final restored = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CloudSyncPage()),
    );
    if (restored != true) return;
    await widget.onRestoreCompleted();
    await _loadDataSize();
  }
}

final class _DataSummary extends StatelessWidget {
  const _DataSummary({
    required this.noteCount,
    required this.attachmentCount,
    required this.dataSize,
  });

  final int noteCount;
  final int attachmentCount;
  final int? dataSize;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.large),
      border: Border.all(color: AppColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.all(
                  Radius.circular(AppRadius.small),
                ),
              ),
              child: SizedBox.square(
                dimension: 38,
                child: Icon(
                  Icons.shield_outlined,
                  color: AppColors.muted,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                context.l10n.localFirst,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                context.l10n.offlineSecure,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 16),
        Row(
          children: [
            _DataMetric('$noteCount', context.l10n.totalItems),
            _DataMetric('$attachmentCount', context.l10n.attachments),
            _DataMetric(
              dataSize == null ? '—' : _formatBytes(dataSize!),
              context.l10n.userDataUsage,
            ),
          ],
        ),
      ],
    ),
  );
}

final class _DataMetric extends StatelessWidget {
  const _DataMetric(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(value, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.muted, fontSize: 11),
        ),
      ],
    ),
  );
}

final class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.large),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      ),
    ],
  );
}

final class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    minTileHeight: 68,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
    leading: DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.small)),
      ),
      child: SizedBox.square(
        dimension: 38,
        child: Icon(icon, size: 20, color: AppColors.ink),
      ),
    ),
    title: Text(
      title,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
    subtitle: Text(
      subtitle,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: AppColors.muted,
        fontSize: 12,
        height: 1.35,
      ),
    ),
    trailing: onTap == null
        ? null
        : const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.subtle,
            size: 21,
          ),
    onTap: onTap,
  );
}

String _languageLabel(AppLocalizations l10n, AppLanguage language) =>
    switch (language) {
      AppLanguage.system => l10n.languageSystem,
      AppLanguage.simplifiedChinese => l10n.languageSimplifiedChinese,
      AppLanguage.english => l10n.languageEnglish,
    };

String _lockTimeoutLabel(AppLocalizations l10n, AppLockTimeout timeout) =>
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

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
}
