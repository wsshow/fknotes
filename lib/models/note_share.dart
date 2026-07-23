import 'dart:math' as math;

import 'note.dart';
import 'note_document.dart';
import 'note_semantic_projection.dart';

enum NoteShareTemplateId {
  letter,
  plain,
  night,
  editorial,
  newspaper,
  manuscript,
  botanical,
  blueprint,
  amber,
  film,
  postcard,
  gallery,
  neon,
  tide,
  vermilion,
}

enum NoteShareCanvasPreset {
  square,
  portraitFourFive,
  noteThreeFour,
  storyNineSixteen,
  landscapeSixteenNine,
  a4,
  long,
  custom,
}

enum NoteShareOrientation { portrait, landscape }

enum NoteShareQuality {
  standard(1080),
  high(1440),
  ultra(2160);

  final int shortSide;
  const NoteShareQuality(this.shortSide);
}

enum NoteShareDensity {
  comfortable(1.12),
  standard(1),
  compact(.88);

  final double scale;
  const NoteShareDensity(this.scale);
}

class NoteSharePixelSize {
  final int width;
  final int height;

  const NoteSharePixelSize(this.width, this.height);

  double get aspectRatio => width / height;
  int get pixels => width * height;

  NoteSharePixelSize swapped() => NoteSharePixelSize(height, width);

  @override
  bool operator ==(Object other) =>
      other is NoteSharePixelSize &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(width, height);
}

class NoteShareCanvasSpec {
  static const minCustomSide = 480;
  static const maxCustomWidth = 4096;
  static const maxCustomHeight = 12000;
  static const maxPixels = 20 * 1000 * 1000;

  final NoteShareCanvasPreset preset;
  final NoteShareOrientation orientation;
  final NoteShareQuality quality;
  final int customWidth;
  final int customHeight;

  const NoteShareCanvasSpec({
    this.preset = NoteShareCanvasPreset.noteThreeFour,
    this.orientation = NoteShareOrientation.portrait,
    this.quality = NoteShareQuality.standard,
    this.customWidth = 1080,
    this.customHeight = 1440,
  });

  bool get isCustom => preset == NoteShareCanvasPreset.custom;
  bool get isLong => preset == NoteShareCanvasPreset.long;

  NoteSharePixelSize get pixelSize {
    if (isCustom) {
      final width = customWidth.clamp(minCustomSide, maxCustomWidth);
      final height = customHeight.clamp(minCustomSide, maxCustomHeight);
      return _boundedCustomSize(width, height);
    }
    final ratio = switch (preset) {
      NoteShareCanvasPreset.square => (1.0, 1.0),
      NoteShareCanvasPreset.portraitFourFive => (4.0, 5.0),
      NoteShareCanvasPreset.noteThreeFour => (3.0, 4.0),
      NoteShareCanvasPreset.storyNineSixteen => (9.0, 16.0),
      NoteShareCanvasPreset.landscapeSixteenNine => (16.0, 9.0),
      NoteShareCanvasPreset.a4 => (210.0, 297.0),
      NoteShareCanvasPreset.long => (3.0, 5.4),
      NoteShareCanvasPreset.custom => throw StateError('handled above'),
    };
    var widthRatio = ratio.$1;
    var heightRatio = ratio.$2;
    if (orientation == NoteShareOrientation.portrait &&
        widthRatio > heightRatio) {
      (widthRatio, heightRatio) = (heightRatio, widthRatio);
    }
    if (orientation == NoteShareOrientation.landscape &&
        widthRatio < heightRatio &&
        !isLong) {
      (widthRatio, heightRatio) = (heightRatio, widthRatio);
    }
    final scale = quality.shortSide / math.min(widthRatio, heightRatio);
    return NoteSharePixelSize(
      (widthRatio * scale).round(),
      (heightRatio * scale).round(),
    );
  }

  NoteSharePixelSize _boundedCustomSize(int width, int height) {
    final pixels = width * height;
    if (pixels <= maxPixels) return NoteSharePixelSize(width, height);
    final scale = math.sqrt(maxPixels / pixels);
    return NoteSharePixelSize(
      math.max(minCustomSide, (width * scale).floor()),
      math.max(minCustomSide, (height * scale).floor()),
    );
  }

  NoteShareCanvasSpec copyWith({
    NoteShareCanvasPreset? preset,
    NoteShareOrientation? orientation,
    NoteShareQuality? quality,
    int? customWidth,
    int? customHeight,
  }) => NoteShareCanvasSpec(
    preset: preset ?? this.preset,
    orientation: orientation ?? this.orientation,
    quality: quality ?? this.quality,
    customWidth: customWidth ?? this.customWidth,
    customHeight: customHeight ?? this.customHeight,
  );

  Map<String, Object> toJson() => {
    'preset': preset.name,
    'orientation': orientation.name,
    'quality': quality.name,
    'customWidth': customWidth,
    'customHeight': customHeight,
  };

