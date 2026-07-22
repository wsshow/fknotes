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

  static String encode(List<NoteBlockData> blocks) =>
      _encodeBlocks(blocks, _encodeInline);

  static String _encodeBlocks(
    List<NoteBlockData> blocks,
    String Function(NoteBlockData block) encodeInline,
  ) {
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
      final text = encodeInline(block);
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
    final runs = <({String value, NoteTextAttributes attributes})>[];
    var start = 0;
    while (start < block.text.length) {
      final current = attributes[start];
      var end = start + 1;
      while (end < block.text.length &&
          _sameMarkdownAttributes(attributes[end], current)) {
        end++;
      }
      runs.add((value: block.text.substring(start, end), attributes: current));
      start = end;
    }
    final encoded = runs
        .map((run) => _encodeInlineRun(run.value, run.attributes))
        .join();
    if (!runs.any((run) => _hasEmphasis(run.attributes))) return encoded;
    if (_inlineEncodingMatches(block.text, attributes, encoded)) {
      return encoded;
    }

    // CommonMark emphasis delimiters can become ambiguous when a formatted
    // run ends with punctuation and plain text immediately follows (for
    // example `**qq，，，**aaa`). Numeric entities preserve the exact visible
    // characters while giving the delimiter an unambiguous punctuation
    // boundary in the Markdown source.
    return List.generate(runs.length, (index) {
      final run = runs[index];
      final touchesEmphasis =
          (index > 0 &&
              (_hasEmphasis(runs[index - 1].attributes) ||
                  _hasEmphasis(run.attributes))) ||
          (index + 1 < runs.length &&
              (_hasEmphasis(run.attributes) ||
                  _hasEmphasis(runs[index + 1].attributes)));
      final value = touchesEmphasis && !run.attributes.inlineCode
          ? _escapeBoundaryRunes(
              run.value,
              first: index > 0,
              last: index + 1 < runs.length,
            )
          : run.value;
      return _encodeInlineRun(value, run.attributes);
    }).join();
  }

  static bool _inlineEncodingMatches(
    String text,
    List<NoteTextAttributes> expected,
    String encoded,
  ) {
    try {
      final document = md.Document(
        extensionSet: md.ExtensionSet.gitHubFlavored,
        encodeHtml: false,
      );
      final parsed = _inlineData(document.parseInline(encoded));
      if (parsed.text != text) return false;
      final actual = List<NoteTextAttributes>.filled(
        text.length,
        NoteTextAttributes.defaults,
      );
      for (final range in parsed.styles) {
        final start = range.start.clamp(0, text.length);
        final end = range.end.clamp(start, text.length);
        for (var index = start; index < end; index++) {
          actual[index] = range.attributes;
        }
      }
      for (var index = 0; index < text.length; index++) {
        if (!_sameMarkdownAttributes(expected[index], actual[index])) {
          return false;
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool _sameMarkdownAttributes(
    NoteTextAttributes left,
    NoteTextAttributes right,
  ) =>
      left.bold == right.bold &&
      left.italic == right.italic &&
      left.strikethrough == right.strikethrough &&
      left.inlineCode == right.inlineCode &&
      left.image == right.image &&
      left.link == right.link;

  static bool _hasEmphasis(NoteTextAttributes attributes) =>
      attributes.bold || attributes.italic || attributes.strikethrough;

  static String _escapeBoundaryRunes(
    String value, {
    required bool first,
    required bool last,
  }) {
    final runes = value.runes.toList();
    if (runes.isEmpty) return value;
    final output = StringBuffer();
    for (var index = 0; index < runes.length; index++) {
      final boundary =
          (first && index == 0) || (last && index == runes.length - 1);
      output.write(
        boundary ? '&#${runes[index]};' : String.fromCharCode(runes[index]),
      );
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
    if (_encodeBlocks(cached, _encodeInlineLegacy) == markdown) return true;
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

  static String _encodeInlineLegacy(NoteBlockData block) {
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
  final Future<NoteAttachment?> Function(KeyboardInsertedContent content)?
  onInsertImageContent;

  const NoteBlockEditor({
    super.key,
    required this.controller,
    this.initialRichContent,
    this.onRichContentChanged,
    required this.hintText,
    this.minLines = 10,
    this.attachments = const [],
    this.onOpenAttachment,
    this.onInsertImageContent,
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
  int _dictationStart = 0;
  int _dictationLength = 0;
  int _activeIndex = 0;
  int _focusRequestGeneration = 0;
  bool _syncing = false;
  late final _BlockTextEditingController _unifiedParagraphController;
  late final List<_UnifiedTextBlockMetadata> _unifiedBlockMetadata;
  final FocusNode _unifiedParagraphFocusNode = FocusNode();
  String? _unifiedRangeCacheText;
  List<TextRange> _unifiedRangeCache = const [];

  static const _paragraphSeparator = '\n\n';

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
    _unifiedBlockMetadata = blocks
        .map(_UnifiedTextBlockMetadata.fromBlock)
        .toList();
    final unified = _flattenParagraphs(blocks);
    _unifiedParagraphController =
        _BlockTextEditingController(text: unified.text, styles: unified.styles)
          ..styleResolver = _unifiedTextStyleAt
          ..leadingSpanResolver = _unifiedLeadingSpan
          ..replacementSpanResolver = _unifiedReplacementSpanAt;
    _unifiedParagraphController.addListener(_handleUnifiedParagraphChange);
    _unifiedParagraphFocusNode.addListener(_handleUnifiedParagraphFocus);
    _lastRichDocument = NoteRichDocumentCodec.encode(_document);
    _currentSnapshot = _createSnapshot(_lastRichDocument);
  }

  ({String text, List<NoteTextStyleRange> styles}) _flattenParagraphs(
    List<NoteBlockData> blocks,
  ) {
    final text = StringBuffer();
    final styles = <NoteTextStyleRange>[];
    var offset = 0;
    for (var index = 0; index < blocks.length; index++) {
      if (index > 0) {
        text.write(_paragraphSeparator);
        offset += _paragraphSeparator.length;
      }
      final block = blocks[index];
      if (!_isUnifiedEmbedType(block.type)) {
        text.write(block.text);
        for (final range in block.styles) {
          styles.add(
            NoteTextStyleRange(
              range.start + offset,
              range.end + offset,
              range.attributes,
            ),
          );
        }
        offset += block.text.length;
      }
    }
    return (text: text.toString(), styles: styles);
  }

  static bool _isUnifiedEmbedType(NoteBlockType type) =>
      type == NoteBlockType.code ||
      type == NoteBlockType.rawMarkdown ||
      type == NoteBlockType.divider ||
      type == NoteBlockType.attachment;

  List<TextRange> get _unifiedParagraphRanges {
    final rawText = _unifiedParagraphController.text;
    if (identical(rawText, _unifiedRangeCacheText)) return _unifiedRangeCache;
    final text = _BlockTextEditingController.visibleText(rawText);
    final ranges = <TextRange>[];
    var start = 0;
    while (start <= text.length) {
      final separator = text.indexOf(_paragraphSeparator, start);
      if (separator < 0) {
        ranges.add(TextRange(start: start, end: text.length));
        break;
      }
      ranges.add(TextRange(start: start, end: separator));
      start = separator + _paragraphSeparator.length;
    }
    _unifiedRangeCacheText = rawText;
    _unifiedRangeCache = ranges;
    return ranges;
  }

  List<NoteBlockData> get _unifiedParagraphDocument {
    final text = _unifiedParagraphController.visibleTextValue;
    final ranges = _unifiedParagraphRanges;
    return [
      for (var index = 0; index < ranges.length; index++)
        _unifiedBlockMetadata[index].toBlock(
          text.substring(ranges[index].start, ranges[index].end),
          styles: _unifiedParagraphController.styleRangesFor(
            ranges[index].start,
            ranges[index].end,
            shift: -ranges[index].start,
          ),
        ),
    ];
  }

  TextStyle _unifiedTextStyleAt(int offset, TextStyle base) {
    final index = _unifiedParagraphIndexForOffset(offset);
    final metadata = _unifiedBlockMetadata[index];
    return switch (metadata.type) {
      NoteBlockType.heading => base.copyWith(
        fontSize: switch (metadata.headingLevel.clamp(1, 6)) {
          1 => 28,
          2 => 24,
          3 => 21,
          _ => 18,
        },
        height: 1.35,
        fontWeight: FontWeight.w800,
      ),
      NoteBlockType.quote => base.copyWith(
        color: AppColors.muted,
        fontStyle: FontStyle.italic,
        backgroundColor: AppColors.softCoral.withValues(alpha: .28),
      ),
      NoteBlockType.todo when metadata.checked => base.copyWith(
        color: AppColors.muted,
        decoration: TextDecoration.lineThrough,
        decorationColor: AppColors.muted,
      ),
      _ => base,
    };
  }

  InlineSpan _unifiedLeadingSpan(TextStyle base) =>
      _unifiedBlockLeadingSpan(0, base);

  InlineSpan? _unifiedReplacementSpanAt(int offset, TextStyle base) {
    final ranges = _unifiedParagraphRanges;
    final index = _unifiedParagraphIndexForOffset(offset);
    if (index > 0 && offset == ranges[index].start - 1) {
      return _unifiedBlockLeadingSpan(index, base);
    }
    return null;
  }

  InlineSpan _unifiedBlockLeadingSpan(int index, TextStyle base) {
    if (index < 0 || index >= _unifiedBlockMetadata.length) {
      return const WidgetSpan(child: SizedBox.shrink());
    }
    final metadata = _unifiedBlockMetadata[index];
    if (_isUnifiedEmbedType(metadata.type)) {
      final screenWidth = MediaQuery.sizeOf(context).width;
      return WidgetSpan(
        alignment: PlaceholderAlignment.top,
        child: SizedBox(
          width: (screenWidth - 48).clamp(180, 680).toDouble(),
          child: Container(
            margin: EdgeInsets.only(
              left: metadata.quoteDepth > 0
                  ? (metadata.quoteDepth - 1) * 10
                  : 0,
            ),
            padding: EdgeInsets.only(left: metadata.quoteDepth > 0 ? 10 : 0),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: metadata.quoteDepth > 0
                      ? AppColors.coral
                      : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: _buildUnifiedEmbed(index, metadata),
          ),
        ),
      );
    }
    final indent = metadata.indent * 18.0;
    final blockMarker = switch (metadata.type) {
      NoteBlockType.bullet => const Icon(
        Icons.circle,
        size: 6,
        color: AppColors.ink,
      ),
      NoteBlockType.ordered => Text(
        '${_unifiedOrderedNumber(index)}.',
        style: base.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.muted,
        ),
      ),
      NoteBlockType.todo => GestureDetector(
        key: ValueKey('unified-todo-$index'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _toggleUnifiedTodo(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(
            metadata.checked
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
            size: 21,
            color: metadata.checked ? AppColors.coral : AppColors.muted,
          ),
        ),
      ),
      NoteBlockType.quote => const SizedBox.shrink(),
      _ => const SizedBox.shrink(),
    };
    final blockMarkerWidth = switch (metadata.type) {
      NoteBlockType.bullet => 28.0,
      NoteBlockType.ordered => 34.0,
      NoteBlockType.todo => 34.0,
      _ => 0.0,
    };
    final quoteWidth = metadata.quoteDepth * 10.0;
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: SizedBox(
        width: indent + quoteWidth + blockMarkerWidth,
        height: 27,
        child: Padding(
          padding: EdgeInsets.only(left: indent),
          child: Row(
            children: [
              for (var depth = 0; depth < metadata.quoteDepth; depth++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Container(
                    key: ValueKey('unified-quote-marker-$index-$depth'),
                    width: 2,
                    height: 27,
                    color: AppColors.coral,
                  ),
                ),
              if (blockMarkerWidth > 0)
                SizedBox(
                  width: blockMarkerWidth,
                  child: Align(alignment: Alignment.center, child: blockMarker),
                ),
            ],
          ),
        ),
      ),
    );
  }

  int _unifiedOrderedNumber(int index) {
    final metadata = _unifiedBlockMetadata[index];
    var number = 1;
    for (var current = index - 1; current >= 0; current--) {
      final previous = _unifiedBlockMetadata[current];
      if (previous.type != NoteBlockType.ordered ||
          previous.indent != metadata.indent) {
        break;
      }
      number++;
    }
    return number;
  }

  Widget _buildUnifiedEmbed(int index, _UnifiedTextBlockMetadata metadata) =>
      switch (metadata.type) {
        NoteBlockType.code => _buildUnifiedCodeBlock(index, metadata),
        NoteBlockType.rawMarkdown => _buildUnifiedRawMarkdownBlock(
          index,
          metadata,
        ),
        NoteBlockType.divider => Semantics(
          label: context.l10n.divider,
          child: InkWell(
            key: ValueKey('unified-divider-$index'),
            onTap: () {
              _activeIndex = index;
              activeType.value = NoteBlockType.divider;
              _unifiedParagraphFocusNode.unfocus();
            },
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 17),
              child: Divider(color: AppColors.line, thickness: 1),
            ),
          ),
        ),
        NoteBlockType.attachment => _buildUnifiedAttachment(index, metadata),
        _ => const SizedBox.shrink(),
      };

  Widget _buildUnifiedCodeBlock(
    int index,
    _UnifiedTextBlockMetadata metadata,
  ) => Container(
    key: ValueKey('unified-code-$index'),
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
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  metadata.codeLanguage?.isNotEmpty == true
                      ? metadata.codeLanguage!
                      : context.l10n.codeBlock,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                key: ValueKey('unified-code-edit-$index'),
                tooltip: context.l10n.edit,
                onPressed: () => _editUnifiedCodeBlock(index),
                icon: const Icon(Icons.edit_outlined, size: 19),
              ),
              IconButton(
                tooltip: context.l10n.remove,
                onPressed: () => _removeUnifiedEmbed(index),
                icon: const Icon(Icons.delete_outline_rounded, size: 19),
              ),
            ],
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 180),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Text(
              metadata.payload,
              style: const TextStyle(
                color: AppColors.ink,
                fontFamily: 'monospace',
                fontSize: 14,
                height: 1.48,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildUnifiedRawMarkdownBlock(
    int index,
    _UnifiedTextBlockMetadata metadata,
  ) {
    final table = MarkdownTableData.tryParse(metadata.payload);
    if (table == null) {
      return Container(
        key: ValueKey('unified-markdown-$index'),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: AppColors.softBlue.withValues(alpha: .52),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: FkMarkdownView(data: metadata.payload, compact: true),
      );
    }
    return Container(
      key: ValueKey('unified-table-$index'),
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
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
            child: Row(
              children: [
                const Icon(
                  Icons.table_chart_outlined,
                  size: 18,
                  color: AppColors.coral,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.l10n.markdownTable,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  context.l10n.tableDimensions(
                    table.headers.length,
                    table.rows.length,
                  ),
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
                IconButton(
                  tooltip: context.l10n.deleteTable,
                  onPressed: () => _removeUnifiedEmbed(index),
                  icon: const Icon(Icons.delete_outline_rounded, size: 19),
                ),
                IconButton(
                  tooltip: context.l10n.editTable,
                  onPressed: () => _editUnifiedTable(index),
                  icon: const Icon(Icons.edit_outlined, size: 19),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: FkMarkdownView(data: table.encode(), compact: true),
          ),
        ],
      ),
    );
  }

  Widget _buildUnifiedAttachment(
    int index,
    _UnifiedTextBlockMetadata metadata,
  ) {
    NoteAttachment? attachment;
    for (final item in widget.attachments) {
      if (item.filePath == metadata.attachmentPath) {
        attachment = item;
        break;
      }
    }
    final resolved = attachment;
    if (resolved?.type == NoteType.image) {
      final file = File(
        FileStorageService.instance.absolutePath(resolved!.filePath),
      );
      return Padding(
        key: ValueKey('unified-image-$index'),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Stack(
          children: [
            Material(
              color: AppColors.softBlue,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => widget.onOpenAttachment?.call(resolved),
                child: SizedBox(
                  height: 240,
                  child: Image.file(
                    file,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: AppColors.muted,
                        size: 30,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 7,
              right: 7,
              child: Material(
                color: AppColors.surface.withValues(alpha: .88),
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: context.l10n.removeReference,
                  onPressed: () => _removeUnifiedEmbed(index),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: AppColors.ink,
                ),
              ),
            ),
          ],
        ),
      );
    }
    final color = resolved == null
        ? AppColors.muted
        : NoteCard.colorForType(resolved.type);
    final thumbnailPath = resolved?.thumbnailPath;
    final thumbnail = thumbnailPath == null
        ? null
        : File(FileStorageService.instance.absolutePath(thumbnailPath));
    return Padding(
      key: ValueKey('unified-attachment-$index'),
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
                  onPressed: () => _removeUnifiedEmbed(index),
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

  void _toggleUnifiedTodo(int index) {
    if (index < 0 ||
        index >= _unifiedBlockMetadata.length ||
        _unifiedBlockMetadata[index].type != NoteBlockType.todo) {
      return;
    }
    _beginDiscreteChange();
    HapticFeedback.selectionClick();
    _activeIndex = index;
    _unifiedBlockMetadata[index].checked =
        !_unifiedBlockMetadata[index].checked;
    _unifiedParagraphController.notifyStyleChanged();
    _refreshActiveFormat();
    _endDiscreteChange();
  }

  void _replaceUnifiedDocument(
    List<NoteBlockData> document, {
    required int activeIndex,
    required TextSelection selection,
    bool refocus = true,
  }) {
    final normalized = document.isEmpty
        ? const [NoteBlockData(NoteBlockType.paragraph, '')]
        : document;
    final unified = _flattenParagraphs(normalized);
    _syncing = true;
    _unifiedBlockMetadata
      ..clear()
      ..addAll(normalized.map(_UnifiedTextBlockMetadata.fromBlock));
    _unifiedParagraphController.replaceVisibleText(
      unified.text,
      unified.styles,
    );
    _activeIndex = activeIndex.clamp(0, normalized.length - 1);
    _syncing = false;
    final safeSelection = TextSelection(
      baseOffset: selection.baseOffset.clamp(0, unified.text.length),
      extentOffset: selection.extentOffset.clamp(0, unified.text.length),
    );
    _unifiedParagraphController.visibleSelectionValue = safeSelection;
    activeType.value = _unifiedBlockMetadata[_activeIndex].type;
    _syncDocument();
    _unifiedParagraphController.notifyStyleChanged();
    if (refocus && !_isUnifiedEmbedType(activeType.value)) {
      _refocusUnifiedParagraph(selection: safeSelection);
    } else {
      _unifiedParagraphFocusNode.unfocus();
      _refreshActiveFormat();
    }
  }

  int _unifiedBlockStartOffset(List<NoteBlockData> document, int index) {
    var offset = 0;
    for (var current = 0; current < index; current++) {
      if (!_isUnifiedEmbedType(document[current].type)) {
        offset += document[current].text.length;
      }
      offset += _paragraphSeparator.length;
    }
    return offset;
  }

  Future<void> _editUnifiedTable(int index) async {
    if (index < 0 || index >= _unifiedBlockMetadata.length) return;
    final table = MarkdownTableData.tryParse(
      _unifiedBlockMetadata[index].payload,
    );
    if (table == null) {
      AppFeedback.error(context, context.l10n.invalidMarkdownTable);
      return;
    }
    _unifiedParagraphFocusNode.unfocus();
    final result = await showModalBottomSheet<MarkdownTableData>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _MarkdownTableEditorSheet(initial: table),
    );
    if (result == null ||
        !mounted ||
        index >= _unifiedBlockMetadata.length ||
        _unifiedBlockMetadata[index].type != NoteBlockType.rawMarkdown) {
      return;
    }
    _beginDiscreteChange();
    final document = _unifiedParagraphDocument;
    document[index] = NoteBlockData(NoteBlockType.rawMarkdown, result.encode());
    final offset = _unifiedBlockStartOffset(document, index);
    _replaceUnifiedDocument(
      document,
      activeIndex: index,
      selection: TextSelection.collapsed(offset: offset),
      refocus: false,
    );
    _endDiscreteChange();
  }

  Future<void> _editUnifiedCodeBlock(int index) async {
    if (index < 0 ||
        index >= _unifiedBlockMetadata.length ||
        _unifiedBlockMetadata[index].type != NoteBlockType.code) {
      return;
    }
    var editedCode = _unifiedBlockMetadata[index].payload;
    _unifiedParagraphFocusNode.unfocus();
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 18,
          top: 12,
          right: 18,
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 18,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .62,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.codeBlock,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('code-block-save'),
                    onPressed: () => Navigator.pop(sheetContext, editedCode),
                    child: Text(context.l10n.save),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TextFormField(
                  key: const ValueKey('code-block-editor'),
                  initialValue: editedCode,
                  onChanged: (value) => editedCode = value,
                  contextMenuBuilder: buildAppEditableTextContextMenu,
                  autofocus: true,
                  expands: true,
                  minLines: null,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 15,
                    height: 1.5,
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.softBlue.withValues(alpha: .52),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.line),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == null ||
        !mounted ||
        index >= _unifiedBlockMetadata.length ||
        _unifiedBlockMetadata[index].type != NoteBlockType.code) {
      return;
    }
    _beginDiscreteChange();
    final document = _unifiedParagraphDocument;
    document[index] = NoteBlockData(
      NoteBlockType.code,
      result,
      codeLanguage: document[index].codeLanguage,
    );
    final offset = _unifiedBlockStartOffset(document, index);
    _replaceUnifiedDocument(
      document,
      activeIndex: index,
      selection: TextSelection.collapsed(offset: offset),
      refocus: false,
    );
    _endDiscreteChange();
  }

  void _removeUnifiedEmbed(int index) {
    if (index < 0 ||
        index >= _unifiedBlockMetadata.length ||
        !_isUnifiedEmbedType(_unifiedBlockMetadata[index].type)) {
      return;
    }
    _beginDiscreteChange();
    HapticFeedback.selectionClick();
    final document = _unifiedParagraphDocument..removeAt(index);
    if (document.isEmpty) {
      document.add(const NoteBlockData(NoteBlockType.paragraph, ''));
    }
    final target = index.clamp(0, document.length - 1);
    final offset = _unifiedBlockStartOffset(document, target);
    _replaceUnifiedDocument(
      document,
      activeIndex: target,
      selection: TextSelection.collapsed(offset: offset),
    );
    _endDiscreteChange();
  }

  int _unifiedParagraphIndexForOffset(int offset) {
    final ranges = _unifiedParagraphRanges;
    var lower = 0;
    var upper = ranges.length - 1;
    while (lower < upper) {
      final middle = lower + ((upper - lower) >> 1);
      if (offset <= ranges[middle].end) {
        upper = middle;
      } else {
        lower = middle + 1;
      }
    }
    return lower;
  }

  void _handleUnifiedParagraphChange() {
    if (_syncing) return;
    final selection = _unifiedParagraphController.visibleSelectionValue;
    if (selection.isValid) {
      _activeIndex = _unifiedParagraphIndexForOffset(selection.extentOffset);
    }
    _reconcileUnifiedBlockMetadata();
    activeType.value = _unifiedBlockMetadata[_activeIndex].type;
    _syncDocument(deferForLargeDocument: true);
  }

  void _reconcileUnifiedBlockMetadata() {
    final targetCount = _unifiedParagraphRanges.length;
    while (_unifiedBlockMetadata.length < targetCount) {
      final insertionIndex = _activeIndex.clamp(
        0,
        _unifiedBlockMetadata.length,
      );
      final sourceIndex = (insertionIndex - 1).clamp(
        0,
        _unifiedBlockMetadata.length - 1,
      );
      _unifiedBlockMetadata.insert(
        insertionIndex,
        _unifiedBlockMetadata[sourceIndex].metadataForSplit(),
      );
    }
    while (_unifiedBlockMetadata.length > targetCount) {
      final removalIndex = (_activeIndex + 1).clamp(
        0,
        _unifiedBlockMetadata.length - 1,
      );
      _unifiedBlockMetadata.removeAt(removalIndex);
    }
    _activeIndex = _activeIndex.clamp(0, targetCount - 1);
  }

  void _handleUnifiedParagraphFocus() {
    if (!_unifiedParagraphFocusNode.hasFocus || !mounted) return;
    activeType.value = _unifiedBlockMetadata[_activeIndex].type;
    _refreshActiveFormat();
  }

  bool _canRemoveUnifiedBlockFormattingAt(int offset) {
    if (_unifiedBlockMetadata.isEmpty) {
      return false;
    }
    final index = _unifiedParagraphIndexForOffset(offset);
    final range = _unifiedParagraphRanges[index];
    return offset == range.start &&
        _unifiedBlockMetadata[index].type != NoteBlockType.paragraph;
  }

  bool _hasUnifiedEmbedBefore(int offset) {
    if (_unifiedBlockMetadata.length < 2) {
      return false;
    }
    final index = _unifiedParagraphIndexForOffset(offset);
    return index > 0 &&
        offset == _unifiedParagraphRanges[index].start &&
        _isUnifiedEmbedType(_unifiedBlockMetadata[index - 1].type);
  }

  void _removeUnifiedEmbedBefore(int offset) {
    if (!_hasUnifiedEmbedBefore(offset)) return;
    final index = _unifiedParagraphIndexForOffset(offset);
    _removeUnifiedEmbed(index - 1);
  }

  void _removeUnifiedBlockFormattingAt(int offset) {
    if (!_canRemoveUnifiedBlockFormattingAt(offset)) return;
    final index = _unifiedParagraphIndexForOffset(offset);
    if (_isUnifiedEmbedType(_unifiedBlockMetadata[index].type)) {
      _removeUnifiedEmbed(index);
      return;
    }
    _beginDiscreteChange();
    HapticFeedback.selectionClick();
    _activeIndex = index;
    final metadata = _unifiedBlockMetadata[_activeIndex]
      ..type = NoteBlockType.paragraph
      ..checked = false
      ..headingLevel = 0
      ..quoteDepth = 0;
    activeType.value = metadata.type;
    _unifiedParagraphController.notifyStyleChanged();
    _refreshActiveFormat();
    _refocusUnifiedParagraph(
      selection: TextSelection.collapsed(offset: offset),
    );
    _endDiscreteChange();
  }

  bool _canExitEmptyUnifiedBlockAt(int offset) {
    if (_unifiedBlockMetadata.isEmpty) {
      return false;
    }
    final index = _unifiedParagraphIndexForOffset(offset);
    final range = _unifiedParagraphRanges[index];
    return !_isUnifiedEmbedType(_unifiedBlockMetadata[index].type) &&
        _unifiedBlockMetadata[index].type != NoteBlockType.paragraph &&
        _unifiedParagraphController.visibleTextValue
            .substring(range.start, range.end)
            .trim()
            .isEmpty;
  }

  void _exitEmptyUnifiedBlockAt(int offset) {
    if (!_canExitEmptyUnifiedBlockAt(offset)) return;
    _beginDiscreteChange();
    HapticFeedback.selectionClick();
    _activeIndex = _unifiedParagraphIndexForOffset(offset);
    final metadata = _unifiedBlockMetadata[_activeIndex]
      ..type = NoteBlockType.paragraph
      ..checked = false
      ..headingLevel = 0
      ..quoteDepth = 0;
    activeType.value = metadata.type;
    _unifiedParagraphController.notifyStyleChanged();
    _refreshActiveFormat();
    _refocusUnifiedParagraph(
      selection: TextSelection.collapsed(offset: offset),
    );
    _endDiscreteChange();
  }

  KeyEventResult _handleUnifiedKeyEvent(FocusNode node, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.backspace ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    final selection = _unifiedParagraphController.visibleSelectionValue;
    if (!selection.isValid || !selection.isCollapsed) {
      return KeyEventResult.ignored;
    }
    if (_hasUnifiedEmbedBefore(selection.extentOffset)) {
      _removeUnifiedEmbedBefore(selection.extentOffset);
      return KeyEventResult.handled;
    }
    if (!_canRemoveUnifiedBlockFormattingAt(selection.extentOffset)) {
      return KeyEventResult.ignored;
    }
    _removeUnifiedBlockFormattingAt(selection.extentOffset);
    return KeyEventResult.handled;
  }

  Widget _buildUnifiedParagraphContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
  ) => buildAppEditableTextContextMenu(
    context,
    editableTextState,
    onPaste: _pasteUnifiedParagraphsFromClipboard,
    onCopy: _copyUnifiedSelection,
    onCut: _cutUnifiedSelection,
  );

  Future<void> _pasteUnifiedParagraphsFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final value = data?.text;
    if (!mounted || value == null || value.isEmpty) return;
    pasteMarkdown(value);
  }

  Future<void> _insertKeyboardImage(KeyboardInsertedContent content) async {
    if (!content.mimeType.startsWith('image/')) return;
    final attachment = await widget.onInsertImageContent?.call(content);
    if (!mounted || attachment == null) return;
    insertAttachmentReference(attachment.filePath);
  }

  ({int start, int end, bool includesLeadingBoundary})
  get _unifiedClipboardSelection {
    final rawSelection = _unifiedParagraphController.selection;
    final textLength = _unifiedParagraphController.visibleTextValue.length;
    if (!rawSelection.isValid) {
      return (start: 0, end: 0, includesLeadingBoundary: false);
    }
    return (
      start: (rawSelection.start - editorBlockBoundary.length).clamp(
        0,
        textLength,
      ),
      end: (rawSelection.end - editorBlockBoundary.length).clamp(0, textLength),
      includesLeadingBoundary:
          rawSelection.start < editorBlockBoundary.length &&
          rawSelection.end >= editorBlockBoundary.length,
    );
  }

  bool _unifiedSelectionIncludesBlockMarker(
    int index,
    ({int start, int end, bool includesLeadingBoundary}) selection,
  ) {
    if (index == 0) return selection.includesLeadingBoundary;
    final markerOffset = _unifiedParagraphRanges[index].start - 1;
    return selection.start <= markerOffset && selection.end > markerOffset;
  }

  String _unifiedEmbedClipboardText(_UnifiedTextBlockMetadata metadata) =>
      switch (metadata.type) {
        NoteBlockType.code || NoteBlockType.rawMarkdown => metadata.payload,
        NoteBlockType.divider => '────────',
        NoteBlockType.attachment => _attachmentClipboardLabel(
          metadata.attachmentPath,
        ),
        _ => '',
      };

  String _attachmentClipboardLabel(String? path) {
    for (final attachment in widget.attachments) {
      if (attachment.filePath == path) return attachment.displayTitle;
    }
    return context.l10n.attachmentReference(path ?? '');
  }

  String _selectedUnifiedPlainText() {
    final selection = _unifiedClipboardSelection;
    if (selection.start == selection.end &&
        !selection.includesLeadingBoundary) {
      return '';
    }
    final text = _unifiedParagraphController.visibleTextValue;
    final ranges = _unifiedParagraphRanges;
    final pieces = <String>[];
    for (var index = 0; index < ranges.length; index++) {
      final metadata = _unifiedBlockMetadata[index];
      if (_isUnifiedEmbedType(metadata.type)) {
        if (_unifiedSelectionIncludesBlockMarker(index, selection)) {
          pieces.add(_unifiedEmbedClipboardText(metadata));
        }
        continue;
      }
      final start = selection.start.clamp(
        ranges[index].start,
        ranges[index].end,
      );
      final end = selection.end.clamp(ranges[index].start, ranges[index].end);
      if (start < end) pieces.add(text.substring(start, end));
    }
    return pieces.join(_paragraphSeparator);
  }

  Future<void> _copyUnifiedSelection() async {
    final selected = _selectedUnifiedPlainText();
    if (selected.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: selected));
  }

  Future<void> _cutUnifiedSelection() async {
    final selection = _unifiedClipboardSelection;
    final selected = _selectedUnifiedPlainText();
    if (selected.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: selected));
    if (!mounted) return;
    _deleteUnifiedRange(
      TextSelection(baseOffset: selection.start, extentOffset: selection.end),
      includesLeadingBoundary: selection.includesLeadingBoundary,
    );
  }

  bool _hasUnifiedStructuralSelection(TextSelection selection) {
    if (!selection.isValid || selection.isCollapsed) return false;
    return _unifiedParagraphIndexForOffset(selection.start) !=
        _unifiedParagraphIndexForOffset(selection.end);
  }

  void _deleteUnifiedRange(
    TextSelection selection, {
    bool includesLeadingBoundary = false,
  }) {
    final document = _unifiedParagraphDocument;
    if (includesLeadingBoundary &&
        selection.isCollapsed &&
        _isUnifiedEmbedType(document.first.type)) {
      _removeUnifiedEmbed(0);
      return;
    }
    final ranges = _unifiedParagraphRanges;
    final textLength = _unifiedParagraphController.visibleTextValue.length;
    final start = selection.start.clamp(0, textLength);
    final end = selection.end.clamp(start, textLength);
    final startIndex = _unifiedParagraphIndexForOffset(start);
    final endIndex = _unifiedParagraphIndexForOffset(end);
    if (startIndex == endIndex) {
      final block = document[startIndex];
      if (_isUnifiedEmbedType(block.type)) {
        _removeUnifiedEmbed(startIndex);
        return;
      }
      final range = ranges[startIndex];
      _replaceUnifiedBlockRangeWithBlocks(
        startIndex,
        TextSelection(
          baseOffset: start - range.start,
          extentOffset: end - range.start,
        ),
        const [NoteBlockData(NoteBlockType.paragraph, '')],
      );
      return;
    }

    final next = document.sublist(0, startIndex);
    final first = document[startIndex];
    final firstRange = ranges[startIndex];
    final prefixLength =
        start.clamp(firstRange.start, firstRange.end) - firstRange.start;
    final prefix = _isUnifiedEmbedType(first.type)
        ? ''
        : first.text.substring(0, prefixLength);
    final prefixStyles = _isUnifiedEmbedType(first.type)
        ? const <NoteTextStyleRange>[]
        : _unifiedParagraphController.styleRangesFor(
            firstRange.start,
            firstRange.start + prefixLength,
            shift: -firstRange.start,
          );

    final last = document[endIndex];
    final lastRange = ranges[endIndex];
    final suffixStart =
        end.clamp(lastRange.start, lastRange.end) - lastRange.start;
    final suffix = _isUnifiedEmbedType(last.type)
        ? ''
        : last.text.substring(suffixStart);
    final suffixStyles = _isUnifiedEmbedType(last.type)
        ? const <NoteTextStyleRange>[]
        : _unifiedParagraphController.styleRangesFor(
            lastRange.start + suffixStart,
            lastRange.end,
            shift: -(lastRange.start + suffixStart) + prefix.length,
          );

    var mergedIndex = -1;
    if (prefix.isNotEmpty || suffix.isNotEmpty) {
      final base = prefix.isNotEmpty && !_isUnifiedEmbedType(first.type)
          ? first
          : !_isUnifiedEmbedType(last.type)
          ? last
          : const NoteBlockData(NoteBlockType.paragraph, '');
      mergedIndex = next.length;
      next.add(
        _copyTextBlock(base, '$prefix$suffix', [
          ...prefixStyles,
          ...suffixStyles,
        ]),
      );
    }
    next.addAll(document.skip(endIndex + 1));
    if (next.isEmpty) {
      next.add(const NoteBlockData(NoteBlockType.paragraph, ''));
    }
    _beginDiscreteChange();
    final target = (mergedIndex >= 0 ? mergedIndex : startIndex).clamp(
      0,
      next.length - 1,
    );
    final offset = _unifiedBlockStartOffset(next, target);
    _replaceUnifiedDocument(
      next,
      activeIndex: target,
      selection: TextSelection.collapsed(
        offset: offset + (mergedIndex >= 0 ? prefix.length : 0),
      ),
    );
    _endDiscreteChange();
  }

  List<NoteBlockData> get _document => _unifiedParagraphDocument;

  bool get _isLargeDocument =>
      _unifiedParagraphRanges.length >= 80 ||
      _unifiedParagraphController.visibleTextValue.length >= 20000;

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

  _EditorSnapshot _createSnapshot(String richDocument) => _EditorSnapshot(
    richDocument: richDocument,
    activeIndex: _activeIndex,
    selection: _unifiedParagraphController.visibleSelectionValue,
  );

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

  bool _ensureUnifiedTextInsertionTarget() {
    final controller = _unifiedParagraphController;
    final text = controller.visibleTextValue;
    final selection = controller.visibleSelectionValue;
    final caret = selection.isValid
        ? selection.extentOffset.clamp(0, text.length)
        : text.length;
    final index = _unifiedParagraphIndexForOffset(caret);
    if (!_isUnifiedEmbedType(_unifiedBlockMetadata[index].type)) return true;
    final document = _unifiedParagraphDocument;
    final target = index + 1;
    document.insert(target, const NoteBlockData(NoteBlockType.paragraph, ''));
    final offset = _unifiedBlockStartOffset(document, target);
    _replaceUnifiedDocument(
      document,
      activeIndex: target,
      selection: TextSelection.collapsed(offset: offset),
    );
    return true;
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
    _ensureUnifiedTextInsertionTarget();
    final text = _unifiedParagraphController.visibleTextValue;
    final selection = _unifiedParagraphController.visibleSelectionValue;
    final caret = selection.isValid
        ? selection.extentOffset.clamp(0, text.length)
        : text.length;
    _unifiedParagraphController.visibleSelectionValue = TextSelection.collapsed(
      offset: caret,
    );
    _activeIndex = _unifiedParagraphIndexForOffset(caret);
    activeType.value = _unifiedBlockMetadata[_activeIndex].type;
    return true;
  }

  /// Inserts finalized, non-empty dictation at the user's current caret.
  /// Manual edits and caret moves remain authoritative while listening.
  bool insertDictationTextAtCaret(String value) {
    if (value.trim().isEmpty) return true;
    if (!prepareDictationInsertion()) return false;
    final controller = _unifiedParagraphController;
    final composing = controller.value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      // Do not destroy an in-progress Chinese/Japanese/Korean IME composition.
      // The page retries the pending finalized segment after the manual edit
      // produces its next stable document update.
      return false;
    }
    final text = controller.visibleTextValue;
    final caret = controller.visibleSelectionValue.extentOffset.clamp(
      0,
      text.length,
    );
    controller.typingAttributes = controller.attributesForSelection(
      TextSelection.collapsed(offset: caret),
    );
    controller.value = TextEditingValue(
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
    final generated = _safeAssistantBlocks(text);
    if (generated.isEmpty) return false;
    _beginDiscreteChange();
    final document = _unifiedParagraphDocument
      ..add(NoteBlockData(NoteBlockType.heading, heading, headingLevel: 2))
      ..addAll(generated);
    final target = document.length - 1;
    final offset = _unifiedBlockStartOffset(document, target);
    _replaceUnifiedDocument(
      document,
      activeIndex: target,
      selection: TextSelection.collapsed(
        offset:
            offset +
            (_isUnifiedEmbedType(document[target].type)
                ? 0
                : document[target].text.length),
      ),
    );
    _endDiscreteChange();
    return true;
  }

  NoteAssistantEditorContext? captureAssistantContext() {
    final document = _unifiedParagraphDocument;
    final ranges = _unifiedParagraphRanges;
    final globalSelection =
        _unifiedParagraphController.visibleSelectionValue.isValid
        ? _unifiedParagraphController.visibleSelectionValue
        : TextSelection.collapsed(
            offset: _unifiedParagraphController.visibleTextValue.length,
          );
    final index = _unifiedParagraphIndexForOffset(globalSelection.extentOffset);
    final range = ranges[index];
    final selection = TextSelection(
      baseOffset:
          globalSelection.baseOffset.clamp(range.start, range.end) -
          range.start,
      extentOffset:
          globalSelection.extentOffset.clamp(range.start, range.end) -
          range.start,
    );
    final text = document[index].text;
    return NoteAssistantEditorContext(
      blockIndex: index,
      selection: selection,
      selectedText: text.substring(selection.start, selection.end),
      currentBlockContent: NoteBlockCodec.encode([document[index]]),
      expectedBlockText: text,
      expectedDocument: NoteRichDocumentCodec.encode(document),
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
    final document = _unifiedParagraphDocument;
    final generated = _safeAssistantBlocks(text);
    if (generated.isEmpty) return false;
    if (scope == NoteAssistantScope.fullNote) {
      if (placement != NoteAssistantPlacement.replace) return false;
      _beginDiscreteChange();
      final target = generated.length - 1;
      final offset = _unifiedBlockStartOffset(generated, target);
      _replaceUnifiedDocument(
        generated,
        activeIndex: target,
        selection: TextSelection.collapsed(
          offset:
              offset +
              (_isUnifiedEmbedType(generated[target].type)
                  ? 0
                  : generated[target].text.length),
        ),
      );
      _endDiscreteChange();
      return true;
    }
    if (anchor.blockIndex < 0 || anchor.blockIndex >= document.length) {
      return false;
    }
    final anchored = document[anchor.blockIndex];
    if (anchored.text != anchor.expectedBlockText) return false;
    if (placement == NoteAssistantPlacement.replace) {
      final selection = scope == NoteAssistantScope.selection
          ? anchor.selection
          : TextSelection(baseOffset: 0, extentOffset: anchored.text.length);
      _replaceUnifiedBlockRangeWithBlocks(
        anchor.blockIndex,
        selection,
        generated,
      );
      return true;
    }
    if (placement != NoteAssistantPlacement.insertBelow) return false;
    _beginDiscreteChange();
    document.insertAll(anchor.blockIndex + 1, generated);
    final target = anchor.blockIndex + generated.length;
    final offset = _unifiedBlockStartOffset(document, target);
    _replaceUnifiedDocument(
      document,
      activeIndex: target,
      selection: TextSelection.collapsed(
        offset:
            offset +
            (_isUnifiedEmbedType(document[target].type)
                ? 0
                : document[target].text.length),
      ),
    );
    _endDiscreteChange();
    return true;
  }

  void _replaceUnifiedBlockRangeWithBlocks(
    int index,
    TextSelection localSelection,
    List<NoteBlockData> replacement,
  ) {
    final document = _unifiedParagraphDocument;
    if (index < 0 || index >= document.length) return;
    final current = document[index];
    if (!_isUnifiedEmbedType(current.type) &&
        replacement.length == 1 &&
        replacement.single.type == NoteBlockType.paragraph) {
      final range = _unifiedParagraphRanges[index];
      final start = localSelection.start.clamp(0, current.text.length);
      final end = localSelection.end.clamp(start, current.text.length);
      final inline = replacement.single;
      final delta = inline.text.length - (end - start);
      final inherited = _unifiedParagraphController.attributesForSelection(
        TextSelection(
          baseOffset: range.start + start,
          extentOffset: range.start + end,
        ),
      );
      final inlineStyles =
          inline.styles.isEmpty &&
              inherited != NoteTextAttributes.defaults &&
              inline.text.isNotEmpty
          ? [NoteTextStyleRange(0, inline.text.length, inherited)]
          : inline.styles;
      final styles = [
        ..._unifiedParagraphController.styleRangesFor(
          range.start,
          range.start + start,
          shift: -range.start,
        ),
        for (final style in inlineStyles)
          NoteTextStyleRange(
            style.start + start,
            style.end + start,
            style.attributes,
          ),
        ..._unifiedParagraphController.styleRangesFor(
          range.start + end,
          range.end,
          shift: -range.start + delta,
        ),
      ];
      document[index] = _copyTextBlock(
        current,
        current.text.replaceRange(start, end, inline.text),
        styles,
      );
      _beginDiscreteChange();
      final offset = _unifiedBlockStartOffset(document, index);
      _replaceUnifiedDocument(
        document,
        activeIndex: index,
        selection: TextSelection.collapsed(
          offset: offset + start + inline.text.length,
        ),
      );
      _endDiscreteChange();
      return;
    }
    final inserted = <NoteBlockData>[];
    if (_isUnifiedEmbedType(current.type)) {
      inserted.addAll(replacement);
    } else {
      final start = localSelection.start.clamp(0, current.text.length);
      final end = localSelection.end.clamp(start, current.text.length);
      if (start > 0) {
        inserted.add(
          _copyTextBlock(
            current,
            current.text.substring(0, start),
            _unifiedParagraphController.styleRangesFor(
              _unifiedParagraphRanges[index].start,
              _unifiedParagraphRanges[index].start + start,
              shift: -_unifiedParagraphRanges[index].start,
            ),
          ),
        );
      }
      inserted.addAll(replacement);
      if (end < current.text.length) {
        final range = _unifiedParagraphRanges[index];
        inserted.add(
          NoteBlockData(
            NoteBlockType.paragraph,
            current.text.substring(end),
            styles: _unifiedParagraphController.styleRangesFor(
              range.start + end,
              range.end,
              shift: -(range.start + end),
            ),
          ),
        );
      }
    }
    if (inserted.isEmpty) {
      inserted.add(const NoteBlockData(NoteBlockType.paragraph, ''));
    }
    _beginDiscreteChange();
    document.replaceRange(index, index + 1, inserted);
    final replacementEnd =
        index +
        replacement.length +
        (inserted.length > replacement.length &&
                !_isUnifiedEmbedType(current.type) &&
                localSelection.start > 0
            ? 1
            : 0);
    final target = (replacementEnd - 1).clamp(index, document.length - 1);
    final targetOffset = _unifiedBlockStartOffset(document, target);
    _replaceUnifiedDocument(
      document,
      activeIndex: target,
      selection: TextSelection.collapsed(
        offset:
            targetOffset +
            (_isUnifiedEmbedType(document[target].type)
                ? 0
                : document[target].text.length),
      ),
    );
    _endDiscreteChange();
  }

  void _replaceUnifiedRangeWithBlocks(
    TextSelection selection,
    List<NoteBlockData> replacement,
  ) {
    final document = _unifiedParagraphDocument;
    final textLength = _unifiedParagraphController.visibleTextValue.length;
    final start = selection.start.clamp(0, textLength);
    final end = selection.end.clamp(start, textLength);
    final startIndex = _unifiedParagraphIndexForOffset(start);
    final endIndex = _unifiedParagraphIndexForOffset(end);
    if (startIndex == endIndex) {
      final range = _unifiedParagraphRanges[startIndex];
      _replaceUnifiedBlockRangeWithBlocks(
        startIndex,
        TextSelection(
          baseOffset: start - range.start,
          extentOffset: end - range.start,
        ),
        replacement,
      );
      return;
    }

    final inserted = <NoteBlockData>[];
    final first = document[startIndex];
    final firstRange = _unifiedParagraphRanges[startIndex];
    final firstCut =
        start.clamp(firstRange.start, firstRange.end) - firstRange.start;
    if (!_isUnifiedEmbedType(first.type) && firstCut > 0) {
      inserted.add(
        _copyTextBlock(
          first,
          first.text.substring(0, firstCut),
          _unifiedParagraphController.styleRangesFor(
            firstRange.start,
            firstRange.start + firstCut,
            shift: -firstRange.start,
          ),
        ),
      );
    }
    final replacementStart = inserted.length;
    inserted.addAll(replacement);

    final last = document[endIndex];
    final lastRange = _unifiedParagraphRanges[endIndex];
    final lastCut = end.clamp(lastRange.start, lastRange.end) - lastRange.start;
    var hasTrailingText = false;
    if (!_isUnifiedEmbedType(last.type) && lastCut < last.text.length) {
      inserted.add(
        NoteBlockData(
          NoteBlockType.paragraph,
          last.text.substring(lastCut),
          styles: _unifiedParagraphController.styleRangesFor(
            lastRange.start + lastCut,
            lastRange.end,
            shift: -(lastRange.start + lastCut),
          ),
        ),
      );
      hasTrailingText = true;
    }
    if (!hasTrailingText &&
        replacement.isNotEmpty &&
        _isUnifiedEmbedType(replacement.last.type) &&
        endIndex == document.length - 1) {
      inserted.add(const NoteBlockData(NoteBlockType.paragraph, ''));
      hasTrailingText = true;
    }
    if (inserted.isEmpty) {
      inserted.add(const NoteBlockData(NoteBlockType.paragraph, ''));
      hasTrailingText = true;
    }

    _beginDiscreteChange();
    document.replaceRange(startIndex, endIndex + 1, inserted);
    final target = hasTrailingText
        ? startIndex + inserted.length - 1
        : startIndex + replacementStart + replacement.length - 1;
    final targetOffset = _unifiedBlockStartOffset(document, target);
    _replaceUnifiedDocument(
      document,
      activeIndex: target,
      selection: TextSelection.collapsed(
        offset:
            targetOffset +
            (hasTrailingText || _isUnifiedEmbedType(document[target].type)
                ? 0
                : document[target].text.length),
      ),
    );
    _endDiscreteChange();
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

  /// Inserts clipboard or imported Markdown at the active caret.
  ///
  /// Inline Markdown stays in the current block. Block Markdown is parsed into
  /// semantic editor blocks in one undoable operation.
  bool pasteMarkdown(String source) =>
      _pasteMarkdownIntoUnifiedParagraphs(source);

  bool _pasteMarkdownIntoUnifiedParagraphs(
    String source, {
    TextSelection? replacedSelection,
  }) {
    if (source.isEmpty) return false;
    final parsed = _safeAssistantBlocks(source);
    final original = _unifiedParagraphController.visibleTextValue;
    final selection = replacedSelection?.isValid == true
        ? replacedSelection!
        : _unifiedParagraphController.visibleSelectionValue.isValid
        ? _unifiedParagraphController.visibleSelectionValue
        : TextSelection.collapsed(offset: original.length);
    _replaceUnifiedRangeWithBlocks(selection, parsed);
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
    final controller = _unifiedParagraphController;
    final text = controller.visibleTextValue;
    final caret = controller.visibleSelectionValue.extentOffset.clamp(
      0,
      text.length,
    );
    final start = caret - previous.length;
    if (start < 0 || text.substring(start, caret) != previous) return false;
    controller.value = TextEditingValue(
      text: text.replaceRange(start, caret, replacement),
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
    return true;
  }

  /// Anchors a live-dictation range at the current caret. Subsequent partial
  /// hypotheses replace only this range, so nearby note text never flickers or
  /// gets duplicated as the recognizer revises its result.
  bool beginDictation() {
    if (_dictating) return false;
    _closeHistoryGroup();
    _dictationSnapshot = _currentSnapshot;
    _dictating = true;
    _ensureUnifiedTextInsertionTarget();
    final controller = _unifiedParagraphController;
    final text = controller.visibleTextValue;
    final selection = controller.visibleSelectionValue;
    final start = selection.isValid
        ? selection.start.clamp(0, text.length)
        : text.length;
    final end = selection.isValid
        ? selection.end.clamp(start, text.length)
        : start;
    _dictationLength = 0;
    controller.typingAttributes = controller.attributesForSelection(
      TextSelection.collapsed(offset: start),
    );
    if (end > start) {
      if (_hasUnifiedStructuralSelection(selection)) {
        _deleteUnifiedRange(selection);
      } else {
        controller.value = TextEditingValue(
          text: text.replaceRange(start, end, ''),
          selection: TextSelection.collapsed(offset: start),
        );
      }
    }
    _dictationStart = controller.visibleSelectionValue.extentOffset.clamp(
      0,
      controller.visibleTextValue.length,
    );
    return true;
  }

  void updateDictation(String value) {
    if (!_dictating) return;
    final controller = _unifiedParagraphController;
    final text = controller.visibleTextValue;
    final start = _dictationStart.clamp(0, text.length);
    final end = (start + _dictationLength).clamp(start, text.length);
    controller.value = TextEditingValue(
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
    final unified = _flattenParagraphs(decoded);
    _restoringHistory = true;
    _syncing = true;
    _unifiedBlockMetadata
      ..clear()
      ..addAll(decoded.map(_UnifiedTextBlockMetadata.fromBlock));
    _unifiedParagraphController.replaceVisibleText(
      unified.text,
      unified.styles,
    );
    _unifiedParagraphController.visibleSelectionValue = snapshot.selection;
    _activeIndex = snapshot.activeIndex.clamp(0, decoded.length - 1);
    final plainText = NoteBlockCodec.encode(decoded);
    widget.controller.value = TextEditingValue(
      text: plainText,
      selection: TextSelection.collapsed(offset: plainText.length),
    );
    _lastRichDocument = snapshot.richDocument;
    _currentSnapshot = snapshot;
    _syncing = false;
    _restoringHistory = false;
    activeType.value = _unifiedBlockMetadata[_activeIndex].type;
    widget.onRichContentChanged?.call(snapshot.richDocument);
    _notifyHistoryChanged();
    _refreshActiveFormat();
    if (_isUnifiedEmbedType(activeType.value)) {
      _unifiedParagraphFocusNode.unfocus();
    } else {
      _refocusUnifiedParagraph(selection: snapshot.selection);
    }
  }

  void _refreshActiveFormat() {
    final metadata = _unifiedBlockMetadata[_activeIndex];
    if (_isUnifiedEmbedType(metadata.type)) {
      activeFormat.value = const NoteEditorFormatState();
      return;
    }
    final selection = _unifiedParagraphController.visibleSelectionValue;
    final attributes = _unifiedParagraphController.attributesForSelection(
      selection,
    );
    _unifiedParagraphController.typingAttributes = attributes;
    activeFormat.value = NoteEditorFormatState(
      bold: attributes.bold,
      italic: attributes.italic,
      strikethrough: attributes.strikethrough,
      inlineCode: attributes.inlineCode,
      underline: attributes.underline,
      fontSize: _unifiedParagraphController.uniformFontSize(selection),
      link: attributes.link,
      indent: metadata.indent,
      headingLevel: metadata.headingLevel,
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
    final link = value?.trim();
    _applyUnifiedParagraphAttributes(
      (attributes) =>
          attributes.copyWith(link: link?.isEmpty == true ? null : link),
    );
  }

  void _toggleAttribute(
    NoteTextAttributes Function(NoteTextAttributes, bool) update,
    bool Function(NoteTextAttributes) read,
  ) {
    final selection = _unifiedParagraphController.visibleSelectionValue;
    final current = selection.isCollapsed
        ? _unifiedParagraphController.typingAttributes
        : _unifiedParagraphController.attributesForSelection(selection);
    _applyUnifiedParagraphAttributes(
      (attributes) => update(attributes, !read(current)),
    );
  }

  void _applyUnifiedParagraphAttributes(
    NoteTextAttributes Function(NoteTextAttributes) update,
  ) {
    if (_isUnifiedEmbedType(_unifiedBlockMetadata[_activeIndex].type) &&
        _unifiedParagraphController.visibleSelectionValue.isCollapsed) {
      return;
    }
    _beginDiscreteChange();
    HapticFeedback.selectionClick();
    final controller = _unifiedParagraphController;
    final selection = controller.visibleSelectionValue;
    if (selection.isCollapsed) {
      controller.setTypingAttributesForSelection(
        selection,
        update(controller.typingAttributes),
      );
    } else {
      controller.applyAttributes(selection, update);
      _syncDocument();
    }
    _refreshActiveFormat();
    _refocusUnifiedParagraph(selection: selection);
    _endDiscreteChange();
  }

  void setFontSize(double fontSize) {
    _applyUnifiedParagraphAttributes(
      (attributes) => attributes.copyWith(fontSize: fontSize),
    );
  }

  void changeIndent(int delta) {
    final metadata = _unifiedBlockMetadata[_activeIndex];
    if (_isUnifiedEmbedType(metadata.type)) return;
    final next = (metadata.indent + delta).clamp(0, 3);
    if (next == metadata.indent) return;
    _beginDiscreteChange();
    HapticFeedback.selectionClick();
    metadata.indent = next;
    _unifiedParagraphController.notifyStyleChanged();
    _refreshActiveFormat();
    _refocusUnifiedParagraph(
      selection: _unifiedParagraphController.visibleSelectionValue,
    );
    _endDiscreteChange();
  }

  void toggleBlock(NoteBlockType type) {
    final supportedUnifiedType =
        type == NoteBlockType.paragraph ||
        type == NoteBlockType.quote ||
        type == NoteBlockType.bullet ||
        type == NoteBlockType.ordered ||
        type == NoteBlockType.todo ||
        type == NoteBlockType.code;
    final activeUnifiedType = _unifiedBlockMetadata[_activeIndex].type;
    if (_isUnifiedEmbedType(activeUnifiedType) &&
        activeUnifiedType != NoteBlockType.code) {
      return;
    }
    if (type == NoteBlockType.code || activeUnifiedType == NoteBlockType.code) {
      _beginDiscreteChange();
      HapticFeedback.selectionClick();
      final document = _unifiedParagraphDocument;
      final current = document[_activeIndex];
      final targetType = current.type == type ? NoteBlockType.paragraph : type;
      final text = current.text;
      document[_activeIndex] = NoteBlockData(
        targetType,
        text,
        indent: current.indent,
        quoteDepth: targetType == NoteBlockType.quote ? 1 : 0,
        codeLanguage: targetType == NoteBlockType.code
            ? current.codeLanguage
            : null,
        styles: targetType == NoteBlockType.code ? const [] : current.styles,
      );
      final offset = _unifiedBlockStartOffset(document, _activeIndex);
      _replaceUnifiedDocument(
        document,
        activeIndex: _activeIndex,
        selection: TextSelection.collapsed(
          offset: targetType == NoteBlockType.code
              ? offset
              : offset + text.length,
        ),
        refocus: targetType != NoteBlockType.code,
      );
      _endDiscreteChange();
      return;
    }
    if (supportedUnifiedType) {
      _beginDiscreteChange();
      HapticFeedback.selectionClick();
      final metadata = _unifiedBlockMetadata[_activeIndex];
      metadata.type = metadata.type == type ? NoteBlockType.paragraph : type;
      metadata.checked = false;
      metadata.headingLevel = 0;
      metadata.quoteDepth = metadata.type == NoteBlockType.quote ? 1 : 0;
      activeType.value = metadata.type;
      _unifiedParagraphController.notifyStyleChanged();
      _refreshActiveFormat();
      _refocusUnifiedParagraph(
        selection: _unifiedParagraphController.visibleSelectionValue,
      );
      _endDiscreteChange();
      return;
    }
  }

  void setHeadingLevel(int? level) {
    if (_isUnifiedEmbedType(_unifiedBlockMetadata[_activeIndex].type)) return;
    _beginDiscreteChange();
    HapticFeedback.selectionClick();
    final metadata = _unifiedBlockMetadata[_activeIndex];
    metadata.type = level == null
        ? NoteBlockType.paragraph
        : NoteBlockType.heading;
    metadata.checked = false;
    metadata.headingLevel = level?.clamp(1, 6) ?? 0;
    metadata.quoteDepth = 0;
    activeType.value = metadata.type;
    _unifiedParagraphController.notifyStyleChanged();
    _refreshActiveFormat();
    _refocusUnifiedParagraph(
      selection: _unifiedParagraphController.visibleSelectionValue,
    );
    _endDiscreteChange();
  }

  NoteBlockData _copyTextBlock(
    NoteBlockData source,
    String text,
    List<NoteTextStyleRange> styles,
  ) => NoteBlockData(
    source.type,
    text,
    checked: source.checked,
    indent: source.indent,
    quoteDepth: source.quoteDepth,
    headingLevel: source.headingLevel,
    codeLanguage: source.codeLanguage,
    styles: styles,
  );

  void _insertUnifiedEmbedAtSelection(NoteBlockData embed) {
    _beginDiscreteChange();
    HapticFeedback.selectionClick();
    final document = _unifiedParagraphDocument;
    final selection = _unifiedParagraphController.visibleSelectionValue;
    final index = _unifiedParagraphIndexForOffset(
      selection.isValid ? selection.extentOffset : 0,
    );
    if (_isUnifiedEmbedType(document[index].type)) {
      document
        ..insert(index + 1, embed)
        ..insert(index + 2, const NoteBlockData(NoteBlockType.paragraph, ''));
      final target = index + 2;
      final offset = _unifiedBlockStartOffset(document, target);
      _replaceUnifiedDocument(
        document,
        activeIndex: target,
        selection: TextSelection.collapsed(offset: offset),
      );
      _endDiscreteChange();
      return;
    }
    final range = _unifiedParagraphRanges[index];
    final localStart =
        (selection.isValid ? selection.start : range.end).clamp(
          range.start,
          range.end,
        ) -
        range.start;
    final localEnd =
        (selection.isValid ? selection.end : range.end).clamp(
          range.start,
          range.end,
        ) -
        range.start;
    final current = document[index];
    final before = _copyTextBlock(
      current,
      current.text.substring(0, localStart),
      _unifiedParagraphController.styleRangesFor(
        range.start,
        range.start + localStart,
        shift: -range.start,
      ),
    );
    final after = NoteBlockData(
      NoteBlockType.paragraph,
      current.text.substring(localEnd),
      indent: current.indent,
      styles: _unifiedParagraphController.styleRangesFor(
        range.start + localEnd,
        range.end,
        shift: -(range.start + localEnd),
      ),
    );
    document.replaceRange(index, index + 1, [before, embed, after]);
    final target = index + 2;
    final offset = _unifiedBlockStartOffset(document, target);
    _replaceUnifiedDocument(
      document,
      activeIndex: target,
      selection: TextSelection.collapsed(offset: offset),
    );
    _endDiscreteChange();
  }

  void insertDivider() {
    _insertUnifiedEmbedAtSelection(
      const NoteBlockData(NoteBlockType.divider, ''),
    );
  }

  void insertAttachmentReference(String filePath) {
    _insertUnifiedEmbedAtSelection(
      NoteBlockData(NoteBlockType.attachment, '', attachmentPath: filePath),
    );
  }

  void _refocusUnifiedParagraph({TextSelection? selection, int? offset}) {
    final requestGeneration = ++_focusRequestGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || requestGeneration != _focusRequestGeneration) {
        return;
      }
      _unifiedParagraphFocusNode.requestFocus();
      final targetSelection = selection?.isValid == true
          ? selection!
          : TextSelection.collapsed(
              offset:
                  offset ?? _unifiedParagraphController.visibleTextValue.length,
            );
      _unifiedParagraphController.visibleSelectionValue = targetSelection;
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void focusAtEnd() {
    final end = _unifiedParagraphController.visibleTextValue.length;
    _unifiedParagraphController.visibleSelectionValue = TextSelection.collapsed(
      offset: end,
    );
    if (!_unifiedParagraphFocusNode.hasFocus) {
      _unifiedParagraphFocusNode.requestFocus();
      return;
    }
    _unifiedParagraphFocusNode.unfocus();
    _refocusUnifiedParagraph(offset: end);
  }

  @override
  void dispose() {
    _historyGroupTimer?.cancel();
    _documentSyncTimer?.cancel();
    _unifiedParagraphController.removeListener(_handleUnifiedParagraphChange);
    _unifiedParagraphFocusNode.removeListener(_handleUnifiedParagraphFocus);
    _unifiedParagraphController.dispose();
    _unifiedParagraphFocusNode.dispose();
    activeType.dispose();
    activeFormat.dispose();
    historyState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _buildUnifiedParagraphEditor();

  Widget _buildUnifiedParagraphEditor() => ConstrainedBox(
    constraints: BoxConstraints(minHeight: widget.minLines * 27),
    child: Stack(
      children: [
        Focus(
          onKeyEvent: _handleUnifiedKeyEvent,
          child: TextField(
            key: const ValueKey('unified-note-editor'),
            controller: _unifiedParagraphController,
            focusNode: _unifiedParagraphFocusNode,
            contextMenuBuilder: _buildUnifiedParagraphContextMenu,
            contentInsertionConfiguration: widget.onInsertImageContent == null
                ? null
                : ContentInsertionConfiguration(
                    allowedMimeTypes: const [
                      'image/png',
                      'image/jpeg',
                      'image/gif',
                      'image/webp',
                    ],
                    onContentInserted: (content) {
                      unawaited(_insertKeyboardImage(content));
                    },
                  ),
            inputFormatters: [
              _ParagraphSeparatorFormatter(
                shouldRemoveBlockFormatting: _canRemoveUnifiedBlockFormattingAt,
                onRemoveBlockFormatting: _removeUnifiedBlockFormattingAt,
                hasEmbedBefore: _hasUnifiedEmbedBefore,
                onRemoveEmbedBefore: _removeUnifiedEmbedBefore,
                hasStructuralSelection: _hasUnifiedStructuralSelection,
                onDeleteStructuralSelection: _deleteUnifiedRange,
                shouldExitEmptyBlock: _canExitEmptyUnifiedBlockAt,
                onExitEmptyBlock: _exitEmptyUnifiedBlockAt,
                onMultilinePaste: (source, selection) =>
                    _pasteMarkdownIntoUnifiedParagraphs(
                      source,
                      replacedSelection: selection,
                    ),
              ),
            ],
            minLines: widget.minLines,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            textCapitalization: TextCapitalization.sentences,
            cursorColor: AppColors.coral,
            style: const TextStyle(
              fontSize: 17,
              height: 1.62,
              color: AppColors.ink,
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
        ),
        Positioned(
          left: 0,
          top: 7,
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _unifiedParagraphController,
            builder: (context, value, child) => IgnorePointer(
              child: _unifiedParagraphController.visibleTextValue.isEmpty
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
  );

  static String _formatSize(int bytes) => bytes < 1024
      ? '$bytes B'
      : bytes < 1048576
      ? '${(bytes / 1024).toStringAsFixed(1)} KB'
      : '${(bytes / 1048576).toStringAsFixed(1)} MB';
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
  TextStyle Function(int offset, TextStyle base)? styleResolver;
  InlineSpan Function(TextStyle base)? leadingSpanResolver;
  InlineSpan? Function(int offset, TextStyle base)? replacementSpanResolver;
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

  void notifyStyleChanged() => notifyListeners();

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
    final children = <InlineSpan>[
      leadingSpanResolver?.call(base) ?? TextSpan(text: boundary, style: base),
    ];
    final text = visibleTextValue;
    if (text.isEmpty) return TextSpan(style: base, children: children);
    bool isComposing(int rawOffset) =>
        withComposing &&
        value.composing.isValid &&
        rawOffset >= value.composing.start &&
        rawOffset < value.composing.end;
    var start = 0;
    while (start < text.length) {
      final replacement = replacementSpanResolver?.call(start, base);
      if (replacement != null) {
        children.add(replacement);
        start++;
        continue;
      }
      final runBase = styleResolver?.call(start, base) ?? base;
      final attributes = start < _attributes.length
          ? _attributes[start]
          : NoteTextAttributes.defaults;
      final rawIndex = start + boundary.length;
      final composing = isComposing(rawIndex);
      final manuallyUnderlined =
          attributes.underline && !_underlineGap.hasMatch(text[start]);
      var end = start + 1;
      while (end < text.length) {
        if (replacementSpanResolver?.call(end, base) != null) break;
        final nextBase = styleResolver?.call(end, base) ?? base;
        final next = end < _attributes.length
            ? _attributes[end]
            : NoteTextAttributes.defaults;
        final nextComposing = isComposing(end + boundary.length);
        final nextManuallyUnderlined =
            next.underline && !_underlineGap.hasMatch(text[end]);
        if (nextBase != runBase ||
            next != attributes ||
            nextComposing != composing ||
            nextManuallyUnderlined != manuallyUnderlined) {
          break;
        }
        end++;
      }
      final decorations = <TextDecoration>[
        if (runBase.decoration != null) runBase.decoration!,
        if (manuallyUnderlined || composing) TextDecoration.underline,
        if (attributes.strikethrough) TextDecoration.lineThrough,
      ];
      children.add(
        TextSpan(
          text: text.substring(start, end),
          style: runBase.copyWith(
            fontWeight: attributes.bold ? FontWeight.w700 : runBase.fontWeight,
            fontStyle: attributes.italic ? FontStyle.italic : runBase.fontStyle,
            fontFamily: attributes.inlineCode
                ? 'monospace'
                : runBase.fontFamily,
            backgroundColor: attributes.inlineCode
                ? AppColors.softBlue
                : runBase.backgroundColor,
            color: attributes.link != null ? AppColors.coral : runBase.color,
            fontSize: attributes.fontSize == NoteTextAttributes.defaultFontSize
                ? runBase.fontSize
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

class _UnifiedTextBlockMetadata {
  NoteBlockType type;
  bool checked;
  int indent;
  int headingLevel;
  int quoteDepth;
  String payload;
  String? attachmentPath;
  String? codeLanguage;

  _UnifiedTextBlockMetadata({
    required this.type,
    this.checked = false,
    this.indent = 0,
    this.headingLevel = 0,
    this.quoteDepth = 0,
    this.payload = '',
    this.attachmentPath,
    this.codeLanguage,
  });

  factory _UnifiedTextBlockMetadata.fromBlock(NoteBlockData block) =>
      _UnifiedTextBlockMetadata(
        type: block.type,
        checked: block.checked,
        indent: block.indent.clamp(0, 3),
        headingLevel: block.type == NoteBlockType.heading
            ? block.headingLevel.clamp(1, 6)
            : 0,
        quoteDepth: block.type == NoteBlockType.quote
            ? block.quoteDepth.clamp(1, 3)
            : 0,
        payload: NoteBlockEditorState._isUnifiedEmbedType(block.type)
            ? block.text
            : '',
        attachmentPath: block.attachmentPath,
        codeLanguage: block.codeLanguage,
      );

  _UnifiedTextBlockMetadata metadataForSplit() => switch (type) {
    NoteBlockType.quote => _UnifiedTextBlockMetadata(
      type: NoteBlockType.quote,
      indent: indent,
      quoteDepth: 1,
    ),
    NoteBlockType.bullet || NoteBlockType.ordered => _UnifiedTextBlockMetadata(
      type: type,
      indent: indent,
    ),
    NoteBlockType.todo => _UnifiedTextBlockMetadata(
      type: NoteBlockType.todo,
      indent: indent,
    ),
    _ => _UnifiedTextBlockMetadata(
      type: NoteBlockType.paragraph,
      indent: indent,
    ),
  };

  NoteBlockData toBlock(
    String text, {
    required List<NoteTextStyleRange> styles,
  }) => NoteBlockData(
    type,
    NoteBlockEditorState._isUnifiedEmbedType(type) ? payload : text,
    checked: type == NoteBlockType.todo && checked,
    attachmentPath: type == NoteBlockType.attachment ? attachmentPath : null,
    indent: indent.clamp(0, 3),
    headingLevel: type == NoteBlockType.heading ? headingLevel.clamp(1, 6) : 0,
    quoteDepth: type == NoteBlockType.quote ? quoteDepth.clamp(1, 3) : 0,
    codeLanguage: type == NoteBlockType.code ? codeLanguage : null,
    styles: NoteBlockEditorState._isUnifiedEmbedType(type) ? const [] : styles,
  );
}

class _ParagraphSeparatorFormatter extends TextInputFormatter {
  final bool Function(int offset) shouldRemoveBlockFormatting;
  final ValueChanged<int> onRemoveBlockFormatting;
  final bool Function(int offset) hasEmbedBefore;
  final ValueChanged<int> onRemoveEmbedBefore;
  final bool Function(TextSelection selection) hasStructuralSelection;
  final ValueChanged<TextSelection> onDeleteStructuralSelection;
  final bool Function(int offset) shouldExitEmptyBlock;
  final ValueChanged<int> onExitEmptyBlock;
  final void Function(String source, TextSelection replacedSelection)
  onMultilinePaste;

  const _ParagraphSeparatorFormatter({
    required this.shouldRemoveBlockFormatting,
    required this.onRemoveBlockFormatting,
    required this.hasEmbedBefore,
    required this.onRemoveEmbedBefore,
    required this.hasStructuralSelection,
    required this.onDeleteStructuralSelection,
    required this.shouldExitEmptyBlock,
    required this.onExitEmptyBlock,
    required this.onMultilinePaste,
  });

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (oldValue.text == newValue.text) return newValue;
    final oldSelection = _BlockTextEditingController.visibleSelection(
      oldValue.selection,
    );
    final removedBoundary =
        oldValue.text.startsWith(_BlockTextEditingController.boundary) &&
        oldSelection.isCollapsed &&
        oldSelection.extentOffset == 0 &&
        newValue.text == oldValue.text.substring(1);
    if (removedBoundary) {
      if (shouldRemoveBlockFormatting(0)) {
        scheduleMicrotask(() => onRemoveBlockFormatting(0));
      }
      return oldValue;
    }
    final normalizedValue = _BlockTextEditingController.withBoundary(newValue);
    final oldText = _BlockTextEditingController.visibleText(oldValue.text);
    final newText = _BlockTextEditingController.visibleText(
      normalizedValue.text,
    );
    final replacement = _replacementBetween(oldText, newText);
    final inserted = replacement.inserted
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    if (inserted.isEmpty &&
        oldSelection.isValid &&
        !oldSelection.isCollapsed &&
        hasStructuralSelection(oldSelection)) {
      scheduleMicrotask(() => onDeleteStructuralSelection(oldSelection));
      return oldValue;
    }
    if (inserted == '\n' &&
        oldSelection.isValid &&
        oldSelection.isCollapsed &&
        shouldExitEmptyBlock(oldSelection.extentOffset)) {
      scheduleMicrotask(() => onExitEmptyBlock(oldSelection.extentOffset));
      return oldValue;
    }
    final deletedBackwardAtBlockStart =
        inserted.isEmpty &&
        oldSelection.isValid &&
        oldSelection.isCollapsed &&
        replacement.oldEnd == oldSelection.extentOffset &&
        replacement.start + 1 == replacement.oldEnd;
    if (deletedBackwardAtBlockStart &&
        hasEmbedBefore(oldSelection.extentOffset)) {
      scheduleMicrotask(() => onRemoveEmbedBefore(oldSelection.extentOffset));
      return oldValue;
    }
    final removesBlockFormatting =
        deletedBackwardAtBlockStart &&
        shouldRemoveBlockFormatting(oldSelection.extentOffset);
    if (removesBlockFormatting) {
      scheduleMicrotask(
        () => onRemoveBlockFormatting(oldSelection.extentOffset),
      );
      return oldValue;
    }
    if (inserted.contains('\n') && inserted != '\n') {
      scheduleMicrotask(
        () => onMultilinePaste(
          inserted,
          TextSelection(
            baseOffset: replacement.start,
            extentOffset: replacement.oldEnd,
          ),
        ),
      );
      return oldValue;
    }
    final deleting = newText.length < oldText.length;

    String normalize(String value) {
      final output = StringBuffer();
      var index = 0;
      while (index < value.length) {
        if (value.codeUnitAt(index) != 10) {
          output.writeCharCode(value.codeUnitAt(index));
          index++;
          continue;
        }
        var end = index + 1;
        while (end < value.length && value.codeUnitAt(end) == 10) {
          end++;
        }
        final runLength = end - index;
        if (!deleting || runLength > 1) {
          output.write(NoteBlockEditorState._paragraphSeparator);
        }
        index = end;
      }
      return output.toString();
    }

    final normalizedText = normalize(normalizedValue.text.replaceAll('\r', ''));
    if (normalizedText == normalizedValue.text) return normalizedValue;

    int mapOffset(int offset) {
      if (offset < 0) return offset;
      final end = offset.clamp(0, normalizedValue.text.length);
      return normalize(normalizedValue.text.substring(0, end)).length;
    }

    return TextEditingValue(
      text: normalizedText,
      selection: normalizedValue.selection.isValid
          ? normalizedValue.selection.copyWith(
              baseOffset: mapOffset(normalizedValue.selection.baseOffset),
              extentOffset: mapOffset(normalizedValue.selection.extentOffset),
            )
          : normalizedValue.selection,
      composing: normalizedValue.composing.isValid
          ? TextRange(
              start: mapOffset(normalizedValue.composing.start),
              end: mapOffset(normalizedValue.composing.end),
            )
          : TextRange.empty,
    );
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
