import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import '../services/backup_service.dart';
import 'app_popup_menu.dart';

enum BackupRecordMenuAction { details, delete }

class BackupRecordCard extends StatelessWidget {
  final BackupRecord record;
  final VoidCallback? onRestore;
  final VoidCallback? onShare;
  final VoidCallback? onSaveCopy;
  final VoidCallback onDetails;
  final VoidCallback? onDelete;
  final bool enabled;

  const BackupRecordCard({
    super.key,
    required this.record,
    this.onRestore,
    this.onShare,
    this.onSaveCopy,
    required this.onDetails,
    this.onDelete,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final date = DateFormat.yMMMd(
      Localizations.localeOf(context).toLanguageTag(),
    ).add_Hm().format(record.createdAt.toLocal());
    return Material(
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.large),
      ),
      child: InkWell(
        onTap: enabled ? onDetails : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.all(
                        Radius.circular(AppRadius.small),
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(9),
                      child: Icon(
                        Icons.inventory_2_outlined,
                        size: 20,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          l10n.backupDateAndSize(
                            date,
                            formatBackupBytes(record.sizeBytes),
                          ),
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AppAnchoredMenuButton<BackupRecordMenuAction>(
                    tooltip: l10n.moreActions,
                    enabled: enabled,
                    icon: const Icon(Icons.more_horiz_rounded),
                    onSelected: (action) {
                      switch (action) {
                        case BackupRecordMenuAction.details:
                          onDetails();
                        case BackupRecordMenuAction.delete:
                          onDelete?.call();
                      }
                    },
                    actions: [
                      AppMenuAction(
                        value: BackupRecordMenuAction.details,
                        icon: Icons.info_outline_rounded,
                        label: l10n.backupDetails,
                      ),
                      if (onDelete != null)
                        AppMenuAction(
                          value: BackupRecordMenuAction.delete,
                          icon: Icons.delete_outline_rounded,
                          label: l10n.deleteBackup,
                          destructive: true,
                        ),
                    ],
                  ),
                ],
              ),
              if (record.description.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  record.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, height: 1.45),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (onRestore != null)
                    FilledButton.tonalIcon(
                      onPressed: enabled ? onRestore : null,
                      icon: const Icon(Icons.settings_backup_restore_rounded),
                      label: Text(l10n.restoreBackupAction),
                    ),
                  if (onShare != null)
                    TextButton.icon(
                      onPressed: enabled ? onShare : null,
                      icon: const Icon(Icons.share_outlined),
                      label: Text(l10n.share),
                    ),
                  if (onSaveCopy != null)
                    TextButton.icon(
                      onPressed: enabled ? onSaveCopy : null,
                      icon: const Icon(Icons.save_alt_rounded),
                      label: Text(l10n.saveBackupCopy),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String formatBackupBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
}

Future<void> showBackupDetailsDialog(
  BuildContext context,
  BackupRecord record,
) async {
  final l10n = context.l10n;
  final date = DateFormat.yMMMMd(
    Localizations.localeOf(context).toLanguageTag(),
  ).add_Hms().format(record.createdAt.toLocal());
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(record.label),
      content: SingleChildScrollView(
        child: SelectionArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (record.description.isNotEmpty) ...[
                Text(record.description),
                const SizedBox(height: 18),
              ],
              _BackupDetail(label: l10n.backupCreatedAt, value: date),
              _BackupDetail(label: l10n.backupFileName, value: record.fileName),
              _BackupDetail(
                label: l10n.fileSize,
                value: formatBackupBytes(record.sizeBytes),
              ),
              _BackupDetail(
                label: l10n.backupFormat,
                value: '${record.formatVersion}',
              ),
              _BackupDetail(
                label: l10n.backupVerificationCode,
                value: record.archiveSha256,
                monospace: true,
              ),
              _BackupDetail(
                label: l10n.backupContentFingerprint,
                value: record.contentDigest,
                monospace: true,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.close),
        ),
      ],
    ),
  );
}

class _BackupDetail extends StatelessWidget {
  final String label;
  final String value;
  final bool monospace;

  const _BackupDetail({
    required this.label,
    required this.value,
    this.monospace = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            height: 1.4,
            fontFamily: monospace ? 'monospace' : null,
            fontSize: monospace ? 12 : null,
          ),
        ),
      ],
    ),
  );
}
