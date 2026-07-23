import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/note_entry.dart';
import '../models/note_share.dart';
import '../models/note_share_theme.dart';
import '../utils/markdown_text.dart';
import '../widgets/note_block_editor.dart';

class NoteSharePageBlock {
  final NoteBlockData block;
  final int? orderedNumber;
  final bool showMarker;

  const NoteSharePageBlock({
    required this.block,
    this.orderedNumber,
    this.showMarker = true,
  });
}

class NoteSharePageLayout {
  final int index;
  final List<NoteSharePageBlock> blocks;
  final double bodyHeight;

  const NoteSharePageLayout({
    required this.index,
    required this.blocks,
    required this.bodyHeight,
  });
}

class NoteShareLayoutResult {
  final double logicalWidth;
  final double logicalHeight;
  final NoteSharePixelSize outputPixelSize;
  final List<NoteSharePageLayout> pages;

  const NoteShareLayoutResult({
    required this.logicalWidth,
    required this.logicalHeight,
    required this.outputPixelSize,
    required this.pages,
  });
}

/// The single source of truth for share-card text geometry and inline styles.
///
/// Pagination must measure the exact same span tree that the canvas renders;
/// otherwise font weight, inline code or a custom font size can change wrapping
/// after the long-image height has already been fixed.
class NoteShareTextPresentation {
  const NoteShareTextPresentation._();

  static String displayText(NoteBlockData block) =>
      block.type == NoteBlockType.rawMarkdown
      ? MarkdownText.toPlainText(block.text)
      : block.text;

  static TextStyle baseStyle(
    NoteBlockData block,
    double densityScale, {
    Color? color,
  }) {
    final fontSize = switch (block.type) {
      NoteBlockType.heading => switch (block.headingLevel.clamp(1, 6)) {
        1 => 21.0,
        2 => 19.0,
        _ => 17.0,
      },
      NoteBlockType.code || NoteBlockType.rawMarkdown => 12.5,
      _ => 15.0,
    };
    return TextStyle(
      color: color,
      fontFamily:
          block.type == NoteBlockType.code ||
              block.type == NoteBlockType.rawMarkdown
          ? 'monospace'
          : null,
      fontSize: fontSize * densityScale,
      height: block.type == NoteBlockType.heading ? 1.28 : 1.48,
      fontWeight: block.type == NoteBlockType.heading
          ? FontWeight.w700
          : FontWeight.w400,
    );
  }

  static TextSpan inlineSpan(
    NoteBlockData block,
    TextStyle base, {
    required double densityScale,
    Color? linkColor,
    Color? inlineCodeBackground,
  }) {
    final text = displayText(block);
    if (block.type == NoteBlockType.rawMarkdown || block.styles.isEmpty) {
      return TextSpan(text: text, style: base);
    }
    final ranges = [...block.styles]
      ..sort((left, right) => left.start.compareTo(right.start));
    final children = <InlineSpan>[];
    var cursor = 0;
    for (final range in ranges) {
      final start = range.start.clamp(cursor, text.length);
      final end = range.end.clamp(start, text.length);
      if (start > cursor) {
        children.add(TextSpan(text: text.substring(cursor, start)));
      }
      final attributes = range.attributes;
      final decorations = <TextDecoration>[
        if (attributes.strikethrough) TextDecoration.lineThrough,
        if (attributes.underline || attributes.link != null)
          TextDecoration.underline,
      ];
      children.add(
        TextSpan(
          text: text.substring(start, end),
          style: TextStyle(
            fontWeight: attributes.bold ? FontWeight.w700 : null,
            fontStyle: attributes.italic ? FontStyle.italic : null,
            fontFamily: attributes.inlineCode ? 'monospace' : null,
            fontSize: attributes.fontSize == NoteTextAttributes.defaultFontSize
                ? null
                : attributes.fontSize * densityScale,
            backgroundColor: attributes.inlineCode
                ? inlineCodeBackground
                : null,
            color: attributes.link != null ? linkColor : null,
            decoration: decorations.isEmpty
                ? null
                : TextDecoration.combine(decorations),
          ),
        ),
      );
      cursor = end;
    }
    if (cursor < text.length) {
      children.add(TextSpan(text: text.substring(cursor)));
    }
    return TextSpan(style: base, children: children);
  }
}

