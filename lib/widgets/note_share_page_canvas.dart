import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app.dart';
import '../models/note.dart';
import '../models/note_document.dart';
import '../models/note_share.dart';
import '../models/note_share_theme.dart';
import '../services/file_storage_service.dart';
import '../services/note_share_layout_engine.dart';

class NoteSharePageCanvas extends StatelessWidget {
  final NoteShareDraft draft;
  final NoteShareOptions options;
  final NoteShareLayoutResult layout;
  final int pageIndex;
  final String untitledTitle;
  final String sourceLabel;
  final Locale locale;

  const NoteSharePageCanvas({
    super.key,
    required this.draft,
    required this.options,
    required this.layout,
    required this.pageIndex,
    required this.untitledTitle,
    required this.sourceLabel,
    required this.locale,
  });

  @override
  Widget build(BuildContext context) {
    final page = layout.pages[pageIndex.clamp(0, layout.pages.length - 1)];
    final palette = _SharePalette.forTemplate(options.template);
    final metrics = NoteShareTemplateMetrics.of(options.template);
    final landscape = layout.logicalHeight < layout.logicalWidth;
    final letter = options.template == NoteShareTemplateId.letter;
    final night = options.template == NoteShareTemplateId.night;
    final paperHeight = layout.logicalHeight * metrics.paperHeightFactor;
    final paperWidth = layout.logicalWidth * metrics.paperWidthFactor;
    final verticalPadding = metrics.verticalPadding(landscape);
    final horizontalPadding = metrics.horizontalPadding(landscape);
    final lastPage = pageIndex == layout.pages.length - 1;
    final paperDecoration = _paperDecoration(options.template, palette);

    return MediaQuery.withNoTextScaling(
      child: SizedBox(
        width: layout.logicalWidth,
        height: layout.logicalHeight,
        child: ClipRect(
          child: ColoredBox(
            color: palette.canvas,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (letter)
                  CustomPaint(
                    key: const ValueKey('note-share-paper-texture'),
                    painter: _PaperTexturePainter(
                      paper: palette.paper,
                      fiber: palette.line,
                      accent: palette.accent,
                    ),
                  ),
                if (night)
                  CustomPaint(
                    key: const ValueKey('note-share-night-backdrop'),
                    painter: _NightBackdropPainter(
                      base: palette.canvas,
                      glow: palette.accent,
                      stars: palette.muted,
                    ),
                  ),
                if (!letter && !night)
                  CustomPaint(
                    key: ValueKey(
                      'note-share-${options.template.name}-backdrop',
                    ),
                    painter: _ThemeBackdropPainter(
                      template: options.template,
                      palette: palette,
                    ),
                  ),
                Align(
                  alignment: _paperAlignment(options.template),
                  child: Container(
                    width: paperWidth,
                    height: paperHeight,
                    decoration: paperDecoration,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _PaperDetailPainter(
                                template: options.template,
                                palette: palette,
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontalPadding,
                            vertical: verticalPadding,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _PageHeader(
                                draft: draft,
                                options: options,
                                pageIndex: pageIndex,
                                pageCount: layout.pages.length,
                                palette: palette,
                                locale: locale,
                              ),
                              if (pageIndex == 0 && options.includeTitle) ...[
                                SizedBox(
                                  height: metrics.titleTopGap(landscape),
                                ),
                                SizedBox(
                                  width: double.infinity,
                                  child: Text(
                                    draft.title.trim().isEmpty
                                        ? untitledTitle
                                        : draft.title.trim(),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: metrics.titleAlign,
                                    style: metrics.titleStyle(
                                      landscape,
                                      color: palette.ink,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  height: metrics.titleBottomGap(landscape),
                                ),
                              ],
                              Expanded(
                                child: ClipRect(
                                  key: const ValueKey(
                                    'note-share-body-viewport',
                                  ),
                                  child: Align(
                                    alignment: Alignment.topLeft,
                                    child: KeyedSubtree(
                                      key: const ValueKey(
                                        'note-share-body-content',
                                      ),
                                      child: _ShareBlocks(
                                        blocks: page.blocks,
                                        draft: draft,
                                        options: options,
                                        palette: palette,
                                        landscape: landscape,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                key: const ValueKey('note-share-footer-gap'),
                                height: NoteShareLayoutEngine.footerGapFor(
                                  landscape,
                                ),
                              ),
                              _BrandFooter(
                                label: sourceLabel,
                                palette: palette,
                                tags:
                                    lastPage &&
                                        options.includeTags &&
                                        draft.tags.isNotEmpty
                                    ? draft.tags
                                    : const [],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Alignment _paperAlignment(NoteShareTemplateId template) => switch (template) {
  NoteShareTemplateId.editorial => Alignment.centerLeft,
  NoteShareTemplateId.gallery => Alignment.centerRight,
  _ => Alignment.center,
};

BoxDecoration _paperDecoration(
  NoteShareTemplateId template,
  _SharePalette palette,
) => switch (template) {
  NoteShareTemplateId.letter ||
  NoteShareTemplateId.manuscript ||
  NoteShareTemplateId.vermilion => const BoxDecoration(
    color: Colors.transparent,
  ),
  NoteShareTemplateId.plain => BoxDecoration(
    color: palette.paper,
    borderRadius: BorderRadius.circular(14),
  ),
  NoteShareTemplateId.night => BoxDecoration(
    gradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF172235), Color(0xFF101826)],
    ),
    borderRadius: BorderRadius.circular(18),
    boxShadow: [
      BoxShadow(
        color: palette.shadow,
        blurRadius: 28,
        offset: const Offset(0, 10),
      ),
    ],
  ),
  NoteShareTemplateId.editorial => BoxDecoration(
    color: palette.paper,
    boxShadow: [
      BoxShadow(
        color: palette.shadow,
        blurRadius: 18,
        offset: const Offset(5, 8),
      ),
    ],
  ),
  NoteShareTemplateId.newspaper => BoxDecoration(color: palette.paper),
  NoteShareTemplateId.botanical => BoxDecoration(
    color: palette.paper.withValues(alpha: .96),
    borderRadius: BorderRadius.circular(24),
    boxShadow: [
      BoxShadow(
        color: palette.shadow,
        blurRadius: 22,
        offset: const Offset(0, 9),
      ),
    ],
  ),
  NoteShareTemplateId.blueprint => BoxDecoration(
    color: palette.paper.withValues(alpha: .92),
    borderRadius: BorderRadius.circular(3),
  ),
  NoteShareTemplateId.amber => BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [palette.paper, const Color(0xFFFFE7BD)],
    ),
    borderRadius: BorderRadius.circular(28),
    boxShadow: [
      BoxShadow(
        color: palette.shadow,
        blurRadius: 30,
        offset: const Offset(0, 12),
      ),
    ],
  ),
  NoteShareTemplateId.film => BoxDecoration(
    color: palette.paper,
    borderRadius: BorderRadius.circular(5),
    boxShadow: [
      BoxShadow(
        color: palette.shadow,
        blurRadius: 22,
        offset: const Offset(0, 8),
      ),
    ],
  ),
  NoteShareTemplateId.postcard => BoxDecoration(
    color: palette.paper,
    boxShadow: [
      BoxShadow(
        color: palette.shadow,
        blurRadius: 16,
        offset: const Offset(0, 7),
      ),
    ],
  ),
  NoteShareTemplateId.gallery => BoxDecoration(
    color: palette.paper,
    boxShadow: [
      BoxShadow(
        color: palette.shadow,
        blurRadius: 26,
        offset: const Offset(-6, 10),
      ),
    ],
  ),
  NoteShareTemplateId.neon => BoxDecoration(
    gradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF141625), Color(0xFF080910)],
    ),
    borderRadius: BorderRadius.circular(16),
    boxShadow: [
      BoxShadow(color: palette.accent.withValues(alpha: .22), blurRadius: 24),
    ],
  ),
  NoteShareTemplateId.tide => BoxDecoration(
    color: palette.paper.withValues(alpha: .94),
    borderRadius: BorderRadius.circular(22),
    boxShadow: [
      BoxShadow(
        color: palette.shadow,
        blurRadius: 24,
        offset: const Offset(0, 9),
      ),
    ],
  ),
};

class _PageHeader extends StatelessWidget {
  final NoteShareDraft draft;
  final NoteShareOptions options;
  final int pageIndex;
  final int pageCount;
  final _SharePalette palette;
  final Locale locale;

  const _PageHeader({
    required this.draft,
    required this.options,
    required this.pageIndex,
    required this.pageCount,
    required this.palette,
    required this.locale,
  });

  @override
  Widget build(BuildContext context) {
    final firstPage = pageIndex == 0;
    final height = firstPage
        ? options.includeDate
              ? 27.0
              : 8.0
        : 24.0;
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              firstPage
                  ? options.includeDate
                        ? DateFormat.yMMMd(
                            locale.toLanguageTag(),
                          ).format(draft.updatedAt)
                        : ''
                  : draft.title.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.muted,
                fontSize: 9.5,
                height: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (pageCount > 1)
            Text(
              '${(pageIndex + 1).toString().padLeft(2, '0')} / '
              '${pageCount.toString().padLeft(2, '0')}',
              style: TextStyle(
                color: palette.muted,
                fontSize: 9.5,
                height: 1.2,
                fontWeight: FontWeight.w700,
                letterSpacing: .4,
              ),
            ),
        ],
      ),
    );
  }
}

class _ShareBlocks extends StatelessWidget {
  final List<NoteSharePageBlock> blocks;
  final NoteShareDraft draft;
  final NoteShareOptions options;
  final _SharePalette palette;
  final bool landscape;

  const _ShareBlocks({
    required this.blocks,
    required this.draft,
    required this.options,
    required this.palette,
    required this.landscape,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final item in blocks)
        _ShareBlockView(
          item: item,
          draft: draft,
          options: options,
          palette: palette,
          landscape: landscape,
        ),
    ],
  );
}

class _ShareBlockView extends StatelessWidget {
  final NoteSharePageBlock item;
  final NoteShareDraft draft;
  final NoteShareOptions options;
  final _SharePalette palette;
  final bool landscape;

  const _ShareBlockView({
    required this.item,
    required this.draft,
    required this.options,
    required this.palette,
    required this.landscape,
  });

  @override
  Widget build(BuildContext context) {
    final block = item.block;
    if (block.type == NoteShareBlockType.divider) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          vertical: NoteShareLayoutEngine.dividerVerticalPadding,
        ),
        child: Divider(height: 1, color: palette.line),
      );
    }
    if (block.type == NoteShareBlockType.attachment) {
      return _ShareAttachment(
        attachment: block.asset,
        includeImages: options.includeImages,
        palette: palette,
        landscape: landscape,
      );
    }
    if (block.type == NoteShareBlockType.table) {
      return _ShareTable(
        table: block.table!,
        palette: palette,
        densityScale: options.density.scale,
      );
    }

    final scale = options.density.scale;
    final baseStyle = NoteShareTextPresentation.baseStyle(
      block,
      scale,
      color: palette.ink,
    );
    final richText = RichText(
      text: NoteShareTextPresentation.inlineSpan(
        block,
        baseStyle,
        densityScale: scale,
        linkColor: palette.accent,
        inlineCodeBackground: palette.code,
      ),
      textAlign: TextAlign.start,
    );
    final margin = EdgeInsets.only(
      left: block.indent * 14,
      bottom: NoteShareLayoutEngine.blockBottomGap * scale,
    );

    return Padding(
      padding: margin,
      child: switch (block.type) {
        NoteShareBlockType.bullet ||
        NoteShareBlockType.ordered ||
        NoteShareBlockType.todo => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 26,
              child: Text(
                item.showMarker
                    ? block.type == NoteShareBlockType.bullet
                          ? '•'
                          : block.type == NoteShareBlockType.ordered
                          ? '${item.orderedNumber ?? 1}.'
                          : block.checked
                          ? '☑'
                          : '☐'
                    : '',
                style: baseStyle.copyWith(
                  color: block.checked ? palette.muted : palette.ink,
                ),
              ),
            ),
            Expanded(child: richText),
          ],
        ),
        NoteShareBlockType.quote => Container(
          padding: const EdgeInsets.fromLTRB(11, 7, 8, 7),
          decoration: BoxDecoration(
            color: palette.quote,
            border: Border(
              left: BorderSide(
                color: palette.accent,
                width: NoteShareLayoutEngine.quoteBorderWidth,
              ),
            ),
          ),
          child: richText,
        ),
        NoteShareBlockType.code => Container(
          padding: const EdgeInsets.all(NoteShareLayoutEngine.codePadding),
          decoration: BoxDecoration(
            color: palette.code,
            borderRadius: BorderRadius.circular(8),
          ),
          child: richText,
        ),
        _ => richText,
      },
    );
  }
}

