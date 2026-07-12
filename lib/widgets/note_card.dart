import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import '../models/note_entry.dart';
import '../services/file_storage_service.dart';
import 'app_popup_menu.dart';

String _localizedNoteType(BuildContext context, NoteType type) =>
    switch (type) {
      NoteType.text => context.l10n.note,
      NoteType.image => context.l10n.image,
      NoteType.audio => context.l10n.audio,
      NoteType.video => context.l10n.video,
      NoteType.document => context.l10n.file,
    };

String _localizedMetadata(BuildContext context, NoteEntry entry) {
  final items = entry.allAttachments;
  if (items.isEmpty) {
    final count = entry.plainTextContent.replaceAll('\n', '').runes.length;
    return '${context.l10n.note} · ${context.l10n.characterCount(count)}';
  }
  final types = items.map((item) => item.type).toSet();
  if (types.length > 1 || (entry.content?.trim().isNotEmpty ?? false)) {
    return context.l10n.mixedAttachmentMetadata(items.length);
  }
  return switch (types.first) {
    NoteType.image => context.l10n.imageAttachmentMetadata(items.length),
    NoteType.audio => context.l10n.audioAttachmentMetadata(items.length),
    NoteType.video => context.l10n.videoAttachmentMetadata(items.length),
    NoteType.document => context.l10n.fileAttachmentMetadata(items.length),
    NoteType.text => context.l10n.note,
  };
}

class NoteCard extends StatelessWidget {
  final NoteEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  final VoidCallback? onFavorite;
  final VoidCallback? onPin;
  final VoidCallback? onArchive;
  final VoidCallback? onRestore;
  final bool compact;

  const NoteCard({
    super.key,
    required this.entry,
    required this.onTap,
    this.onDelete,
    this.onEdit,
    this.onFavorite,
    this.onPin,
    this.onArchive,
    this.onRestore,
    this.compact = false,
  });

  static IconData iconForType(NoteType type) => switch (type) {
    NoteType.text => Icons.subject_rounded,
    NoteType.image => Icons.image_rounded,
    NoteType.audio => Icons.graphic_eq_rounded,
    NoteType.video => Icons.play_arrow_rounded,
    NoteType.document => Icons.description_rounded,
  };

