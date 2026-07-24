import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/widgets/note_delta_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders Delta emphasis as styles instead of syntax markers', (
    tester,
  ) async {
    final note = _noteWithDocument(
      Delta()
        ..insert('加粗', {'bold': true})
        ..insert('与')
        ..insert('倾斜', {'italic': true})
        ..insert('\n'),
    );

    await tester.pumpWidget(_TestApp(child: NoteDeltaPreview(note: note)));

    final text = tester.widget<Text>(
      find.byKey(const Key('note-delta-preview-text')),
    );
    final root = text.textSpan! as TextSpan;
    final spans = root.children!.cast<TextSpan>();
    expect(spans.map((span) => span.text).join(), '加粗与倾斜');
    expect(spans[0].style?.fontWeight, FontWeight.w700);
    expect(spans[2].style?.fontStyle, FontStyle.italic);
  });

  testWidgets('projects attachment IDs through note metadata', (tester) async {
    final id = NoteAttachmentId.generate();
    final now = DateTime.utc(2026, 7, 23);
    final asset = NoteAsset(
      id: id,
      kind: NoteAssetKind.image,
      storageKey: 'notes/images/preview.png',
      originalName: '设计稿.png',
      byteLength: 20,
      mimeType: 'image/png',
      createdAt: now,
      updatedAt: now,
    );
    final note = Note(
      id: NoteId.generate(),
      title: '图片',
      document: NoteDocument.fromDelta(
        Delta()
          ..insert('正文\n')
          ..insert(NoteEmbed.attachment(id).toDeltaData())
          ..insert('\n'),
      ),
      assets: [asset],
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(_TestApp(child: NoteDeltaPreview(note: note)));

    expect(find.textContaining('【设计稿.png】'), findsOneWidget);
  });

  testWidgets('keeps table cell content visible in the library preview', (
    tester,
  ) async {
    final table = NoteTable(
      rows: const [
        ['项目', '状态'],
        ['Quill', '完成'],
      ],
    );
    final note = _noteWithDocument(
      Delta()
        ..insert(NoteEmbed.table(table).toDeltaData())
        ..insert('\n'),
    );

    await tester.pumpWidget(_TestApp(child: NoteDeltaPreview(note: note)));

    final text = tester.widget<Text>(
      find.byKey(const Key('note-delta-preview-text')),
    );
    expect(text.textSpan!.toPlainText(), contains('项目\t状态'));
    expect(text.textSpan!.toPlainText(), contains('Quill\t完成'));
  });

  testWidgets('compact preview skips blank lines and collapses whitespace', (
    tester,
  ) async {
    final note = _noteWithDocument(
      Delta()
        ..insert('\n\n第一段  ')
        ..insert('重点', {'bold': true})
        ..insert('\n\n第二段\n'),
    );

    await tester.pumpWidget(
      _TestApp(child: NoteDeltaPreview(note: note, compactWhitespace: true)),
    );

    final text = tester.widget<Text>(
      find.byKey(const Key('note-delta-preview-text')),
    );
    expect(text.textSpan!.toPlainText(), '第一段 重点 第二段');
  });
}

Note _noteWithDocument(Delta delta) {
  final now = DateTime.utc(2026, 7, 23);
  return Note(
    id: NoteId.generate(),
    title: '格式预览',
    document: NoteDocument.fromDelta(delta),
    createdAt: now,
    updatedAt: now,
  );
}

final class _TestApp extends StatelessWidget {
  const _TestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(body: child),
  );
}
