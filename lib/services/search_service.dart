import 'package:sqflite/sqflite.dart';

import '../models/note_entry.dart';
import 'database_service.dart';
import 'note_service.dart';

enum LocalSearchFilter { all, notes, attachments, conversations }

extension LocalSearchFilterInfo on LocalSearchFilter {
  String get label => switch (this) {
    LocalSearchFilter.all => '全部',
    LocalSearchFilter.notes => '笔记',
    LocalSearchFilter.attachments => '附件',
    LocalSearchFilter.conversations => '对话',
  };
}

class LocalSearchResult {
  final String id;
  final NoteEntry? note;
  final String? chatSessionId;
  final String title;
  final String snippet;
  final bool matchedNote;
  final bool matchedAttachment;
  final double rank;
  final DateTime updatedAt;

  const LocalSearchResult({
    required this.id,
    required this.note,
    required this.chatSessionId,
    required this.title,
    required this.snippet,
    required this.matchedNote,
    required this.matchedAttachment,
    required this.rank,
    required this.updatedAt,
  });

  bool get isConversation => chatSessionId != null;

  String get sourceLabel {
    if (isConversation) return '对话命中';
    if (matchedNote && matchedAttachment) return '笔记与附件命中';
    if (matchedAttachment) return '附件命中';
    return '笔记命中';
  }

  bool matches(LocalSearchFilter filter) => switch (filter) {
    LocalSearchFilter.all => true,
    LocalSearchFilter.notes => !isConversation && matchedNote,
    LocalSearchFilter.attachments => !isConversation && matchedAttachment,
    LocalSearchFilter.conversations => isConversation,
  };
}

class SearchService {
  SearchService._();

  static final SearchService instance = SearchService._();

  final _notes = NoteService.instance;