class _ShareTable extends StatelessWidget {
  const _ShareTable({
    required this.table,
    required this.palette,
    required this.densityScale,
  });

  final NoteTable table;
  final _SharePalette palette;
  final double densityScale;

  @override
  Widget build(BuildContext context) => Container(
    margin: EdgeInsets.only(
      bottom: NoteShareLayoutEngine.blockBottomGap * densityScale,
    ),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      border: Border.all(color: palette.line),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Table(
      border: TableBorder(
        horizontalInside: BorderSide(color: palette.line),
        verticalInside: BorderSide(color: palette.line),
      ),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        for (var rowIndex = 0; rowIndex < table.rows.length; rowIndex++)
          TableRow(
            decoration: rowIndex == 0
                ? BoxDecoration(color: palette.code)
                : null,
            children: [
              for (
                var columnIndex = 0;
                columnIndex < table.columnCount;
                columnIndex++
              )
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal:
                        NoteShareLayoutEngine.tableCellHorizontalPadding,
                    vertical: NoteShareLayoutEngine.tableCellVerticalPadding,
                  ),
                  child: Text(
                    table.rows[rowIndex][columnIndex],
                    textAlign: switch (table.alignments[columnIndex]) {
                      NoteTableAlignment.start => TextAlign.start,
                      NoteTableAlignment.center => TextAlign.center,
                      NoteTableAlignment.end => TextAlign.end,
                    },
                    style: TextStyle(
                      color: palette.ink,
                      fontSize:
                          NoteShareLayoutEngine.tableFontSize * densityScale,
                      height: NoteShareLayoutEngine.tableLineHeight,
                      fontWeight: rowIndex == 0
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                ),
            ],
          ),
      ],
    ),
  );
}

