import 'package:flutter_quill/quill_delta.dart';
import 'package:markdown/markdown.dart' as md;

import '../models/note_document.dart';

/// Converts Markdown boundary content into native Quill semantics.
///
/// Notes remain Delta documents. Markdown is accepted only at explicit
/// boundaries such as clipboard paste and local-model output.
final class NoteMarkdownCodec {
  static final _fencedCodeMarker = RegExp(r'^[ \t]{0,3}(`{3,}|~{3,})');
  static final _listTaskMarker = RegExp(
    r'^([ \t]*)(?:[-+*]|\d+[.)])[ \t]+\[[ \t]*([xX]?)[ \t]*\][ \t]*(.*)$',
  );
  static final _bareTaskMarker = RegExp(
    r'^( {0,3})\[[ \t]*([xX]?)[ \t]*\][ \t]*(.*)$',
  );
  static final _listSymbolTaskMarker = RegExp(
    r'^([ \t]*)(?:[-+*]|\d+[.)])[ \t]+(☐|☑|☒|✅|✔)[ \t]*(.*)$',
  );
  static final _bareSymbolTaskMarker = RegExp(
    r'^( {0,3})(☐|☑|☒|✅|✔)[ \t]*(.*)$',
  );

  static const _richTags = <String>{
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'ul',
    'ol',
    'blockquote',
    'pre',
    'hr',
    'table',
    'strong',
    'b',
    'em',
    'i',
    'del',
    'code',
    'a',
    'img',
  };

  /// Decodes Markdown regardless of whether it contains visible formatting.
  static Delta decode(String source) {
    final normalized = _normalize(source);
    if (normalized.trim().isEmpty) return Delta()..insert('\n');
    try {
      return _decodeNodes(_parse(normalized), fallback: normalized);
    } catch (_) {
      return _plainTextDelta(normalized);
    }
  }

  /// Decodes only content that has semantic Markdown formatting.
  ///
  /// Returning `null` lets Flutter Quill keep its native plain-text, HTML, and
  /// internal Delta paste paths for ordinary clipboard content.
  static Delta? decodeIfRich(String source) {
    final normalized = _normalize(source);
    if (normalized.trim().isEmpty) return null;
    try {
      final nodes = _parse(normalized);
      if (!nodes.any(_containsRichSyntax)) return null;
      return _decodeNodes(nodes, fallback: normalized);
    } catch (_) {
      return null;
    }
  }

  static String _normalize(String source) {
    final normalized = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final trimmed = normalized
        .replaceFirst(RegExp(r'^(?:[ \t]*\n)+'), '')
        .replaceFirst(RegExp(r'(?:\n[ \t]*)+$'), '');
    return _normalizeTaskMarkers(trimmed);
  }

