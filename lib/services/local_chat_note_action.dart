import '../models/local_chat.dart';
import '../models/note_entry.dart';
import '../widgets/note_block_editor.dart';

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
    final blocks = _safeBlocks(call.content!);
    return NoteEntry(
      type: NoteType.text,
      title: call.title?.trim().isNotEmpty == true
          ? call.title!.trim()
          : untitledLabel,
      content: NoteBlockCodec.encode(blocks),
      richContent: NoteRichDocumentCodec.encode(blocks),
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
    final incomingBlocks = _safeBlocks(incoming);
    final blocks = switch (call.name) {
      LocalChatToolName.appendNote => [
        ..._existingBlocks(target),
        ...incomingBlocks,
      ],
      LocalChatToolName.replaceNote => incomingBlocks,
      _ => throw const FormatException('不是可应用到现有笔记的操作'),
    };
    return target.copyWith(
      content: NoteBlockCodec.encode(blocks),
      richContent: NoteRichDocumentCodec.encode(blocks),
      updatedAt: now,
    );
  }

  static List<NoteBlockData> _existingBlocks(NoteEntry target) {
    final rich = NoteRichDocumentCodec.tryDecode(target.richContent);
    if (rich != null &&
        NoteBlockCodec.structurallyMatches(rich, target.content ?? '')) {
      return rich;
    }
    return NoteBlockCodec.decode(target.content ?? '');
  }

  static List<NoteBlockData> _safeBlocks(String source) =>
      NoteBlockCodec.decode(source.trim())
          .map((block) {
            if (block.type != NoteBlockType.attachment) return block;
            return const NoteBlockData(NoteBlockType.paragraph, '[附件引用已忽略]');
          })
          .toList(growable: false);
}