class _ShareAttachment extends StatelessWidget {
  final NoteAsset? attachment;
  final bool includeImages;
  final _SharePalette palette;
  final bool landscape;

  const _ShareAttachment({
    required this.attachment,
    required this.includeImages,
    required this.palette,
    required this.landscape,
  });

  @override
  Widget build(BuildContext context) {
    final item = attachment;
    if (item != null && item.kind == NoteAssetKind.image && includeImages) {
      return Container(
        height: landscape
            ? NoteShareLayoutEngine.landscapeImageHeight
            : NoteShareLayoutEngine.portraitImageHeight,
        margin: const EdgeInsets.only(
          bottom: NoteShareLayoutEngine.attachmentBottomGap,
        ),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: palette.code,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: palette.line),
        ),
        child: _attachmentImage(item),
      );
    }
    return Container(
      constraints: const BoxConstraints(
        minHeight: NoteShareLayoutEngine.attachmentMinHeight,
      ),
      margin: const EdgeInsets.only(
        bottom: NoteShareLayoutEngine.attachmentBottomGap,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: palette.code,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: palette.line),
      ),
      child: Row(
        children: [
          Icon(_attachmentIcon(item?.kind), size: 18, color: palette.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item?.displayTitle ?? '附件已移除',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.ink,
                fontSize: 11,
                height: 1.25,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _attachmentImage(NoteAsset item) {
    try {
      final path = FileStorageService.instance.absolutePath(item.storageKey);
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, _, _) => _imagePlaceholder(),
      );
    } catch (_) {
      return _imagePlaceholder();
    }
  }

  Widget _imagePlaceholder() => Center(
    child: Icon(Icons.broken_image_outlined, color: palette.muted, size: 26),
  );

  IconData _attachmentIcon(NoteAssetKind? type) => switch (type) {
    NoteAssetKind.image => Icons.image_outlined,
    NoteAssetKind.audio => Icons.graphic_eq_rounded,
    NoteAssetKind.video => Icons.videocam_outlined,
    NoteAssetKind.file || null => Icons.attach_file_rounded,
  };
}

class _BrandFooter extends StatelessWidget {
  final String label;
  final _SharePalette palette;
  final List<String> tags;