class NoteShareLayoutEngine {
  static const logicalWidth = 360.0;
  static const chromeMeasurementSafety = 4.0;
  static const blockMeasurementSafety = 1.0;
  static const blockBottomGap = 8.0;
  static const dividerVerticalPadding = 10.0;
  static const quoteBorderWidth = 2.5;
  static const quoteHorizontalPadding = 21.5;
  static const quoteVerticalPadding = 14.0;
  static const codePadding = 10.0;
  static const attachmentBottomGap = 10.0;
  static const attachmentMinHeight = 48.0;
  static const portraitImageHeight = 140.0;
  static const landscapeImageHeight = 82.0;

  static double footerGapFor(bool landscape) => landscape ? 8.0 : 12.0;

  const NoteShareLayoutEngine();

  NoteShareLayoutResult paginate({
    required NoteShareDraft draft,
    required NoteShareOptions options,
    required TextDirection textDirection,
    required String untitledTitle,
  }) {
    final pixelSize = options.canvas.pixelSize;
    if (options.canvas.isLong) {
      return _layoutLongImage(
        draft: draft,
        options: options,
        textDirection: textDirection,
        untitledTitle: untitledTitle,
      );
    }
    final logicalHeight = logicalWidth / pixelSize.aspectRatio;
    final blocks = _shareableBlocks(draft, options);
    final pageBlocks = <List<NoteSharePageBlock>>[[]];
    final usedHeights = <double>[0];
    var orderedNumber = 0;
    NoteBlockType? previousType;

    double capacity(int pageIndex) => _bodyCapacity(
      logicalHeight: logicalHeight,
      pageIndex: pageIndex,
      draft: draft,
      options: options,
      textDirection: textDirection,
      untitledTitle: untitledTitle,
    );

    void nextPage() {
      pageBlocks.add([]);
      usedHeights.add(0);
    }

    void addBlock(NoteBlockData block, {bool showMarker = true}) {
      if (block.type == NoteBlockType.ordered && showMarker) {
        orderedNumber = previousType == NoteBlockType.ordered
            ? orderedNumber + 1
            : 1;
      } else if (block.type != NoteBlockType.ordered) {
        orderedNumber = 0;
      }

      var remainingBlock = block;
      var marker = showMarker;
      while (true) {
        final pageIndex = pageBlocks.length - 1;
        final available = capacity(pageIndex) - usedHeights[pageIndex];
        final measured = _blockHeight(
          remainingBlock,
          draft: draft,
          options: options,
          textDirection: textDirection,
        );
        if (measured <= available ||
            (pageBlocks[pageIndex].isEmpty && !_canSplit(remainingBlock))) {
          pageBlocks[pageIndex].add(
            NoteSharePageBlock(
              block: remainingBlock,
              orderedNumber: remainingBlock.type == NoteBlockType.ordered
                  ? orderedNumber
                  : null,
              showMarker: marker,
            ),
          );
          usedHeights[pageIndex] += math.min(measured, capacity(pageIndex));
          break;
        }

        if (pageBlocks[pageIndex].isNotEmpty) {
          if (_canSplit(remainingBlock) &&
              available >=
                  _minimumSplitHeight(remainingBlock, options: options)) {
            final split = _splitToFit(
              remainingBlock,
              maxHeight: available,
              draft: draft,
              options: options,
              textDirection: textDirection,
            );
            if (split != null) {
              final headHeight = _blockHeight(
                split.$1,
                draft: draft,
                options: options,
                textDirection: textDirection,
              );
              pageBlocks[pageIndex].add(
                NoteSharePageBlock(
                  block: split.$1,
                  orderedNumber: remainingBlock.type == NoteBlockType.ordered
                      ? orderedNumber
                      : null,
                  showMarker: marker,
                ),
              );
              usedHeights[pageIndex] += headHeight;
              remainingBlock = split.$2;
              marker = false;
              nextPage();
              continue;
            }
          }
          nextPage();
          continue;
        }

        final split = _splitToFit(
          remainingBlock,
          maxHeight: math.max(24, capacity(pageIndex)),
          draft: draft,
          options: options,
          textDirection: textDirection,
        );
        if (split == null) {
          pageBlocks[pageIndex].add(
            NoteSharePageBlock(
              block: remainingBlock,
              orderedNumber: remainingBlock.type == NoteBlockType.ordered
                  ? orderedNumber
                  : null,
              showMarker: marker,
            ),
          );
          usedHeights[pageIndex] = capacity(pageIndex);
          break;
        }
        pageBlocks[pageIndex].add(
          NoteSharePageBlock(
            block: split.$1,
            orderedNumber: remainingBlock.type == NoteBlockType.ordered
                ? orderedNumber
                : null,
            showMarker: marker,
          ),
        );
        usedHeights[pageIndex] = _blockHeight(
          split.$1,
          draft: draft,
          options: options,
          textDirection: textDirection,
        );
        remainingBlock = split.$2;
        marker = false;
        nextPage();
      }
      previousType = block.type;
    }

    for (final block in blocks) {
      addBlock(block);
    }

    if (pageBlocks.length > 1 && pageBlocks.last.isEmpty) {
      pageBlocks.removeLast();
      usedHeights.removeLast();
    }
    final pages = <NoteSharePageLayout>[];
    for (var index = 0; index < pageBlocks.length; index++) {
      pages.add(
        NoteSharePageLayout(
          index: index,
          blocks: List.unmodifiable(pageBlocks[index]),
          bodyHeight: capacity(index),
        ),
      );
    }
    return NoteShareLayoutResult(
      logicalWidth: logicalWidth,
      logicalHeight: logicalHeight,
      outputPixelSize: pixelSize,
      pages: List.unmodifiable(pages),
    );
  }

