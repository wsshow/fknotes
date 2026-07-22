import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;

import '../app.dart';
import '../l10n/l10n.dart';
import '../models/note_entry.dart';
import '../services/file_storage_service.dart';
import '../services/note_assistant_prompt_builder.dart';
import 'app_feedback.dart';
import 'app_popup_menu.dart';
import 'editor_context_menu.dart';
import 'fk_markdown_view.dart';
import 'note_card.dart';

enum NoteBlockType {
  paragraph,
  heading,
  bullet,
  ordered,
  todo,
  quote,
  code,
  rawMarkdown,
  divider,
  attachment,
}

String _localizedNoteType(BuildContext context, NoteType type) =>
    switch (type) {
      NoteType.text => context.l10n.note,
      NoteType.image => context.l10n.image,
      NoteType.audio => context.l10n.audio,
      NoteType.video => context.l10n.video,
      NoteType.document => context.l10n.file,
    };

class NoteBlockData {
  final NoteBlockType type;
  final String text;
  final bool checked;
  final String? attachmentPath;
  final int indent;
  final int quoteDepth;
  final int headingLevel;
  final String? codeLanguage;
  final List<NoteTextStyleRange> styles;

  const NoteBlockData(
    this.type,
    this.text, {
    this.checked = false,
    this.attachmentPath,
    this.indent = 0,
    this.quoteDepth = 0,
    this.headingLevel = 0,
    this.codeLanguage,
    this.styles = const [],
  });
}

class NoteTextAttributes {
  static const defaultFontSize = 17.0;
  static const defaults = NoteTextAttributes();

  final bool bold;
  final bool italic;
  final bool strikethrough;
  final bool inlineCode;
  final bool image;
  final bool underline;
  final double fontSize;
  final String? link;

  static const Object _keepLink = Object();

  const NoteTextAttributes({
    this.bold = false,
    this.italic = false,
    this.strikethrough = false,
    this.inlineCode = false,
    this.image = false,
    this.underline = false,
    this.fontSize = defaultFontSize,
    this.link,
  });

  NoteTextAttributes copyWith({
    bool? bold,
    bool? italic,
    bool? strikethrough,
    bool? inlineCode,
    bool? image,
    bool? underline,
    double? fontSize,
    Object? link = _keepLink,
  }) => NoteTextAttributes(
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    strikethrough: strikethrough ?? this.strikethrough,
    inlineCode: inlineCode ?? this.inlineCode,
    image: image ?? this.image,
    underline: underline ?? this.underline,
    fontSize: fontSize ?? this.fontSize,
    link: identical(link, _keepLink) ? this.link : link as String?,
  );

  Map<String, Object> toMap() => {
    if (bold) 'bold': true,
    if (italic) 'italic': true,
    if (strikethrough) 'strikethrough': true,
    if (inlineCode) 'inlineCode': true,
    if (image) 'image': true,
    if (underline) 'underline': true,
    if (fontSize != defaultFontSize) 'fontSize': fontSize,
    'link': ?link,
  };

