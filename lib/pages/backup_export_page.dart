import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import '../services/backup_service.dart';
import '../widgets/app_feedback.dart';
import '../widgets/backup_record_card.dart';
import '../widgets/empty_state.dart';

class BackupExportPage extends StatefulWidget {
  const BackupExportPage({super.key});

  @override
  State<BackupExportPage> createState() => _BackupExportPageState();
}

class _BackupExportPageState extends State<BackupExportPage> {
  final _service = BackupService.instance;
  final _label = TextEditingController();
  final _description = TextEditingController();
  List<BackupRecord> _records = const [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _label.dispose();
    _description.dispose();
    super.dispose();
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
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: l10n.back,
            onPressed: _busy ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Text(l10n.exportCompleteBackup),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
          children: [
            _BackupScopeCard(message: l10n.backupScopeDescription),
            const SizedBox(height: 24),
            _sectionTitle(l10n.createNewBackup),
            const SizedBox(height: 10),
            Material(
              color: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: AppColors.line),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      key: const Key('backup-label-field'),
                      controller: _label,
                      enabled: !_busy,
                      maxLength: 40,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: l10n.backupName,
                        hintText: l10n.backupNameHint,
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('backup-description-field'),
                      controller: _description,
                      enabled: !_busy,
                      maxLength: 240,
                      minLines: 2,
                      maxLines: 4,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: l10n.backupDescription,
                        hintText: l10n.backupDescriptionHint,
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const Key('create-managed-backup'),
                        onPressed: _busy ? null : _create,
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.add_to_drive_outlined),
                        label: Text(
                          _busy ? l10n.creatingBackup : l10n.createBackup,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.backupStoredLocally,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            _sectionTitle(l10n.backupHistory),
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
                  key: Key('backup-record-${_records[index].fileName}'),
                  record: _records[index],
                  enabled: !_busy,
                  onDetails: () =>
                      showBackupDetailsDialog(context, _records[index]),
                  onShare: () => _share(_records[index]),
                  onSaveCopy: () => _saveCopy(_records[index]),
                  onDelete: () => _delete(_records[index]),
                ),
                if (index != _records.length - 1) const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String value) => Text(
    value,
    style: Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
  );

  Future<void> _create() async {
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await _service.createManagedBackup(
        label: _label.text,
        description: _description.text,
      );
      _label.clear();
      _description.clear();
      await _load();
      if (mounted) {
        AppFeedback.success(context, context.l10n.backupSavedDefault);
      }
    } catch (error) {
      if (mounted) {
        AppFeedback.error(context, context.l10n.exportFailed('$error'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(BackupRecord record) async {
    setState(() => _busy = true);
    try {
      final size = MediaQuery.sizeOf(context);
      final shared = await _service.shareManagedBackup(
        record,
        sharePositionOrigin: Rect.fromLTWH(
          size.width / 2,
          size.height / 2,
          1,
          1,
        ),
      );
      if (shared && mounted) {
        AppFeedback.success(context, context.l10n.backupExported);
      }
    } catch (error) {
      if (mounted) {
        AppFeedback.error(context, context.l10n.exportFailed('$error'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveCopy(BackupRecord record) async {
    setState(() => _busy = true);
    try {
      final saved = await _service.saveManagedBackupCopy(record);
      if (saved && mounted) {
        AppFeedback.success(context, context.l10n.backupCopySaved);
      }
    } catch (error) {
      if (mounted) {
        AppFeedback.error(context, context.l10n.exportFailed('$error'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(BackupRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.deleteBackupQuestion),
        content: Text(context.l10n.deleteBackupDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.deleteBackup),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _service.deleteManagedBackup(record);
      await _load();
      if (mounted) AppFeedback.success(context, context.l10n.backupDeleted);
    } catch (error) {
      if (mounted) {
        AppFeedback.error(context, context.l10n.exportFailed('$error'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _BackupScopeCard extends StatelessWidget {
  final String message;

  const _BackupScopeCard({required this.message});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.softGreen,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.verified_user_outlined, color: AppColors.moss),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: AppColors.muted, height: 1.5),
          ),
        ),
      ],
    ),
  );
}