  NoteShareLayoutResult _layoutLongImage({
    required NoteShareDraft draft,
    required NoteShareOptions options,
    required TextDirection textDirection,
    required String untitledTitle,
  }) {
    final blocks = _shareableBlocks(draft, options);
    final pageBlocks = <NoteSharePageBlock>[];
    var orderedNumber = 0;
    NoteBlockType? previousType;
    var bodyHeight = 0.0;
    for (final block in blocks) {
      if (block.type == NoteBlockType.ordered) {
        orderedNumber = previousType == NoteBlockType.ordered
            ? orderedNumber + 1
            : 1;
      } else {
        orderedNumber = 0;
      }
      pageBlocks.add(
        NoteSharePageBlock(
          block: block,
          orderedNumber: block.type == NoteBlockType.ordered
              ? orderedNumber
              : null,
        ),
      );
      bodyHeight += _blockHeight(
        block,
        draft: draft,
        options: options,
        textDirection: textDirection,
      );
      previousType = block.type;
    }

    final fixedHeight = _fixedChromeHeight(
      pageIndex: 0,
      draft: draft,
      options: options,
      textDirection: textDirection,
      untitledTitle: untitledTitle,
      landscape: false,
    );
    final paperFactor = NoteShareTemplateMetrics.of(
      options.template,
    ).paperHeightFactor;
    final logicalHeight = math.max(
      480.0,
      (fixedHeight + bodyHeight) / paperFactor,
    );
    final outputPixelSize = _longOutputPixelSize(
      logicalHeight,
      options.canvas.quality,
    );
    return NoteShareLayoutResult(
      logicalWidth: logicalWidth,
      logicalHeight: logicalHeight,
      outputPixelSize: outputPixelSize,
      pages: [
        NoteSharePageLayout(
          index: 0,
          blocks: List.unmodifiable(pageBlocks),
          bodyHeight: bodyHeight,
        ),
      ],
    );
  }

  NoteSharePixelSize _longOutputPixelSize(
    double logicalHeight,
    NoteShareQuality quality,
  ) {
    var width = quality.shortSide.toDouble();
    var height = width * logicalHeight / logicalWidth;
    final heightScale = NoteShareCanvasSpec.maxCustomHeight / height;
    final pixelScale = math.sqrt(
      NoteShareCanvasSpec.maxPixels / (width * height),
    );
    final scale = math.min(1.0, math.min(heightScale, pixelScale));
    width *= scale;
    height *= scale;
    return NoteSharePixelSize(width.round(), height.round());
  }

