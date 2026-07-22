import 'package:fknotes/models/note_entry.dart';
import 'package:fknotes/utils/markdown_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Markdown plain-text projection removes syntax and keeps structure', () {
    const markdown = '''# 标题

**重点**与[链接](https://example.com)

- [x] 完成
- 第二项

| 项目 | 状态 |
| --- | --- |
| 基础 | 完成 |
''';

    expect(
      MarkdownText.toPlainText(markdown),
      '标题\n重点与链接\n完成\n第二项\n项目 · 状态\n基础 · 完成',
    );
  });

  test('note preview and text statistics do not expose Markdown markers', () {
    final entry = NoteEntry(
      type: NoteType.text,
      content: '# 标题\n\n**重点**',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    expect(entry.previewText, '标题\n重点');
    expect(entry.attachmentSummary, '文字 · 4 字');
    expect(entry.readableContent, '# 标题\n\n**重点**');
  });

  test('plain-text projection keeps special characters readable', () {
    expect(MarkdownText.toPlainText('他说："探索" & 2 < 3'), '他说："探索" & 2 < 3');
    expect(MarkdownText.toPlainText('&quot;旧内容&quot;'), '"旧内容"');
  });
}
