import 'package:fknotes/models/local_chat.dart';
import 'package:fknotes/models/note_entry.dart';
import 'package:fknotes/services/local_chat_note_context_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds note context from text, OCR and transcripts', () {
    final note = NoteEntry(
      id: 8,
      type: NoteType.text,
      title: '会议记录',
      content: '# 结论\n正文内容',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026, 7, 14),
      attachments: [
        NoteAttachment(
          type: NoteType.image,
          filePath: 'image.jpg',
          fileName: '白板',
          fileSize: 10,
          mimeType: 'image/jpeg',
          ocrText: '白板上的时间是周五',
          createdAt: DateTime(2026),
        ),
        NoteAttachment(
          type: NoteType.audio,
          filePath: 'audio.m4a',
          fileName: '录音',
          fileSize: 10,
          mimeType: 'audio/mp4',
          transcript: '负责人确认按期发布',
          createdAt: DateTime(2026),
        ),
      ],
    );

    final context = LocalChatNoteContextBuilder.fromNote(note);

    expect(context.noteId, 8);
    expect(context.content, contains('结论'));
    expect(context.content, contains('【图片 OCR】'));
    expect(context.content, contains('白板上的时间是周五'));
    expect(context.content, contains('【语音转写】'));
    expect(context.content, contains('负责人确认按期发布'));
  });

  test('deduplicates notes and fits them into the mobile context budget', () {
    LocalChatNoteContext context(int id) => LocalChatNoteContext(
      noteId: id,
      title: '笔记 $id',
      scope: LocalChatNoteScope.fullNote,
      content: List.filled(1800, '$id').join(),
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