  /// Accepts the task markers produced by FKNotes' assistant and common
  /// Markdown variants, then feeds one canonical form into the parser.
  ///
  /// Fenced code is deliberately left untouched: examples such as
  /// `☐ example` inside a code block are content, not editor formatting.
  static String _normalizeTaskMarkers(String source) {
    String? openFence;
    final lines = source.split('\n');
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final fence = _fencedCodeMarker.firstMatch(line)?.group(1);
      if (fence != null) {
        if (openFence == null) {
          openFence = fence;
        } else if (fence.codeUnitAt(0) == openFence.codeUnitAt(0) &&
            fence.length >= openFence.length) {
          openFence = null;
        }
        continue;
      }
      if (openFence != null) continue;

      final listTask = _listTaskMarker.firstMatch(line);
      if (listTask != null) {
        lines[index] = _canonicalTaskLine(
          indent: listTask.group(1)!,
          checked: listTask.group(2)!.isNotEmpty,
          content: listTask.group(3)!,
        );
        continue;
      }
      final bareTask = _bareTaskMarker.firstMatch(line);
      if (bareTask != null) {
        lines[index] = _canonicalTaskLine(
          indent: bareTask.group(1)!,
          checked: bareTask.group(2)!.isNotEmpty,
          content: bareTask.group(3)!,
        );
        continue;
      }
      final symbolTask =
          _listSymbolTaskMarker.firstMatch(line) ??
          _bareSymbolTaskMarker.firstMatch(line);
      if (symbolTask != null) {
        lines[index] = _canonicalTaskLine(
          indent: symbolTask.group(1)!,
          checked: symbolTask.group(2) != '☐',
          content: symbolTask.group(3)!,
        );
      }
    }
    return lines.join('\n');
  }

  static String _canonicalTaskLine({
    required String indent,
    required bool checked,
    required String content,
  }) {
    final marker = checked ? 'x' : ' ';
    final text = content.trimLeft();
    return '$indent- [$marker]${text.isEmpty ? ' ' : ' $text'}';
  }

  static List<md.Node> _parse(String source) => md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  ).parse(source);

  static bool _containsRichSyntax(md.Node node) {
    if (node is! md.Element) return false;
    if (_richTags.contains(node.tag)) return true;
    return (node.children ?? const <md.Node>[]).any(_containsRichSyntax);
  }

  static Delta _decodeNodes(List<md.Node> nodes, {required String fallback}) {
    final output = _DeltaBlockWriter();
    for (final node in nodes) {
      _appendNode(output, node);
    }
    return output.finish(fallback: fallback);
  }

  static void _appendNode(
    _DeltaBlockWriter output,
    md.Node node, {
    int indent = 0,
    int quoteDepth = 0,
  }) {
    if (node is md.Text) {
      if (node.text.trim().isNotEmpty) {
        output.addInlineBlock([_InlineRun(node.text)]);
      }
      return;
    }
    if (node is! md.Element) return;
    final tag = node.tag;
    final heading = RegExp(r'^h([1-6])$').firstMatch(tag);
    if (heading != null) {
      output.addInlineBlock(
        _inlineRuns(node.children),
        blockAttributes: {'header': int.parse(heading.group(1)!)},
      );
      return;
    }
    switch (tag) {
      case 'p':
        output.addInlineBlock(
          _inlineRuns(node.children),
          blockAttributes: quoteDepth > 0
              ? {
                  'blockquote': true,
                  if (quoteDepth > 1) 'indent': (quoteDepth - 1).clamp(0, 3),
                }
              : null,
        );
      case 'ul':
      case 'ol':
        _appendList(
          output,
          node,
          ordered: tag == 'ol',
          indent: indent,
          quoteDepth: quoteDepth,
        );
      case 'blockquote':
        for (final child in node.children ?? const <md.Node>[]) {
          _appendNode(
            output,
            child,
            indent: indent,
            quoteDepth: (quoteDepth + 1).clamp(1, 4),
          );
        }
      case 'pre':
        final code = (node.children ?? const <md.Node>[])
            .whereType<md.Element>()
            .firstWhere(
              (child) => child.tag == 'code',
              orElse: () => md.Element.text('code', node.textContent),
            );
        output.addCodeBlock(code.textContent.replaceFirst(RegExp(r'\n$'), ''));
      case 'hr':
        output.addEmbed(const NoteEmbed.divider());
      case 'table':
        output.addEmbed(NoteEmbed.table(_table(node)));
      default:
        final inline = _inlineRuns(node.children);
        if (inline.any((run) => run.text.trim().isNotEmpty)) {
          output.addInlineBlock(inline);
        }
    }
  }

  static void _appendList(
    _DeltaBlockWriter output,
    md.Element list, {
    required bool ordered,
    required int indent,
    required int quoteDepth,
  }) {
    for (final item
        in (list.children ?? const <md.Node>[]).whereType<md.Element>()) {
      if (item.tag != 'li') continue;
      final checkbox = _findFirstElement(item, 'input');
      final isTask =
          checkbox != null ||
          item.attributes['class']
                  ?.split(RegExp(r'\s+'))
                  .contains('task-list-item') ==
              true;
      final isChecked =
          checkbox?.attributes.containsKey('checked') == true &&
          checkbox?.attributes['checked'] != 'false';
      final attributes = <String, dynamic>{
        'list': !isTask
            ? ordered
                  ? 'ordered'
                  : 'bullet'
            : isChecked
            ? 'checked'
            : 'unchecked',
        if (indent > 0) 'indent': indent.clamp(0, 8),
      };
      output.addInlineBlock(
        _listItemRuns(item.children),
        blockAttributes: attributes,
      );
      for (final child
          in (item.children ?? const <md.Node>[]).whereType<md.Element>()) {
        if (child.tag == 'ul' || child.tag == 'ol') {
          _appendList(
            output,
            child,
            ordered: child.tag == 'ol',
            indent: indent + 1,
            quoteDepth: quoteDepth,
          );
        }
      }
    }
  }

  static List<_InlineRun> _inlineRuns(
    List<md.Node>? nodes, {
    bool skipBlockLists = false,
  }) {
    final output = <_InlineRun>[];
    void write(String value, Map<String, dynamic> attributes) {
      if (value.isEmpty) return;
      output.add(
        _InlineRun(value, attributes.isEmpty ? null : Map.of(attributes)),
      );
    }

    void visit(md.Node node, Map<String, dynamic> attributes) {
      if (node is md.Text) {
        write(node.text, attributes);
        return;
      }
      if (node is! md.Element || node.tag == 'input') return;
      if (skipBlockLists && (node.tag == 'ul' || node.tag == 'ol')) return;
      if (node.tag == 'br') {
        write('\n', attributes);
        return;
      }
      final next = Map<String, dynamic>.of(attributes);
      switch (node.tag) {
        case 'strong' || 'b':
          next['bold'] = true;
        case 'em' || 'i':
          next['italic'] = true;
        case 'del':
          next['strike'] = true;
        case 'code':
          next['code'] = true;
        case 'a':
          final href = node.attributes['href']?.trim();
          if (href != null && href.isNotEmpty) next['link'] = href;
        case 'img':
          final alt = node.attributes['alt']?.trim();
          write(alt?.isNotEmpty == true ? alt! : node.textContent, attributes);
          return;
      }
      for (final child in node.children ?? const <md.Node>[]) {
        visit(child, next);
      }
    }

    for (final node in nodes ?? const <md.Node>[]) {
      visit(node, const <String, dynamic>{});
    }
    return output;
  }

  static List<_InlineRun> _listItemRuns(List<md.Node>? nodes) {
    final output = <_InlineRun>[];
    for (final node in nodes ?? const <md.Node>[]) {
      if (node is md.Element && (node.tag == 'ul' || node.tag == 'ol')) {
        continue;
      }
      final runs = _inlineRuns([node], skipBlockLists: true);
      if (runs.isEmpty) continue;
      final startsNewBlock =
          node is md.Element &&
          const {'p', 'pre', 'blockquote', 'table'}.contains(node.tag);
      if (startsNewBlock &&
          output.isNotEmpty &&
          !output.last.text.endsWith('\n')) {
        output.add(const _InlineRun('\n'));
      }
      output.addAll(runs);
    }
    return output;
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

  static NoteTable _table(md.Element table) {
    final rows = <List<String>>[];
    final alignments = <NoteTableAlignment>[];
    void visit(md.Element element) {
      if (element.tag == 'tr') {
        final cells = (element.children ?? const <md.Node>[])
            .whereType<md.Element>()
            .where((child) => child.tag == 'th' || child.tag == 'td')
            .toList(growable: false);
        if (cells.isNotEmpty) {
          rows.add(
            cells
                .map((cell) => cell.textContent.trim())
                .toList(growable: false),
          );
          if (alignments.isEmpty) {
            alignments.addAll(cells.map(_tableAlignment));
          }
        }
        return;
      }
      for (final child
          in (element.children ?? const <md.Node>[]).whereType<md.Element>()) {
        visit(child);
      }
    }

    visit(table);
    return NoteTable(rows: rows, alignments: alignments);
  }

  static NoteTableAlignment _tableAlignment(md.Element cell) {
    final value = [
      cell.attributes['align'],
      cell.attributes['style'],
    ].whereType<String>().join(' ').toLowerCase();
    if (value.contains('center')) return NoteTableAlignment.center;
    if (value.contains('right') || value.contains('end')) {
      return NoteTableAlignment.end;
    }
    return NoteTableAlignment.start;
  }

  static Delta _plainTextDelta(String source) {
    final delta = Delta()..insert(source);
    if (!source.endsWith('\n')) delta.insert('\n');
    return delta;
  }
}

