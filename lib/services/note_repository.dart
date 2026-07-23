import 'package:sqflite/sqflite.dart';

import '../models/note.dart';
import '../models/note_document.dart';

final class NoteWriteConflict implements Exception {
  const NoteWriteConflict(this.noteId);

  final NoteId noteId;

  @override
  String toString() => 'NoteWriteConflict(${noteId.value})';
}

/// Persistence for the Delta-based note model.
///
/// This repository intentionally has no legacy Markdown or integer-ID adapter.
/// Callers either provide a complete valid note graph or the transaction fails.
final class NoteRepository {
  NoteRepository(this._database);

  final Database _database;
  bool _usesFts = false;

  Future<void> initialize() async {
    await _database.execute('PRAGMA foreign_keys = ON');
    await _database.execute('''
      CREATE TABLE IF NOT EXISTS notes (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        document_json TEXT NOT NULL,
        search_text TEXT NOT NULL,
        is_pinned INTEGER NOT NULL CHECK(is_pinned IN (0, 1)),
        cover_attachment_id TEXT,
        revision INTEGER NOT NULL CHECK(revision > 0),
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(cover_attachment_id) REFERENCES note_assets(id)
          ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED
      )
    ''');
    await _database.execute('''
      CREATE TABLE IF NOT EXISTS note_assets (
        id TEXT PRIMARY KEY,
        note_id TEXT NOT NULL,
        kind TEXT NOT NULL CHECK(kind IN ('image', 'audio', 'video', 'file')),
        storage_key TEXT NOT NULL UNIQUE,
        original_name TEXT NOT NULL,
        display_name TEXT,
        byte_length INTEGER NOT NULL CHECK(byte_length >= 0),
        mime_type TEXT NOT NULL,
        preview_storage_key TEXT UNIQUE,
        duration_ms INTEGER CHECK(duration_ms IS NULL OR duration_ms >= 0),
        ocr_text TEXT,
        transcript TEXT,
        transcription_engine TEXT,
        transcribed_at INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(note_id) REFERENCES notes(id) ON DELETE CASCADE
      )
    ''');
    await _database.execute('''
      CREATE TABLE IF NOT EXISTS note_tags (
        note_id TEXT NOT NULL,
        position INTEGER NOT NULL CHECK(position >= 0),
        value TEXT NOT NULL,
        normalized_value TEXT NOT NULL,
        PRIMARY KEY(note_id, normalized_value),
        UNIQUE(note_id, position),
        FOREIGN KEY(note_id) REFERENCES notes(id) ON DELETE CASCADE
      )
    ''');
    await _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_notes_updated '
      'ON notes(is_pinned DESC, updated_at DESC)',
    );
    await _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_note_assets_note ON note_assets(note_id)',
    );
    await _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_note_tags_value '
      'ON note_tags(normalized_value)',
    );
    await _createSearchIndex();
  }

  Future<Note> create(Note note) async {
    if (note.revision != 0) {
      throw ArgumentError.value(
        note.revision,
        'revision',
        'Must start at zero',
      );
    }
    final persisted = note.copyWith(revision: 1);
    await _database.transaction((transaction) async {
      await transaction.insert('notes', _noteMap(persisted, cover: null));
      await _insertOwnedRows(transaction, persisted);
      await _writeCover(transaction, persisted);
    });
    return persisted;
  }

  Future<Note> update(Note note) async {
    if (note.revision < 1) {
      throw ArgumentError.value(note.revision, 'revision', 'Must be persisted');
    }
    final persisted = note.copyWith(revision: note.revision + 1);
    await _database.transaction((transaction) async {
      final changed = await transaction.update(
        'notes',
        _noteMap(persisted, cover: null),
        where: 'id = ? AND revision = ?',
        whereArgs: [note.id.value, note.revision],
      );
      if (changed != 1) throw NoteWriteConflict(note.id);
      await transaction.delete(
        'note_assets',
        where: 'note_id = ?',
        whereArgs: [note.id.value],
      );
      await transaction.delete(
        'note_tags',
        where: 'note_id = ?',
        whereArgs: [note.id.value],
      );
      await _insertOwnedRows(transaction, persisted);
      await _writeCover(transaction, persisted);
    });
    return persisted;
  }

  Future<Note?> get(NoteId id) async {
    final rows = await _database.query(
      'notes',
      where: 'id = ?',
      whereArgs: [id.value],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (await _hydrate(rows)).single;
  }

  Future<List<Note>> list() async {
    final rows = await _database.query(
      'notes',
      orderBy: 'is_pinned DESC, updated_at DESC',
    );
    return _hydrate(rows);
  }

  Future<List<Note>> search(String query) async {
    final normalized = query.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return const [];
    List<Map<String, Object?>> rows;
    // Trigram FTS cannot match one- or two-rune CJK queries. Those are common
    // for note search, so route them through the exact LIKE fallback.
    if (_usesFts && normalized.runes.length >= 3) {
      final phrase = '"${normalized.replaceAll('"', '""')}"';
      try {
        rows = await _database.rawQuery(
          '''
          SELECT notes.*
          FROM note_search_fts
          JOIN notes ON notes.id = note_search_fts.note_id
          WHERE note_search_fts MATCH ?
          ORDER BY notes.is_pinned DESC, notes.updated_at DESC
          ''',
          [phrase],
        );
      } on DatabaseException {
        rows = await _searchWithLike(normalized);
      }
    } else {
      rows = await _searchWithLike(normalized);
    }
    return _hydrate(rows);
  }

  Future<void> deletePermanently(NoteId id) async {
    await _database.delete('notes', where: 'id = ?', whereArgs: [id.value]);
  }

  Future<List<Map<String, Object?>>> _searchWithLike(String query) =>
      _database.query(
        'notes',
        where: "search_text LIKE ? ESCAPE '\\'",
        whereArgs: ['%${_escapeLike(query)}%'],
        orderBy: 'is_pinned DESC, updated_at DESC',
      );

  Future<void> _createSearchIndex() async {
    try {
      await _database.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS note_search_fts USING fts5(
          note_id UNINDEXED,
          content,
          tokenize = 'trigram case_sensitive 0'
        )
      ''');
    } on DatabaseException {
      try {
        await _database.execute('''
          CREATE VIRTUAL TABLE IF NOT EXISTS note_search_fts USING fts5(
            note_id UNINDEXED,
            content,
            tokenize = 'unicode61 remove_diacritics 2'
          )
        ''');
      } on DatabaseException {
        await _database.execute('''
          CREATE TABLE IF NOT EXISTS note_search_fts (
            note_id TEXT PRIMARY KEY,
            content TEXT NOT NULL
          )
        ''');
      }
    }
    final table = await _database.rawQuery(
      "SELECT sql FROM sqlite_master WHERE name = 'note_search_fts'",
    );
    _usesFts =
        table.singleOrNull?['sql']?.toString().toUpperCase().contains(
          'VIRTUAL TABLE',
        ) ==
        true;
    for (final trigger in [
      'notes_search_insert',
      'notes_search_update',
      'notes_search_delete',
    ]) {
      await _database.execute('DROP TRIGGER IF EXISTS $trigger');
    }
    await _database.execute('''
      CREATE TRIGGER notes_search_insert AFTER INSERT ON notes BEGIN
        INSERT INTO note_search_fts(note_id, content)
        VALUES(NEW.id, NEW.search_text);
      END
    ''');
    await _database.execute('''
      CREATE TRIGGER notes_search_update AFTER UPDATE ON notes BEGIN
        DELETE FROM note_search_fts WHERE note_id = OLD.id;
        INSERT INTO note_search_fts(note_id, content)
        VALUES(NEW.id, NEW.search_text);
      END
    ''');
    await _database.execute('''
      CREATE TRIGGER notes_search_delete AFTER DELETE ON notes BEGIN
        DELETE FROM note_search_fts WHERE note_id = OLD.id;
      END
    ''');
    await _database.delete('note_search_fts');
    await _database.execute('''
      INSERT INTO note_search_fts(note_id, content)
      SELECT id, search_text FROM notes
    ''');
  }

  Future<void> _insertOwnedRows(DatabaseExecutor transaction, Note note) async {
    for (final asset in note.assets) {
      await transaction.insert('note_assets', _assetMap(note.id, asset));
    }
    for (var index = 0; index < note.tags.length; index++) {
      final tag = note.tags[index];
      await transaction.insert('note_tags', {
        'note_id': note.id.value,
        'position': index,
        'value': tag,
        'normalized_value': tag.toLowerCase(),
      });
    }
  }

  Future<void> _writeCover(DatabaseExecutor transaction, Note note) async {
    final cover = note.coverAttachmentId;
    if (cover == null) return;
    await transaction.update(
      'notes',
      {'cover_attachment_id': cover.value},
      where: 'id = ?',
      whereArgs: [note.id.value],
    );
  }

  Future<List<Note>> _hydrate(List<Map<String, Object?>> noteRows) async {
    if (noteRows.isEmpty) return const [];
    final ids = noteRows.map((row) => row['id']! as String).toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    final assetRows = await _database.rawQuery(
      'SELECT * FROM note_assets WHERE note_id IN ($placeholders) '
      'ORDER BY created_at, id',
      ids,
    );
    final tagRows = await _database.rawQuery(
      'SELECT * FROM note_tags WHERE note_id IN ($placeholders) '
      'ORDER BY position',
      ids,
    );
    final assetsByNote = <String, List<NoteAsset>>{};
    for (final row in assetRows) {
      assetsByNote
          .putIfAbsent(row['note_id']! as String, () => [])
          .add(_assetFromMap(row));
    }
    final tagsByNote = <String, List<String>>{};
    for (final row in tagRows) {
      tagsByNote
          .putIfAbsent(row['note_id']! as String, () => [])
          .add(row['value']! as String);
    }
    return [
      for (final row in noteRows)
        _noteFromMap(
          row,
          assetsByNote[row['id']] ?? const [],
          tagsByNote[row['id']] ?? const [],
        ),
    ];
  }

  static Map<String, Object?> _noteMap(Note note, {NoteAttachmentId? cover}) =>
      {
        'id': note.id.value,
        'title': note.title,
        'document_json': note.document.toJsonString(),
        'search_text': note.searchText,
        'is_pinned': note.isPinned ? 1 : 0,
        'cover_attachment_id': cover?.value,
        'revision': note.revision,
        'created_at': note.createdAt.millisecondsSinceEpoch,
        'updated_at': note.updatedAt.millisecondsSinceEpoch,
      };

  static Map<String, Object?> _assetMap(NoteId noteId, NoteAsset asset) => {
    'id': asset.id.value,
    'note_id': noteId.value,
    'kind': asset.kind.name,
    'storage_key': asset.storageKey,
    'original_name': asset.originalName,
    'display_name': asset.displayName,
    'byte_length': asset.byteLength,
    'mime_type': asset.mimeType,
    'preview_storage_key': asset.previewStorageKey,
    'duration_ms': asset.durationMs,
    'ocr_text': asset.ocrText,
    'transcript': asset.transcript,
    'transcription_engine': asset.transcriptionEngine,
    'transcribed_at': asset.transcribedAt?.toUtc().millisecondsSinceEpoch,
    'created_at': asset.createdAt.millisecondsSinceEpoch,
    'updated_at': asset.updatedAt.millisecondsSinceEpoch,
  };

  static Note _noteFromMap(
    Map<String, Object?> map,
    List<NoteAsset> assets,
    List<String> tags,
  ) => Note(
    id: NoteId.parse(map['id']! as String),
    title: map['title']! as String,
    document: NoteDocument.fromJsonString(map['document_json']! as String),
    tags: tags,
    isPinned: map['is_pinned'] == 1,
    coverAttachmentId: map['cover_attachment_id'] == null
        ? null
        : NoteAttachmentId.parse(map['cover_attachment_id']! as String),
    assets: assets,
    revision: map['revision']! as int,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      map['created_at']! as int,
      isUtc: true,
    ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      map['updated_at']! as int,
      isUtc: true,
    ),
  );

  static NoteAsset _assetFromMap(Map<String, Object?> map) => NoteAsset(
    id: NoteAttachmentId.parse(map['id']! as String),
    kind: NoteAssetKind.values.byName(map['kind']! as String),
    storageKey: map['storage_key']! as String,
    originalName: map['original_name']! as String,
    displayName: map['display_name'] as String?,
    byteLength: map['byte_length']! as int,
    mimeType: map['mime_type']! as String,
    previewStorageKey: map['preview_storage_key'] as String?,
    durationMs: map['duration_ms'] as int?,
    ocrText: map['ocr_text'] as String?,
    transcript: map['transcript'] as String?,
    transcriptionEngine: map['transcription_engine'] as String?,
    transcribedAt: map['transcribed_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            map['transcribed_at']! as int,
            isUtc: true,
          ),
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      map['created_at']! as int,
      isUtc: true,
    ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      map['updated_at']! as int,
      isUtc: true,
    ),
  );

  static String _escapeLike(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');
}
