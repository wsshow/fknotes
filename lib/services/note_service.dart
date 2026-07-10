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
        await _syncAttachments(txn, entry.id!, entry.allAttachments);
      }
      return count;
    });
  }

  /// Append one completed background import without rewriting every existing
  /// attachment row for the note.
  Future<NoteAttachment> insertAttachment(
    int noteId,
    NoteAttachment attachment,
  ) async {
    final db = await _db;
    return db.transaction((txn) async {
      final count =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM attachments WHERE note_id = ?',
              [noteId],
            ),
          ) ??
          0;
      final maxOrder = Sqflite.firstIntValue(
        await txn.rawQuery(
          'SELECT MAX(sort_order) FROM attachments WHERE note_id = ?',
          [noteId],
        ),
      );
      final persisted = attachment.copyWith(
        noteId: noteId,
        sortOrder: maxOrder == null ? 0 : maxOrder + 1,
      );
      final map = persisted.toMap(parentId: noteId)..remove('id');
      final id = await txn.insert('attachments', map);
      final entryUpdates = <String, Object?>{
        'updated_at': attachment.createdAt.toIso8601String(),
        if (count == 0) ...{
          'type': attachment.type.dbValue,
          'file_path': attachment.filePath,
          'file_name': attachment.fileName,
          'file_size': attachment.fileSize,
          'mime_type': attachment.mimeType,
          'thumbnail_path': attachment.thumbnailPath,
          'duration_ms': attachment.durationMs,
          'ocr_text': attachment.ocrText,
        },
      };
      await txn.update(
        'entries',
        entryUpdates,
        where: 'id = ?',
        whereArgs: [noteId],
      );
      return persisted.copyWith(id: id);
    });
  }

  Future<int> deleteEntry(int id) async {
    final db = await _db;
    return db.delete('entries', where: 'id = ?', whereArgs: [id]);
  }

  Future<NoteEntry?> updateAttachmentTranscript({
    required int noteId,
    required String filePath,
    required String transcript,
    required String model,
    required DateTime transcribedAt,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      final updated = await txn.update(
        'attachments',
        {
          'transcript': transcript,
          'transcription_model': model,
          'transcribed_at': transcribedAt.toIso8601String(),
        },
        where: 'note_id = ? AND file_path = ?',
        whereArgs: [noteId, filePath],
      );
      if (updated == 0) throw StateError('找不到需要转写的音频附件');
      await txn.update(
        'entries',
        {'updated_at': transcribedAt.toIso8601String()},
        where: 'id = ?',
        whereArgs: [noteId],
      );
    });
    return getEntry(noteId);
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
        a.transcript LIKE ? OR a.file_name LIKE ?
      )
      ORDER BY e.is_pinned DESC, e.updated_at DESC
      ''',
      [like, like, like, like, like, like, like, like],
    );
    return _hydrate(db, maps);
  }

  Future<List<NoteEntry>> _hydrate(
    DatabaseExecutor db,
    List<Map<String, Object?>> maps,
  ) async {
    if (maps.isEmpty) return <NoteEntry>[];
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

  Future<void> _syncAttachments(
    DatabaseExecutor db,
    int noteId,
    List<NoteAttachment> attachments,
  ) async {
    final existingMaps = await db.query(
      'attachments',
      where: 'note_id = ?',
      whereArgs: [noteId],
    );
    final existingByPath = {
      for (final map in existingMaps) map['file_path'] as String: map,
    };
    final incomingPaths = attachments.map((item) => item.filePath).toSet();
    for (final map in existingMaps) {
      if (!incomingPaths.contains(map['file_path'])) {
        await db.delete('attachments', where: 'id = ?', whereArgs: [map['id']]);
      }
    }
    for (var index = 0; index < attachments.length; index++) {
      final attachment = attachments[index].copyWith(
        noteId: noteId,
        sortOrder: index,
      );
      final map = attachment.toMap(parentId: noteId)..remove('id');
      final existing = existingByPath[attachment.filePath];
      if (existing == null) {
        await db.insert('attachments', map);
      } else {
        await db.update(
          'attachments',
          map,
          where: 'id = ?',
          whereArgs: [existing['id']],
        );
      }
    }
  }
}
