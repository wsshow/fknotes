import 'dart:math' as math;

import '../models/local_chat.dart';
import '../models/note_entry.dart';

class LocalChatNoteContextBuilder {
  static const maxNotes = 5;
  static const maxTotalCharacters = 1600;
  static const maxCharactersPerNote = 1200;

  static LocalChatNoteContext fromNote(
    NoteEntry note, {
    LocalChatNoteScope scope = LocalChatNoteScope.fullNote,
    String? content,
    String untitledLabel = '无标题',
  }) {
    final noteId = note.id;
    if (noteId == null) throw ArgumentError('笔记必须先保存才能作为对话来源');
    return LocalChatNoteContext(
      noteId: noteId,
      title: note.title.trim().isEmpty ? untitledLabel : note.title.trim(),
      scope: scope,
      content: content ?? _readableSource(note),
      updatedAt: note.updatedAt,
    );
  }

  static List<LocalChatNoteContext> fit(
    Iterable<LocalChatNoteContext> contexts,
  ) {
    final unique = <int, LocalChatNoteContext>{};
    for (final context in contexts) {
      unique.putIfAbsent(context.noteId, () => context);
      if (unique.length == maxNotes) break;
    }
    if (unique.isEmpty) return const [];
    final perNoteLimit = math.min(
      maxCharactersPerNote,
      maxTotalCharacters ~/ unique.length,
    );
    return unique.values
        .map(
          (context) => context.copyWith(
            content: _bounded(context.content.trim(), perNoteLimit),
          ),
        )
        .toList(growable: false);
  }

  static String _readableSource(NoteEntry note) {
    final parts = <String>[
      if (note.plainTextContent.trim().isNotEmpty) note.plainTextContent.trim(),
      if (note.aggregateOcr.trim().isNotEmpty)
        '【图片 OCR】\n${note.aggregateOcr.trim()}',
      if (note.aggregateTranscripts.trim().isNotEmpty)
        '【语音转写】\n${note.aggregateTranscripts.trim()}',
    ];
    return parts.join('\n\n');
  }

  static String _bounded(String value, int limit) {
    if (value.length <= limit) return value;
    const marker = '\n…[中间内容已省略]…\n';
    if (limit <= marker.length) return value.substring(0, limit);
    final available = limit - marker.length;
    final leading = (available * .65).floor();
    final trailing = available - leading;
    return '${value.substring(0, leading)}$marker'
        '${value.substring(value.length - trailing)}';
  }
}
