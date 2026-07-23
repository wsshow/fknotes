import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/models/note_entry.dart';
import 'package:fknotes/utils/markdown_text.dart';
import 'package:fknotes/widgets/note_card.dart';
import 'package:flutter/material.dart';
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

  test('lossless editor text cleans previews from legacy ambiguous emphasis', () {
    final entry = NoteEntry(
      type: NoteType.text,
      content: '**qq，，，**aaa',
      richContent:
          '{"version":2,"blocks":[{"type":"paragraph","text":"qq，，，aaa","styles":[{"start":0,"end":5,"bold":true}]}]}',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    expect(entry.previewText, 'qq，，，aaa');
    expect(entry.previewText, isNot(contains('**')));
  });

  test('rich attachment nodes keep readable labels in downstream text', () {
    final entry = NoteEntry(
      type: NoteType.image,
      content: '检查结果\n\n[[附件:images/result.png]]',
      richContent:
          '{"version":2,"blocks":[{"type":"paragraph","text":"检查结果"},{"type":"attachment","text":"","attachmentPath":"images/result.png"}]}',
      attachments: [
        NoteAttachment(
          type: NoteType.image,
          filePath: 'images/result.png',
          fileName: 'result.png',
          displayName: '化验结果',
          fileSize: 1,
          mimeType: 'image/png',
          createdAt: DateTime(2026),
        ),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    expect(entry.plainTextContent, '检查结果\n【附件：化验结果】');
    expect(entry.toMap()['search_text'], entry.plainTextContent);
  });

  testWidgets('library card displays a clean summary without Markdown syntax', (
    tester,
  ) async {
    final entry = NoteEntry(
      type: NoteType.text,
      title: '语音笔记',
      content: '**qq，，，**aaa',
      richContent:
          '{"version":2,"blocks":[{"type":"paragraph","text":"qq，，，aaa","styles":[{"start":0,"end":5,"bold":true}]}]}',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: NoteCard(entry: entry, onTap: () {}),
        ),
      ),
    );

    expect(find.text('qq，，，aaa'), findsOneWidget);
    expect(find.textContaining('**'), findsNothing);
  });

  test('plain-text projection keeps special characters readable', () {
    expect(MarkdownText.toPlainText('他说："探索" & 2 < 3'), '他说："探索" & 2 < 3');
    expect(MarkdownText.toPlainText('&quot;旧内容&quot;'), '"旧内容"');
  });
}
