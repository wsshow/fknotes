import 'dart:io';

import 'package:fknotes/services/database_service.dart';
import 'package:fknotes/services/file_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory storageDirectory;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    storageDirectory = await Directory.systemTemp.createTemp(
      'fknotes_database_migration_test_',
    );
    await FileStorageService.instance.init(baseDir: storageDirectory.path);

    final legacy = await openDatabase(
      p.join(storageDirectory.path, 'fknotes.db'),
      version: 2,
      onCreate: (db, version) => db.execute('''
        CREATE TABLE entries (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          type TEXT NOT NULL DEFAULT 'text',
          title TEXT NOT NULL DEFAULT '',
          content TEXT,
          file_path TEXT,
          file_name TEXT,
          file_size INTEGER,
          mime_type TEXT,
          thumbnail_path TEXT,
          duration_ms INTEGER,
          ocr_text TEXT,
          tags TEXT NOT NULL DEFAULT '',
          is_favorite INTEGER NOT NULL DEFAULT 0,
          is_pinned INTEGER NOT NULL DEFAULT 0,
          is_archived INTEGER NOT NULL DEFAULT 0,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          deleted_at TEXT,
          created_at TEXT NOT NULL DEFAULT '2026-01-01T00:00:00.000',
          updated_at TEXT NOT NULL DEFAULT '2026-01-01T00:00:00.000'
        )
      '''),
    );
    await legacy.insert('entries', {'content': '旧笔记正文'});
    await legacy.close();
  });

  tearDownAll(() async {
    await DatabaseService.instance.close();
    await storageDirectory.delete(recursive: true);
  });

  test(
    'version 2 database gains rich_content without losing plain text',
    () async {
      final db = await DatabaseService.instance.database;
      final columns = await db.rawQuery('PRAGMA table_info(entries)');
      expect(columns.map((column) => column['name']), contains('rich_content'));
      final rows = await db.query('entries');
      expect(rows.single['content'], '旧笔记正文');
      expect(rows.single['rich_content'], isNull);
      final attachmentColumns = await db.rawQuery(
        'PRAGMA table_info(attachments)',
      );
      expect(
        attachmentColumns.map((column) => column['name']),
        containsAll([
          'transcript',
          'transcription_model',
          'transcribed_at',
          'display_name',
        ]),
      );
      final chatTables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      expect(
        chatTables.map((row) => row['name']),
        containsAll([
          'chat_sessions',
          'chat_messages',
          'chat_personas',
          'search_fts',
        ]),
      );
      final sessionColumns = await db.rawQuery(
        'PRAGMA table_info(chat_sessions)',
      );
      expect(
        sessionColumns.map((column) => column['name']),
        contains('persona_id'),
      );
      final messageColumns = await db.rawQuery(
        'PRAGMA table_info(chat_messages)',
      );
      expect(
        messageColumns.map((column) => column['name']),
        contains('attachments_json'),
      );
      final searchRows = await db.query(
        'search_fts',
        where: 'kind = ? AND body = ?',
        whereArgs: ['note', '旧笔记正文'],
      );
      expect(searchRows, hasLength(1));
    },
  );
}