final class _InlineRun {
  const _InlineRun(this.text, [this.attributes]);

  final String text;
  final Map<String, dynamic>? attributes;
}

final class _DeltaBlockWriter {
  final Delta _delta = Delta();

  void addInlineBlock(
    List<_InlineRun> runs, {
    Map<String, dynamic>? blockAttributes,
  }) {
    var wroteNewline = false;
    for (final run in runs) {
      final pieces = run.text.split('\n');
      for (var index = 0; index < pieces.length; index++) {
        final piece = pieces[index];
        if (piece.isNotEmpty) _delta.insert(piece, run.attributes);
        if (index < pieces.length - 1) {
          _delta.insert('\n', blockAttributes);
          wroteNewline = true;
        }
      }
    }
    if (!wroteNewline ||
        _delta.isEmpty ||
        _delta.operations.last.data != '\n') {
      _delta.insert('\n', blockAttributes);
    }
  }

  void addCodeBlock(String code) {
    final lines = code.split('\n');
    for (final line in lines) {
      if (line.isNotEmpty) _delta.insert(line);
      _delta.insert('\n', {'code-block': true});
    }
  }

  void addEmbed(NoteEmbed embed) {
    _delta
      ..insert(embed.toDeltaData())
      ..insert('\n');
  }

  Delta finish({required String fallback}) =>
      _delta.isEmpty ? NoteMarkdownCodec._plainTextDelta(fallback) : _delta;
}