  factory NoteTextAttributes.fromMap(Map<String, Object?> map) =>
      NoteTextAttributes(
        bold: map['bold'] == true,
        italic: map['italic'] == true,
        strikethrough: map['strikethrough'] == true,
        inlineCode: map['inlineCode'] == true,
        image: map['image'] == true,
        underline: map['underline'] == true,
        fontSize: ((map['fontSize'] as num?)?.toDouble() ?? defaultFontSize)
            .clamp(12, 36),
        link: map['link'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is NoteTextAttributes &&
      bold == other.bold &&
      italic == other.italic &&
      strikethrough == other.strikethrough &&
      inlineCode == other.inlineCode &&
      image == other.image &&
      underline == other.underline &&
      fontSize == other.fontSize &&
      link == other.link;

  @override
  int get hashCode => Object.hash(
    bold,
    italic,
    strikethrough,
    inlineCode,
    image,
    underline,
    fontSize,
    link,
  );
}

class NoteTextStyleRange {
  final int start;
  final int end;
  final NoteTextAttributes attributes;

  const NoteTextStyleRange(this.start, this.end, this.attributes);

  Map<String, Object> toMap() => {
    'start': start,
    'end': end,
    ...attributes.toMap(),
  };

  factory NoteTextStyleRange.fromMap(Map<String, Object?> map) =>
      NoteTextStyleRange(
        map['start'] as int? ?? 0,
        map['end'] as int? ?? 0,
        NoteTextAttributes.fromMap(map),
      );
}

class NoteEditorFormatState {
  final bool bold;
  final bool italic;
  final bool strikethrough;
  final bool inlineCode;
  final bool underline;
  final double? fontSize;
  final String? link;
  final int indent;
  final int headingLevel;

  const NoteEditorFormatState({
    this.bold = false,
    this.italic = false,
    this.strikethrough = false,
    this.inlineCode = false,
    this.underline = false,
    this.fontSize = NoteTextAttributes.defaultFontSize,
    this.link,
    this.indent = 0,
    this.headingLevel = 0,
  });

  @override
  bool operator ==(Object other) =>
      other is NoteEditorFormatState &&
      bold == other.bold &&
      italic == other.italic &&
      strikethrough == other.strikethrough &&
      inlineCode == other.inlineCode &&
      underline == other.underline &&
      fontSize == other.fontSize &&
      link == other.link &&
      indent == other.indent &&
      headingLevel == other.headingLevel;

  @override
  int get hashCode => Object.hash(
    bold,
    italic,
    strikethrough,
    inlineCode,
    underline,
    fontSize,
    link,
    indent,
    headingLevel,
  );
}

class NoteHistoryState {
  final bool canUndo;
  final bool canRedo;

  const NoteHistoryState({this.canUndo = false, this.canRedo = false});

  @override
  bool operator ==(Object other) =>
      other is NoteHistoryState &&
      canUndo == other.canUndo &&
      canRedo == other.canRedo;

  @override
  int get hashCode => Object.hash(canUndo, canRedo);
}

class NoteAssistantEditorContext {
  final int blockIndex;
  final TextSelection selection;
  final String selectedText;
  final String currentBlockContent;
  final String expectedBlockText;
  final String expectedDocument;

  const NoteAssistantEditorContext({
    required this.blockIndex,
    required this.selection,
    required this.selectedText,
    required this.currentBlockContent,
    required this.expectedBlockText,
    required this.expectedDocument,
  });

  bool get hasSelection => selectedText.trim().isNotEmpty;
}

class _EditorSnapshot {
  final String richDocument;
  final int activeIndex;
  final TextSelection selection;

  const _EditorSnapshot({
    required this.richDocument,
    required this.activeIndex,
    required this.selection,
  });
}

class NoteRichDocumentCodec {
  static const version = 2;

  static String encode(List<NoteBlockData> blocks) => jsonEncode({
    'version': version,
    'blocks': [
      for (final block in blocks)
        {
          'type': block.type.name,
          'text': block.text,
          if (block.checked) 'checked': true,
          if (block.attachmentPath != null)
            'attachmentPath': block.attachmentPath,
          if (block.indent > 0) 'indent': block.indent,
          if (block.quoteDepth > 0) 'quoteDepth': block.quoteDepth,
          if (block.headingLevel > 0) 'headingLevel': block.headingLevel,
          if (block.codeLanguage?.isNotEmpty == true)
            'codeLanguage': block.codeLanguage,
          if (block.styles.isNotEmpty)
            'styles': block.styles.map((range) => range.toMap()).toList(),
        },
    ],
  });

  static List<NoteBlockData>? tryDecode(String? source) {
    if (source?.trim().isEmpty ?? true) return null;
    try {
      final root = jsonDecode(source!) as Map<String, Object?>;
      if (root['version'] != version) return null;
      final rawBlocks = root['blocks'] as List<Object?>?;
      if (rawBlocks == null || rawBlocks.isEmpty) return null;
      return rawBlocks.map((raw) {
        final map = raw as Map<String, Object?>;
        final typeName = map['type'] as String? ?? 'paragraph';
        final type = NoteBlockType.values.firstWhere(
          (candidate) => candidate.name == typeName,
          orElse: () => NoteBlockType.paragraph,
        );
        final text = map['text'] as String? ?? '';
        final ranges = <NoteTextStyleRange>[];
        for (final rawRange in map['styles'] as List<Object?>? ?? const []) {
          final range = NoteTextStyleRange.fromMap(
            rawRange as Map<String, Object?>,
          );
          final start = range.start.clamp(0, text.length);
          final end = range.end.clamp(start, text.length);
          if (start < end) {
            ranges.add(NoteTextStyleRange(start, end, range.attributes));
          }
        }
        return NoteBlockData(
          type,
          text,
          checked: map['checked'] == true,
          attachmentPath: map['attachmentPath'] as String?,
          indent: (map['indent'] as int? ?? 0).clamp(0, 3),
          quoteDepth: (map['quoteDepth'] as int? ?? 0).clamp(0, 3),
          headingLevel: (map['headingLevel'] as int? ?? 0).clamp(0, 6),
          codeLanguage: map['codeLanguage'] as String?,
          styles: ranges,
        );
      }).toList();
    } catch (_) {
      return null;
    }
  }
}

/// Converts between the editor's blocks and GitHub Flavored Markdown.
///
/// Parsing is delegated to the mature `markdown` AST. FKNotes only maps that
/// AST to editable blocks and retains its local attachment reference extension.
class NoteBlockCodec {
  static final _attachment = RegExp(r'^\[\[附件:(.+)\]\]$');

  static List<NoteBlockData> decode(String source) {
    if (source.isEmpty) {
      return const [NoteBlockData(NoteBlockType.paragraph, '')];
    }
    final normalized = source.replaceAll('\r\n', '\n');
    final blocks = <NoteBlockData>[];
    final markdownLines = <String>[];

    void flushMarkdown() {
      if (markdownLines.isEmpty) return;
      final markdownSource = markdownLines.join('\n');
      markdownLines.clear();
      if (markdownSource.trim().isEmpty) return;
      try {
        final nodes = md.Document(
          extensionSet: md.ExtensionSet.gitHubFlavored,
          encodeHtml: false,
        ).parse(markdownSource);
        for (final node in nodes) {
          _appendNode(blocks, node);
        }
      } catch (_) {
        blocks.add(NoteBlockData(NoteBlockType.paragraph, markdownSource));
      }
    }

    for (final line in normalized.split('\n')) {
      final attachment = _attachment.firstMatch(line.trim());
      if (attachment == null) {
        markdownLines.add(line);
        continue;
      }
      flushMarkdown();
      blocks.add(
        NoteBlockData(
          NoteBlockType.attachment,
          '',
          attachmentPath: attachment.group(1),
        ),
      );
    }
    flushMarkdown();
    return blocks.isEmpty
        ? const [NoteBlockData(NoteBlockType.paragraph, '')]
        : blocks;
  }

  static void _appendNode(
    List<NoteBlockData> blocks,
    md.Node node, {
    int indent = 0,
    int quoteDepth = 0,
  }) {
    if (node is md.Text) {
      if (node.text.trim().isNotEmpty) {
        blocks.add(NoteBlockData(NoteBlockType.paragraph, node.text));
      }
      return;
    }
    if (node is! md.Element) return;
    final tag = node.tag;
    if (RegExp(r'^h[1-6]$').hasMatch(tag)) {
      final inline = _inlineData(node.children);
      blocks.add(
        NoteBlockData(
          NoteBlockType.heading,
          inline.text,
          indent: indent,
          quoteDepth: quoteDepth,
          headingLevel: int.parse(tag.substring(1)),
          styles: inline.styles,
        ),
      );
      return;
    }
    switch (tag) {
      case 'p':
        final inline = _inlineData(node.children);
        blocks.add(
          NoteBlockData(
            quoteDepth > 0 ? NoteBlockType.quote : NoteBlockType.paragraph,
            inline.text,
            indent: indent,
            quoteDepth: quoteDepth,
            styles: inline.styles,
          ),
        );
        break;
      case 'ul':
      case 'ol':
        _appendList(
          blocks,
          node,
          ordered: tag == 'ol',
          indent: indent,
          quoteDepth: quoteDepth,
        );
        break;
      case 'blockquote':
        for (final child in node.children ?? const <md.Node>[]) {
          _appendNode(
            blocks,
            child,
            indent: indent,
            quoteDepth: (quoteDepth + 1).clamp(1, 3),
          );
        }
        break;
      case 'pre':
        final code = (node.children ?? const <md.Node>[])
            .whereType<md.Element>()
            .firstWhere(
              (child) => child.tag == 'code',
              orElse: () => md.Element.text('code', node.textContent),
            );
        final className = code.attributes['class'] ?? '';
        blocks.add(
          NoteBlockData(
            NoteBlockType.code,
            code.textContent.replaceFirst(RegExp(r'\n$'), ''),
            quoteDepth: quoteDepth,
            codeLanguage: className.startsWith('language-')
                ? className.substring('language-'.length)
                : null,
          ),
        );
        break;
      case 'hr':
        blocks.add(const NoteBlockData(NoteBlockType.divider, ''));
        break;
      case 'table':
        blocks.add(
          NoteBlockData(
            NoteBlockType.rawMarkdown,
            _tableToMarkdown(node),
            quoteDepth: quoteDepth,
          ),
        );
        break;
      default:
        final inline = _inlineData(node.children);
        if (inline.text.trim().isNotEmpty) {
          blocks.add(
            NoteBlockData(
              quoteDepth > 0 ? NoteBlockType.quote : NoteBlockType.paragraph,
              inline.text,
              indent: indent,
              quoteDepth: quoteDepth,
              styles: inline.styles,
            ),
          );
        }
        break;
    }
  }

  static void _appendList(
    List<NoteBlockData> blocks,
    md.Element list, {
    required bool ordered,
    required int indent,
    required int quoteDepth,
  }) {
    final listChildren = list.children;
    if (listChildren == null) return;
    for (final item in listChildren.whereType<md.Element>()) {
      if (item.tag != 'li') continue;
      final input = _findFirstElement(item, 'input');
      final inline = _inlineData(item.children, skipBlockLists: true);
      blocks.add(
        NoteBlockData(
          input != null
              ? NoteBlockType.todo
              : ordered
              ? NoteBlockType.ordered
              : NoteBlockType.bullet,
          inline.text.trimRight(),
          checked: input?.attributes['checked'] == 'true',
          indent: indent,
          quoteDepth: quoteDepth,
          styles: inline.styles,
        ),
      );
      for (final child
          in (item.children ?? const <md.Node>[]).whereType<md.Element>()) {
        if (child.tag == 'ul' || child.tag == 'ol') {
          _appendList(
            blocks,
            child,
            ordered: child.tag == 'ol',
            indent: (indent + 1).clamp(0, 3),
            quoteDepth: quoteDepth,
          );
        }
      }
    }
  }

  static md.Element? _findFirstElement(md.Element root, String tag) {
    for (final child in root.children ?? const <md.Node>[]) {
      if (child is! md.Element) continue;
      if (child.tag == tag) return child;
      final nested = _findFirstElement(child, tag);
      if (nested != null) return nested;
    }
    return null;
  }

  static _InlineData _inlineData(
    List<md.Node>? nodes, {
    bool skipBlockLists = false,
  }) {
    final output = _InlineAccumulator();
    void visit(md.Node node, NoteTextAttributes attributes) {
      if (node is md.Text) {
        output.write(node.text, attributes);
        return;
      }
      if (node is! md.Element || node.tag == 'input') return;
      if (skipBlockLists && (node.tag == 'ul' || node.tag == 'ol')) return;
      if (node.tag == 'br') {
        output.write('\n', attributes);
        return;
      }
      var next = attributes;
      switch (node.tag) {
        case 'strong':
          next = next.copyWith(bold: true);
          break;
        case 'em':
          next = next.copyWith(italic: true);
          break;
        case 'del':
          next = next.copyWith(strikethrough: true);
          break;
        case 'code':
          next = next.copyWith(inlineCode: true);
          break;
        case 'a':
          next = next.copyWith(link: node.attributes['href']);
          break;
        case 'img':
          final alt = node.attributes['alt'] ?? node.textContent;
          output.write(
            alt,
            next.copyWith(link: node.attributes['src'], image: true),
          );
          return;
        default:
          break;
      }
      for (final child in node.children ?? const <md.Node>[]) {
        visit(child, next);
      }
    }

    for (final node in nodes ?? const <md.Node>[]) {
      visit(node, NoteTextAttributes.defaults);
    }
    return output.finish();
  }

  static String _tableToMarkdown(md.Element table) {
    final rows = <List<String>>[];
    final alignments = <String>[];
    void visit(md.Element element) {
      if (element.tag == 'tr') {
        final cells = <String>[];
        for (final cell
            in (element.children ?? const <md.Node>[])
                .whereType<md.Element>()) {
          if (cell.tag != 'th' && cell.tag != 'td') continue;
          cells.add(_escapeTableCell(cell.textContent));
          if (rows.isEmpty) {
            final alignment =
                cell.attributes['align'] ?? cell.attributes['style'] ?? '';
            alignments.add(
              alignment.contains('center')
                  ? ':---:'
                  : alignment.contains('right')
                  ? '---:'
                  : ':---',
            );
          }
        }
        if (cells.isNotEmpty) rows.add(cells);
      }
      for (final child
          in (element.children ?? const <md.Node>[]).whereType<md.Element>()) {
        visit(child);
      }
    }

    visit(table);
    if (rows.isEmpty) return table.textContent;
    final width = rows.fold<int>(
      0,
      (value, row) => row.length > value ? row.length : value,
    );
    String row(List<String> cells) =>
        '| ${List.generate(width, (index) => index < cells.length ? cells[index] : '').join(' | ')} |';
    return [
      row(rows.first),
      row(
        List.generate(
          width,
          (index) => index < alignments.length ? alignments[index] : '---',
        ),
      ),
      ...rows.skip(1).map(row),
    ].join('\n');
  }

  static String _escapeTableCell(String value) =>
      value.replaceAll('|', r'\|').replaceAll('\n', '<br>');

  static int visibleCharacterCount(String source) =>
      decode(source).fold(0, (count, block) => count + block.text.runes.length);

  static String encode(List<NoteBlockData> blocks) {
    var orderedNumber = 0;
    NoteBlockType? previous;
    final sections = <({NoteBlockData block, String markdown})>[];
    for (final block in blocks) {
      if (block.type == NoteBlockType.ordered) {
        final previousBlock = sections.isEmpty ? null : sections.last.block;
        orderedNumber =
            previous == NoteBlockType.ordered &&
                previousBlock?.indent == block.indent
            ? orderedNumber + 1
            : 1;
      } else {
        orderedNumber = 0;
      }
      final text = _encodeInline(block);
      var markdown = switch (block.type) {
        NoteBlockType.paragraph => text,
        NoteBlockType.heading =>
          '${'#' * block.headingLevel.clamp(1, 6)} $text',
        NoteBlockType.bullet => '${'  ' * block.indent}- $text',
        NoteBlockType.ordered => '${'  ' * block.indent}$orderedNumber. $text',
        NoteBlockType.todo =>
          '${'  ' * block.indent}- [${block.checked ? 'x' : ' '}] $text',
        NoteBlockType.quote => text,
        NoteBlockType.code => _encodeCodeBlock(block),
        NoteBlockType.rawMarkdown => block.text,
        NoteBlockType.divider => '---',
        NoteBlockType.attachment => '[[附件:${block.attachmentPath ?? ''}]]',
      };
      final quoteDepth = block.type == NoteBlockType.quote
          ? block.quoteDepth.clamp(1, 3)
          : block.quoteDepth.clamp(0, 3);
      if (quoteDepth > 0) {
        final prefix = '${'>' * quoteDepth} ';
        markdown = markdown
            .split('\n')
            .map((line) => '$prefix$line')
            .join('\n');
      }
      sections.add((block: block, markdown: markdown));
      previous = block.type;
    }
    final output = StringBuffer();
    for (var index = 0; index < sections.length; index++) {
      if (index > 0) {
        final before = sections[index - 1].block;
        final current = sections[index].block;
        final sameList = _isList(before.type) && _isList(current.type);
        output.write(sameList ? '\n' : '\n\n');
      }
      output.write(sections[index].markdown);
    }
    return output.toString();
  }

  static bool _isList(NoteBlockType type) =>
      type == NoteBlockType.bullet ||
      type == NoteBlockType.ordered ||
      type == NoteBlockType.todo;

  static String _encodeInline(NoteBlockData block) {
    if (block.text.isEmpty) return '';
    final attributes = List<NoteTextAttributes>.filled(
      block.text.length,
      NoteTextAttributes.defaults,
    );
    for (final range in block.styles) {
      final start = range.start.clamp(0, block.text.length);
      final end = range.end.clamp(start, block.text.length);
      for (var index = start; index < end; index++) {
        attributes[index] = range.attributes;
      }
    }
    final output = StringBuffer();
    var start = 0;
    while (start < block.text.length) {
      final current = attributes[start];
      var end = start + 1;
      while (end < block.text.length && attributes[end] == current) {
        end++;
      }
      output.write(_encodeInlineRun(block.text.substring(start, end), current));
      start = end;
    }
    return output.toString();
  }

  static String _encodeInlineRun(String value, NoteTextAttributes attributes) {
    var encoded = attributes.inlineCode
        ? _wrapInlineCode(value)
        : value
              .replaceAll('\\', r'\\')
              .replaceAllMapped(
                RegExp(r'([`*_\[\]~])'),
                (match) => '\\${match.group(1)}',
              )
              .replaceAll('\n', '  \n');
    if (!attributes.inlineCode) {
      if (attributes.strikethrough) encoded = '~~$encoded~~';
      if (attributes.italic) encoded = '*$encoded*';
      if (attributes.bold) encoded = '**$encoded**';
    }
    final link = attributes.link;
    if (link != null && link.isNotEmpty) {
      final target = link.replaceAll('\\', r'\\').replaceAll(')', r'\)');
      encoded = '${attributes.image ? '!' : ''}[$encoded]($target)';
    }
    return encoded;
  }

  static String _wrapInlineCode(String value) {
    final longest = RegExp(r'`+')
        .allMatches(value)
        .fold<int>(
          0,
          (length, match) =>
              match.group(0)!.length > length ? match.group(0)!.length : length,
        );
    final fence = '`' * (longest + 1);
    final padding = value.startsWith('`') || value.endsWith('`') ? ' ' : '';
    return '$fence$padding$value$padding$fence';
  }

  static String _encodeCodeBlock(NoteBlockData block) {
    final longest = RegExp(r'`{3,}')
        .allMatches(block.text)
        .fold<int>(
          2,
          (length, match) =>
              match.group(0)!.length > length ? match.group(0)!.length : length,
        );
    final fence = '`' * (longest + 1);
    return '$fence${block.codeLanguage ?? ''}\n${block.text}\n$fence';
  }

  static bool structurallyMatches(List<NoteBlockData> cached, String markdown) {
    if (encode(cached) == markdown) return true;
    final parsed = decode(markdown);
    if (cached.length != parsed.length) return false;
    for (var index = 0; index < cached.length; index++) {
      final left = cached[index];
      final right = parsed[index];
      if (left.type != right.type ||
          left.text != right.text ||
          left.checked != right.checked ||
          left.attachmentPath != right.attachmentPath ||
          left.indent != right.indent ||
          left.quoteDepth != right.quoteDepth ||
          left.headingLevel != right.headingLevel ||
          left.codeLanguage != right.codeLanguage) {
        return false;
      }
    }
    return true;
  }
}

class _InlineData {
  final String text;
  final List<NoteTextStyleRange> styles;

  const _InlineData(this.text, this.styles);
}

class _InlineAccumulator {
  final _text = StringBuffer();
  final _styles = <NoteTextStyleRange>[];
  var _length = 0;

  void write(String value, NoteTextAttributes attributes) {
    if (value.isEmpty) return;
    final start = _length;
    _text.write(value);
    _length += value.length;
    if (attributes != NoteTextAttributes.defaults) {
      _styles.add(NoteTextStyleRange(start, _length, attributes));
    }
  }

  _InlineData finish() => _InlineData(_text.toString(), _styles);
}

enum MarkdownTableAlignment { left, center, right }

class MarkdownTableData {
  final List<String> headers;
  final List<List<String>> rows;
  final List<MarkdownTableAlignment> alignments;

  const MarkdownTableData({
    required this.headers,
    required this.rows,
    required this.alignments,
  });

  static MarkdownTableData? tryParse(String source) {
    final lines = source
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.length < 2) return null;
    final headers = _splitRow(lines[0]);
    final separators = _splitRow(lines[1]);
    if (headers.isEmpty || separators.length != headers.length) return null;
    final alignments = <MarkdownTableAlignment>[];
    for (final separator in separators) {
      final value = separator.trim();
      if (!RegExp(r'^:?-{3,}:?$').hasMatch(value)) return null;
      alignments.add(
        value.startsWith(':') && value.endsWith(':')
            ? MarkdownTableAlignment.center
            : value.endsWith(':')
            ? MarkdownTableAlignment.right
            : MarkdownTableAlignment.left,
      );
    }
    final rows = <List<String>>[];
    for (final line in lines.skip(2)) {
      final cells = _splitRow(line);
      rows.add(
        List.generate(
          headers.length,
          (index) => index < cells.length ? cells[index] : '',
        ),
      );
    }
    while (rows.isNotEmpty && rows.last.every((cell) => cell.trim().isEmpty)) {
      rows.removeLast();
    }
    return MarkdownTableData(
      headers: headers,
      rows: rows,
      alignments: alignments,
    );
  }

  String encode() {
    final width = headers.length;
    String row(List<String> cells) =>
        '| ${List.generate(width, (index) => _escapeCell(index < cells.length ? cells[index] : '')).join(' | ')} |';
    final separators = List.generate(width, (index) {
      final alignment = index < alignments.length
          ? alignments[index]
          : MarkdownTableAlignment.left;
      return switch (alignment) {
        MarkdownTableAlignment.left => ':---',
        MarkdownTableAlignment.center => ':---:',
        MarkdownTableAlignment.right => '---:',
      };
    });
    return [row(headers), row(separators), ...rows.map(row)].join('\n');
  }

  static List<String> _splitRow(String source) {
    var value = source.trim();
    if (value.startsWith('|')) value = value.substring(1);
    if (value.endsWith('|') && !value.endsWith(r'\|')) {
      value = value.substring(0, value.length - 1);
    }
    final cells = <String>[];
    final current = StringBuffer();
    var escaped = false;
    for (final rune in value.runes) {
      final character = String.fromCharCode(rune);
      if (escaped) {
        current.write(character);
        escaped = false;
      } else if (character == r'\') {
        escaped = true;
      } else if (character == '|') {
        cells.add(current.toString().trim());
        current.clear();
      } else {
        current.write(character);
      }
    }
    if (escaped) current.write(r'\');
    cells.add(current.toString().trim());
    return cells;
  }

  static String _escapeCell(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('|', r'\|')
      .replaceAll('\n', '<br>');
}

class NoteBlockEditor extends StatefulWidget {
  final TextEditingController controller;
  final String? initialRichContent;
  final ValueChanged<String>? onRichContentChanged;
  final String hintText;
  final int minLines;
  final List<NoteAttachment> attachments;
  final ValueChanged<NoteAttachment>? onOpenAttachment;

  const NoteBlockEditor({
    super.key,
    required this.controller,
    this.initialRichContent,
    this.onRichContentChanged,
    required this.hintText,
    this.minLines = 10,
    this.attachments = const [],
    this.onOpenAttachment,
  });

  @override
  NoteBlockEditorState createState() => NoteBlockEditorState();
}

class NoteBlockEditorState extends State<NoteBlockEditor> {
  final ValueNotifier<NoteBlockType> activeType = ValueNotifier(
    NoteBlockType.paragraph,
  );
  final ValueNotifier<NoteEditorFormatState> activeFormat = ValueNotifier(
    const NoteEditorFormatState(),
  );
  final ValueNotifier<NoteHistoryState> historyState = ValueNotifier(
    const NoteHistoryState(),
  );
  late final List<_EditableBlock> _blocks;
  late String _lastRichDocument;
  late _EditorSnapshot _currentSnapshot;
  final List<_EditorSnapshot> _undoStack = [];
  final List<_EditorSnapshot> _redoStack = [];
  Timer? _historyGroupTimer;
  Timer? _documentSyncTimer;
  bool _historyGroupOpen = false;
  bool _restoringHistory = false;
  bool _dictating = false;
  _EditorSnapshot? _dictationSnapshot;
  _EditableBlock? _dictationBlock;
  int _dictationStart = 0;
  int _dictationLength = 0;
  int _activeIndex = 0;
  int _focusRequestGeneration = 0;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    final richBlocks = NoteRichDocumentCodec.tryDecode(
      widget.initialRichContent,
    );
    final plainBlocks = NoteBlockCodec.decode(widget.controller.text);
    final blocks =
        richBlocks != null &&
            NoteBlockCodec.structurallyMatches(
              richBlocks,
              widget.controller.text,
            )
        ? richBlocks
        : plainBlocks;
    _blocks = blocks.map(_makeBlock).toList();
    _lastRichDocument = NoteRichDocumentCodec.encode(_document);
    _currentSnapshot = _createSnapshot(_lastRichDocument);
  }

  _EditableBlock _makeBlock(NoteBlockData data) {
    late final _EditableBlock block;
    block = _EditableBlock(
      type: data.type,
      checked: data.checked,
      attachmentPath: data.attachmentPath,
      indent: data.indent,
      quoteDepth: data.quoteDepth,
      headingLevel: data.headingLevel,
      codeLanguage: data.codeLanguage,
      controller: _BlockTextEditingController(
        text: data.text,
        styles: data.styles,
      ),
      focusNode: FocusNode(),
    );
    block.controller.addListener(
      () => _syncDocument(deferForLargeDocument: true),
    );
    block.focusNode.addListener(() {
      if (!block.focusNode.hasFocus || !mounted) return;
      final index = _blocks.indexOf(block);
      if (index >= 0) {
        _activeIndex = index;
        activeType.value = block.type;
        _refreshActiveFormat();
      }
    });
    return block;
  }

  Widget _buildBlockContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    _EditableBlock? owner;
    for (final block in _blocks) {
      if (identical(block.controller, editableTextState.widget.controller)) {
        owner = block;
        break;
      }
    }
    final block = owner;
    return buildAppEditableTextContextMenu(
      context,
      editableTextState,
      onPaste: block == null ? null : () => _pasteFromClipboard(block),
    );
  }

  List<NoteBlockData> get _document => [
    for (final block in _blocks)
      NoteBlockData(
        block.type,
        block.controller.visibleTextValue,
        checked: block.checked,
        attachmentPath: block.attachmentPath,
        indent: block.indent,
        quoteDepth: block.quoteDepth,
        headingLevel: block.headingLevel,
        codeLanguage: block.codeLanguage,
        styles: block.controller.styleRanges,
      ),
  ];

  bool get _isLargeDocument {
    if (_blocks.length >= 80) return true;
    var characters = 0;
    for (final block in _blocks) {
      characters += block.controller.visibleTextValue.length;
      if (characters >= 20000) return true;
    }
    return false;
  }

  void _syncDocument({bool deferForLargeDocument = false}) {
    _refreshActiveFormat();
    if (_syncing) return;
    if (deferForLargeDocument && _isLargeDocument) {
      _documentSyncTimer?.cancel();
      _documentSyncTimer = Timer(
        const Duration(milliseconds: 120),
        _performDocumentSync,
      );
      return;
    }
    _documentSyncTimer?.cancel();
    _documentSyncTimer = null;
    _performDocumentSync();
  }

  void _performDocumentSync() {
    if (_syncing) return;
    _documentSyncTimer = null;
    final text = NoteBlockCodec.encode(_document);
    if (widget.controller.text != text) {
      widget.controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    final richDocument = NoteRichDocumentCodec.encode(_document);
    _recordHistory(richDocument);
    if (_lastRichDocument != richDocument) {
      _lastRichDocument = richDocument;
      widget.onRichContentChanged?.call(richDocument);
    }
  }

  /// Flushes a pending large-document update before persistence or mode changes.
  String flushPendingChanges() {
    _documentSyncTimer?.cancel();
    _documentSyncTimer = null;
    _performDocumentSync();
    return _lastRichDocument;
  }

  _EditorSnapshot _createSnapshot(String richDocument) {
    final block = _blocks.isEmpty
        ? null
        : _blocks[_activeIndex.clamp(0, _blocks.length - 1)];
    return _EditorSnapshot(
      richDocument: richDocument,
      activeIndex: _activeIndex,
      selection:
          block?.controller.visibleSelectionValue ??
          const TextSelection.collapsed(offset: 0),
    );
  }

  void _recordHistory(String richDocument) {
    final next = _createSnapshot(richDocument);
    if (_restoringHistory || _dictating) {
      _currentSnapshot = next;
      return;
    }
    if (next.richDocument == _currentSnapshot.richDocument) {
      _currentSnapshot = next;
      return;
    }
    if (!_historyGroupOpen) {
      _undoStack.add(_currentSnapshot);
      if (_undoStack.length > 100) _undoStack.removeAt(0);
      _redoStack.clear();
      _historyGroupOpen = true;
    }
    _currentSnapshot = next;
    _historyGroupTimer?.cancel();
    _historyGroupTimer = Timer(
      const Duration(milliseconds: 650),
      _closeHistoryGroup,
    );
    _notifyHistoryChanged();
  }

  void _closeHistoryGroup() {
    _historyGroupTimer?.cancel();
    _historyGroupTimer = null;
    _historyGroupOpen = false;
  }

  void _beginDiscreteChange() => _closeHistoryGroup();

  void _endDiscreteChange() => _closeHistoryGroup();

  void _notifyHistoryChanged() {
    historyState.value = NoteHistoryState(
      canUndo: _undoStack.isNotEmpty,
      canRedo: _redoStack.isNotEmpty,
    );
  }

  void undo() {
    if (_documentSyncTimer != null) flushPendingChanges();
    if (_undoStack.isEmpty) return;
    HapticFeedback.selectionClick();
    _closeHistoryGroup();
    final target = _undoStack.removeLast();
    _redoStack.add(_currentSnapshot);
    _restoreSnapshot(target);
  }

  void redo() {
    if (_documentSyncTimer != null) flushPendingChanges();
    if (_redoStack.isEmpty) return;
    HapticFeedback.selectionClick();
    _closeHistoryGroup();
    final target = _redoStack.removeLast();
    _undoStack.add(_currentSnapshot);
    _restoreSnapshot(target);
  }

  /// Ensures continuous dictation has an editable insertion target without
  /// taking ownership of the caret or disabling normal keyboard editing.
  bool prepareDictationInsertion() {
    if (_blocks.isEmpty) return false;
    var block = _activeEditableBlock;
    if (block == null) {
      final index = _blocks.lastIndexWhere(
        (item) =>
            item.type != NoteBlockType.divider &&
            item.type != NoteBlockType.attachment,
      );
      if (index < 0) return false;
      _activeIndex = index;
      block = _blocks[index];
    }
    final text = block.controller.visibleTextValue;
    final selection = block.controller.visibleSelectionValue;
    final caret = selection.isValid
        ? selection.extentOffset.clamp(0, text.length)
        : text.length;
    block.controller.visibleSelectionValue = TextSelection.collapsed(
      offset: caret,
    );
    _activeIndex = _blocks.indexOf(block);
    activeType.value = block.type;
    return true;
  }

  /// Inserts finalized, non-empty dictation at the user's current caret.
  /// Manual edits and caret moves remain authoritative while listening.
  bool insertDictationTextAtCaret(String value) {
    if (value.trim().isEmpty) return true;
    if (!prepareDictationInsertion()) return false;
    final block = _activeEditableBlock!;
    final composing = block.controller.value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      // Do not destroy an in-progress Chinese/Japanese/Korean IME composition.
      // The page retries the pending finalized segment after the manual edit
      // produces its next stable document update.
      return false;
    }
    final text = block.controller.visibleTextValue;
    final selection = block.controller.visibleSelectionValue;
    final caret = selection.isValid
        ? selection.extentOffset.clamp(0, text.length)
        : text.length;
    final attributes = block.controller.attributesForSelection(
      TextSelection.collapsed(offset: caret),
    );
    block.controller.typingAttributes = attributes;
    block.controller.value = TextEditingValue(
      text: text.replaceRange(caret, caret, value),
      selection: TextSelection.collapsed(offset: caret + value.length),
    );
    return true;
  }

  /// Appends reviewed assistant output as an undoable document change.
  ///
  /// Generated attachment markers are deliberately converted to plain text so
  /// model output can never manufacture a live reference to a local file.
  bool appendAssistantText({required String heading, required String text}) {
    if (text.trim().isEmpty) return false;
    _beginDiscreteChange();
    final generated = _safeAssistantBlocks(text);
    _blocks.add(
      _makeBlock(
        NoteBlockData(NoteBlockType.heading, heading, headingLevel: 2),
      ),
    );
    _blocks.addAll(generated.map(_makeBlock));
    _activeIndex = _blocks.length - 1;
    _syncDocument();
    _endDiscreteChange();
    setState(() {});
    final block = _blocks[_activeIndex];
    if (block.type != NoteBlockType.divider &&
        block.type != NoteBlockType.attachment) {
      _refocus(
        block,
        selection: TextSelection.collapsed(
          offset: block.controller.visibleTextValue.length,
        ),
      );
    }
    return true;
  }

  NoteAssistantEditorContext? captureAssistantContext() {
    var block = _activeEditableBlock;
    if (block == null) {
      final index = _blocks.lastIndexWhere(
        (item) =>
            item.type != NoteBlockType.divider &&
            item.type != NoteBlockType.attachment,
      );
      if (index < 0) {
        return NoteAssistantEditorContext(
          blockIndex: -1,
          selection: const TextSelection.collapsed(offset: 0),
          selectedText: '',
          currentBlockContent: '',
          expectedBlockText: '',
          expectedDocument: NoteRichDocumentCodec.encode(_document),
        );
      }
      block = _blocks[index];
    }
    final blockIndex = _blocks.indexOf(block);
    final text = block.controller.visibleTextValue;
    final rawSelection = block.controller.visibleSelectionValue;
    final selection = rawSelection.isValid
        ? TextSelection(
            baseOffset: rawSelection.baseOffset.clamp(0, text.length),
            extentOffset: rawSelection.extentOffset.clamp(0, text.length),
          )
        : TextSelection.collapsed(offset: text.length);
    final start = selection.start.clamp(0, text.length);
    final end = selection.end.clamp(start, text.length);
    return NoteAssistantEditorContext(
      blockIndex: blockIndex,
      selection: selection,
      selectedText: text.substring(start, end),
      currentBlockContent: NoteBlockCodec.encode([_document[blockIndex]]),
      expectedBlockText: text,
      expectedDocument: NoteRichDocumentCodec.encode(_document),
    );
  }

  bool applyAssistantResult({
    required NoteAssistantEditorContext anchor,
    required NoteAssistantScope scope,
    required NoteAssistantPlacement placement,
    required String text,
    required String heading,
  }) {
    if (text.trim().isEmpty ||
        NoteRichDocumentCodec.encode(_document) != anchor.expectedDocument) {
      return false;
    }
    if (placement == NoteAssistantPlacement.append) {
      return appendAssistantText(heading: heading, text: text);
    }
    if (scope == NoteAssistantScope.fullNote) {
      if (placement != NoteAssistantPlacement.replace) return false;
      final generated = _safeAssistantBlocks(text);
      if (generated.isEmpty) return false;
      _beginDiscreteChange();
      _releaseBlockFocus();
      _syncing = true;
      for (final block in _blocks) {
        block.dispose();
      }
      _blocks
        ..clear()
        ..addAll(generated.map(_makeBlock));
      _syncing = false;
      _activeIndex = _blocks.length - 1;
      activeType.value = _blocks[_activeIndex].type;
      _syncDocument();
      _endDiscreteChange();
      setState(() {});
      _focusAssistantResult();
      return true;
    }
    if (anchor.blockIndex < 0 || anchor.blockIndex >= _blocks.length) {
      return false;
    }
    final block = _blocks[anchor.blockIndex];
    if (block.controller.visibleTextValue != anchor.expectedBlockText) {
      return false;
    }
    if (placement == NoteAssistantPlacement.replace) {
      _activeIndex = anchor.blockIndex;
      block.controller.visibleSelectionValue =
          scope == NoteAssistantScope.selection
          ? anchor.selection
          : TextSelection(
              baseOffset: 0,
              extentOffset: block.controller.visibleTextValue.length,
            );
      return _pasteMarkdown(block, text.trim());
    }
    if (placement != NoteAssistantPlacement.insertBelow) return false;
    final generated = _safeAssistantBlocks(text);
    if (generated.isEmpty) return false;
    _beginDiscreteChange();
    _syncing = true;
    final inserted = generated.map(_makeBlock).toList();
    _blocks.insertAll(anchor.blockIndex + 1, inserted);
    _syncing = false;
    _activeIndex = anchor.blockIndex + inserted.length;
    activeType.value = _blocks[_activeIndex].type;
    _syncDocument();
    _endDiscreteChange();
    setState(() {});
    _focusAssistantResult();
    return true;
  }

  void _focusAssistantResult() {
    final index = _blocks.lastIndexWhere(
      (item) =>
          item.type != NoteBlockType.divider &&
          item.type != NoteBlockType.attachment,
      _activeIndex,
    );
    if (index < 0) {
      _refreshActiveFormat();
      return;
    }
    _activeIndex = index;
    activeType.value = _blocks[index].type;
    _refocus(_blocks[index]);
  }

  List<NoteBlockData> _safeAssistantBlocks(String text) =>
      NoteBlockCodec.decode(text.trim())
          .map((block) {
            if (block.type != NoteBlockType.attachment) return block;
            return NoteBlockData(
              NoteBlockType.paragraph,
              context.l10n.attachmentReference(block.attachmentPath ?? ''),
            );
          })
          .toList(growable: false);

  Future<void> _pasteFromClipboard(_EditableBlock block) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final value = data?.text;
    if (!mounted ||
        value == null ||
        value.isEmpty ||
        !_blocks.contains(block)) {
      return;
    }
    _pasteMarkdown(block, value);
  }

