import 'dart:convert';

import 'package:markdown/markdown.dart' as md;

/// Plain-text projection used by compact previews, statistics and speech.
///
/// The stored note remains Markdown. This projection removes formatting
/// syntax without executing HTML or resolving external resources.
abstract final class MarkdownText {
  /// Uses the editor's lossless document when available, then falls back to
  /// Markdown parsing. This also keeps compact previews clean for notes saved
  /// by older versions with an ambiguous emphasis boundary.
  static String toPlainTextDocument(String source, {String? richContent}) {
    final richText = _richDocumentText(richContent);
    if (richText?.isNotEmpty == true) return richText!;
    return toPlainText(source);
  }

  static String toPlainText(String source) {
    if (source.trim().isEmpty) return '';
    try {
      final nodes = md.Document(
        extensionSet: md.ExtensionSet.gitHubFlavored,
        encodeHtml: false,
      ).parse(source);
      final lines = <String>[];
      for (final node in nodes) {
        _appendBlock(lines, node);
      }
      return lines
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .join('\n');
    } catch (_) {
      return source;
    }
  }

  static void _appendBlock(List<String> lines, md.Node node) {
    if (node is md.Text) {
      if (node.text.trim().isNotEmpty) lines.add(node.text);
      return;
    }
    if (node is! md.Element) return;
    if (node.tag == 'ul' || node.tag == 'ol') {
      for (final item
          in (node.children ?? const <md.Node>[]).whereType<md.Element>()) {
        if (item.tag != 'li') continue;
        final text = _inlineText(item, skipLists: true).trim();
        if (text.isNotEmpty) lines.add(text);
        for (final child
            in (item.children ?? const <md.Node>[]).whereType<md.Element>()) {
          if (child.tag == 'ul' || child.tag == 'ol') {
            _appendBlock(lines, child);
          }
        }
      }
      return;
    }
    if (node.tag == 'blockquote') {
      for (final child in node.children ?? const <md.Node>[]) {
        _appendBlock(lines, child);
      }
      return;
    }
    if (node.tag == 'table') {
      _appendTable(lines, node);
      return;
    }
    final text = _inlineText(node).trim();
    if (text.isNotEmpty) lines.add(text);
  }

  static void _appendTable(List<String> lines, md.Element table) {
    void visit(md.Element element) {
      if (element.tag == 'tr') {
        final cells = (element.children ?? const <md.Node>[])
            .whereType<md.Element>()
            .where((cell) => cell.tag == 'th' || cell.tag == 'td')
            .map((cell) => _inlineText(cell).trim())
            .where((cell) => cell.isNotEmpty)
            .toList();
        if (cells.isNotEmpty) lines.add(cells.join(' · '));
        return;
      }
      for (final child
          in (element.children ?? const <md.Node>[]).whereType<md.Element>()) {
        visit(child);
      }
    }

    visit(table);
  }

  static String _inlineText(md.Element element, {bool skipLists = false}) {
    final output = StringBuffer();
    void visit(md.Node node) {
      if (node is md.Text) {
        output.write(node.text);
        return;
      }
      if (node is! md.Element || node.tag == 'input') return;
      if (skipLists && (node.tag == 'ul' || node.tag == 'ol')) return;
      if (node.tag == 'br') output.write('\n');
      for (final child in node.children ?? const <md.Node>[]) {
        visit(child);
      }
    }

    visit(element);
    return output.toString();
  }

  static String? _richDocumentText(String? source) {
    if (source?.trim().isEmpty ?? true) return null;
    try {
      final root = jsonDecode(source!) as Map<String, Object?>;
      if (root['version'] != 2) return null;
      final blocks = root['blocks'] as List<Object?>?;
      if (blocks == null || blocks.isEmpty) return null;
      final lines = <String>[];
      for (final rawBlock in blocks) {
        final block = rawBlock as Map<String, Object?>;
        final type = block['type'] as String? ?? 'paragraph';
        if (type == 'attachment' || type == 'divider') continue;
        final text = block['text'] as String? ?? '';
        final plain = type == 'rawMarkdown' ? toPlainText(text) : text;
        final normalized = plain.trim();
        if (normalized.isNotEmpty) lines.add(normalized);
      }
      return lines.join('\n');
    } catch (_) {
      return null;
    }
  }
}
