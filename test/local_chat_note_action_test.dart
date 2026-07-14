import 'package:fknotes/models/local_chat.dart';
import 'package:fknotes/models/note_entry.dart';
import 'package:fknotes/services/local_chat_note_action.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('creates a note only from a valid create proposal', () {
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

    expect(created.title, '新计划');
    expect(created.content, '计划正文');
    expect(created.id, isNull);
  });

  test(
    'appends or replaces the latest note body and clears stale rich data',
    () {
      final note = NoteEntry(
        id: 42,
        type: NoteType.text,
        title: '项目记录',
        content: '原内容',
        richContent: '{"version":1}',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final appended = LocalChatNoteAction.applyToNote(
        const LocalChatToolCall(
          id: 'append',
          name: LocalChatToolName.appendNote,
          noteId: 42,
          content: '追加内容',
        ),
        note,
        now: DateTime(2026, 7, 14),
      );
      final replaced = LocalChatNoteAction.applyToNote(
        const LocalChatToolCall(
          id: 'replace',
          name: LocalChatToolName.replaceNote,
          noteId: 42,
          content: '替换内容',
        ),
        note,
        now: DateTime(2026, 7, 14),
      );

      expect(appended.content, '原内容\n\n追加内容');
      expect(appended.richContent, isNull);
      expect(replaced.content, '替换内容');
      expect(replaced.richContent, isNull);
    },
  );
}