  /// Inserts clipboard or imported Markdown at the active caret.
  ///
  /// Inline Markdown stays in the current block. Block Markdown is parsed into
  /// semantic editor blocks in one undoable operation.
  bool pasteMarkdown(String source) {
    final block = _activeEditableBlock;
    if (block == null || source.isEmpty) return false;
    return _pasteMarkdown(block, source);
  }

  bool _pasteMarkdown(
    _EditableBlock block,
    String source, {
    TextSelection? replacedSelection,
  }) {
    final index = _blocks.indexOf(block);
    if (index < 0) return false;
    final parsed = NoteBlockCodec.decode(source).map((item) {
      if (item.type != NoteBlockType.attachment) return item;
      return NoteBlockData(
        NoteBlockType.paragraph,
        context.l10n.attachmentReference(item.attachmentPath ?? ''),
      );
    }).toList();
    if (parsed.isEmpty) return false;
    final currentSelection = block.controller.visibleSelectionValue;
    final selection = replacedSelection?.isValid == true
        ? replacedSelection!
        : currentSelection.isValid
        ? currentSelection
        : TextSelection.collapsed(
            offset: block.controller.visibleTextValue.length,
          );
    final start = selection.start.clamp(
      0,
      block.controller.visibleTextValue.length,
    );
    final end = selection.end.clamp(
      start,
      block.controller.visibleTextValue.length,
    );
    _beginDiscreteChange();

    final inline =
        !source.contains('\n') &&
        parsed.length == 1 &&
        parsed.single.type == NoteBlockType.paragraph;
    if (inline) {
      final inserted = parsed.single;
      final original = block.controller.visibleTextValue;
      final nextText = original.replaceRange(start, end, inserted.text);
      final delta = inserted.text.length - (end - start);
      final inherited = block.controller.attributesForSelection(selection);
      final insertedStyles =
          inserted.styles.isEmpty &&
              inherited != NoteTextAttributes.defaults &&
              inserted.text.isNotEmpty
          ? [NoteTextStyleRange(start, start + inserted.text.length, inherited)]
          : [
              for (final range in inserted.styles)
                NoteTextStyleRange(
                  range.start + start,
                  range.end + start,
                  range.attributes,
                ),
            ];
      final styles = [
        ...block.controller.styleRangesFor(0, start),
        ...insertedStyles,
        ...block.controller.styleRangesFor(end, original.length, shift: delta),
      ];
      _syncing = true;
      block.controller.replaceVisibleText(nextText, styles);
      _syncing = false;
      block.controller.visibleSelectionValue = TextSelection.collapsed(
        offset: start + inserted.text.length,
      );
      _syncDocument();
      _refocus(block, offset: start + inserted.text.length);
      _endDiscreteChange();
      return true;
    }

    final original = block.controller.visibleTextValue;
    final beforeText = original.substring(0, start);
    final afterText = original.substring(end);
    final replacement = <NoteBlockData>[
      if (beforeText.isNotEmpty)
        NoteBlockData(
          block.type,
          beforeText,
          checked: block.checked,
          indent: block.indent,
          quoteDepth: block.quoteDepth,
          headingLevel: block.headingLevel,
          codeLanguage: block.codeLanguage,
          styles: block.controller.styleRangesFor(0, start),
        ),
      ...parsed,
      if (afterText.isNotEmpty)
        NoteBlockData(
          NoteBlockType.paragraph,
          afterText,
          styles: block.controller.styleRangesFor(
            end,
            original.length,
            shift: -end,
          ),
        ),
    ];
    _releaseBlockFocus();
    _syncing = true;
    final removed = _blocks.removeAt(index)..dispose();
    assert(removed == block);
    final insertedBlocks = replacement.map(_makeBlock).toList();
    _blocks.insertAll(index, insertedBlocks);
    _syncing = false;
    _activeIndex = index + insertedBlocks.length - 1;
    activeType.value = _blocks[_activeIndex].type;
    _syncDocument();
    setState(() {});
    final target = _blocks[_activeIndex];
    _refocus(target);
    _endDiscreteChange();
    return true;
  }

