import 'package:sqflite/sqflite.dart';

import '../models/note_entry.dart';
import 'database_service.dart';

class NoteService {
  NoteService._();
  static final NoteService instance = NoteService._();

  Future<Database> get _db => DatabaseService.instance.database;

  Future<List<NoteEntry>> getAllEntries() async {
    final db = await _db;
    final maps = await db.query(
      'entries',
      orderBy: 'is_pinned DESC, updated_at DESC',
    );
    return _hydrate(db, maps);
  }

  Future<NoteEntry?> getEntry(int id) async {
    final db = await _db;
    final maps = await db.query('entries', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return (await _hydrate(db, maps)).first;
  }

  Future<int> insertEntry(NoteEntry entry) async {
    final db = await _db;
    return db.transaction((txn) async {
      final id = await txn.insert('entries', entry.toMap());
      await _replaceAttachments(txn, id, entry.allAttachments);
      return id;
    });
  }

  Future<int> updateEntry(NoteEntry entry) async {
    final db = await _db;
    return db.transaction((txn) async {
      final count = await txn.update(
        'entries',
        entry.toMap(),
        where: 'id = ?',
        whereArgs: [entry.id],
      );
      if (entry.id != null) {
        await _replaceAttachments(txn, entry.id!, entry.allAttachments);
      }
      return count;
    });
  }

  Future<int> deleteEntry(int id) async {
    final db = await _db;
    return db.delete('entries', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<NoteEntry>> search(String query) => searchLike(query);

  Future<List<NoteEntry>> searchLike(String query) async {
    if (query.trim().isEmpty) return const [];
    final db = await _db;
    final like = '%${query.trim()}%';
    final maps = await db.rawQuery(
      '''
      SELECT DISTINCT e.*
      FROM entries e
      LEFT JOIN attachments a ON a.note_id = e.id
      WHERE e.is_deleted = 0 AND (
        e.title LIKE ? OR e.content LIKE ? OR e.ocr_text LIKE ? OR
        e.file_name LIKE ? OR e.tags LIKE ? OR a.ocr_text LIKE ? OR
        a.file_name LIKE ?
      )
      ORDER BY e.is_pinned DESC, e.updated_at DESC
      ''',
      [like, like, like, like, like, like, like],
    );
    return _hydrate(db, maps);
  }

  Future<List<NoteEntry>> _hydrate(
    DatabaseExecutor db,
    List<Map<String, Object?>> maps,
  ) async {
    if (maps.isEmpty) return const [];
    final ids = maps.map((map) => map['id'] as int).toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    final attachmentMaps = await db.rawQuery(
      'SELECT * FROM attachments WHERE note_id IN ($placeholders) ORDER BY note_id, sort_order, id',
      ids,
    );
    final byNote = <int, List<NoteAttachment>>{};
    for (final map in attachmentMaps) {
      final item = NoteAttachment.fromMap(map);
      byNote.putIfAbsent(item.noteId!, () => []).add(item);
    }
    return maps
        .map(
          (map) => NoteEntry.fromMap(
            map,
          ).copyWith(attachments: byNote[map['id'] as int] ?? const []),
        )
        .toList();
  }

  Future<void> _replaceAttachments(
    DatabaseExecutor db,
    int noteId,
    List<NoteAttachment> attachments,
  ) async {
    await db.delete('attachments', where: 'note_id = ?', whereArgs: [noteId]);
    for (var index = 0; index < attachments.length; index++) {
      final map =
          attachments[index]
              .copyWith(noteId: noteId, sortOrder: index)
              .toMap(parentId: noteId)
            ..remove('id');
      await db.insert('attachments', map);
    }
  }
}
