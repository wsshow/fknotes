import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/models/note_semantic_projection.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NoteSemanticProjection', () {
    test('preserves inline and block semantics without markup leakage', () {
      final note = _note(
        Delta()
          ..insert('章节')
          ..insert('\n', {'header': 2, 'align': 'center'})
          ..insert('加粗', {'bold': true})
          ..insert('、')
          ..insert('链接', {
            'italic': true,
            'underline': true,
            'link': 'https://example.com',
          })
          ..insert('\n')
          ..insert('任务')
          ..insert('\n', {'list': 'unchecked', 'indent': 2})
          ..insert('引用')
          ..insert('\n', {'blockquote': true})
          ..insert('print(1)')
          ..insert('\n', {'code-block': true}),
      );

      final projection = NoteSemanticProjection.fromNote(note);

      expect(projection.blocks, hasLength(5));
      expect(projection.blocks[0].kind, NoteSemanticBlockKind.heading);
      expect(projection.blocks[0].headingLevel, 2);
      expect(projection.blocks[0].alignment, NoteSemanticAlignment.center);
      expect(projection.blocks[1].plainText, '加粗、链接');
      expect(projection.blocks[1].runs[0].style.bold, isTrue);
      expect(projection.blocks[1].runs[2].style.italic, isTrue);
      expect(projection.blocks[1].runs[2].style.underline, isTrue);
      expect(projection.blocks[1].runs[2].style.link, 'https://example.com');
      expect(projection.blocks[2].kind, NoteSemanticBlockKind.uncheckedList);
      expect(projection.blocks[2].indent, 2);
      expect(projection.blocks[3].kind, NoteSemanticBlockKind.blockQuote);
      expect(projection.blocks[4].kind, NoteSemanticBlockKind.codeBlock);
      expect(projection.bodyText, '章节\n加粗、链接\n任务\n引用\nprint(1)');
      expect(projection.bodyText, isNot(contains('**')));
    });

    test('speech skips attachment labels, extraction and dividers', () {
      final imageId = NoteAttachmentId.generate();
      final note = _note(
        Delta()
          ..insert('可朗读正文\n')
          ..insert(NoteEmbed.attachment(imageId).toDeltaData())
          ..insert('\n')
          ..insert(const NoteEmbed.divider().toDeltaData())
          ..insert('\n')
          ..insert('结尾\n'),
        title: '标题',
        assets: [
          _asset(
            imageId,
            kind: NoteAssetKind.image,
            name: '化验单.png',
            ocrText: '不应自动朗读的 OCR',
          ),
        ],
      );

      final speech = NoteSemanticProjection.fromNote(note).speechText();

      expect(speech, '标题\n\n可朗读正文\n结尾');
      expect(speech, isNot(contains('化验单')));
      expect(speech, isNot(contains('OCR')));
      expect(speech, isNot(contains('——')));
    });

    test('AI source keeps media extraction in document order only once', () {
      final imageId = NoteAttachmentId.generate();
      final audioId = NoteAttachmentId.generate();
      final note = _note(
        Delta()
          ..insert('开始\n')
          ..insert(NoteEmbed.attachment(imageId).toDeltaData())
          ..insert('\n')
          ..insert('中间\n')
          ..insert(NoteEmbed.attachment(audioId).toDeltaData())
          ..insert('\n')
          ..insert(NoteEmbed.attachment(imageId).toDeltaData())
          ..insert('\n'),
        title: '研究记录',
        tags: const ['工作', '访谈'],
        assets: [
          _asset(
            imageId,
            kind: NoteAssetKind.image,
            name: '白板.png',
            ocrText: '白板识别内容',
          ),
          _asset(
            audioId,
            kind: NoteAssetKind.audio,
            name: '讨论.m4a',
            transcript: '会议转写内容',
          ),
        ],
      );

      final source = NoteSemanticProjection.fromNote(note).assistantSource();

      expect(source, contains('标题:\n研究记录'));
      expect(source, contains('标签:\n工作、访谈'));
      expect(source.indexOf('开始'), lessThan(source.indexOf('白板.png')));
      expect(source.indexOf('白板.png'), lessThan(source.indexOf('中间')));
      expect(source.indexOf('中间'), lessThan(source.indexOf('讨论.m4a')));
      expect('白板.png'.allMatches(source), hasLength(1));
      expect(source, contains('图片文字:\n白板识别内容'));
      expect(source, contains('语音转写:\n会议转写内容'));
    });

    test('AI source truncates by Unicode code points deterministically', () {
      final note = _note(
        NoteDocument.fromPlainText('${'开头' * 80}😀${'结尾' * 80}').toDelta(),
        title: '长笔记',
      );
      final projection = NoteSemanticProjection.fromNote(note);

      final first = projection.assistantSource(maxCharacters: 90);
      final second = projection.assistantSource(maxCharacters: 90);

      expect(first, second);
      expect(first.runes.length, 90);
      expect(first, contains('[中间内容已省略]'));
      expect(first.runes, isNot(contains(0xFFFD)));
    });

    test('merges adjacent runs that have identical portable style', () {
      final note = _note(
        Delta()
          ..insert('甲', {'bold': true, 'color': '#ff0000'})
          ..insert('乙', {'bold': true, 'color': '#00ff00'})
          ..insert('\n'),
      );

      final block = NoteSemanticProjection.fromNote(note).blocks.single;

      expect(block.runs, hasLength(1));
      expect(block.runs.single.text, '甲乙');
      expect(block.runs.single.style.bold, isTrue);
    });

    test('keeps table rows available to search, speech and AI consumers', () {
      final table = NoteTable(
        rows: const [
          ['项目', '状态'],
          ['Quill', '完成'],
        ],
      );
      final note = _note(
        Delta()
          ..insert(NoteEmbed.table(table).toDeltaData())
          ..insert('\n'),
      );

      final projection = NoteSemanticProjection.fromNote(note);

      expect(projection.blocks.single.kind, NoteSemanticBlockKind.table);
      expect(projection.blocks.single.table!.rows, table.rows);
      expect(projection.bodyText, '项目\t状态\nQuill\t完成');
      expect(projection.speechText(), contains('Quill'));
      expect(projection.assistantSource(), contains('表格：\n项目\t状态'));
    });
  });
}

Note _note(
  Delta delta, {
  String title = '',
  List<String> tags = const [],
  List<NoteAsset> assets = const [],
}) {
  final now = DateTime.utc(2026, 7, 23);
  return Note(
    id: NoteId.generate(),
    title: title,
    document: NoteDocument.fromDelta(delta),
    tags: tags,
    assets: assets,
    createdAt: now,
    updatedAt: now,
  );
}

NoteAsset _asset(
  NoteAttachmentId id, {
  required NoteAssetKind kind,
  required String name,
  String? ocrText,
  String? transcript,
}) {
  final now = DateTime.utc(2026, 7, 23);
  return NoteAsset(
    id: id,
    kind: kind,
    storageKey: switch (kind) {
      NoteAssetKind.image => 'notes/images/${id.value}',
      NoteAssetKind.audio => 'notes/audio/${id.value}',
      NoteAssetKind.video => 'notes/video/${id.value}',
      NoteAssetKind.file => 'notes/files/${id.value}',
    },
    originalName: name,
    byteLength: 10,
    mimeType: switch (kind) {
      NoteAssetKind.image => 'image/png',
      NoteAssetKind.audio => 'audio/m4a',
      NoteAssetKind.video => 'video/mp4',
      NoteAssetKind.file => 'application/octet-stream',
    },
    ocrText: ocrText,
    transcript: transcript,
    createdAt: now,
    updatedAt: now,
  );
}
