import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app.dart';
import '../l10n/l10n.dart';
import '../services/backup_service.dart';
import '../widgets/app_feedback.dart';
import '../widgets/backup_record_card.dart';
import '../widgets/empty_state.dart';

class BackupRestorePage extends StatefulWidget {
  const BackupRestorePage({super.key});

  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  final _service = BackupService.instance;
  List<BackupRecord> _records = const [];
  bool _loading = true;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final records = await _service.listManagedBackups();
    if (!mounted) return;
    setState(() {
      _records = records;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopScope(
      canPop: !_restoring,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 64,
          titleTextStyle: Theme.of(context).textTheme.titleLarge,
          leading: IconButton(
            tooltip: l10n.back,
            onPressed: _restoring ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Text(l10n.restoreFromBackup),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.warningSoft,
                borderRadius: BorderRadius.circular(AppRadius.large),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _restoring ? l10n.restoringBackup : l10n.restoreWarning,
                      style: const TextStyle(
                        color: AppColors.muted,
                        height: 1.5,
                      ),
                    ),
                  ),
                  if (_restoring)
                    const Padding(
                      padding: EdgeInsets.only(left: 12, top: 2),
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('choose-external-backup'),
                onPressed: _restoring ? null : _chooseExternal,
                icon: const Icon(Icons.folder_open_rounded),
                label: Text(l10n.chooseExternalBackup),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              l10n.backupHistory,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.backupHistorySubtitle,
              style: const TextStyle(color: AppColors.muted, height: 1.45),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(36),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_records.isEmpty)
              EmptyState(
                icon: Icons.inventory_2_outlined,
                message: l10n.noBackupHistory,
                alignment: const Alignment(0, -0.1),
              )
            else
              for (var index = 0; index < _records.length; index++) ...[
                BackupRecordCard(
                  key: Key('restore-backup-record-${_records[index].fileName}'),
                  record: _records[index],
                  enabled: !_restoring,
                  onDetails: () =>
                      showBackupDetailsDialog(context, _records[index]),
                  onRestore: () => _confirmAndRestore(
                    _service.managedBackupFile(_records[index]),
                    _records[index].label,
                  ),
                ),
                if (index != _records.length - 1) const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }

  Future<void> _chooseExternal() async {
    try {
      final file = await _service.chooseBackupFile();
      if (file == null || !mounted) return;
      await _confirmAndRestore(file, p.basename(file.path));
    } catch (error) {
      if (mounted) {
        AppFeedback.error(context, context.l10n.restoreFailed('$error'));
      }
    }
  }

  Future<void> _confirmAndRestore(File file, String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.restoreCompleteBackupQuestion),
        content: Text('$label\n\n${context.l10n.restoreWarning}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.restoreBackupAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _restoring = true);
    try {
      await _service.restoreBackupFile(file);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        AppFeedback.error(context, context.l10n.restoreFailed('$error'));
        setState(() => _restoring = false);
      }
    }
  }
}