  const _BrandFooter({
    required this.label,
    required this.palette,
    required this.tags,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 31,
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.line)),
      ),
      child: Row(
        children: [
          SizedBox.square(
            key: const ValueKey('note-share-source-mark'),
            dimension: 13,
            child: CustomPaint(painter: _FkMarkPainter(color: palette.accent)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.muted,
                fontSize: 9.5,
                height: 1.2,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (tags.isNotEmpty) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                tags.map((tag) => '#$tag').join('  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 9.5,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _SharePalette {
  final Color canvas;
  final Color paper;
  final Color ink;
  final Color muted;
  final Color accent;
  final Color line;
  final Color quote;
  final Color code;
  final Color shadow;

  const _SharePalette({
    required this.canvas,
    required this.paper,
    required this.ink,
    required this.muted,
    required this.accent,
    required this.line,
    required this.quote,
    required this.code,
    required this.shadow,
  });

  factory _SharePalette.forTemplate(NoteShareTemplateId template) =>
      switch (template) {
        NoteShareTemplateId.letter => const _SharePalette(
          canvas: Color(0xFFF6EEDF),
          paper: Color(0xFFF6EEDF),
          ink: Color(0xFF342E28),
          muted: Color(0xFF776B60),
          accent: Color(0xFFB85C43),
          line: Color(0xFFD8CAB8),
          quote: Color(0x59E8D8C4),
          code: Color(0x73E9DECF),
          shadow: Colors.transparent,
        ),
        NoteShareTemplateId.plain => const _SharePalette(
          canvas: Color(0xFFF5F0E9),
          paper: Color(0xFFFFFDFC),
          ink: AppColors.ink,
          muted: AppColors.muted,
          accent: AppColors.moss,
          line: AppColors.line,
          quote: Color(0xFFF8F3EE),
          code: AppColors.softBlue,
          shadow: Colors.transparent,
        ),
        NoteShareTemplateId.night => const _SharePalette(
          canvas: Color(0xFF090F1B),
          paper: Color(0xFF172235),
          ink: Color(0xFFF4EEDA),
          muted: Color(0xFFA7B2C5),
          accent: Color(0xFFE4C27A),
          line: Color(0xFF35445D),
          quote: Color(0xFF1D2D44),
          code: Color(0xFF0C1523),
          shadow: Color(0xA6000000),
        ),
        NoteShareTemplateId.editorial => const _SharePalette(
          canvas: Color(0xFFE9E8E3),
          paper: Color(0xFFFCFCFA),
          ink: Color(0xFF161616),
          muted: Color(0xFF72706B),
          accent: Color(0xFFE94832),
          line: Color(0xFFD5D3CD),
          quote: Color(0xFFF0EFEB),
          code: Color(0xFFE8E7E2),
          shadow: Color(0x24000000),
        ),
        NoteShareTemplateId.newspaper => const _SharePalette(
          canvas: Color(0xFFD8D3C8),
          paper: Color(0xFFF3EFE3),
          ink: Color(0xFF24221E),
          muted: Color(0xFF68635A),
          accent: Color(0xFF8A2E27),
          line: Color(0xFFAAA295),
          quote: Color(0xFFE7E1D5),
          code: Color(0xFFDDD7CA),
          shadow: Colors.transparent,
        ),
        NoteShareTemplateId.manuscript => const _SharePalette(
          canvas: Color(0xFFFFFCF4),
          paper: Color(0xFFFFFCF4),
          ink: Color(0xFF2B3135),
          muted: Color(0xFF758087),
          accent: Color(0xFFD86662),
          line: Color(0xFFB7D6DD),
          quote: Color(0x667DB8C5),
          code: Color(0xA6E4F0F2),
          shadow: Colors.transparent,
        ),
        NoteShareTemplateId.botanical => const _SharePalette(
          canvas: Color(0xFFDDE5D7),
          paper: Color(0xFFF5F4E9),
          ink: Color(0xFF2F3A2E),
          muted: Color(0xFF6C7868),
          accent: Color(0xFF6F8760),
          line: Color(0xFFC5CFBD),
          quote: Color(0xFFEAEEE2),
          code: Color(0xFFE2E8DC),
          shadow: Color(0x26354A31),
        ),
        NoteShareTemplateId.blueprint => const _SharePalette(
          canvas: Color(0xFF0A3B67),
          paper: Color(0xFF0D4B7C),
          ink: Color(0xFFF1FAFF),
          muted: Color(0xFFB5D7EA),
          accent: Color(0xFF6FE3FF),
          line: Color(0xFF4A87AC),
          quote: Color(0xFF165A88),
          code: Color(0xFF082F52),
          shadow: Color(0x55002038),
        ),
        NoteShareTemplateId.amber => const _SharePalette(
          canvas: Color(0xFF7B3B20),
          paper: Color(0xFFFFF1D3),
          ink: Color(0xFF4B2D1E),
          muted: Color(0xFF8C6953),
          accent: Color(0xFFC86B2C),
          line: Color(0xFFE0BE8A),
          quote: Color(0xFFFFE1AF),
          code: Color(0xFFF2D09D),
          shadow: Color(0x5C4C1F0B),
        ),
        NoteShareTemplateId.film => const _SharePalette(
          canvas: Color(0xFF161616),
          paper: Color(0xFF242321),
          ink: Color(0xFFF2EBDC),
          muted: Color(0xFFAAA398),
          accent: Color(0xFFE75A3C),
          line: Color(0xFF514E49),
          quote: Color(0xFF302E2A),
          code: Color(0xFF111110),
          shadow: Color(0xB3000000),
        ),
        NoteShareTemplateId.postcard => const _SharePalette(
          canvas: Color(0xFFB9D1DB),
          paper: Color(0xFFFFFBF0),
          ink: Color(0xFF273849),
          muted: Color(0xFF6F7D87),
          accent: Color(0xFFC94D48),
          line: Color(0xFF92A9B4),
          quote: Color(0xFFE8F0F0),
          code: Color(0xFFDDE9EB),
          shadow: Color(0x38445E68),
        ),
        NoteShareTemplateId.gallery => const _SharePalette(
          canvas: Color(0xFFD8D4CD),
          paper: Color(0xFFFFFFFF),
          ink: Color(0xFF171717),
          muted: Color(0xFF76736E),
          accent: Color(0xFF245C4A),
          line: Color(0xFFD9D7D2),
          quote: Color(0xFFF2F1EE),
          code: Color(0xFFEAEDEA),
          shadow: Color(0x30000000),
        ),
        NoteShareTemplateId.neon => const _SharePalette(
          canvas: Color(0xFF05050B),
          paper: Color(0xFF10111B),
          ink: Color(0xFFF5F4FF),
          muted: Color(0xFFA7A8BA),
          accent: Color(0xFF43F2D2),
          line: Color(0xFF38415A),
          quote: Color(0xFF181D2B),
          code: Color(0xFF080A10),
          shadow: Color(0xD9000000),
        ),
        NoteShareTemplateId.tide => const _SharePalette(
          canvas: Color(0xFFC8E0E9),
          paper: Color(0xFFF5FBFC),
          ink: Color(0xFF244252),
          muted: Color(0xFF6A8795),
          accent: Color(0xFF3B8BA5),
          line: Color(0xFFB9D6DE),
          quote: Color(0xFFE4F2F5),
          code: Color(0xFFDCECF0),
          shadow: Color(0x2E2A6275),
        ),
        NoteShareTemplateId.vermilion => const _SharePalette(
          canvas: Color(0xFFF4EBDD),
          paper: Color(0xFFF4EBDD),
          ink: Color(0xFF2F2925),
          muted: Color(0xFF746B63),
          accent: Color(0xFFB43A32),
          line: Color(0xFFD4C3B2),
          quote: Color(0xFFE9DCCE),
          code: Color(0xFFDFD1C2),
          shadow: Colors.transparent,
        ),
      };
}

class _ThemeBackdropPainter extends CustomPainter {
  final NoteShareTemplateId template;
  final _SharePalette palette;

  const _ThemeBackdropPainter({required this.template, required this.palette});

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(bounds, Paint()..color = palette.canvas);
    switch (template) {
      case NoteShareTemplateId.plain:
        canvas.drawRect(
          bounds,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white.withValues(alpha: .16), Colors.transparent],
            ).createShader(bounds),
        );
      case NoteShareTemplateId.editorial:
        canvas.drawRect(
          Rect.fromLTWH(size.width - 16, 0, 16, size.height),
          Paint()..color = palette.ink,
        );
        canvas.drawRect(
          Rect.fromLTWH(size.width - 16, size.height * .18, 16, 54),
          Paint()..color = palette.accent,
        );
      case NoteShareTemplateId.newspaper:
        final paint = Paint()
          ..color = palette.ink.withValues(alpha: .055)
          ..strokeWidth = .45;
        for (var y = 7.0; y < size.height; y += 7) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
      case NoteShareTemplateId.manuscript:
        canvas.drawRect(bounds, Paint()..color = palette.paper);
      case NoteShareTemplateId.botanical:
        canvas.drawRect(
          bounds,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFFC8D7C0),
                palette.canvas,
                const Color(0xFFE6E8D6),
              ],
            ).createShader(bounds),
        );
        canvas.drawCircle(
          Offset(size.width * .92, size.height * .08),
          size.width * .28,
          Paint()..color = palette.accent.withValues(alpha: .12),
        );
      case NoteShareTemplateId.blueprint:
        canvas.drawRect(
          bounds,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0E578B), Color(0xFF062D53)],
            ).createShader(bounds),
        );
        _drawGrid(canvas, size, palette.accent.withValues(alpha: .12), 18);
      case NoteShareTemplateId.amber:
        canvas.drawRect(
          bounds,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFA85825), Color(0xFF64321F), Color(0xFF3A241C)],
            ).createShader(bounds),
        );
        canvas.drawCircle(
          Offset(size.width * .88, size.height * .12),
          size.width * .22,
          Paint()..color = const Color(0xFFFFC56E).withValues(alpha: .18),
        );
      case NoteShareTemplateId.film:
        canvas.drawRect(
          bounds,
          Paint()
            ..shader = const RadialGradient(
              center: Alignment.topLeft,
              radius: 1.35,
              colors: [Color(0xFF33312D), Color(0xFF111111)],
            ).createShader(bounds),
        );
        final grain = Paint()..color = Colors.white.withValues(alpha: .035);
        for (var index = 0; index < 110; index++) {
          final x = ((index * 73 + 19) % 997) / 997 * size.width;
          final y = ((index * 131 + 37) % 991) / 991 * size.height;
          canvas.drawCircle(Offset(x, y), index.isEven ? .35 : .22, grain);
        }
      case NoteShareTemplateId.postcard:
        canvas.drawRect(
          bounds,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFD6E8EC), Color(0xFF9FBECA)],
            ).createShader(bounds),
        );
      case NoteShareTemplateId.gallery:
        canvas.drawRect(
          bounds,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFE4E1DA), Color(0xFFCBC6BD)],
            ).createShader(bounds),
        );
        canvas.drawRect(
          Rect.fromLTWH(
            0,
            size.height * .64,
            size.width * .1,
            size.height * .22,
          ),
          Paint()..color = palette.accent,
        );
      case NoteShareTemplateId.neon:
        canvas.drawRect(
          bounds,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF17102D), Color(0xFF05050B), Color(0xFF071A1B)],
            ).createShader(bounds),
        );
        _drawGlow(
          canvas,
          bounds,
          const Alignment(-1, -.75),
          const Color(0xFFEF4CFF),
        );
        _drawGlow(canvas, bounds, const Alignment(1, .8), palette.accent);
      case NoteShareTemplateId.tide:
        canvas.drawRect(
          bounds,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFE2F1F4), Color(0xFFAACDD9)],
            ).createShader(bounds),
        );
        _drawWaves(canvas, size, palette.accent.withValues(alpha: .16), 34);
      case NoteShareTemplateId.vermilion:
        canvas.drawRect(bounds, Paint()..color = palette.paper);
        canvas.drawCircle(
          Offset(size.width * .94, size.height * .08),
          size.width * .18,
          Paint()..color = palette.accent.withValues(alpha: .055),
        );
      case NoteShareTemplateId.letter || NoteShareTemplateId.night:
        break;
    }
  }

  void _drawGrid(Canvas canvas, Size size, Color color, double step) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = .45;
    for (var x = 0.0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _drawGlow(Canvas canvas, Rect bounds, Alignment center, Color color) {
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = RadialGradient(
          center: center,
          radius: .75,
          colors: [color.withValues(alpha: .2), color.withValues(alpha: 0)],
        ).createShader(bounds),
    );
  }

  void _drawWaves(Canvas canvas, Size size, Color color, double spacing) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var y = spacing; y < size.height; y += spacing) {
      final path = Path()..moveTo(-12, y);
      for (var x = -12.0; x < size.width + 30; x += 36) {
        path.quadraticBezierTo(x + 9, y - 5, x + 18, y);
        path.quadraticBezierTo(x + 27, y + 5, x + 36, y);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ThemeBackdropPainter oldDelegate) =>
      template != oldDelegate.template || palette != oldDelegate.palette;
}