  factory NoteShareCanvasSpec.fromJson(Map<String, Object?> json) =>
      NoteShareCanvasSpec(
        preset: _enumByName(
          NoteShareCanvasPreset.values,
          json['preset'],
          NoteShareCanvasPreset.noteThreeFour,
        ),
        orientation: _enumByName(
          NoteShareOrientation.values,
          json['orientation'],
          NoteShareOrientation.portrait,
        ),
        quality: _enumByName(
          NoteShareQuality.values,
          json['quality'],
          NoteShareQuality.standard,
        ),
        customWidth: (json['customWidth'] as num?)?.round() ?? 1080,
        customHeight: (json['customHeight'] as num?)?.round() ?? 1440,
      );
}

class NoteShareOptions {
  final NoteShareTemplateId template;
  final NoteShareCanvasSpec canvas;
  final NoteShareDensity density;
  final bool includeTitle;
  final bool includeDate;
  final bool includeTags;
  final bool includeImages;
  final bool includeAttachments;

  const NoteShareOptions({
    this.template = NoteShareTemplateId.letter,
    this.canvas = const NoteShareCanvasSpec(),
    this.density = NoteShareDensity.standard,
    this.includeTitle = true,
    this.includeDate = true,
    this.includeTags = true,
    this.includeImages = true,
    this.includeAttachments = true,
  });

  NoteShareOptions copyWith({
    NoteShareTemplateId? template,
    NoteShareCanvasSpec? canvas,
    NoteShareDensity? density,
    bool? includeTitle,
    bool? includeDate,
    bool? includeTags,
    bool? includeImages,
    bool? includeAttachments,
  }) => NoteShareOptions(
    template: template ?? this.template,
    canvas: canvas ?? this.canvas,
    density: density ?? this.density,
    includeTitle: includeTitle ?? this.includeTitle,
    includeDate: includeDate ?? this.includeDate,
    includeTags: includeTags ?? this.includeTags,
    includeImages: includeImages ?? this.includeImages,
    includeAttachments: includeAttachments ?? this.includeAttachments,
  );

  Map<String, Object> toJson() => {
    'template': template.name,
    'canvas': canvas.toJson(),
    'density': density.name,
    'includeTitle': includeTitle,
    'includeDate': includeDate,
    'includeTags': includeTags,
    'includeImages': includeImages,
    'includeAttachments': includeAttachments,
  };

  factory NoteShareOptions.fromJson(Map<String, Object?> json) =>
      NoteShareOptions(
        template: _enumByName(
          NoteShareTemplateId.values,
          json['template'],
          NoteShareTemplateId.letter,
        ),
        canvas: json['canvas'] is Map
            ? NoteShareCanvasSpec.fromJson(
                Map<String, Object?>.from(json['canvas'] as Map),
              )
            : const NoteShareCanvasSpec(),
        density: _enumByName(
          NoteShareDensity.values,
          json['density'],
          NoteShareDensity.standard,
        ),
        includeTitle: json['includeTitle'] as bool? ?? true,
        includeDate: json['includeDate'] as bool? ?? true,
        includeTags: json['includeTags'] as bool? ?? true,
        includeImages: json['includeImages'] as bool? ?? true,
        includeAttachments: json['includeAttachments'] as bool? ?? true,
      );
}

enum NoteShareBlockType {
  paragraph,
  heading,
  bullet,
  ordered,
  todo,
  quote,
  code,
  divider,
  table,
  attachment,
}

final class NoteShareTextStyle {
  const NoteShareTextStyle({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikeThrough = false,
    this.inlineCode = false,
    this.link,
  });

  factory NoteShareTextStyle.fromSemantic(NoteSemanticStyle style) =>
      NoteShareTextStyle(
        bold: style.bold,
        italic: style.italic,
        underline: style.underline,
        strikeThrough: style.strikeThrough,
        inlineCode: style.inlineCode,
        link: style.link,
      );

  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikeThrough;
  final bool inlineCode;
  final String? link;
}

final class NoteShareTextRange {
  const NoteShareTextRange(this.start, this.end, this.style)
    : assert(start >= 0),
      assert(end >= start);

  final int start;
  final int end;
  final NoteShareTextStyle style;
}

final class NoteShareBlock {
  NoteShareBlock({
    required this.type,
    this.text = '',
    this.checked = false,
    this.indent = 0,
    this.headingLevel = 0,
    this.asset,
    this.table,
    Iterable<NoteShareTextRange> styles = const [],
  }) : styles = List.unmodifiable(styles) {
    if (type == NoteShareBlockType.attachment && asset == null) {
      throw ArgumentError('An attachment share block requires its asset.');
    }
    if (type != NoteShareBlockType.attachment && asset != null) {
      throw ArgumentError('Only attachment share blocks may own an asset.');
    }
    if (type == NoteShareBlockType.table && table == null) {
      throw ArgumentError('A table share block requires its table.');
    }
    if (type != NoteShareBlockType.table && table != null) {
      throw ArgumentError('Only table share blocks may own a table.');
    }
    for (final range in this.styles) {
      if (range.end > text.length) {
        throw ArgumentError('A share text style exceeds its block.');
      }
    }
  }