  static Color colorForType(NoteType type) => switch (type) {
    NoteType.text => const Color(0xFFB9573D),
    NoteType.image => const Color(0xFF7B6758),
    NoteType.audio => const Color(0xFFA66742),
    NoteType.video => const Color(0xFFA94F46),
    NoteType.document => const Color(0xFF77665B),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final thumbnail = _thumbnailFile();
    final preview = entry.previewText.trim();
    final accent = colorForType(entry.primaryType);

    if (compact) {
      return _RecentNoteRow(
        entry: entry,
        thumbnail: thumbnail,
        accent: accent,
        onTap: onTap,
        friendlyTime: _friendlyTime(context, entry.updatedAt),
      );
    }

    final content = InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _EditorialPreviewTile(
                  entry: entry,
                  thumbnail: thumbnail,
                  accent: accent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(right: _hasActions ? 36 : 0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (entry.isPinned) ...[
                              const Padding(
                                padding: EdgeInsets.only(top: 3),
                                child: Icon(
                                  Icons.vertical_align_top_rounded,
                                  size: 15,
                                  color: AppColors.moss,
                                ),
                              ),
                              const SizedBox(width: 5),
                            ],
                            Expanded(
                              child: Text(
                                entry.title.trim().isEmpty
                                    ? context.l10n.untitled
                                    : entry.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  height: 1.25,
                                ),
                              ),
                            ),
                            if (entry.isFavorite)
                              const Padding(
                                padding: EdgeInsets.only(left: 6, top: 2),
                                child: Icon(
                                  Icons.star_rounded,
                                  size: 18,
                                  color: Color(0xFFE3A82B),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (preview.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          preview.replaceAll('\n', ' '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.4,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ] else if (entry.primaryAttachment?.fileName.isNotEmpty ==
                          true) ...[
                        const SizedBox(height: 8),
                        Text(
                          entry.primaryAttachment!.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.4,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (entry.tags.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: entry.tags
                              .take(3)
                              .map(
                                (tag) => Text(
                                  '#$tag',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: AppColors.moss,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _TypePill(
                            label: _localizedNoteType(
                              context,
                              entry.primaryType,
                            ),
                            color: accent,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _friendlyTime(context, entry.updatedAt),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 12,
                                height: 1,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_hasActions)
              Positioned(top: -12, right: -12, child: _MoreMenu(card: this)),
          ],
        ),
      ),
    );

    return Card(clipBehavior: Clip.antiAlias, child: content);
  }

  bool get _hasActions =>
      onDelete != null ||
      onFavorite != null ||
      onPin != null ||
      onArchive != null ||
      onRestore != null;

  File? _thumbnailFile() {
    final thumbnailPath = entry.primaryAttachment?.thumbnailPath;
    if (thumbnailPath == null) return null;
    final file = File(FileStorageService.instance.absolutePath(thumbnailPath));
    return file.existsSync() ? file : null;
  }

  String _friendlyTime(BuildContext context, DateTime date) {
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

class _RecentNoteRow extends StatelessWidget {
  final NoteEntry entry;
  final File? thumbnail;
  final Color accent;
  final VoidCallback onTap;
  final String friendlyTime;

  const _RecentNoteRow({
    required this.entry,
    required this.thumbnail,
    required this.accent,
    required this.onTap,
    required this.friendlyTime,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = entry.previewText.trim().isNotEmpty
        ? entry.previewText.trim().replaceAll('\n', ' ')
        : (entry.primaryAttachment?.fileName ?? '');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _EditorialPreviewTile(
                entry: entry,
                thumbnail: thumbnail,
                accent: accent,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title.trim().isEmpty
                          ? context.l10n.untitled
                          : entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontFamily: 'serif',
                        fontSize: 18,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.muted,
                          height: 1.45,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          _metadataIcon(entry.primaryType),
                          size: 15,
                          color: AppColors.muted,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            _localizedMetadata(context, entry),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                              height: 1,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          friendlyTime,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontFamily: 'serif',
                            fontSize: 12,
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _metadataIcon(NoteType type) => switch (type) {
    NoteType.text => Icons.article_outlined,
    NoteType.image => Icons.image_outlined,
    NoteType.audio => Icons.mic_none_rounded,
    NoteType.video => Icons.play_circle_outline_rounded,
    NoteType.document => Icons.description_outlined,
  };
}

class _EditorialPreviewTile extends StatelessWidget {
  final NoteEntry entry;
  final File? thumbnail;
  final Color accent;

  const _EditorialPreviewTile({
    required this.entry,
    required this.thumbnail,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    if (thumbnail != null) {
      final imageCount = entry.attachmentCountFor(NoteType.image);
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            Image.file(thumbnail!, width: 76, height: 88, fit: BoxFit.cover),
            if (imageCount > 1)
              Positioned(
                right: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.ink.withValues(alpha: .78),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$imageCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      height: 1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    if (entry.primaryType == NoteType.text) {
      return Container(
        width: 76,
        height: 92,
        decoration: BoxDecoration(
          color: AppColors.softAmber,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              context.l10n.quickNoteTile,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.ink,
                fontFamily: 'serif',
                fontSize: 15,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 5),
            const DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.fromBorderSide(
                  BorderSide(color: AppColors.moss, width: 1.5),
                ),
              ),
              child: SizedBox.square(dimension: 7),
            ),
          ],
        ),
      );
    }

    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        NoteCard.iconForType(entry.primaryType),
        color: accent,
        size: 28,
      ),
    );
  }
}

class _TypePill extends StatelessWidget {
  final String label;
  final Color color;
  const _TypePill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 24,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              height: 1,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    ),
  );
}

enum _Action { favorite, pin, archive, restore, edit, delete }

class _MoreMenu extends StatelessWidget {
  final NoteCard card;
  const _MoreMenu({required this.card});

  @override
  Widget build(BuildContext context) => AppAnchoredMenuButton<_Action>(
    tooltip: context.l10n.more,
    icon: const Icon(Icons.more_horiz_rounded, size: 21),
    onSelected: (action) {
      switch (action) {
        case _Action.favorite:
          card.onFavorite?.call();
        case _Action.pin:
          card.onPin?.call();
        case _Action.archive:
          card.onArchive?.call();
        case _Action.restore:
          card.onRestore?.call();
        case _Action.edit:
          (card.onEdit ?? card.onTap).call();
        case _Action.delete:
          card.onDelete?.call();
      }
    },
    actions: [
      if (card.onRestore != null)
        AppMenuAction(
          value: _Action.restore,
          icon: Icons.restore_rounded,
          label: context.l10n.restore,
        ),
      if (card.onFavorite != null)
        AppMenuAction(
          value: _Action.favorite,
          icon: card.entry.isFavorite
              ? Icons.star_outline_rounded
              : Icons.star_rounded,
          label: card.entry.isFavorite
              ? context.l10n.removeFavorite
              : context.l10n.addFavorite,
          selected: card.entry.isFavorite,
        ),
      if (card.onPin != null)
        AppMenuAction(
          value: _Action.pin,
          icon: Icons.vertical_align_top_rounded,
          label: card.entry.isPinned ? context.l10n.unpin : context.l10n.pin,
          selected: card.entry.isPinned,
        ),
      if (card.onArchive != null)
        AppMenuAction(
          value: _Action.archive,
          icon: Icons.archive_outlined,
          label: card.entry.isArchived
              ? context.l10n.removeFromArchive
              : context.l10n.archive,
          selected: card.entry.isArchived,
        ),
      if (card.onEdit != null)
        AppMenuAction(
          value: _Action.edit,
          icon: Icons.edit_outlined,
          label: context.l10n.edit,
        ),
      if (card.onDelete != null)
        AppMenuAction(
          value: _Action.delete,
          icon: Icons.delete_outline_rounded,
          label: card.entry.isDeleted
              ? context.l10n.deletePermanently
              : context.l10n.moveToTrash,
          destructive: true,
        ),
    ],
  );
}
