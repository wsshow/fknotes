import 'package:flutter_quill/quill_delta.dart';

import '../models/local_chat.dart';
import '../models/note.dart';
import '../models/note_document.dart';

/// Applies a user-confirmed assistant write to canonical Delta notes.
final class LocalChatNoteAction {
  static Note createNote(
    LocalChatToolCall call, {
    required DateTime now,
    required String untitledLabel,
  }) {
    final content = call.content?.trim();
    if (call.name != LocalChatToolName.createNote ||
        content?.isNotEmpty != true) {
      throw const FormatException('创建笔记提案不完整');
    }
    return Note(
      id: NoteId.generate(),
      title: call.title?.trim().isNotEmpty == true
          ? call.title!.trim()
          : untitledLabel,
      document: NoteDocument.fromPlainText(content!),
      createdAt: now,
      updatedAt: now,
    );
  }

  static Note applyToNote(
    LocalChatToolCall call,
    Note target, {
    required DateTime now,
  }) {
    if (call.noteId != target.id) {
      throw const FormatException('目标笔记不匹配');
    }
    final incoming = call.content?.trim();
    if (incoming == null || incoming.isEmpty) {
      throw const FormatException('写入内容不能为空');
    }
    return switch (call.name) {
      LocalChatToolName.appendNote => target.copyWith(
        document: _append(target.document, incoming),
        updatedAt: now,
      ),
      LocalChatToolName.replaceNote => target.copyWith(
        document: NoteDocument.fromPlainText(incoming),
        assets: const [],
        coverAttachmentId: null,
        updatedAt: now,
      ),
      _ => throw const FormatException('不是可应用到现有笔记的操作'),
    };
  }

  static NoteDocument _append(NoteDocument existing, String incoming) {
    if (existing.project().isVisuallyEmpty) {
      return NoteDocument.fromPlainText(incoming);
    }
    final combined = Delta.from(existing.toDelta());
    for (final operation in NoteDocument.fromPlainText(
      incoming,
    ).toDelta().operations) {
      combined.push(operation);
    }
    return NoteDocument.fromDelta(combined);
  }
}