  /// Replaces the contiguous dictation immediately before the current caret.
  ///
  /// The final offline pass can revise the whole streaming hypothesis. This
  /// guarded replacement succeeds only when the expected streaming text is
  /// still untouched, so a user's caret move or manual edit remains authoritative.
  bool replaceDictationTextBeforeCaret({
    required String previous,
    required String replacement,
  }) {
    if (previous == replacement) return true;
    if (previous.isEmpty) return insertDictationTextAtCaret(replacement);
    if (!prepareDictationInsertion()) return false;
    final block = _activeEditableBlock!;
    final text = block.controller.visibleTextValue;
    final selection = block.controller.visibleSelectionValue;
    final caret = selection.isValid
        ? selection.extentOffset.clamp(0, text.length)
        : text.length;
    final start = caret - previous.length;
    if (start < 0 || text.substring(start, caret) != previous) return false;
    block.controller.value = TextEditingValue(
      text: text.replaceRange(start, caret, replacement),
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
    return true;
  }

  /// Anchors a live-dictation range at the current caret. Subsequent partial
  /// hypotheses replace only this range, so nearby note text never flickers or
  /// gets duplicated as the recognizer revises its result.
  bool beginDictation() {
    if (_dictating || _blocks.isEmpty) return false;
    var block = _activeEditableBlock;
    if (block == null) {
      final index = _blocks.lastIndexWhere(
        (item) =>
            item.type != NoteBlockType.divider &&
            item.type != NoteBlockType.attachment,
      );
      if (index < 0) return false;
      _activeIndex = index;
      block = _blocks[index];
    }
    _closeHistoryGroup();
    _dictationSnapshot = _currentSnapshot;
    _dictationBlock = block;
    final text = block.controller.visibleTextValue;
    final selection = block.controller.visibleSelectionValue;
    final start = selection.isValid
        ? selection.start.clamp(0, text.length)
        : text.length;
    final end = selection.isValid
        ? selection.end.clamp(start, text.length)
        : start;
    _dictationStart = start;
    _dictationLength = 0;
    _dictating = true;
    block.controller.typingAttributes = block.controller.attributesForSelection(
      TextSelection.collapsed(offset: start),
    );
    if (end > start) {
      block.controller.value = TextEditingValue(
        text: text.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start),
      );
    }
    _activeIndex = _blocks.indexOf(block);
    activeType.value = block.type;
    return true;
  }

  void updateDictation(String value) {
    if (!_dictating) return;
    final block = _dictationBlock;
    if (block == null || !_blocks.contains(block)) return;
    final text = block.controller.visibleTextValue;
    final start = _dictationStart.clamp(0, text.length);
    final end = (start + _dictationLength).clamp(start, text.length);
    block.controller.value = TextEditingValue(
      text: text.replaceRange(start, end, value),
      selection: TextSelection.collapsed(offset: start + value.length),
    );
    _dictationLength = value.length;
  }

  void finishDictation({required bool keepText}) {
    if (!_dictating) return;
    if (_documentSyncTimer != null) flushPendingChanges();
    final before = _dictationSnapshot;
    _dictating = false;
    _dictationSnapshot = null;
    _dictationBlock = null;
    _dictationLength = 0;
    if (!keepText && before != null) {
      _restoreSnapshot(before);
      return;
    }
    if (before != null &&
        before.richDocument != _currentSnapshot.richDocument) {
      _undoStack.add(before);
      if (_undoStack.length > 100) _undoStack.removeAt(0);
      _redoStack.clear();
      _notifyHistoryChanged();
    }
    _closeHistoryGroup();
  }