  Future<List<LocalSearchResult>> search(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) return const [];
    final database = await DatabaseService.instance.database;
    List<Map<String, Object?>> rows = const [];
    if (query.runes.length >= 3 && await _usesTrigramIndex(database)) {
      try {
        final literal = '"${query.replaceAll('"', '""')}"';
        rows = await database.rawQuery(
          '''
          SELECT kind, source_id, parent_id, title, body, metadata,
            snippet(search_fts, 4, '', '', '…', 24) AS snippet,
            bm25(search_fts, 0.0, 0.0, 0.0, 8.0, 1.0, 0.5) AS rank
          FROM search_fts
          WHERE search_fts MATCH ?
          ORDER BY rank
          LIMIT 160
          ''',
          [literal],
        );
      } on DatabaseException {
        rows = const [];
      }
    }
    if (rows.isEmpty) rows = await _fallbackSearch(database, query);
    return _hydrateResults(database, rows);
  }

  Future<bool> _usesTrigramIndex(Database database) async {
    final rows = await database.rawQuery(
      "SELECT sql FROM sqlite_master WHERE name = 'search_fts' LIMIT 1",
    );
    final sql = rows.firstOrNull?['sql']?.toString().toLowerCase() ?? '';
    return sql.contains('using fts5') && sql.contains('trigram');
  }

  Future<List<Map<String, Object?>>> _fallbackSearch(
    Database database,
    String query,
  ) {
    final like = '%$query%';
    return database.rawQuery(
      '''
      SELECT 'note' AS kind, CAST(e.id AS TEXT) AS source_id, '' AS parent_id,
        e.title AS title, COALESCE(e.content, '') AS body,
        COALESCE(e.tags, '') || ' ' || COALESCE(e.ocr_text, '') || ' ' ||
          COALESCE(e.file_name, '') AS metadata,
        COALESCE(e.content, e.title) AS snippet, 0.0 AS rank
      FROM entries e
      WHERE e.is_deleted = 0 AND (
        e.title LIKE ? OR e.content LIKE ? OR e.tags LIKE ? OR
        e.ocr_text LIKE ? OR e.file_name LIKE ?
      )
      UNION ALL
      SELECT 'attachment', CAST(a.id AS TEXT), CAST(a.note_id AS TEXT),
        a.file_name, COALESCE(a.ocr_text, '') || ' ' || COALESCE(a.transcript, ''),
        a.type || ' ' || a.mime_type,
        COALESCE(NULLIF(a.transcript, ''), NULLIF(a.ocr_text, ''), a.file_name), 0.0
      FROM attachments a
      JOIN entries e ON e.id = a.note_id
      WHERE e.is_deleted = 0 AND (
        a.file_name LIKE ? OR a.ocr_text LIKE ? OR a.transcript LIKE ?
      )
      UNION ALL
      SELECT 'chat_session', s.id, '', s.title, s.system_prompt, '',
        COALESCE(NULLIF(s.system_prompt, ''), s.title), 0.0
      FROM chat_sessions s
      WHERE s.title LIKE ? OR s.system_prompt LIKE ?
      UNION ALL
      SELECT 'chat_message', m.id, m.session_id, '', m.content, m.role,
        m.content, 0.0
      FROM chat_messages m
      WHERE m.content LIKE ?
      LIMIT 160
      ''',
      [like, like, like, like, like, like, like, like, like, like, like],
    );
  }

  Future<List<LocalSearchResult>> _hydrateResults(
    Database database,
    List<Map<String, Object?>> rows,
  ) async {
    final notes = <int, _SearchGroup>{};
    final chats = <String, _SearchGroup>{};
    for (final row in rows) {
      final kind = row['kind'] as String? ?? '';
      final rank = (row['rank'] as num?)?.toDouble() ?? 0;
      final snippet = _bestSnippet(row);
      if (kind == 'note' || kind == 'attachment') {
        final rawId = kind == 'note' ? row['source_id'] : row['parent_id'];
        final noteId = int.tryParse(rawId?.toString() ?? '');
        if (noteId == null) continue;
        notes
            .putIfAbsent(noteId, _SearchGroup.new)
            .add(
              rank: rank,
              snippet: snippet,
              note: kind == 'note',
              attachment: kind == 'attachment',
            );
      } else if (kind == 'chat_session' || kind == 'chat_message') {
        final sessionId =
            (kind == 'chat_session' ? row['source_id'] : row['parent_id'])
                ?.toString();
        if (sessionId == null || sessionId.isEmpty) continue;
        chats
            .putIfAbsent(sessionId, _SearchGroup.new)
            .add(rank: rank, snippet: snippet);
      }
    }

    final results = <LocalSearchResult>[];
    for (final item in notes.entries) {
      final note = await _notes.getEntry(item.key);
      if (note == null || note.isDeleted) continue;
      final group = item.value;
      results.add(
        LocalSearchResult(
          id: 'note:${item.key}',
          note: note,
          chatSessionId: null,
          title: note.title.isEmpty ? '无标题' : note.title,
          snippet: group.snippet.isEmpty ? note.previewText : group.snippet,
          matchedNote: group.matchedNote,
          matchedAttachment: group.matchedAttachment,
          rank: group.rank,
          updatedAt: note.updatedAt,
        ),
      );
    }
    for (final item in chats.entries) {
      final sessionRows = await database.query(
        'chat_sessions',
        columns: ['title', 'updated_at'],
        where: 'id = ?',
        whereArgs: [item.key],
        limit: 1,
      );
      if (sessionRows.isEmpty) continue;
      final row = sessionRows.single;
      results.add(
        LocalSearchResult(
          id: 'chat:${item.key}',
          note: null,
          chatSessionId: item.key,
          title: row['title'] as String? ?? '本地对话',
          snippet: item.value.snippet,
          matchedNote: false,
          matchedAttachment: false,
          rank: item.value.rank,
          updatedAt:
              DateTime.tryParse(row['updated_at'] as String? ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );
    }
    results.sort((left, right) {
      final rank = left.rank.compareTo(right.rank);
      return rank != 0 ? rank : right.updatedAt.compareTo(left.updatedAt);
    });
    return results;
  }

  String _bestSnippet(Map<String, Object?> row) {
    for (final key in ['snippet', 'body', 'title', 'metadata']) {
      final value = row[key]?.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      if (value?.isNotEmpty == true) {
        return value!.length > 180 ? '${value.substring(0, 180)}…' : value;
      }
    }
    return '';
  }
}

class _SearchGroup {
  double rank = double.infinity;
  String snippet = '';
  bool matchedNote = false;
  bool matchedAttachment = false;

  void add({
    required double rank,
    required String snippet,
    bool note = false,
    bool attachment = false,
  }) {
    matchedNote |= note;
    matchedAttachment |= attachment;
    if (rank < this.rank || this.snippet.isEmpty) {
      this.rank = rank;
      this.snippet = snippet;
    }
  }
}
