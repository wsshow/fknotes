import 'dart:math' as math;

import '../models/local_chat.dart';
import '../models/note.dart';

class LocalChatNoteContextBuilder {
  static const maxNotes = 5;
  static const maxTotalCharacters = 1600;
  static const maxCharactersPerNote = 1200;

  static LocalChatNoteContext fromNote(
    Note note, {
    LocalChatNoteScope scope = LocalChatNoteScope.fullNote,
    String? content,
    String untitledLabel = '无标题',
  }) {
    return LocalChatNoteContext(
      noteId: note.id,
      title: note.title.trim().isEmpty ? untitledLabel : note.title.trim(),
      scope: scope,
      content: content ?? _readableSource(note),
      updatedAt: note.updatedAt,
    );
  }

  static List<LocalChatNoteContext> fit(
    Iterable<LocalChatNoteContext> contexts,
  ) {
    final unique = <NoteId, LocalChatNoteContext>{};
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

  static String _readableSource(Note note) {
    final ocr = _assetText(note.assets, (asset) => asset.ocrText);
    final transcripts = _assetText(note.assets, (asset) => asset.transcript);
    final parts = <String>[
      if (note.contentProjection.plainText.trim().isNotEmpty)
        note.contentProjection.plainText.trim(),
      if (ocr.isNotEmpty) '【图片 OCR】\n$ocr',
      if (transcripts.isNotEmpty) '【语音转写】\n$transcripts',
    ];
    return parts.join('\n\n');
  }

  static String _assetText(
    List<NoteAsset> assets,
    String? Function(NoteAsset asset) select,
  ) => assets
      .map(select)
      .whereType<String>()
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .join('\n');

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