  List<NoteBlockData> _shareableBlocks(
    NoteShareDraft draft,
    NoteShareOptions options,
  ) {
    final richBlocks = NoteRichDocumentCodec.tryDecode(draft.richContent);
    final decoded =
        richBlocks != null &&
            NoteBlockCodec.structurallyMatches(richBlocks, draft.content)
        ? richBlocks
        : NoteBlockCodec.decode(draft.content);
    final result = <NoteBlockData>[];
    final referencedPaths = <String>{};
    for (final block in decoded) {
      if (block.type == NoteBlockType.attachment) {
        final path = block.attachmentPath;
        if (path != null) referencedPaths.add(path);
        if (!options.includeAttachments) continue;
      }
      if (block.text.trim().isEmpty &&
          block.type != NoteBlockType.divider &&
          block.type != NoteBlockType.attachment) {
        continue;
      }
      result.add(block);
    }
    if (options.includeAttachments) {
      for (final attachment in draft.attachments) {
        if (referencedPaths.contains(attachment.filePath)) continue;
        result.add(
          NoteBlockData(
            NoteBlockType.attachment,
            '',
            attachmentPath: attachment.filePath,
          ),
        );
      }
    }
    return result;
  }

  double _bodyCapacity({
    required double logicalHeight,
    required int pageIndex,
    required NoteShareDraft draft,
    required NoteShareOptions options,
    required TextDirection textDirection,
    required String untitledTitle,
  }) {
    final landscape = logicalHeight < logicalWidth;
    final paperHeight =
        logicalHeight *
        NoteShareTemplateMetrics.of(options.template).paperHeightFactor;
    final fixedHeight = _fixedChromeHeight(
      pageIndex: pageIndex,
      draft: draft,
      options: options,
      textDirection: textDirection,
      untitledTitle: untitledTitle,
      landscape: landscape,
    );
    return math.max(28, paperHeight - fixedHeight);
  }

  double _fixedChromeHeight({
    required int pageIndex,
    required NoteShareDraft draft,
    required NoteShareOptions options,
    required TextDirection textDirection,
    required String untitledTitle,
    required bool landscape,
  }) {
    final metrics = NoteShareTemplateMetrics.of(options.template);
    final paperPadding = metrics.verticalPadding(landscape) * 2;
    final runningHeader = pageIndex == 0
        ? options.includeDate
              ? 27.0
              : 8.0
        : 24.0;
    final title = pageIndex == 0 && options.includeTitle
        ? _measureText(
                draft.title.trim().isEmpty ? untitledTitle : draft.title.trim(),
                metrics.titleStyle(landscape),
                _contentWidth(options, landscape),
                textDirection,
                maxLines: 3,
              ) +
              metrics.titleTopGap(landscape) +
              metrics.titleBottomGap(landscape)
        : 0.0;
    final footer = 31.0 + footerGapFor(landscape) + chromeMeasurementSafety;
    return paperPadding + runningHeader + title + footer;
  }

  double _contentWidth(NoteShareOptions options, bool landscape) {
    final metrics = NoteShareTemplateMetrics.of(options.template);
    return logicalWidth * metrics.paperWidthFactor -
        metrics.horizontalPadding(landscape) * 2;
  }

  double _blockHeight(
    NoteBlockData block, {
    required NoteShareDraft draft,
    required NoteShareOptions options,
    required TextDirection textDirection,
  }) {
    final landscape = options.canvas.pixelSize.aspectRatio > 1;
    final width = _contentWidth(options, landscape) - block.indent * 14;
    final scale = options.density.scale;
    if (block.type == NoteBlockType.divider) {
      return dividerVerticalPadding * 2 + 1;
    }
    if (block.type == NoteBlockType.attachment) {
      final attachment = draft.attachmentsByPath[block.attachmentPath];
      final image = attachment?.type == NoteType.image;
      if (image && options.includeImages) {
        return (landscape ? landscapeImageHeight : portraitImageHeight) +
            attachmentBottomGap;
      }
      return attachmentMinHeight + attachmentBottomGap;
    }
    final style = NoteShareTextPresentation.baseStyle(block, scale);
    final prefixWidth = switch (block.type) {
      NoteBlockType.bullet ||
      NoteBlockType.ordered ||
      NoteBlockType.todo => 26.0,
      _ => 0.0,
    };
    final horizontalDecoration = switch (block.type) {
      NoteBlockType.quote => quoteHorizontalPadding,
      NoteBlockType.code || NoteBlockType.rawMarkdown => codePadding * 2,
      _ => 0.0,
    };
    final textHeight = _measureSpan(
      NoteShareTextPresentation.inlineSpan(block, style, densityScale: scale),
      math.max(40, width - prefixWidth - horizontalDecoration),
      textDirection,
    );
    final decoration = switch (block.type) {
      NoteBlockType.quote => quoteVerticalPadding,
      NoteBlockType.code || NoteBlockType.rawMarkdown => codePadding * 2,
      _ => 0.0,
    };
    // RichText can round individual line metrics slightly above TextPainter's
    // aggregate result. Keep a tiny per-block guard so those fractions never
    // accumulate into a visible RenderFlex overflow at the footer.
    return textHeight +
        decoration +
        (blockBottomGap + blockMeasurementSafety) * scale;
  }

