import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:markdown/markdown.dart' as md;

enum NoteAssistantEditScope { selection, currentLine, document }

enum NoteAssistantEditPlacement { replace, insertBelow, append }

final class NoteAssistantAnchor {
  const NoteAssistantAnchor({
    required this.expectedDocument,
    required this.selection,
    required this.lineStart,
    required this.lineEnd,
    required this.selectedText,
    required this.currentLineText,
  });

  final String expectedDocument;
  final TextSelection selection;
  final int lineStart;
  final int lineEnd;
  final String selectedText;
  final String currentLineText;

  bool get hasSelection => selectedText.trim().isNotEmpty;
  bool get hasCurrentLine => currentLineText.trim().isNotEmpty;
}

/// Converts the Markdown boundary used by local models into native Quill
/// semantics. Markdown never becomes note storage or visible editor text.
final class NoteAssistantMarkdownCodec {
  static Delta decode(String source) {
    final normalized = source
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .trim();
    if (normalized.isEmpty) return Delta()..insert('\n');
    try {
      final output = _DeltaBlockWriter();
      final nodes = md.Document(
        extensionSet: md.ExtensionSet.gitHubFlavored,
        encodeHtml: false,
      ).parse(normalized);
      for (final node in nodes) {
        _appendNode(output, node);
      }
      return output.finish(fallback: normalized);
    } catch (_) {
      return _plainTextDelta(normalized);
    }
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
        // The AI boundary cannot mint domain embeds. A readable divider is a
        // safe semantic substitute and remains fully editable.
        output.addInlineBlock(const [_InlineRun('——')]);
      case 'table':
        output.addInlineBlock([_InlineRun(_tableText(node))]);
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
      final attributes = <String, dynamic>{
        'list': checkbox == null
            ? ordered
                  ? 'ordered'
                  : 'bullet'
            : checkbox.attributes['checked'] == 'true'
            ? 'checked'
            : 'unchecked',
        if (indent > 0) 'indent': indent.clamp(0, 8),
      };
      output.addInlineBlock(
        _inlineRuns(item.children, skipBlockLists: true),
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

  static md.Element? _findFirstElement(md.Element root, String tag) {
    for (final child in root.children ?? const <md.Node>[]) {
      if (child is! md.Element) continue;
      if (child.tag == tag) return child;
      final nested = _findFirstElement(child, tag);
      if (nested != null) return nested;
    }
    return null;
  }

  static String _tableText(md.Element table) {
    final rows = <String>[];
    void visit(md.Element element) {
      if (element.tag == 'tr') {
        final cells = (element.children ?? const <md.Node>[])
            .whereType<md.Element>()
            .where((child) => child.tag == 'th' || child.tag == 'td')
            .map((child) => child.textContent.trim())
            .toList(growable: false);
        if (cells.isNotEmpty) rows.add(cells.join('\t'));
        return;
      }
      for (final child
          in (element.children ?? const <md.Node>[]).whereType<md.Element>()) {
        visit(child);
      }
    }

    visit(table);
    return rows.join('\n');
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

  Delta finish({required String fallback}) => _delta.isEmpty
      ? NoteAssistantMarkdownCodec._plainTextDelta(fallback)
      : _delta;
}

String encodeAssistantExpectedDocument(Delta delta) =>
    jsonEncode(delta.toJson());
