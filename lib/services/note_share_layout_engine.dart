import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/note.dart';
import '../models/note_share.dart';
import '../models/note_share_theme.dart';

class NoteSharePageBlock {
  final NoteShareBlock block;
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

  static String displayText(NoteShareBlock block) => block.text;

  static TextStyle baseStyle(
    NoteShareBlock block,
    double densityScale, {
    Color? color,
  }) {
    final fontSize = switch (block.type) {
      NoteShareBlockType.heading => switch (block.headingLevel.clamp(1, 6)) {
        1 => 21.0,
        2 => 19.0,
        _ => 17.0,
      },
      NoteShareBlockType.code => 12.5,
      _ => 15.0,
    };
    return TextStyle(
      color: color,
      fontFamily: block.type == NoteShareBlockType.code ? 'monospace' : null,
      fontSize: fontSize * densityScale,
      height: block.type == NoteShareBlockType.heading ? 1.28 : 1.48,
      fontWeight: block.type == NoteShareBlockType.heading
          ? FontWeight.w700
          : FontWeight.w400,
    );
  }

  static TextSpan inlineSpan(
    NoteShareBlock block,
    TextStyle base, {
    required double densityScale,
    Color? linkColor,
    Color? inlineCodeBackground,
  }) {
    final text = displayText(block);
    if (block.styles.isEmpty) {
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
      final attributes = range.style;
      final decorations = <TextDecoration>[
        if (attributes.strikeThrough) TextDecoration.lineThrough,
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
    NoteShareBlockType? previousType;

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

    void addBlock(NoteShareBlock block, {bool showMarker = true}) {
      if (block.type == NoteShareBlockType.ordered && showMarker) {
        orderedNumber = previousType == NoteShareBlockType.ordered
            ? orderedNumber + 1
            : 1;
      } else if (block.type != NoteShareBlockType.ordered) {
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
              orderedNumber: remainingBlock.type == NoteShareBlockType.ordered
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
                  orderedNumber:
                      remainingBlock.type == NoteShareBlockType.ordered
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
              orderedNumber: remainingBlock.type == NoteShareBlockType.ordered
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
            orderedNumber: remainingBlock.type == NoteShareBlockType.ordered
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
    NoteShareBlockType? previousType;
    var bodyHeight = 0.0;
    for (final block in blocks) {
      if (block.type == NoteShareBlockType.ordered) {
        orderedNumber = previousType == NoteShareBlockType.ordered
            ? orderedNumber + 1
            : 1;
      } else {
        orderedNumber = 0;
      }
      pageBlocks.add(
        NoteSharePageBlock(
          block: block,
          orderedNumber: block.type == NoteShareBlockType.ordered
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

  List<NoteShareBlock> _shareableBlocks(
    NoteShareDraft draft,
    NoteShareOptions options,
  ) {
    final result = <NoteShareBlock>[];
    for (final block in draft.blocks) {
      if (block.type == NoteShareBlockType.attachment) {
        if (!options.includeAttachments) continue;
      }
      if (block.text.trim().isEmpty &&
          block.type != NoteShareBlockType.divider &&
          block.type != NoteShareBlockType.attachment) {
        continue;
      }
      result.add(block);
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
    NoteShareBlock block, {
    required NoteShareDraft draft,
    required NoteShareOptions options,
    required TextDirection textDirection,
  }) {
    final landscape = options.canvas.pixelSize.aspectRatio > 1;
    final width = _contentWidth(options, landscape) - block.indent * 14;
    final scale = options.density.scale;
    if (block.type == NoteShareBlockType.divider) {
      return dividerVerticalPadding * 2 + 1;
    }
    if (block.type == NoteShareBlockType.attachment) {
      final image = block.asset?.kind == NoteAssetKind.image;
      if (image && options.includeImages) {
        return (landscape ? landscapeImageHeight : portraitImageHeight) +
            attachmentBottomGap;
      }
      return attachmentMinHeight + attachmentBottomGap;
    }
    final style = NoteShareTextPresentation.baseStyle(block, scale);
    final prefixWidth = switch (block.type) {
      NoteShareBlockType.bullet ||
      NoteShareBlockType.ordered ||
      NoteShareBlockType.todo => 26.0,
      _ => 0.0,
    };
    final horizontalDecoration = switch (block.type) {
      NoteShareBlockType.quote => quoteHorizontalPadding,
      NoteShareBlockType.code => codePadding * 2,
      _ => 0.0,
    };
    final textHeight = _measureSpan(
      NoteShareTextPresentation.inlineSpan(block, style, densityScale: scale),
      math.max(40, width - prefixWidth - horizontalDecoration),
      textDirection,
    );
    final decoration = switch (block.type) {
      NoteShareBlockType.quote => quoteVerticalPadding,
      NoteShareBlockType.code => codePadding * 2,
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
    NoteShareBlock block, {
    required NoteShareOptions options,
  }) {
    final scale = options.density.scale;
    final style = NoteShareTextPresentation.baseStyle(block, scale);
    final lineHeight = (style.fontSize ?? 15) * (style.height ?? 1.48);
    final decoration = switch (block.type) {
      NoteShareBlockType.quote => quoteVerticalPadding,
      NoteShareBlockType.code => codePadding * 2,
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

  bool _canSplit(NoteShareBlock block) =>
      block.text.length > 1 &&
      block.type != NoteShareBlockType.heading &&
      block.type != NoteShareBlockType.divider &&
      block.type != NoteShareBlockType.attachment;

  (NoteShareBlock, NoteShareBlock)? _splitToFit(
    NoteShareBlock block, {
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
      RegExp(
        block.type == NoteShareBlockType.code ? r'\n' : r'[\n\s，。！？；、,.!?;]',
      ),
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

  NoteShareBlock _sliceBlock(NoteShareBlock block, int start, int end) =>
      block.slice(start, end);
}
