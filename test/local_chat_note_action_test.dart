import 'package:fknotes/models/local_chat.dart';
import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/services/local_chat_note_action.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final noteId = NoteId.parse('f1341a17-27a4-42f8-bd30-b589550f0f57');

  test('creates a canonical Delta note from a valid proposal', () {
    final created = LocalChatNoteAction.createNote(
      const LocalChatToolCall(
        id: 'create',
        name: LocalChatToolName.createNote,
        title: '新计划',
        content: '计划正文',
      ),
      now: DateTime(2026, 7, 14),
      untitledLabel: '无标题',
    );

    expect(created.id.value, matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(created.title, '新计划');
    expect(created.contentProjection.plainText, '计划正文');
    expect(created.document.toDelta().toJson(), [
      {'insert': '计划正文\n'},
    ]);
    expect(created.revision, 0);
  });

  test('append preserves Delta styles and owned assets', () {
    final assetId = NoteAttachmentId.parse(
      '3d2be3d5-00c8-4f5c-8e69-e90085dc2873',
    );
    final note = Note(
      id: noteId,
      title: '项目记录',
      document: NoteDocument.fromDelta(
        Delta()
          ..insert('原内容', {'bold': true})
          ..insert('\n')
          ..insert(NoteEmbed.attachment(assetId).toDeltaData())
          ..insert('\n'),
      ),
      assets: [_asset(assetId)],
      revision: 3,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    final appended = LocalChatNoteAction.applyToNote(
      LocalChatToolCall(
        id: 'append',
        name: LocalChatToolName.appendNote,
        noteId: noteId,
        content: '追加内容',
      ),
      note,
      now: DateTime(2026, 7, 14),
    );

    expect(appended.document.toDelta().toJson(), [
      {
        'insert': '原内容',
        'attributes': {'bold': true},
      },
      {'insert': '\n'},
      {'insert': NoteEmbed.attachment(assetId).toDeltaData()},
      {'insert': '\n追加内容\n'},
    ]);
    expect(appended.assets, note.assets);
    expect(appended.revision, 3);
  });

  test('replace builds a fresh document and detaches removed assets', () {
    final assetId = NoteAttachmentId.parse(
      '3d2be3d5-00c8-4f5c-8e69-e90085dc2873',
    );
    final note = Note(
      id: noteId,
      title: '项目记录',
      document: NoteDocument.fromDelta(
        Delta()
          ..insert(NoteEmbed.attachment(assetId).toDeltaData())
          ..insert('\n'),
      ),
      assets: [_asset(assetId)],
      coverAttachmentId: assetId,
      revision: 2,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    final replaced = LocalChatNoteAction.applyToNote(
      LocalChatToolCall(
        id: 'replace',
        name: LocalChatToolName.replaceNote,
        noteId: noteId,
        content: '替换内容',
      ),
      note,
      now: DateTime(2026, 7, 14),
    );

    expect(replaced.contentProjection.plainText, '替换内容');
    expect(replaced.assets, isEmpty);
    expect(replaced.coverAttachmentId, isNull);
  });

  test('rejects writes whose UUID does not match the target note', () {
    final note = Note(
      id: noteId,
      title: '',
      document: NoteDocument.empty(),
      revision: 1,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    expect(
      () => LocalChatNoteAction.applyToNote(
        LocalChatToolCall(
          id: 'replace',
          name: LocalChatToolName.replaceNote,
          noteId: NoteId.parse('1f166ea4-1df5-40c8-b494-7042929cf7cc'),
          content: '内容',
        ),
        note,
        now: DateTime(2026, 7, 14),
      ),
      throwsFormatException,
    );
  });
}

NoteAsset _asset(NoteAttachmentId id) => NoteAsset(
  id: id,
  kind: NoteAssetKind.image,
  storageKey: 'notes/images/example.png',
  originalName: 'example.png',
  byteLength: 10,
  mimeType: 'image/png',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);
