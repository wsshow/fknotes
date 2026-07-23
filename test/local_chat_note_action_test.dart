import 'package:fknotes/models/local_chat.dart';
import 'package:fknotes/models/note_entry.dart';
import 'package:fknotes/services/local_chat_note_action.dart';
import 'package:fknotes/widgets/note_block_editor.dart';
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
    expect(NoteRichDocumentCodec.tryDecode(created.richContent), isNotNull);
    expect(created.id, isNull);
  });

  test(
    'append preserves rich styles while replace writes a complete document',
    () {
      const originalBlocks = [
        NoteBlockData(
          NoteBlockType.paragraph,
          '原内容',
          styles: [
            NoteTextStyleRange(
              0,
              3,
              NoteTextAttributes(underline: true, fontSize: 24),
            ),
          ],
        ),
      ];
      final note = NoteEntry(
        id: 42,
        type: NoteType.text,
        title: '项目记录',
        content: '原内容',
        richContent: NoteRichDocumentCodec.encode(originalBlocks),
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
      final appendedBlocks = NoteRichDocumentCodec.tryDecode(
        appended.richContent,
      )!;
      expect(appendedBlocks, hasLength(2));
      expect(appendedBlocks.first.styles.single.attributes.underline, isTrue);
      expect(appendedBlocks.first.styles.single.attributes.fontSize, 24);
      expect(replaced.content, '替换内容');
      expect(
        NoteRichDocumentCodec.tryDecode(replaced.richContent)!.single.text,
        '替换内容',
      );
    },
  );

  test('generated attachment tokens remain inert text', () {
    final created = LocalChatNoteAction.createNote(
      const LocalChatToolCall(
        id: 'safe-create',
        name: LocalChatToolName.createNote,
        content: '[[附件:images/private.png]]',
      ),
      now: DateTime(2026, 7, 14),
      untitledLabel: '无标题',
    );

    expect(created.content, isNot(contains('[[附件:')));
    expect(
      NoteRichDocumentCodec.tryDecode(created.richContent)!.single,
      isA<NoteBlockData>()
          .having((block) => block.type, 'type', NoteBlockType.paragraph)
          .having((block) => block.text, 'text', '[附件引用已忽略]'),
    );
  });
}