  void _restoreSnapshot(_EditorSnapshot snapshot) {
    final decoded = NoteRichDocumentCodec.tryDecode(snapshot.richDocument);
    if (decoded == null || decoded.isEmpty) return;
    _releaseBlockFocus();
    _restoringHistory = true;
    _syncing = true;
    for (final block in _blocks) {
      block.dispose();
    }
    _blocks
      ..clear()
      ..addAll(decoded.map(_makeBlock));
    _activeIndex = snapshot.activeIndex.clamp(0, _blocks.length - 1);
    final plainText = NoteBlockCodec.encode(_document);
    widget.controller.value = TextEditingValue(
      text: plainText,
      selection: TextSelection.collapsed(offset: plainText.length),
    );
    _lastRichDocument = snapshot.richDocument;
    _currentSnapshot = snapshot;
    _syncing = false;
    _restoringHistory = false;
    activeType.value = _blocks[_activeIndex].type;
    setState(() {});
    widget.onRichContentChanged?.call(snapshot.richDocument);
    _notifyHistoryChanged();
    final block = _blocks[_activeIndex];
    if (block.type != NoteBlockType.divider &&
        block.type != NoteBlockType.attachment) {
      _refocus(block, selection: snapshot.selection);
    } else {
      _refreshActiveFormat();
    }
  }

  _EditableBlock? get _activeEditableBlock {
    if (_blocks.isEmpty || _activeIndex >= _blocks.length) return null;
    final block = _blocks[_activeIndex];
    if (block.type == NoteBlockType.divider ||
        block.type == NoteBlockType.attachment) {
      return null;
    }
    return block;
  }

  void _refreshActiveFormat() {
    final block = _activeEditableBlock;
    if (block == null) {
      activeFormat.value = const NoteEditorFormatState();
      return;
    }
    final selection = block.controller.visibleSelectionValue;
    final attributes = block.controller.attributesForSelection(selection);
    block.controller.typingAttributes = attributes;
    activeFormat.value = NoteEditorFormatState(
      bold: attributes.bold,
      italic: attributes.italic,
      strikethrough: attributes.strikethrough,
      inlineCode: attributes.inlineCode,
      underline: attributes.underline,
      fontSize: block.controller.uniformFontSize(selection),
      link: attributes.link,
      indent: block.indent,
      headingLevel: block.headingLevel,
    );
  }

  void toggleBold() => _toggleAttribute(
    (attributes, enabled) => attributes.copyWith(bold: enabled),
    (attributes) => attributes.bold,
  );

  void toggleUnderline() => _toggleAttribute(
    (attributes, enabled) => attributes.copyWith(underline: enabled),
    (attributes) => attributes.underline,
  );

  void toggleItalic() => _toggleAttribute(
    (attributes, enabled) => attributes.copyWith(italic: enabled),
    (attributes) => attributes.italic,
  );

  void toggleStrikethrough() => _toggleAttribute(
    (attributes, enabled) => attributes.copyWith(strikethrough: enabled),
    (attributes) => attributes.strikethrough,
  );

  void toggleInlineCode() => _toggleAttribute(
    (attributes, enabled) => attributes.copyWith(inlineCode: enabled),
    (attributes) => attributes.inlineCode,
  );

  void setLink(String? value) {
    final block = _activeEditableBlock;
    if (block == null) return;
    final link = value?.trim();
    _beginDiscreteChange();
    HapticFeedback.selectionClick();
    final selection = block.controller.visibleSelectionValue;
    if (selection.isCollapsed) {
      block.controller.setTypingAttributesForSelection(
        selection,
        block.controller.typingAttributes.copyWith(
          link: link?.isEmpty == true ? null : link,
        ),
      );
      _refreshActiveFormat();
      _refocus(block, selection: selection);
      _endDiscreteChange();
      return;
    }
    block.controller.applyAttributes(
      selection,
      (attributes) =>
          attributes.copyWith(link: link?.isEmpty == true ? null : link),
    );
    _syncDocument();
    _refreshActiveFormat();
    _refocus(block, selection: selection);
    _endDiscreteChange();
  }

  void _toggleAttribute(
    NoteTextAttributes Function(NoteTextAttributes, bool) update,
    bool Function(NoteTextAttributes) read,
  ) {
    final block = _activeEditableBlock;
    if (block == null) return;
    _beginDiscreteChange();
    HapticFeedback.selectionClick();
    final selection = block.controller.visibleSelectionValue;
    final current = selection.isCollapsed
        ? block.controller.typingAttributes
        : block.controller.attributesForSelection(selection);
    if (selection.isCollapsed) {
      block.controller.setTypingAttributesForSelection(
        selection,
        update(current, !read(current)),
      );
      activeFormat.value = NoteEditorFormatState(
        bold: block.controller.typingAttributes.bold,
        italic: block.controller.typingAttributes.italic,
        strikethrough: block.controller.typingAttributes.strikethrough,
        inlineCode: block.controller.typingAttributes.inlineCode,
        underline: block.controller.typingAttributes.underline,
        fontSize: block.controller.typingAttributes.fontSize,
        link: block.controller.typingAttributes.link,
        indent: block.indent,
        headingLevel: block.headingLevel,
      );
      _refocus(block, selection: selection);
      _endDiscreteChange();
      return;
    }
    block.controller.applyAttributes(
      selection,
      (attributes) => update(attributes, !read(current)),
    );
    _syncDocument();
    _refreshActiveFormat();
    _refocus(block, selection: selection);
    _endDiscreteChange();
  }

  void setFontSize(double fontSize) {
    final block = _activeEditableBlock;
    if (block == null) return;
    _beginDiscreteChange();
    HapticFeedback.selectionClick();
    final selection = block.controller.visibleSelectionValue;
    if (selection.isCollapsed) {
      block.controller.setTypingAttributesForSelection(
        selection,
        block.controller.typingAttributes.copyWith(fontSize: fontSize),
      );
      activeFormat.value = NoteEditorFormatState(
        bold: block.controller.typingAttributes.bold,
        italic: block.controller.typingAttributes.italic,
        strikethrough: block.controller.typingAttributes.strikethrough,
        inlineCode: block.controller.typingAttributes.inlineCode,
        underline: block.controller.typingAttributes.underline,
        fontSize: fontSize,
        link: block.controller.typingAttributes.link,
        indent: block.indent,
        headingLevel: block.headingLevel,
      );
      _refocus(block, selection: selection);
      _endDiscreteChange();
      return;
    }
    block.controller.applyAttributes(
      selection,
      (attributes) => attributes.copyWith(fontSize: fontSize),
    );
    _syncDocument();
    _refreshActiveFormat();
    _refocus(block, selection: selection);
    _endDiscreteChange();
  }

  void changeIndent(int delta) {
    final block = _activeEditableBlock;
    if (block == null) return;
    final next = (block.indent + delta).clamp(0, 3);
    if (next == block.indent) return;
    _beginDiscreteChange();
    HapticFeedback.selectionClick();
    final selection = block.controller.visibleSelectionValue;
    setState(() => block.indent = next);
    _syncDocument();
    _refocus(block, selection: selection);
    _endDiscreteChange();
  }

  void toggleBlock(NoteBlockType type) {
    _beginDiscreteChange();
    HapticFeedback.selectionClick();
    if (_activeIndex >= _blocks.length) _activeIndex = _blocks.length - 1;
    final block = _blocks[_activeIndex];
    if (block.type == NoteBlockType.divider ||
        block.type == NoteBlockType.attachment) {
      _insertAfterDivider(type);
      return;
    }
    final selection = block.controller.visibleSelectionValue;
    setState(() {
      _setBlockType(block, block.type == type ? NoteBlockType.paragraph : type);
      activeType.value = block.type;
    });
    _syncDocument();
    _refocus(block, selection: selection);
    _endDiscreteChange();
  }

  void setHeadingLevel(int? level) {
    final block = _activeEditableBlock;
    if (block == null) return;
    _beginDiscreteChange();
    HapticFeedback.selectionClick();
    final selection = block.controller.visibleSelectionValue;
    setState(() {
      if (level == null) {
        _setBlockType(block, NoteBlockType.paragraph);
      } else {
        _setBlockType(block, NoteBlockType.heading);
        block.headingLevel = level.clamp(1, 6);
      }
      activeType.value = block.type;
    });
    _syncDocument();
    _refreshActiveFormat();
    _refocus(block, selection: selection);
    _endDiscreteChange();
  }

  void _setBlockType(_EditableBlock block, NoteBlockType type) {
    block.type = type;
    block.quoteDepth = type == NoteBlockType.quote ? 1 : 0;
    if (type != NoteBlockType.todo) block.checked = false;
    if (type == NoteBlockType.heading && block.headingLevel == 0) {
      block.headingLevel = 2;
    } else if (type != NoteBlockType.heading) {
      block.headingLevel = 0;
    }
    if (type != NoteBlockType.code) block.codeLanguage = null;
  }

  void insertDivider() {
    _beginDiscreteChange();
    HapticFeedback.selectionClick();
    if (_activeIndex >= _blocks.length) _activeIndex = _blocks.length - 1;
    final current = _blocks[_activeIndex];
    if (current.type == NoteBlockType.divider) {
      _insertAfterDivider(NoteBlockType.paragraph);
      return;
    }
    final selection = current.controller.visibleSelectionValue;
    final start = selection.isValid
        ? selection.start
        : current.controller.visibleTextValue.length;
    final end = selection.isValid ? selection.end : start;
    final before = current.controller.visibleTextValue.substring(0, start);
    final after = current.controller.visibleTextValue.substring(end);
    final beforeStyles = current.controller.styleRangesFor(0, start);
    final afterStyles = current.controller.styleRangesFor(
      end,
      current.controller.visibleTextValue.length,
      shift: -end,
    );
    final divider = _makeBlock(const NoteBlockData(NoteBlockType.divider, ''));
    final next = _makeBlock(
      NoteBlockData(
        NoteBlockType.paragraph,
        after,
        indent: current.indent,
        styles: afterStyles,
      ),
    );
    _syncing = true;
    current.controller.replaceVisibleText(before, beforeStyles);
    _syncing = false;
    setState(() {
      _blocks.insert(_activeIndex + 1, divider);
      _blocks.insert(_activeIndex + 2, next);
      _activeIndex += 2;
      activeType.value = NoteBlockType.paragraph;
    });
    _syncDocument();
    _refocus(next, atStart: true);
    _endDiscreteChange();
  }

  void insertAttachmentReference(String filePath) {
    _beginDiscreteChange();
    HapticFeedback.selectionClick();
    if (_activeIndex >= _blocks.length) _activeIndex = _blocks.length - 1;
    final current = _blocks[_activeIndex];
    final reference = _makeBlock(
      NoteBlockData(NoteBlockType.attachment, '', attachmentPath: filePath),
    );
    if (current.type == NoteBlockType.divider ||
        current.type == NoteBlockType.attachment) {
      final next = _makeBlock(const NoteBlockData(NoteBlockType.paragraph, ''));
      setState(() {
        _blocks.insert(_activeIndex + 1, reference);
        _blocks.insert(_activeIndex + 2, next);
        _activeIndex += 2;
        activeType.value = NoteBlockType.paragraph;
      });
      _syncDocument();
      _refocus(next, atStart: true);
      _endDiscreteChange();
      return;
    }

    final selection = current.controller.visibleSelectionValue;
    final start = selection.isValid
        ? selection.start
        : current.controller.visibleTextValue.length;
    final end = selection.isValid ? selection.end : start;
    final before = current.controller.visibleTextValue.substring(0, start);
    final after = current.controller.visibleTextValue.substring(end);
    final beforeStyles = current.controller.styleRangesFor(0, start);
    final afterStyles = current.controller.styleRangesFor(
      end,
      current.controller.visibleTextValue.length,
      shift: -end,
    );
    final next = _makeBlock(
      NoteBlockData(
        NoteBlockType.paragraph,
        after,
        indent: current.indent,
        styles: afterStyles,
      ),
    );
    _syncing = true;
    current.controller.replaceVisibleText(before, beforeStyles);
    _syncing = false;
    setState(() {
      _blocks.insert(_activeIndex + 1, reference);
      _blocks.insert(_activeIndex + 2, next);
      _activeIndex += 2;
      activeType.value = NoteBlockType.paragraph;
    });
    _syncDocument();
    _refocus(next, atStart: true);
    _endDiscreteChange();
  }

  void _insertAfterDivider(NoteBlockType type) {
    final next = _makeBlock(NoteBlockData(type, ''));
    setState(() {
      _blocks.insert(_activeIndex + 1, next);
      _activeIndex++;
      activeType.value = type;
    });
    _syncDocument();
    _refocus(next, atStart: true);
    _endDiscreteChange();
  }