class _PaperDetailPainter extends CustomPainter {
  final NoteShareTemplateId template;
  final _SharePalette palette;

  const _PaperDetailPainter({required this.template, required this.palette});

  @override
  void paint(Canvas canvas, Size size) {
    _drawOutline(canvas, size);
    switch (template) {
      case NoteShareTemplateId.plain:
        canvas.drawLine(
          const Offset(18, 14),
          Offset(size.width - 18, 14),
          Paint()
            ..color = palette.line.withValues(alpha: .5)
            ..strokeWidth = .6,
        );
      case NoteShareTemplateId.night:
        canvas.drawCircle(
          Offset(size.width - 26, 24),
          17,
          Paint()
            ..color = palette.accent.withValues(alpha: .05)
            ..style = PaintingStyle.stroke
            ..strokeWidth = .8,
        );
      case NoteShareTemplateId.editorial:
        canvas.drawRect(
          const Rect.fromLTWH(18, 18, 22, 4),
          Paint()..color = palette.accent,
        );
        canvas.drawLine(
          Offset(size.width - 22, 18),
          Offset(size.width - 22, size.height - 18),
          Paint()
            ..color = palette.line
            ..strokeWidth = .55,
        );
      case NoteShareTemplateId.newspaper:
        final paint = Paint()
          ..color = palette.ink.withValues(alpha: .78)
          ..strokeWidth = .7;
        canvas.drawLine(
          const Offset(14, 14),
          Offset(size.width - 14, 14),
          paint,
        );
        canvas.drawLine(
          const Offset(14, 17),
          Offset(size.width - 14, 17),
          paint,
        );
        canvas.drawLine(
          Offset(14, size.height - 17),
          Offset(size.width - 14, size.height - 17),
          paint,
        );
        canvas.drawLine(
          Offset(14, size.height - 14),
          Offset(size.width - 14, size.height - 14),
          paint,
        );
      case NoteShareTemplateId.manuscript:
        final linePaint = Paint()
          ..color = palette.line.withValues(alpha: .58)
          ..strokeWidth = .55;
        for (var y = 28.0; y < size.height; y += 22) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
        }
        canvas.drawLine(
          const Offset(30, 0),
          Offset(30, size.height),
          Paint()
            ..color = palette.accent.withValues(alpha: .5)
            ..strokeWidth = .8,
        );
      case NoteShareTemplateId.botanical:
        _drawBranch(canvas, const Offset(20, 24), .72, false);
        _drawBranch(
          canvas,
          Offset(size.width - 18, size.height - 24),
          .68,
          true,
        );
      case NoteShareTemplateId.blueprint:
        _drawGrid(canvas, size, palette.accent.withValues(alpha: .13), 16);
        final mark = Paint()
          ..color = palette.accent.withValues(alpha: .68)
          ..strokeWidth = .8;
        for (final point in [
          const Offset(12, 12),
          Offset(size.width - 12, 12),
          Offset(12, size.height - 12),
          Offset(size.width - 12, size.height - 12),
        ]) {
          canvas.drawLine(point.translate(-4, 0), point.translate(4, 0), mark);
          canvas.drawLine(point.translate(0, -4), point.translate(0, 4), mark);
        }
      case NoteShareTemplateId.amber:
        canvas.drawCircle(
          Offset(size.width - 22, 22),
          40,
          Paint()..color = palette.accent.withValues(alpha: .065),
        );
        canvas.drawCircle(
          Offset(size.width - 22, 22),
          27,
          Paint()
            ..color = palette.accent.withValues(alpha: .16)
            ..style = PaintingStyle.stroke
            ..strokeWidth = .8,
        );
      case NoteShareTemplateId.film:
        final hole = Paint()..color = const Color(0xFF090909);
        for (var y = 12.0; y < size.height - 10; y += 24) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(8, y, 11, 7),
              const Radius.circular(1.4),
            ),
            hole,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(size.width - 19, y, 11, 7),
              const Radius.circular(1.4),
            ),
            hole,
          );
        }
      case NoteShareTemplateId.postcard:
        _drawAirmailBorder(canvas, size);
        final postmark = Paint()
          ..color = palette.muted.withValues(alpha: .25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
        canvas.drawCircle(Offset(size.width - 38, 34), 18, postmark);
        for (var y = 25.0; y <= 43; y += 6) {
          canvas.drawLine(
            Offset(size.width - 54, y),
            Offset(size.width - 16, y + 5),
            postmark,
          );
        }
      case NoteShareTemplateId.gallery:
        canvas.drawRect(
          Rect.fromLTWH(0, 0, 8, size.height * .28),
          Paint()..color = palette.accent,
        );
        canvas.drawRect(
          Rect.fromLTWH(0, size.height * .28, 8, 18),
          Paint()..color = const Color(0xFFD7A94A),
        );
        canvas.drawLine(
          Offset(size.width - 18, 22),
          Offset(size.width - 18, 62),
          Paint()
            ..color = palette.ink
            ..strokeWidth = 2,
        );
      case NoteShareTemplateId.neon:
        final rect = Offset.zero & size;
        canvas.drawRect(
          Rect.fromLTWH(0, 0, size.width, 2),
          Paint()
            ..shader = const LinearGradient(
              colors: [Color(0xFFEF4CFF), Color(0xFF43F2D2)],
            ).createShader(rect),
        );
        canvas.drawRect(
          Rect.fromLTWH(0, 0, 2, size.height * .34),
          Paint()..color = const Color(0xFFEF4CFF).withValues(alpha: .85),
        );
        canvas.drawLine(
          Offset(18, size.height - 16),
          Offset(size.width * .45, size.height - 16),
          Paint()
            ..color = palette.accent.withValues(alpha: .7)
            ..strokeWidth = 1,
        );
      case NoteShareTemplateId.tide:
        _drawWave(canvas, size.height * .16, size, .09);
        _drawWave(canvas, size.height * .84, size, .13);
      case NoteShareTemplateId.vermilion:
        canvas.drawLine(
          const Offset(22, 0),
          Offset(22, size.height),
          Paint()
            ..color = palette.accent.withValues(alpha: .44)
            ..strokeWidth = 1,
        );
        final sealRect = Rect.fromLTWH(
          size.width - 42,
          size.height - 45,
          22,
          22,
        );
        canvas.drawRect(
          sealRect,
          Paint()
            ..color = palette.accent.withValues(alpha: .22)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
        canvas.drawCircle(
          sealRect.center,
          6,
          Paint()
            ..color = palette.accent.withValues(alpha: .16)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      case NoteShareTemplateId.letter:
        break;
    }
  }

  void _drawOutline(Canvas canvas, Size size) {
    final (double radius, double width, Color color)? outline =
        switch (template) {
          NoteShareTemplateId.plain => (14, 1, palette.line),
          NoteShareTemplateId.night => (18, 1, palette.line),
          NoteShareTemplateId.newspaper => (0, 1.2, palette.ink),
          NoteShareTemplateId.botanical => (24, 1, palette.line),
          NoteShareTemplateId.blueprint => (
            3,
            1,
            palette.accent.withValues(alpha: .7),
          ),
          NoteShareTemplateId.amber => (28, 1, palette.line),
          NoteShareTemplateId.film => (5, 1, palette.line),
          NoteShareTemplateId.postcard => (0, 1.2, palette.line),
          NoteShareTemplateId.neon => (16, 1, palette.line),
          NoteShareTemplateId.tide => (22, 1, palette.line),
          _ => null,
        };
    if (outline != null) {
      final inset = outline.$2 / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            inset,
            inset,
            size.width - outline.$2,
            size.height - outline.$2,
          ),
          Radius.circular(outline.$1),
        ),
        Paint()
          ..color = outline.$3
          ..style = PaintingStyle.stroke
          ..strokeWidth = outline.$2,
      );
    }
    if (template == NoteShareTemplateId.editorial) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, 4, size.height),
        Paint()..color = palette.accent,
      );
    }
  }

  void _drawGrid(Canvas canvas, Size size, Color color, double step) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = .4;
    for (var x = 0.0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _drawBranch(Canvas canvas, Offset origin, double scale, bool reverse) {
    final direction = reverse ? -1.0 : 1.0;
    final stem = Paint()
      ..color = palette.accent.withValues(alpha: .3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .9;
    final path = Path()
      ..moveTo(origin.dx, origin.dy)
      ..quadraticBezierTo(
        origin.dx + 20 * direction * scale,
        origin.dy + 12 * direction * scale,
        origin.dx + 34 * direction * scale,
        origin.dy + 34 * direction * scale,
      );
    canvas.drawPath(path, stem);
    final leaf = Paint()..color = palette.accent.withValues(alpha: .15);
    for (var index = 0; index < 3; index++) {
      final dx = origin.dx + (9 + index * 9) * direction * scale;
      final dy = origin.dy + (7 + index * 8) * direction * scale;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(dx, dy),
          width: 10 * scale,
          height: 5 * scale,
        ),
        leaf,
      );
    }
  }

  void _drawAirmailBorder(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    const stripe = 12.0;
    for (
      var offset = -size.height;
      offset < size.width + size.height;
      offset += stripe
    ) {
      final color = ((offset / stripe).round()).isEven
          ? palette.accent
          : const Color(0xFF3C6E99);
      final paint = Paint()..color = color.withValues(alpha: .72);
      final path = Path()
        ..moveTo(offset, 0)
        ..lineTo(offset + 7, 0)
        ..lineTo(offset - 3, 7)
        ..lineTo(offset - 10, 7)
        ..close();
      canvas.drawPath(path, paint);
      canvas.save();
      canvas.translate(0, size.height - 7);
      canvas.drawPath(path, paint);
      canvas.restore();
    }
    canvas.restore();
  }

  void _drawWave(Canvas canvas, double y, Size size, double alpha) {
    final path = Path()..moveTo(-8, y);
    for (var x = -8.0; x < size.width + 32; x += 40) {
      path.cubicTo(x + 10, y - 7, x + 30, y + 7, x + 40, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = palette.accent.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant _PaperDetailPainter oldDelegate) =>
      template != oldDelegate.template || palette != oldDelegate.palette;
}

class _PaperTexturePainter extends CustomPainter {
  final Color paper;
  final Color fiber;
  final Color accent;

  const _PaperTexturePainter({
    required this.paper,
    required this.fiber,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(bounds, Paint()..color = paper);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: .13),
            accent.withValues(alpha: .025),
            fiber.withValues(alpha: .045),
          ],
          stops: const [0, .58, 1],
        ).createShader(bounds),
    );

    final fiberPaint = Paint()
      ..color = fiber.withValues(alpha: .18)
      ..strokeWidth = .38
      ..strokeCap = StrokeCap.round;
    final lightFiberPaint = Paint()
      ..color = Colors.white.withValues(alpha: .19)
      ..strokeWidth = .32
      ..strokeCap = StrokeCap.round;
    final count = (size.height / 5).clamp(80, 520).round();
    for (var index = 0; index < count; index++) {
      final x = ((index * 83 + 29) % 997) / 997 * size.width;
      final y = ((index * 137 + 61) % 991) / 991 * size.height;
      final length = 2.2 + (index % 7) * .58;
      final slope = ((index % 5) - 2) * .17;
      canvas.drawLine(
        Offset(x, y),
        Offset((x + length).clamp(0, size.width), y + slope),
        index.isEven ? fiberPaint : lightFiberPaint,
      );
    }

    final speckPaint = Paint()..color = fiber.withValues(alpha: .12);
    final specks = (size.height / 16).clamp(28, 180).round();
    for (var index = 0; index < specks; index++) {
      final x = ((index * 193 + 17) % 983) / 983 * size.width;
      final y = ((index * 227 + 43) % 977) / 977 * size.height;
      canvas.drawCircle(Offset(x, y), index.isEven ? .34 : .22, speckPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PaperTexturePainter oldDelegate) =>
      paper != oldDelegate.paper ||
      fiber != oldDelegate.fiber ||
      accent != oldDelegate.accent;
}