  double _minimumSplitHeight(
    NoteBlockData block, {
    required NoteShareOptions options,
  }) {
    final scale = options.density.scale;
    final style = NoteShareTextPresentation.baseStyle(block, scale);
    final lineHeight = (style.fontSize ?? 15) * (style.height ?? 1.48);
    final decoration = switch (block.type) {
      NoteBlockType.quote => quoteVerticalPadding,
      NoteBlockType.code || NoteBlockType.rawMarkdown => codePadding * 2,
      _ => 0.0,
    };
    return lineHeight +
        decoration +
        (blockBottomGap + blockMeasurementSafety) * scale;
  }

  double _measureText(
    String text,
    TextStyle style,
    double maxWidth,
    TextDirection textDirection, {
    int? maxLines,
  }) {
    if (text.isEmpty) return 0;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      maxLines: maxLines,
      ellipsis: maxLines == null ? null : '…',
    )..layout(maxWidth: maxWidth);
    return painter.height;
  }

  double _measureSpan(
    InlineSpan span,
    double maxWidth,
    TextDirection textDirection,
  ) {
    final painter = TextPainter(text: span, textDirection: textDirection)
      ..layout(maxWidth: maxWidth);
    return painter.height;
  }

  bool _canSplit(NoteBlockData block) =>
      block.text.length > 1 &&
      block.type != NoteBlockType.heading &&
      block.type != NoteBlockType.divider &&
      block.type != NoteBlockType.attachment;

  (NoteBlockData, NoteBlockData)? _splitToFit(
    NoteBlockData block, {
    required double maxHeight,
    required NoteShareDraft draft,
    required NoteShareOptions options,
    required TextDirection textDirection,
  }) {
    if (!_canSplit(block)) return null;
    var low = 1;
    var high = block.text.length - 1;
    var best = 0;
    while (low <= high) {
      final middle = (low + high) ~/ 2;
      final index = _safeSplitIndex(block.text, middle);
      final head = _sliceBlock(block, 0, index);
      final height = _blockHeight(
        head,
        draft: draft,
        options: options,
        textDirection: textDirection,
      );
      if (height <= maxHeight) {
        best = index;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    if (best <= 0 || best >= block.text.length) return null;
    var splitAt = best;
    final preferred = block.text.lastIndexOf(
      RegExp(block.type == NoteBlockType.code ? r'\n' : r'[\n\s，。！？；、,.!?;]'),
      best,
    );
    if (preferred > best * .55) splitAt = preferred + 1;
    splitAt = _safeSplitIndex(block.text, splitAt);
    final preferredHead = _sliceBlock(block, 0, splitAt);
    if (_blockHeight(
          preferredHead,
          draft: draft,
          options: options,
          textDirection: textDirection,
        ) >
        maxHeight) {
      splitAt = best;
    }
    if (splitAt <= 0 || splitAt >= block.text.length) return null;
    return (
      _sliceBlock(block, 0, splitAt),
      _sliceBlock(block, splitAt, block.text.length),
    );
  }

  int _safeSplitIndex(String text, int index) {
    var result = index.clamp(1, text.length - 1);
    final code = text.codeUnitAt(result - 1);
    if (code >= 0xD800 && code <= 0xDBFF) result++;
    return result.clamp(1, text.length - 1);
  }

  NoteBlockData _sliceBlock(NoteBlockData block, int start, int end) {
    final styles = <NoteTextStyleRange>[];
    for (final range in block.styles) {
      final overlapStart = math.max(start, range.start);
      final overlapEnd = math.min(end, range.end);
      if (overlapStart >= overlapEnd) continue;
      styles.add(
        NoteTextStyleRange(
          overlapStart - start,
          overlapEnd - start,
          range.attributes,
        ),
      );
    }
    return NoteBlockData(
      block.type,
      block.text.substring(start, end),
      checked: block.checked,
      attachmentPath: block.attachmentPath,
      indent: block.indent,
      quoteDepth: block.quoteDepth,
      headingLevel: block.headingLevel,
      codeLanguage: block.codeLanguage,
      styles: styles,
    );
  }
}