  void _splitBlock(_EditableBlock block, TextSelection replacedSelection) {
    if (!mounted) return;
    final index = _blocks.indexOf(block);
    if (index < 0) return;
    _beginDiscreteChange();
    final text = block.controller.visibleTextValue;
    final start = replacedSelection.start.clamp(0, text.length);
    final end = replacedSelection.end.clamp(start, text.length);
    final before = text.substring(0, start);
    final after = text.substring(end);
    final beforeStyles = block.controller.styleRangesFor(0, start);
    final afterStyles = block.controller.styleRangesFor(
      end,
      text.length,
      shift: -end,
    );

    if (block.type != NoteBlockType.paragraph &&
        before.trim().isEmpty &&
        after.trim().isEmpty) {
      setState(() {
        _setBlockType(block, NoteBlockType.paragraph);
        activeType.value = NoteBlockType.paragraph;
      });
      _syncDocument();
      _refocus(block, atStart: true);
      _endDiscreteChange();
      return;
    }

    final nextType = switch (block.type) {
      NoteBlockType.bullet => NoteBlockType.bullet,
      NoteBlockType.ordered => NoteBlockType.ordered,
      NoteBlockType.todo => NoteBlockType.todo,
      NoteBlockType.quote => NoteBlockType.quote,
      _ => NoteBlockType.paragraph,
    };
    final next = _makeBlock(
      NoteBlockData(
        nextType,
        after,
        indent: block.indent,
        quoteDepth: block.quoteDepth,
        styles: afterStyles,
      ),
    );
    _syncing = true;
    block.controller.replaceVisibleText(before, beforeStyles);
    _syncing = false;
    setState(() {
      _blocks.insert(index + 1, next);
      _activeIndex = index + 1;
      activeType.value = nextType;
    });
    _syncDocument();
    _refocus(next, atStart: true);
    _endDiscreteChange();
  }

  void _mergeWithPrevious(_EditableBlock block) {
    if (!mounted) return;
    final index = _blocks.indexOf(block);
    if (index <= 0) return;
    final previous = _blocks[index - 1];
    if (previous.type == NoteBlockType.divider) {
      setState(() => _blocks.removeAt(index - 1).dispose());
      _activeIndex = index - 1;
      _syncDocument();
      _refocus(block, atStart: true);
      return;
    }
    if (previous.type == NoteBlockType.attachment) {
      setState(() => _blocks.removeAt(index - 1).dispose());
      _activeIndex = index - 1;
      _syncDocument();
      _refocus(block, atStart: true);
      return;
    }
    final joinAt = previous.controller.visibleTextValue.length;
    final mergedStyles = [
      ...previous.controller.styleRanges,
      ...block.controller.styleRangesFor(
        0,
        block.controller.visibleTextValue.length,
        shift: joinAt,
      ),
    ];
    _syncing = true;
    previous.controller.replaceVisibleText(
      previous.controller.visibleTextValue + block.controller.visibleTextValue,
      mergedStyles,
    );
    _syncing = false;
    _releaseBlockFocus();
    setState(() {
      _blocks.removeAt(index).dispose();
      _activeIndex = index - 1;
      activeType.value = previous.type;
    });
    _syncDocument();
    _refocus(previous, offset: joinAt);
  }

  void _backspaceAtStart(_EditableBlock block) {
    if (!mounted) return;
    final index = _blocks.indexOf(block);
    if (index < 0) return;
    _beginDiscreteChange();

    if (block.type != NoteBlockType.paragraph) {
      setState(() {
        _setBlockType(block, NoteBlockType.paragraph);
        _activeIndex = index;
        activeType.value = NoteBlockType.paragraph;
      });
      _syncDocument();
      _refocus(block, atStart: true);
      _endDiscreteChange();
      return;
    }

    _mergeWithPrevious(block);
    _endDiscreteChange();
  }

  KeyEventResult _handleBlockKeyEvent(_EditableBlock block, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.backspace ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    final selection = block.controller.visibleSelectionValue;
    if (!selection.isValid || !selection.isCollapsed || selection.start != 0) {
      return KeyEventResult.ignored;
    }
    _backspaceAtStart(block);
    return KeyEventResult.handled;
  }