  factory NoteShareBlock.fromSemantic(NoteSemanticBlock block) {
    if (block.kind == NoteSemanticBlockKind.attachment) {
      return NoteShareBlock(
        type: NoteShareBlockType.attachment,
        asset: block.asset,
      );
    }
    if (block.kind == NoteSemanticBlockKind.divider) {
      return NoteShareBlock(type: NoteShareBlockType.divider);
    }
    if (block.kind == NoteSemanticBlockKind.table) {
      return NoteShareBlock(type: NoteShareBlockType.table, table: block.table);
    }
    final text = StringBuffer();
    final styles = <NoteShareTextRange>[];
    for (final run in block.runs) {
      final start = text.length;
      text.write(run.text);
      final end = text.length;
      final style = NoteShareTextStyle.fromSemantic(run.style);
      if (_hasPortableStyle(style) && end > start) {
        styles.add(NoteShareTextRange(start, end, style));
      }
    }
    return NoteShareBlock(
      type: switch (block.kind) {
        NoteSemanticBlockKind.paragraph => NoteShareBlockType.paragraph,
        NoteSemanticBlockKind.heading => NoteShareBlockType.heading,
        NoteSemanticBlockKind.bulletList => NoteShareBlockType.bullet,
        NoteSemanticBlockKind.orderedList => NoteShareBlockType.ordered,
        NoteSemanticBlockKind.checkedList => NoteShareBlockType.todo,
        NoteSemanticBlockKind.uncheckedList => NoteShareBlockType.todo,
        NoteSemanticBlockKind.blockQuote => NoteShareBlockType.quote,
        NoteSemanticBlockKind.codeBlock => NoteShareBlockType.code,
        NoteSemanticBlockKind.attachment ||
        NoteSemanticBlockKind.divider ||
        NoteSemanticBlockKind.table => throw StateError('Handled above.'),
      },
      text: text.toString(),
      checked: block.kind == NoteSemanticBlockKind.checkedList,
      indent: block.indent,
      headingLevel: block.headingLevel ?? 0,
      styles: styles,
    );
  }

  final NoteShareBlockType type;
  final String text;
  final bool checked;
  final int indent;
  final int headingLevel;
  final NoteAsset? asset;
  final NoteTable? table;
  final List<NoteShareTextRange> styles;

  NoteShareBlock slice(int start, int end) {
    if (type == NoteShareBlockType.attachment ||
        type == NoteShareBlockType.divider ||
        type == NoteShareBlockType.table) {
      throw StateError('Only text share blocks can be sliced.');
    }
    final slicedStyles = <NoteShareTextRange>[];
    for (final range in styles) {
      final overlapStart = math.max(start, range.start);
      final overlapEnd = math.min(end, range.end);
      if (overlapStart < overlapEnd) {
        slicedStyles.add(
          NoteShareTextRange(
            overlapStart - start,
            overlapEnd - start,
            range.style,
          ),
        );
      }
    }
    return NoteShareBlock(
      type: type,
      text: text.substring(start, end),
      checked: checked,
      indent: indent,
      headingLevel: headingLevel,
      styles: slicedStyles,
    );
  }

  static bool _hasPortableStyle(NoteShareTextStyle style) =>
      style.bold ||
      style.italic ||
      style.underline ||
      style.strikeThrough ||
      style.inlineCode ||
      style.link != null;
}

final class NoteShareDraft {
  NoteShareDraft({
    required this.title,
    required Iterable<NoteShareBlock> blocks,
    required Iterable<String> tags,
    required this.createdAt,
    required this.updatedAt,
  }) : blocks = List.unmodifiable(blocks),
       tags = List.unmodifiable(tags);

  factory NoteShareDraft.fromNote(Note note) {
    final projection = NoteSemanticProjection.fromNote(note);
    return NoteShareDraft(
      title: projection.title,
      blocks: projection.blocks.map(NoteShareBlock.fromSemantic),
      tags: projection.tags,
      createdAt: projection.createdAt,
      updatedAt: projection.updatedAt,
    );
  }

  final String title;
  final List<NoteShareBlock> blocks;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;

  List<NoteAsset> get attachments {
    final seen = <NoteAttachmentId>{};
    return List.unmodifiable(
      blocks
          .map((block) => block.asset)
          .whereType<NoteAsset>()
          .where((asset) => seen.add(asset.id)),
    );
  }

  bool get hasContent =>
      title.trim().isNotEmpty ||
      blocks.any(
        (block) =>
            block.text.trim().isNotEmpty ||
            block.type == NoteShareBlockType.attachment ||
            block.type == NoteShareBlockType.table,
      );
}

T _enumByName<T extends Enum>(List<T> values, Object? raw, T fallback) {
  if (raw is! String) return fallback;
  return values.firstWhere(
    (value) => value.name == raw,
    orElse: () => fallback,
  );
}
