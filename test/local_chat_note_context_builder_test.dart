import 'package:fknotes/models/local_chat.dart';
import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/services/local_chat_note_context_builder.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds note context from Delta text, OCR and transcripts', () {
    final imageId = NoteAttachmentId.parse(
      '3d2be3d5-00c8-4f5c-8e69-e90085dc2873',
    );
    final audioId = NoteAttachmentId.parse(
      'dca51acb-2e50-4ef1-9ad8-c4ce1e150f48',
    );
    final note = Note(
      id: NoteId.parse('f1341a17-27a4-42f8-bd30-b589550f0f57'),
      title: '会议记录',
      document: NoteDocument.fromDelta(
        Delta()
          ..insert('结论', {'bold': true})
          ..insert('\n正文内容\n')
          ..insert(NoteEmbed.attachment(imageId).toDeltaData())
          ..insert('\n')
          ..insert(NoteEmbed.attachment(audioId).toDeltaData())
          ..insert('\n'),
      ),
      assets: [
        _asset(
          imageId,
          kind: NoteAssetKind.image,
          path: 'notes/images/whiteboard.jpg',
          mimeType: 'image/jpeg',
          ocrText: '白板上的时间是周五',
        ),
        _asset(
          audioId,
          kind: NoteAssetKind.audio,
          path: 'notes/audio/meeting.m4a',
          mimeType: 'audio/mp4',
          transcript: '负责人确认按期发布',
        ),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026, 7, 14),
    );

    final context = LocalChatNoteContextBuilder.fromNote(note);

    expect(context.noteId, note.id);
    expect(context.content, contains('结论'));
    expect(context.content, contains('【图片 OCR】'));
    expect(context.content, contains('白板上的时间是周五'));
    expect(context.content, contains('【语音转写】'));
    expect(context.content, contains('负责人确认按期发布'));
  });

  test('deduplicates notes and fits them into the mobile context budget', () {
    LocalChatNoteContext context(int index) => LocalChatNoteContext(
      noteId: NoteId.parse(
        '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
      ),
      title: '笔记 $index',
      scope: LocalChatNoteScope.fullNote,
      content: List.filled(1800, '$index').join(),
      updatedAt: DateTime(2026),
    );

    final fitted = LocalChatNoteContextBuilder.fit([
      context(1),
      context(1),
      context(2),
      context(3),
      context(4),
      context(5),
      context(6),
    ]);

    expect(fitted, hasLength(LocalChatNoteContextBuilder.maxNotes));
    expect(fitted.map((item) => item.noteId).toSet(), hasLength(fitted.length));
    expect(
      fitted.fold<int>(0, (sum, item) => sum + item.content.length),
      lessThanOrEqualTo(LocalChatNoteContextBuilder.maxTotalCharacters),
    );
  });
}

NoteAsset _asset(
  NoteAttachmentId id, {
  required NoteAssetKind kind,
  required String path,
  required String mimeType,
  String? ocrText,
  String? transcript,
}) => NoteAsset(
  id: id,
  kind: kind,
  storageKey: path,
  originalName: path.split('/').last,
  byteLength: 10,
  mimeType: mimeType,
  ocrText: ocrText,
  transcript: transcript,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);