class _NightBackdropPainter extends CustomPainter {
  final Color base;
  final Color glow;
  final Color stars;

  const _NightBackdropPainter({
    required this.base,
    required this.glow,
    required this.stars,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF17243A), Color(0xFF090F1B), Color(0xFF070B13)],
          stops: [0, .52, 1],
        ).createShader(bounds),
    );
    final glowRect = Rect.fromCircle(
      center: Offset(size.width * .12, size.height * .04),
      radius: size.width * .85,
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.topLeft,
          radius: 1,
          colors: [glow.withValues(alpha: .13), base.withValues(alpha: 0)],
        ).createShader(glowRect),
    );
    final starPaint = Paint()..color = stars.withValues(alpha: .22);
    final starCount = (size.height / 48).clamp(14, 80).round();
    for (var index = 0; index < starCount; index++) {
      final x = ((index * 149 + 73) % 967) / 967 * size.width;
      final y = ((index * 211 + 31) % 953) / 953 * size.height;
      canvas.drawCircle(Offset(x, y), index % 5 == 0 ? .65 : .34, starPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _NightBackdropPainter oldDelegate) =>
      base != oldDelegate.base ||
      glow != oldDelegate.glow ||
      stars != oldDelegate.stars;
}

class _FkMarkPainter extends CustomPainter {
  final Color color;
  const _FkMarkPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / 100;
    final scaleY = size.height / 100;
    canvas.save();
    canvas.scale(scaleX, scaleY);
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(33, 20)
      ..lineTo(69, 20)
      ..cubicTo(75, 20, 79, 24, 79, 30)
      ..lineTo(79, 70)
      ..cubicTo(79, 76, 75, 80, 69, 80)
      ..lineTo(33, 80)
      ..cubicTo(27, 80, 23, 76, 23, 70)
      ..lineTo(23, 30)
      ..cubicTo(23, 24, 27, 20, 33, 20)
      ..close();
    final cutout = Paint()
      ..color = Colors.white
      ..blendMode = BlendMode.dstOut;
    canvas.saveLayer(const Rect.fromLTWH(0, 0, 100, 100), Paint());
    canvas.drawPath(path, paint);
    canvas.drawPath(
      Path()
        ..moveTo(35.5, 20)
        ..cubicTo(39, 31, 39, 69, 35.5, 80)
        ..lineTo(39, 80)
        ..cubicTo(42.5, 69, 42.5, 31, 39, 20)
        ..close(),
      cutout,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(46, 41, 27, 6),
        const Radius.circular(3),
      ),
      cutout,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(46, 54, 20, 6),
        const Radius.circular(3),
      ),
      cutout,
    );
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FkMarkPainter oldDelegate) =>
      color != oldDelegate.color;
}
