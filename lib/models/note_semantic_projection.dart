import 'dart:collection';

import 'note.dart';
import 'note_document.dart';

enum NoteSemanticBlockKind {
  paragraph,
  heading,
  bulletList,
  orderedList,
  checkedList,
  uncheckedList,
  blockQuote,
  codeBlock,
  attachment,
  divider,
}

enum NoteSemanticAlignment { start, center, end, justify }

/// Portable inline semantics derived from Quill Delta.
///
/// Deliberately excludes editor-only presentation such as a temporary font or
/// color. Consumers choose a legible palette while retaining the author's
/// emphasis and links.
final class NoteSemanticStyle {
  const NoteSemanticStyle({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikeThrough = false,
    this.inlineCode = false,
    this.link,
  });

  factory NoteSemanticStyle.fromDeltaAttributes(
    Map<String, dynamic>? attributes,
  ) {
    final values = attributes ?? const <String, dynamic>{};
    final rawLink = values['link'];
    return NoteSemanticStyle(
      bold: values['bold'] == true,
      italic: values['italic'] == true,
      underline: values['underline'] == true,
      strikeThrough: values['strike'] == true,
      inlineCode: values['code'] == true,
      link: rawLink is String && rawLink.trim().isNotEmpty
          ? rawLink.trim()
          : null,
    );
  }

  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikeThrough;
  final bool inlineCode;
  final String? link;
}

final class NoteSemanticRun {
  const NoteSemanticRun({required this.text, required this.style});

  final String text;
  final NoteSemanticStyle style;
}

final class NoteSemanticBlock {
  NoteSemanticBlock._({
    required this.kind,
    Iterable<NoteSemanticRun> runs = const [],
    this.headingLevel,
    this.indent = 0,
    this.alignment = NoteSemanticAlignment.start,
    this.asset,
  }) : runs = List.unmodifiable(runs);

  factory NoteSemanticBlock.text({
    required NoteSemanticBlockKind kind,
    required Iterable<NoteSemanticRun> runs,
    int? headingLevel,
    int indent = 0,
    NoteSemanticAlignment alignment = NoteSemanticAlignment.start,
  }) {
    if (kind == NoteSemanticBlockKind.attachment ||
        kind == NoteSemanticBlockKind.divider) {
      throw ArgumentError.value(kind, 'kind', 'Expected a text block.');
    }
    return NoteSemanticBlock._(
      kind: kind,
      runs: runs,
      headingLevel: headingLevel,
      indent: indent,
      alignment: alignment,
    );
  }

  factory NoteSemanticBlock.attachment(NoteAsset asset) =>
      NoteSemanticBlock._(kind: NoteSemanticBlockKind.attachment, asset: asset);

  factory NoteSemanticBlock.divider() =>
      NoteSemanticBlock._(kind: NoteSemanticBlockKind.divider);

  final NoteSemanticBlockKind kind;
  final List<NoteSemanticRun> runs;
  final int? headingLevel;
  final int indent;
  final NoteSemanticAlignment alignment;
  final NoteAsset? asset;

  String get plainText => runs.map((run) => run.text).join();
}

/// Consumer-neutral reading of a canonical note.
///
/// This projection is built only when a persisted snapshot is consumed. It is
/// never maintained during typing, so richer sharing and AI context do not add
/// work to the editor's keystroke path.
final class NoteSemanticProjection {
  NoteSemanticProjection._({
    required this.noteId,
    required this.title,
    required Iterable<String> tags,
    required Iterable<NoteSemanticBlock> blocks,
    required this.createdAt,
    required this.updatedAt,
  }) : tags = List.unmodifiable(tags),
       blocks = List.unmodifiable(blocks);

  factory NoteSemanticProjection.fromNote(Note note) {
    final parser = _NoteDeltaSemanticParser(note.assetsById);
    return NoteSemanticProjection._(
      noteId: note.id,
      title: note.title.trim(),
      tags: note.tags,
      blocks: parser.parse(note.document),
      createdAt: note.createdAt,
      updatedAt: note.updatedAt,
    );
  }

  final NoteId noteId;
  final String title;
  final List<String> tags;
  final List<NoteSemanticBlock> blocks;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Text that is genuinely visible to a reader. Attachment names, OCR,
  /// transcripts and divider glyphs are intentionally excluded.
  String get bodyText => blocks
      .where((block) => _isReadableTextBlock(block.kind))
      .map((block) => block.plainText.trimRight())
      .join('\n')
      .trim();

