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
    this.controller,
    this.editorBuilder,
    this.assistantBuilder,
    this.noteLoader,
    this.dataSizeLoader,
    super.key,
  });

  final NoteLibraryController? controller;
  final NoteLibraryEditorBuilder? editorBuilder;
  final NoteHomeAssistantBuilder? assistantBuilder;
  final NoteHomeNoteLoader? noteLoader;
  final NoteHomeDataSizeLoader? dataSizeLoader;

  @override
  State<QuillHomePage> createState() => _QuillHomePageState();
}

final class _QuillHomePageState extends State<QuillHomePage> {
  late final NoteLibraryController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? NoteLibraryController();
  }

  Future<void> _openEditor([Note? note]) async {
    final builder =
        widget.editorBuilder ??
        (context, value) => NoteQuillEditorPage(initialNote: value);
    await Navigator.push<Note?>(
      context,
      MaterialPageRoute(builder: (context) => builder(context, note)),
    );
    if (mounted) await _refreshAfterRestore();
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
    if (mounted) await _refreshAfterRestore();
  }

  Future<void> _openAssistantSource(LocalChatNoteContext source) async {
    final loader =
        widget.noteLoader ??
        (id) async => (await NoteDatabaseService.instance.repository).get(id);
    final note = await loader(source.noteId);
    if (!mounted) return;
    if (note == null) {
      AppFeedback.error(context, context.l10n.toolActionTargetMissing);
      return;
    }
    await _openEditor(note);
  }

  Future<void> _refreshAfterRestore() async {
    await _controller.refresh();
  }

  Future<void> _openData() async {
    await _controller.refresh();
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (pageContext) => Scaffold(
          backgroundColor: AppColors.canvas,
          body: _QuillDataTab(
            controller: _controller,
            dataSizeLoader:
                widget.dataSizeLoader ??
                FileStorageService.instance.userDataSize,
            onRestoreCompleted: _refreshAfterRestore,
            onBack: () => Navigator.pop(pageContext),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    body: NoteLibraryPage(
      controller: _controller,
      editorBuilder: widget.editorBuilder,
      onOpenAssistant: _openAssistant,
      onOpenData: _openData,
    ),
    floatingActionButton: FloatingActionButton(
      key: const Key('quill-home-new-note'),
      heroTag: null,
      tooltip: context.l10n.newNote,
      onPressed: _openEditor,
      child: const Icon(Icons.add_rounded),
    ),
  );

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }
}

final class _QuillDataTab extends StatefulWidget {
  const _QuillDataTab({
    required this.controller,
    required this.dataSizeLoader,
    required this.onRestoreCompleted,
    required this.onBack,
  });

  final NoteLibraryController controller;
  final NoteHomeDataSizeLoader dataSizeLoader;
  final AsyncCallback onRestoreCompleted;
  final VoidCallback onBack;

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
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 48),
        children: [
          Row(
            children: [
              IconButton(
                key: const Key('quill-data-back'),
                tooltip: context.l10n.back,
                onPressed: widget.onBack,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  fixedSize: const Size.square(44),
                ),
                icon: const Icon(Icons.arrow_back_rounded, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.l10n.localData,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