  void _refocus(
    _EditableBlock block, {
    bool atStart = false,
    int? offset,
    TextSelection? selection,
  }) {
    final requestGeneration = ++_focusRequestGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          requestGeneration != _focusRequestGeneration ||
          !_blocks.contains(block)) {
        return;
      }
      block.focusNode.requestFocus();
      if (selection?.isValid == true) {
        block.controller.visibleSelectionValue = selection!;
      } else {
        final target =
            offset ?? (atStart ? 0 : block.controller.visibleTextValue.length);
        block.controller.visibleSelectionValue = TextSelection.collapsed(
          offset: target,
        );
      }
    });
    // Some refocus requests originate from tapping otherwise inert whitespace.
    // That gesture does not necessarily schedule a frame by itself.
    WidgetsBinding.instance.scheduleFrame();
  }

  void _releaseBlockFocus() {
    _focusRequestGeneration++;
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus != null &&
        _blocks.any((block) => identical(block.focusNode, primaryFocus))) {
      primaryFocus.unfocus();
    }
  }

  void focusAtEnd() {
    final editable = _blocks.where(
      (item) =>
          item.type != NoteBlockType.divider &&
          item.type != NoteBlockType.attachment,
    );
    if (editable.isEmpty) return;
    final target = editable.last;
    final end = target.controller.visibleTextValue.length;
    target.controller.visibleSelectionValue = TextSelection.collapsed(
      offset: end,
    );
    if (!target.focusNode.hasFocus) {
      // The block is already mounted, so the first whitespace tap can focus it
      // immediately without waiting for an unrelated frame.
      target.focusNode.requestFocus();
      return;
    }
    // Android keeps the field focused after the user dismisses the keyboard,
    // but the old input connection may no longer reopen reliably. Recreate
    // the connection before requesting focus again.
    target.focusNode.unfocus();
    _refocus(target, offset: end);
  }

  int _numberFor(int index) {
    var number = 1;
    for (var i = index - 1; i >= 0; i--) {
      if (_blocks[i].type != NoteBlockType.ordered ||
          _blocks[i].indent != _blocks[index].indent) {
        break;
      }
      number++;
    }
    return number;
  }

  @override
  void dispose() {
    _historyGroupTimer?.cancel();
    _documentSyncTimer?.cancel();
    activeType.dispose();
    activeFormat.dispose();
    historyState.dispose();
    for (final block in _blocks) {
      block.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: focusAtEnd,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: widget.minLines * 27),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < _blocks.length; index++)
              KeyedSubtree(
                key: ObjectKey(_blocks[index]),
                child: _buildBlock(index),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlock(int index) {
    final block = _blocks[index];
    if (block.type == NoteBlockType.attachment) {
      return _buildAttachmentReference(index, block);
    }
    if (block.type == NoteBlockType.rawMarkdown) {
      return _buildTableBlock(block);
    }
    if (block.type == NoteBlockType.divider) {
      return Semantics(
        label: context.l10n.divider,
        child: InkWell(
          onTap: () {
            _activeIndex = index;
            activeType.value = NoteBlockType.divider;
            FocusScope.of(context).unfocus();
          },
          borderRadius: BorderRadius.circular(8),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 17),
            child: Divider(color: AppColors.line, thickness: 1),
          ),
        ),
      );
    }

    final plainQuote = block.type == NoteBlockType.quote;
    final quote = plainQuote || block.quoteDepth > 0;
    final code = block.type == NoteBlockType.code;
    final rawMarkdown = block.type == NoteBlockType.rawMarkdown;
    final heading = block.type == NoteBlockType.heading;
    final connectsPreviousQuote =
        quote &&
        index > 0 &&
        (_blocks[index - 1].type == NoteBlockType.quote ||
            _blocks[index - 1].quoteDepth > 0) &&
        _blocks[index - 1].quoteDepth == block.quoteDepth &&
        _blocks[index - 1].indent == block.indent;
    final connectsNextQuote =
        quote &&
        index + 1 < _blocks.length &&
        (_blocks[index + 1].type == NoteBlockType.quote ||
            _blocks[index + 1].quoteDepth > 0) &&
        _blocks[index + 1].quoteDepth == block.quoteDepth &&
        _blocks[index + 1].indent == block.indent;
    return Container(
      margin: EdgeInsets.only(
        left: quote ? (block.quoteDepth.clamp(1, 3) - 1) * 18 : 0,
        top: connectsPreviousQuote ? 0 : 1,
        bottom: connectsNextQuote ? 0 : 1,
      ),
      padding: EdgeInsets.only(
        left: quote ? 10 + block.indent * 18 : block.indent * 18,
      ),
      decoration: BoxDecoration(
        color: code || rawMarkdown
            ? AppColors.softBlue.withValues(alpha: .52)
            : Colors.transparent,
        borderRadius: code || rawMarkdown ? BorderRadius.circular(12) : null,
        border: Border(
          left: BorderSide(
            color: quote ? AppColors.coral : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width:
                block.type == NoteBlockType.paragraph ||
                    plainQuote ||
                    heading ||
                    code ||
                    rawMarkdown
                ? 0
                : 34,
            height: 43,
            child: _buildLeading(index, block),
          ),
          Expanded(
            child: Focus(
              canRequestFocus: false,
              onKeyEvent: (_, event) => _handleBlockKeyEvent(block, event),
              child: Stack(
                children: [
                  TextField(
                    controller: block.controller,
                    focusNode: block.focusNode,
                    contextMenuBuilder: _buildBlockContextMenu,
                    inputFormatters: [
                      _BlockInputFormatter(
                        onNewline: (selection) => _splitBlock(block, selection),
                        onMultilinePaste: (source, selection) => _pasteMarkdown(
                          block,
                          source,
                          replacedSelection: selection,
                        ),
                        onBackspaceAtStart: () => _backspaceAtStart(block),
                        allowNewlines: code || rawMarkdown,
                      ),
                    ],
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    textCapitalization: TextCapitalization.sentences,
                    cursorColor: AppColors.coral,
                    style: TextStyle(
                      fontSize: heading
                          ? switch (block.headingLevel.clamp(1, 6)) {
                              1 => 28,
                              2 => 24,
                              3 => 21,
                              _ => 18,
                            }
                          : 17,
                      height: code || rawMarkdown ? 1.48 : 1.62,
                      color: plainQuote ? AppColors.muted : AppColors.ink,
                      fontStyle: plainQuote
                          ? FontStyle.italic
                          : FontStyle.normal,
                      fontWeight: heading ? FontWeight.w800 : null,
                      fontFamily: code || rawMarkdown ? 'monospace' : null,
                      decoration:
                          block.type == NoteBlockType.todo && block.checked
                          ? TextDecoration.lineThrough
                          : null,
                      decorationColor: AppColors.muted,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 7),
                    ),
                  ),
                  if (index == 0)
                    Positioned(
                      left: 0,
                      top: 7,
                      child: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: block.controller,
                        builder: (context, value, child) => IgnorePointer(
                          child: block.controller.visibleTextValue.isEmpty
                              ? Text(
                                  widget.hintText,
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 17,
                                    height: 1.62,
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableBlock(_EditableBlock block) {
    final table = MarkdownTableData.tryParse(block.controller.visibleTextValue);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.softBlue.withValues(alpha: .52),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 0),
            child: Row(
              children: [
                const Icon(
                  Icons.table_chart_outlined,
                  size: 18,
                  color: AppColors.coral,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.markdownTable,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (table != null)
                  Text(
                    context.l10n.tableDimensions(
                      table.headers.length,
                      table.rows.length,
                    ),
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                IconButton(
                  tooltip: context.l10n.deleteTable,
                  onPressed: () => _removeNonTextBlock(block),
                  icon: const Icon(Icons.delete_outline_rounded, size: 19),
                ),
                IconButton(
                  tooltip: context.l10n.editTable,
                  onPressed: () => _editMarkdownTable(block),
                  icon: const Icon(Icons.edit_outlined, size: 19),
                ),
              ],
            ),
          ),
          if (table == null)
            Focus(
              canRequestFocus: false,
              onKeyEvent: (_, event) => _handleBlockKeyEvent(block, event),
              child: TextField(
                controller: block.controller,
                focusNode: block.focusNode,
                contextMenuBuilder: _buildBlockContextMenu,
                inputFormatters: [
                  _BlockInputFormatter(
                    onNewline: (selection) => _splitBlock(block, selection),
                    onMultilinePaste: (source, selection) => _pasteMarkdown(
                      block,
                      source,
                      replacedSelection: selection,
                    ),
                    onBackspaceAtStart: () => _backspaceAtStart(block),
                    allowNewlines: true,
                  ),
                ],
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                cursorColor: AppColors.coral,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  height: 1.5,
                  color: AppColors.ink,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.fromLTRB(12, 6, 12, 12),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: FkMarkdownView(data: table.encode(), compact: true),
            ),
        ],
      ),
    );
  }

  Future<void> _editMarkdownTable(_EditableBlock block) async {
    final table = MarkdownTableData.tryParse(block.controller.visibleTextValue);
    if (table == null) {
      AppFeedback.error(context, context.l10n.invalidMarkdownTable);
      return;
    }
    final result = await showModalBottomSheet<MarkdownTableData>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _MarkdownTableEditorSheet(initial: table),
    );
    if (result == null || !mounted || !_blocks.contains(block)) return;
    _beginDiscreteChange();
    _syncing = true;
    block.controller.replaceVisibleText(result.encode(), const []);
    _syncing = false;
    _syncDocument();
    _refocus(block);
    _endDiscreteChange();
  }

  Widget _buildAttachmentReference(int index, _EditableBlock block) {
    NoteAttachment? attachment;
    for (final item in widget.attachments) {
      if (item.filePath == block.attachmentPath) {
        attachment = item;
        break;
      }
    }
    final resolved = attachment;
    final color = resolved == null
        ? AppColors.muted
        : NoteCard.colorForType(resolved.type);
    final thumbnailPath = resolved?.thumbnailPath;
    final thumbnail = thumbnailPath == null
        ? null
        : File(FileStorageService.instance.absolutePath(thumbnailPath));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Material(
        color: resolved == null
            ? AppColors.softBlue
            : color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: resolved == null
              ? null
              : () => widget.onOpenAttachment?.call(resolved),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 46,
                    height: 46,
                    color: color.withValues(alpha: .08),
                    padding: thumbnail?.existsSync() == true
                        ? const EdgeInsets.all(2)
                        : EdgeInsets.zero,
                    child: thumbnail?.existsSync() == true
                        ? Image.file(thumbnail!, fit: BoxFit.contain)
                        : Icon(
                            resolved == null
                                ? Icons.link_off_rounded
                                : NoteCard.iconForType(resolved.type),
                            size: 22,
                            color: color,
                          ),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        resolved?.displayTitle ??
                            context.l10n.attachmentRemoved,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        resolved == null
                            ? context.l10n.brokenAttachmentReference
                            : context.l10n.attachmentReferenceDescription(
                                _localizedNoteType(context, resolved.type),
                                _formatSize(resolved.fileSize),
                              ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.removeReference,
                  onPressed: () => _removeNonTextBlock(block),
                  icon: const Icon(Icons.close_rounded, size: 19),
                  color: AppColors.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _removeNonTextBlock(_EditableBlock block) {
    final index = _blocks.indexOf(block);
    if (index < 0) return;
    _beginDiscreteChange();
    HapticFeedback.selectionClick();
    final removed = _blocks.removeAt(index)..dispose();
    assert(
      removed.type == NoteBlockType.attachment ||
          removed.type == NoteBlockType.rawMarkdown,
    );
    _EditableBlock target;
    if (_blocks.isEmpty) {
      target = _makeBlock(const NoteBlockData(NoteBlockType.paragraph, ''));
      _blocks.add(target);
      _activeIndex = 0;
    } else if (index < _blocks.length &&
        _blocks[index].type != NoteBlockType.divider &&
        _blocks[index].type != NoteBlockType.attachment) {
      target = _blocks[index];
      _activeIndex = index;
    } else {
      target = _makeBlock(const NoteBlockData(NoteBlockType.paragraph, ''));
      _blocks.insert(index.clamp(0, _blocks.length), target);
      _activeIndex = index.clamp(0, _blocks.length - 1);
    }
    setState(() => activeType.value = target.type);
    _syncDocument();
    _refocus(target, atStart: true);
    _endDiscreteChange();
  }

  static String _formatSize(int bytes) => bytes < 1024
      ? '$bytes B'
      : bytes < 1048576
      ? '${(bytes / 1024).toStringAsFixed(1)} KB'
      : '${(bytes / 1048576).toStringAsFixed(1)} MB';

  Widget _buildLeading(int index, _EditableBlock block) {
    return switch (block.type) {
      NoteBlockType.bullet => const Center(
        child: Icon(Icons.circle, size: 6, color: AppColors.ink),
      ),
      NoteBlockType.ordered => Center(
        child: Text(
          '${_numberFor(index)}.',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.muted,
          ),
        ),
      ),
      NoteBlockType.todo => Center(
        child: InkResponse(
          radius: 20,
          onTap: () {
            _beginDiscreteChange();
            HapticFeedback.selectionClick();
            setState(() => block.checked = !block.checked);
            _syncDocument();
            _endDiscreteChange();
          },
          child: Icon(
            block.checked
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
            size: 22,
            color: block.checked ? AppColors.coral : AppColors.muted,
          ),
        ),
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

class _MarkdownTableEditorSheet extends StatefulWidget {
  final MarkdownTableData initial;

  const _MarkdownTableEditorSheet({required this.initial});

  @override
  State<_MarkdownTableEditorSheet> createState() =>
      _MarkdownTableEditorSheetState();
}

class _MarkdownTableEditorSheetState extends State<_MarkdownTableEditorSheet> {
  late final List<List<TextEditingController>> _cells;
  late final List<MarkdownTableAlignment> _alignments;

  @override
  void initState() {
    super.initState();
    _cells = [
      [
        for (final value in widget.initial.headers)
          TextEditingController(text: value),
      ],
      for (final row in widget.initial.rows)
        [for (final value in row) TextEditingController(text: value)],
    ];
    _alignments = [...widget.initial.alignments];
  }

  @override
  void dispose() {
    for (final row in _cells) {
      for (final controller in row) {
        controller.dispose();
      }
    }
    super.dispose();
  }

  void _addRow() => setState(() {
    _cells.add(
      List.generate(_cells.first.length, (_) => TextEditingController()),
    );
  });

  void _removeRow(int index) => setState(() {
    final removed = _cells.removeAt(index);
    for (final controller in removed) {
      controller.dispose();
    }
  });

  void _addColumn() => setState(() {
    for (final row in _cells) {
      row.add(TextEditingController());
    }
    _alignments.add(MarkdownTableAlignment.left);
  });

  void _removeColumn(int index) => setState(() {
    if (_cells.first.length <= 1) return;
    for (final row in _cells) {
      row.removeAt(index).dispose();
    }
    _alignments.removeAt(index);
  });

  void _finish() {
    Navigator.pop(
      context,
      MarkdownTableData(
        headers: _cells.first.map((cell) => cell.text.trim()).toList(),
        rows: [
          for (final row in _cells.skip(1))
            row.map((cell) => cell.text.trim()).toList(),
        ],
        alignments: [..._alignments],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: FractionallySizedBox(
        heightFactor: .82,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.editTable,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          context.l10n.tableEditorDescription(
                            _cells.first.length,
                            _cells.length - 1,
                          ),
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.addColumn,
                    onPressed: _addColumn,
                    icon: const Icon(Icons.view_column_outlined),
                  ),
                  IconButton(
                    key: const Key('markdown-table-add-row'),
                    tooltip: context.l10n.addRow,
                    onPressed: _addRow,
                    icon: const Icon(Icons.table_rows_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          border: Border.all(color: AppColors.line),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Table(
                          defaultVerticalAlignment:
                              TableCellVerticalAlignment.top,
                          columnWidths: {
                            0: const FixedColumnWidth(48),
                            for (
                              var column = 0;
                              column < _cells.first.length;
                              column++
                            )
                              column + 1: const FixedColumnWidth(190),
                          },
                          border: const TableBorder(
                            horizontalInside: BorderSide(color: AppColors.line),
                            verticalInside: BorderSide(color: AppColors.line),
                          ),
                          children: [
                            TableRow(
                              decoration: const BoxDecoration(
                                color: AppColors.softGreen,
                              ),
                              children: [
                                const TableCell(
                                  verticalAlignment:
                                      TableCellVerticalAlignment.middle,
                                  child: Icon(
                                    Icons.view_column_outlined,
                                    size: 19,
                                    color: AppColors.muted,
                                  ),
                                ),
                                for (
                                  var column = 0;
                                  column < _cells.first.length;
                                  column++
                                )
                                  _TableHeaderCell(
                                    controller: _cells.first[column],
                                    alignment: _alignments[column],
                                    canRemove: _cells.first.length > 1,
                                    onAlignmentChanged: (value) => setState(
                                      () => _alignments[column] = value,
                                    ),
                                    onRemove: () => _removeColumn(column),
                                  ),
                              ],
                            ),
                            for (var row = 1; row < _cells.length; row++)
                              TableRow(
                                decoration: BoxDecoration(
                                  color: row.isEven
                                      ? AppColors.canvas.withValues(alpha: .55)
                                      : AppColors.surface,
                                ),
                                children: [
                                  TableCell(
                                    verticalAlignment:
                                        TableCellVerticalAlignment.middle,
                                    child: IconButton(
                                      tooltip: context.l10n.deleteRow(row),
                                      onPressed: () => _removeRow(row),
                                      icon: const Icon(
                                        Icons.remove_circle_outline_rounded,
                                        size: 19,
                                      ),
                                    ),
                                  ),
                                  for (final controller in _cells[row])
                                    _TableBodyCell(controller: controller),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                overflowAlignment: OverflowBarAlignment.end,
                spacing: 8,
                overflowSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _addRow,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(context.l10n.addRow),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(context.l10n.cancel),
                  ),
                  FilledButton(
                    key: const Key('markdown-table-save'),
                    onPressed: _finish,
                    child: Text(context.l10n.saveTable),
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

class _TableHeaderCell extends StatelessWidget {
  final TextEditingController controller;
  final MarkdownTableAlignment alignment;
  final bool canRemove;
  final ValueChanged<MarkdownTableAlignment> onAlignmentChanged;
  final VoidCallback onRemove;

  const _TableHeaderCell({
    required this.controller,
    required this.alignment,
    required this.canRemove,
    required this.onAlignmentChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                contextMenuBuilder: buildAppEditableTextContextMenu,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: context.l10n.tableHeader,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            if (canRemove)
              IconButton(
                tooltip: context.l10n.deleteColumn,
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
          ],
        ),
        const SizedBox(height: 6),
        AppAnchoredMenuButton<MarkdownTableAlignment>(
          tooltip: context.l10n.cellAlignment,
          onSelected: onAlignmentChanged,
          actions: [
            AppMenuAction(
              value: MarkdownTableAlignment.left,
              icon: Icons.format_align_left_rounded,
              label: context.l10n.alignLeft,
              selected: alignment == MarkdownTableAlignment.left,
            ),
            AppMenuAction(
              value: MarkdownTableAlignment.center,
              icon: Icons.format_align_center_rounded,
              label: context.l10n.alignCenter,
              selected: alignment == MarkdownTableAlignment.center,
            ),
            AppMenuAction(
              value: MarkdownTableAlignment.right,
              icon: Icons.format_align_right_rounded,
              label: context.l10n.alignRight,
              selected: alignment == MarkdownTableAlignment.right,
            ),
          ],
          child: SizedBox(
            height: 40,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      switch (alignment) {
                        MarkdownTableAlignment.left => context.l10n.alignLeft,
                        MarkdownTableAlignment.center =>
                          context.l10n.alignCenter,
                        MarkdownTableAlignment.right => context.l10n.alignRight,
                      },
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down_rounded, size: 19),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _TableBodyCell extends StatelessWidget {
  final TextEditingController controller;

  const _TableBodyCell({required this.controller});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(4),
    child: TextField(
      controller: controller,
      contextMenuBuilder: buildAppEditableTextContextMenu,
      minLines: 1,
      maxLines: 6,
      textAlignVertical: TextAlignVertical.top,
      decoration: InputDecoration(
        isDense: true,
        hintText: context.l10n.content,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 11,
        ),
      ),
    ),
  );
}

class _BlockTextEditingController extends TextEditingController {
  static const boundary = editorBlockBoundary;
  static final _underlineGap = RegExp(r'^\s$', unicode: true);
  List<NoteTextAttributes> _attributes;
  NoteTextAttributes typingAttributes = NoteTextAttributes.defaults;
  int? _typingAttributesOffset;

  _BlockTextEditingController({
    String text = '',
    List<NoteTextStyleRange> styles = const [],
  }) : _attributes = _expandStyles(text.length, styles),
       super.fromValue(
         withBoundary(
           TextEditingValue(
             text: text,
             selection: TextSelection.collapsed(offset: text.length),
           ),
         ),
       );

  static List<NoteTextAttributes> _expandStyles(
    int length,
    List<NoteTextStyleRange> styles,
  ) {
    final expanded = List<NoteTextAttributes>.filled(
      length,
      NoteTextAttributes.defaults,
      growable: true,
    );
    for (final range in styles) {
      final start = range.start.clamp(0, length);
      final end = range.end.clamp(start, length);
      for (var index = start; index < end; index++) {
        expanded[index] = range.attributes;
      }
    }
    return expanded;
  }

  static String visibleText(String rawText) => rawText.startsWith(boundary)
      ? rawText.substring(boundary.length)
      : rawText;

  static TextSelection visibleSelection(TextSelection rawSelection) {
    if (!rawSelection.isValid) return rawSelection;
    return rawSelection.copyWith(
      baseOffset: (rawSelection.baseOffset - boundary.length).clamp(0, 1 << 31),
      extentOffset: (rawSelection.extentOffset - boundary.length).clamp(
        0,
        1 << 31,
      ),
    );
  }

  static TextEditingValue withBoundary(TextEditingValue incoming) {
    final hasBoundary = incoming.text.startsWith(boundary);
    final shift = hasBoundary ? 0 : boundary.length;
    final normalizedText = hasBoundary
        ? incoming.text
        : '$boundary${incoming.text}';

    int shiftedOffset(int value) {
      if (value < 0) return value;
      final shifted = value + shift;
      if (shifted < boundary.length) return boundary.length;
      if (shifted > normalizedText.length) return normalizedText.length;
      return shifted;
    }

    final selection = incoming.selection.isValid
        ? incoming.selection.copyWith(
            baseOffset: shiftedOffset(incoming.selection.baseOffset),
            extentOffset: shiftedOffset(incoming.selection.extentOffset),
          )
        : incoming.selection;
    final composing = incoming.composing.isValid
        ? TextRange(
            start: shiftedOffset(incoming.composing.start),
            end: shiftedOffset(incoming.composing.end),
          )
        : TextRange.empty;
    return incoming.copyWith(
      text: normalizedText,
      selection: selection,
      composing: composing,
    );
  }

  String get visibleTextValue => visibleText(super.text);

  set visibleTextValue(String newText) {
    text = newText;
  }

  TextSelection get visibleSelectionValue => visibleSelection(super.selection);

  set visibleSelectionValue(TextSelection newSelection) {
    if (!newSelection.isValid) {
      super.selection = newSelection;
      return;
    }
    super.selection = newSelection.copyWith(
      baseOffset: newSelection.baseOffset + boundary.length,
      extentOffset: newSelection.extentOffset + boundary.length,
    );
  }

  List<NoteTextStyleRange> get styleRanges {
    final ranges = <NoteTextStyleRange>[];
    if (_attributes.isEmpty) return ranges;
    var start = 0;
    var current = _attributes.first;
    for (var index = 1; index <= _attributes.length; index++) {
      final changed =
          index == _attributes.length || _attributes[index] != current;
      if (!changed) continue;
      if (current != NoteTextAttributes.defaults) {
        ranges.add(NoteTextStyleRange(start, index, current));
      }
      if (index < _attributes.length) {
        start = index;
        current = _attributes[index];
      }
    }
    return ranges;
  }

  List<NoteTextStyleRange> styleRangesFor(int start, int end, {int shift = 0}) {
    final ranges = <NoteTextStyleRange>[];
    for (final range in styleRanges) {
      final clippedStart = range.start.clamp(start, end);
      final clippedEnd = range.end.clamp(start, end);
      if (clippedStart < clippedEnd) {
        ranges.add(
          NoteTextStyleRange(
            clippedStart + shift,
            clippedEnd + shift,
            range.attributes,
          ),
        );
      }
    }
    return ranges;
  }

  NoteTextAttributes attributesForSelection(TextSelection selection) {
    if (_attributes.isEmpty) return typingAttributes;
    if (!selection.isValid || selection.isCollapsed) {
      final offset = selection.isValid ? selection.extentOffset : 0;
      if (selection.isValid && _typingAttributesOffset == offset) {
        return typingAttributes;
      }
      final index = offset <= 0
          ? 0
          : (offset - 1).clamp(0, _attributes.length - 1);
      return _attributes[index];
    }
    final start = selection.start.clamp(0, _attributes.length);
    final end = selection.end.clamp(start, _attributes.length);
    if (start == end) return typingAttributes;
    final selected = _attributes.sublist(start, end);
    final first = selected.first;
    return NoteTextAttributes(
      bold: selected.every((attributes) => attributes.bold),
      italic: selected.every((attributes) => attributes.italic),
      strikethrough: selected.every((attributes) => attributes.strikethrough),
      inlineCode: selected.every((attributes) => attributes.inlineCode),
      image: selected.every((attributes) => attributes.image),
      underline: selected.every((attributes) => attributes.underline),
      fontSize:
          selected.every((attributes) => attributes.fontSize == first.fontSize)
          ? first.fontSize
          : NoteTextAttributes.defaultFontSize,
      link: selected.every((attributes) => attributes.link == first.link)
          ? first.link
          : null,
    );
  }

  double? uniformFontSize(TextSelection selection) {
    if (_attributes.isEmpty) return typingAttributes.fontSize;
    if (!selection.isValid || selection.isCollapsed) {
      return attributesForSelection(selection).fontSize;
    }
    final start = selection.start.clamp(0, _attributes.length);
    final end = selection.end.clamp(start, _attributes.length);
    if (start == end) return typingAttributes.fontSize;
    final size = _attributes[start].fontSize;
    return _attributes
            .sublist(start, end)
            .every((attributes) => attributes.fontSize == size)
        ? size
        : null;
  }

  void applyAttributes(
    TextSelection selection,
    NoteTextAttributes Function(NoteTextAttributes) update,
  ) {
    if (!selection.isValid || selection.isCollapsed) {
      typingAttributes = update(attributesForSelection(selection));
      notifyListeners();
      return;
    }
    final start = selection.start.clamp(0, _attributes.length);
    final end = selection.end.clamp(start, _attributes.length);
    for (var index = start; index < end; index++) {
      _attributes[index] = update(_attributes[index]);
    }
    typingAttributes = attributesForSelection(selection);
    notifyListeners();
  }

  void replaceVisibleText(String text, List<NoteTextStyleRange> styles) {
    _attributes = _expandStyles(text.length, styles);
    _typingAttributesOffset = null;
    typingAttributes = _attributes.isEmpty
        ? NoteTextAttributes.defaults
        : _attributes.last;
    super.value = withBoundary(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ),
    );
  }

  @override
  set value(TextEditingValue newValue) {
    final normalized = withBoundary(newValue);
    final oldText = visibleText(super.text);
    final newText = visibleText(normalized.text);
    if (oldText != newText) _reconcileStyles(oldText, newText);
    final selection = visibleSelection(normalized.selection);
    if (!selection.isValid ||
        !selection.isCollapsed ||
        selection.extentOffset != _typingAttributesOffset) {
      _typingAttributesOffset = null;
    }
    super.value = normalized;
  }

  void setTypingAttributesForSelection(
    TextSelection selection,
    NoteTextAttributes attributes,
  ) {
    typingAttributes = attributes;
    _typingAttributesOffset = selection.isValid && selection.isCollapsed
        ? selection.extentOffset
        : null;
  }

  void _reconcileStyles(String oldText, String newText) {
    if (_attributes.length != oldText.length) {
      _attributes = List<NoteTextAttributes>.filled(
        oldText.length,
        NoteTextAttributes.defaults,
        growable: true,
      );
    }
    var prefix = 0;
    while (prefix < oldText.length &&
        prefix < newText.length &&
        oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < oldText.length - prefix &&
        suffix < newText.length - prefix &&
        oldText.codeUnitAt(oldText.length - suffix - 1) ==
            newText.codeUnitAt(newText.length - suffix - 1)) {
      suffix++;
    }
    final oldEnd = oldText.length - suffix;
    final insertedLength = newText.length - prefix - suffix;
    _attributes.replaceRange(
      prefix,
      oldEnd,
      List<NoteTextAttributes>.filled(insertedLength, typingAttributes),
    );
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    final children = <InlineSpan>[TextSpan(text: boundary, style: base)];
    final text = visibleTextValue;
    if (text.isEmpty) return TextSpan(style: base, children: children);
    bool isComposing(int rawOffset) =>
        withComposing &&
        value.composing.isValid &&
        rawOffset >= value.composing.start &&
        rawOffset < value.composing.end;
    var start = 0;
    while (start < text.length) {
      final attributes = start < _attributes.length
          ? _attributes[start]
          : NoteTextAttributes.defaults;
      final rawIndex = start + boundary.length;
      final composing = isComposing(rawIndex);
      final manuallyUnderlined =
          attributes.underline && !_underlineGap.hasMatch(text[start]);
      var end = start + 1;
      while (end < text.length) {
        final next = end < _attributes.length
            ? _attributes[end]
            : NoteTextAttributes.defaults;
        final nextComposing = isComposing(end + boundary.length);
        final nextManuallyUnderlined =
            next.underline && !_underlineGap.hasMatch(text[end]);
        if (next != attributes ||
            nextComposing != composing ||
            nextManuallyUnderlined != manuallyUnderlined) {
          break;
        }
        end++;
      }
      final decorations = <TextDecoration>[
        if (base.decoration != null) base.decoration!,
        if (manuallyUnderlined || composing) TextDecoration.underline,
        if (attributes.strikethrough) TextDecoration.lineThrough,
      ];
      children.add(
        TextSpan(
          text: text.substring(start, end),
          style: base.copyWith(
            fontWeight: attributes.bold ? FontWeight.w700 : base.fontWeight,
            fontStyle: attributes.italic ? FontStyle.italic : base.fontStyle,
            fontFamily: attributes.inlineCode ? 'monospace' : base.fontFamily,
            backgroundColor: attributes.inlineCode
                ? AppColors.softBlue
                : base.backgroundColor,
            color: attributes.link != null ? AppColors.coral : base.color,
            fontSize: attributes.fontSize == NoteTextAttributes.defaultFontSize
                ? base.fontSize
                : attributes.fontSize,
            decoration: decorations.isEmpty
                ? null
                : TextDecoration.combine(decorations),
          ),
        ),
      );
      start = end;
    }
    return TextSpan(style: base, children: children);
  }
}

class _EditableBlock {
  NoteBlockType type;
  bool checked;
  int indent;
  int quoteDepth;
  int headingLevel;
  String? codeLanguage;
  final String? attachmentPath;
  final _BlockTextEditingController controller;
  final FocusNode focusNode;

  _EditableBlock({
    required this.type,
    required this.checked,
    required this.indent,
    required this.quoteDepth,
    required this.headingLevel,
    this.codeLanguage,
    this.attachmentPath,
    required this.controller,
    required this.focusNode,
  });

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}

class _BlockInputFormatter extends TextInputFormatter {
  final ValueChanged<TextSelection> onNewline;
  final void Function(String source, TextSelection replacedSelection)
  onMultilinePaste;
  final VoidCallback onBackspaceAtStart;
  final bool allowNewlines;

  const _BlockInputFormatter({
    required this.onNewline,
    required this.onMultilinePaste,
    required this.onBackspaceAtStart,
    this.allowNewlines = false,
  });

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final removedBoundary =
        oldValue.text.startsWith(_BlockTextEditingController.boundary) &&
        oldValue.selection.isCollapsed &&
        oldValue.selection.start ==
            _BlockTextEditingController.boundary.length &&
        newValue.text == oldValue.text.substring(1);
    if (removedBoundary) {
      scheduleMicrotask(onBackspaceAtStart);
      return oldValue;
    }

    final normalized = _BlockTextEditingController.withBoundary(newValue);
    final oldText = _BlockTextEditingController.visibleText(oldValue.text);
    final newText = _BlockTextEditingController.visibleText(normalized.text);
    if (allowNewlines) return normalized;
    final replacement = _replacementBetween(oldText, newText);
    final inserted = replacement.inserted
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    if (!inserted.contains('\n')) return normalized;
    final selection = TextSelection(
      baseOffset: replacement.start,
      extentOffset: replacement.oldEnd,
    );
    if (inserted == '\n') {
      scheduleMicrotask(() => onNewline(selection));
    } else {
      scheduleMicrotask(() => onMultilinePaste(inserted, selection));
    }
    return oldValue;
  }

  static ({int start, int oldEnd, String inserted}) _replacementBetween(
    String oldText,
    String newText,
  ) {
    var start = 0;
    while (start < oldText.length &&
        start < newText.length &&
        oldText.codeUnitAt(start) == newText.codeUnitAt(start)) {
      start++;
    }
    var oldEnd = oldText.length;
    var newEnd = newText.length;
    while (oldEnd > start &&
        newEnd > start &&
        oldText.codeUnitAt(oldEnd - 1) == newText.codeUnitAt(newEnd - 1)) {
      oldEnd--;
      newEnd--;
    }
    return (
      start: start,
      oldEnd: oldEnd,
      inserted: newText.substring(start, newEnd),
    );
  }
}
