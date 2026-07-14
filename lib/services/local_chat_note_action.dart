import '../models/local_chat.dart';
import '../models/note_entry.dart';

class LocalChatNoteAction {
  static NoteEntry createNote(
    LocalChatToolCall call, {
    required DateTime now,
    required String untitledLabel,
  }) {
    if (call.name != LocalChatToolName.createNote ||
        call.content?.trim().isEmpty != false) {
      throw const FormatException('创建笔记提案不完整');
    }
    return NoteEntry(
      type: NoteType.text,
      title: call.title?.trim().isNotEmpty == true
          ? call.title!.trim()
          : untitledLabel,
      content: call.content!.trim(),
      createdAt: now,
      updatedAt: now,
    );
  }

  static NoteEntry applyToNote(
    LocalChatToolCall call,
    NoteEntry target, {
    required DateTime now,
  }) {
    if (target.id == null || call.noteId != target.id) {
      throw const FormatException('目标笔记不匹配');
    }
    final incoming = call.content?.trim();
    if (incoming == null || incoming.isEmpty) {
      throw const FormatException('写入内容不能为空');
    }
    final content = switch (call.name) {
      LocalChatToolName.appendNote => [
        if (target.content?.trim().isNotEmpty == true) target.content!.trim(),
        incoming,
      ].join('\n\n'),
      LocalChatToolName.replaceNote => incoming,
      _ => throw const FormatException('不是可应用到现有笔记的操作'),
    };
    return target.copyWith(
      content: content,
      clearRichContent: true,
      updatedAt: now,
    );
  }
}
