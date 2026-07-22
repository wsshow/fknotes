import 'dart:math' as math;

import 'note_entry.dart';

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

class NoteShareDraft {
  final String title;
  final String content;
  final List<String> tags;
  final List<NoteAttachment> attachments;
  final DateTime createdAt;
  final DateTime updatedAt;

  const NoteShareDraft({
    required this.title,
    required this.content,
    required this.tags,
    required this.attachments,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get hasContent =>
      title.trim().isNotEmpty ||
      content.trim().isNotEmpty ||
      attachments.isNotEmpty;

  Map<String, NoteAttachment> get attachmentsByPath => {
    for (final attachment in attachments) attachment.filePath: attachment,
  };
}

T _enumByName<T extends Enum>(List<T> values, Object? raw, T fallback) {
  if (raw is! String) return fallback;
  return values.firstWhere(
    (value) => value.name == raw,
    orElse: () => fallback,
  );
}