  String speechText({bool includeTitle = true}) => [
    if (includeTitle && title.isNotEmpty) title,
    if (bodyText.isNotEmpty) bodyText,
  ].join('\n\n');

  /// Structured local-AI input. Extracted media text remains adjacent to the
  /// attachment that produced it and is included only once even when the same
  /// asset is embedded repeatedly.
  String assistantSource({
    int maxCharacters = 2800,
    String languageCode = 'zh',
  }) {
    if (maxCharacters <= 0) return '';
    final english = languageCode.toLowerCase().startsWith('en');
    final buffer = StringBuffer();
    void section(String label, String value) {
      final normalized = value.trim();
      if (normalized.isEmpty) return;
      if (buffer.isNotEmpty) buffer.writeln('\n');
      buffer.writeln('$label:');
      buffer.write(normalized);
    }

    section(english ? 'Title' : '标题', title);
    section(english ? 'Tags' : '标签', tags.join(english ? ', ' : '、'));

    final body = StringBuffer();
    final describedAssets = <NoteAttachmentId>{};
    var orderedNumber = 0;
    NoteSemanticBlockKind? previousKind;
    for (final block in blocks) {
      if (block.kind != NoteSemanticBlockKind.orderedList ||
          previousKind != NoteSemanticBlockKind.orderedList) {
        orderedNumber = 0;
      }
      previousKind = block.kind;
      switch (block.kind) {
        case NoteSemanticBlockKind.attachment:
          final asset = block.asset!;
          if (!describedAssets.add(asset.id)) break;
          _writeSeparatedLine(
            body,
            english
                ? '[Attachment: ${asset.displayTitle}]'
                : '【附件：${asset.displayTitle}】',
          );
          final ocr = asset.ocrText?.trim() ?? '';
          if (ocr.isNotEmpty) {
            _writeSeparatedLine(
              body,
              '${english ? 'Image text' : '图片文字'}:\n$ocr',
            );
          }
          final transcript = asset.transcript?.trim() ?? '';
          if (transcript.isNotEmpty) {
            _writeSeparatedLine(
              body,
              '${english ? 'Transcript' : '语音转写'}:\n$transcript',
            );
          }
        case NoteSemanticBlockKind.divider:
          _writeSeparatedLine(body, '——');
        case NoteSemanticBlockKind.heading:
          _writeSeparatedLine(
            body,
            '${english ? 'Heading' : '小标题'}：${block.plainText}',
          );
        case NoteSemanticBlockKind.bulletList:
          _writeSeparatedLine(body, '• ${block.plainText}');
        case NoteSemanticBlockKind.orderedList:
          orderedNumber++;
          _writeSeparatedLine(body, '$orderedNumber. ${block.plainText}');
        case NoteSemanticBlockKind.checkedList:
          _writeSeparatedLine(body, '☑ ${block.plainText}');
        case NoteSemanticBlockKind.uncheckedList:
          _writeSeparatedLine(body, '☐ ${block.plainText}');
        case NoteSemanticBlockKind.blockQuote:
          _writeSeparatedLine(
            body,
            '${english ? 'Quote' : '引用'}：${block.plainText}',
          );
        case NoteSemanticBlockKind.codeBlock:
          _writeSeparatedLine(
            body,
            '${english ? 'Code' : '代码'}：\n${block.plainText}',
          );
        case NoteSemanticBlockKind.paragraph:
          _writeSeparatedLine(body, block.plainText);
      }
    }
    section(english ? 'Body' : '正文', body.toString());

    return _fitRunes(
      buffer.toString().trim(),
      maxCharacters,
      english ? '\n…[middle omitted]…\n' : '\n…[中间内容已省略]…\n',
    );
  }

  static bool _isReadableTextBlock(NoteSemanticBlockKind kind) =>
      kind != NoteSemanticBlockKind.attachment &&
      kind != NoteSemanticBlockKind.divider;

  static void _writeSeparatedLine(StringBuffer buffer, String value) {
    if (buffer.isNotEmpty) buffer.writeln();
    buffer.write(value.trimRight());
  }

  static String _fitRunes(String source, int limit, String marker) {
    final codePoints = source.runes.toList(growable: false);
    if (codePoints.length <= limit) return source;
    final markerCodePoints = marker.runes.toList(growable: false);
    if (limit <= markerCodePoints.length) {
      return String.fromCharCodes(codePoints.take(limit));
    }
    final available = limit - markerCodePoints.length;
    final leading = (available * .65).floor();
    final trailing = available - leading;
    return String.fromCharCodes([
      ...codePoints.take(leading),
      ...markerCodePoints,
      ...codePoints.skip(codePoints.length - trailing),
    ]);
  }
}

final class _NoteDeltaSemanticParser {
  _NoteDeltaSemanticParser(Map<NoteAttachmentId, NoteAsset> assets)
    : _assets = UnmodifiableMapView(assets);

  final UnmodifiableMapView<NoteAttachmentId, NoteAsset> _assets;
  final List<NoteSemanticBlock> _blocks = [];
  final List<NoteSemanticRun> _runs = [];
  NoteEmbed? _pendingEmbed;

  List<NoteSemanticBlock> parse(NoteDocument document) {
    for (final operation in document.toDelta().operations) {
      final data = operation.data;
      if (data is! String) {
        _pendingEmbed = NoteEmbed.parse(data);
        continue;
      }

      var start = 0;
      for (var index = 0; index < data.length; index++) {
        if (data.codeUnitAt(index) != 10) continue;
        if (index > start) {
          _appendRun(data.substring(start, index), operation.attributes);
        }
        _finishLine(operation.attributes);
        start = index + 1;
      }
      if (start < data.length) {
        _appendRun(data.substring(start), operation.attributes);
      }
    }
    return List.unmodifiable(_blocks);
  }

  void _appendRun(String text, Map<String, dynamic>? attributes) {
    if (text.isEmpty) return;
    final run = NoteSemanticRun(
      text: text,
      style: NoteSemanticStyle.fromDeltaAttributes(attributes),
    );
    if (_runs.isNotEmpty && _sameStyle(_runs.last.style, run.style)) {
      final previous = _runs.removeLast();
      _runs.add(
        NoteSemanticRun(
          text: '${previous.text}${run.text}',
          style: previous.style,
        ),
      );
    } else {
      _runs.add(run);
    }
  }

  void _finishLine(Map<String, dynamic>? attributes) {
    final embed = _pendingEmbed;
    if (embed != null) {
      _blocks.add(switch (embed.kind) {
        NoteEmbedKind.attachment => NoteSemanticBlock.attachment(
          _assets[embed.attachmentId]!,
        ),
        NoteEmbedKind.divider => NoteSemanticBlock.divider(),
      });
      _pendingEmbed = null;
      return;
    }

    final values = attributes ?? const <String, dynamic>{};
    final header = values['header'];
    final list = values['list'];
    final kind = switch ((header, list)) {
      (_, _) when values['code-block'] == true =>
        NoteSemanticBlockKind.codeBlock,
      (_, _) when values['blockquote'] == true =>
        NoteSemanticBlockKind.blockQuote,
      (_, 'bullet') => NoteSemanticBlockKind.bulletList,
      (_, 'ordered') => NoteSemanticBlockKind.orderedList,
      (_, 'checked') => NoteSemanticBlockKind.checkedList,
      (_, 'unchecked') => NoteSemanticBlockKind.uncheckedList,
      (int value, _) when value >= 1 && value <= 6 =>
        NoteSemanticBlockKind.heading,
      _ => NoteSemanticBlockKind.paragraph,
    };
    final rawIndent = values['indent'];
    _blocks.add(
      NoteSemanticBlock.text(
        kind: kind,
        runs: List.of(_runs),
        headingLevel: kind == NoteSemanticBlockKind.heading
            ? header as int
            : null,
        indent: rawIndent is int && rawIndent > 0 ? rawIndent : 0,
        alignment: _alignment(values['align']),
      ),
    );
    _runs.clear();
  }

  static NoteSemanticAlignment _alignment(Object? value) => switch (value) {
    'center' => NoteSemanticAlignment.center,
    'right' => NoteSemanticAlignment.end,
    'justify' => NoteSemanticAlignment.justify,
    _ => NoteSemanticAlignment.start,
  };

  static bool _sameStyle(NoteSemanticStyle first, NoteSemanticStyle second) =>
      first.bold == second.bold &&
      first.italic == second.italic &&
      first.underline == second.underline &&
      first.strikeThrough == second.strikeThrough &&
      first.inlineCode == second.inlineCode &&
      first.link == second.link;
}
