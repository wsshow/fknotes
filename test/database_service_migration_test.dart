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
          content TEXT
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
        containsAll(['transcript', 'transcription_model', 'transcribed_at']),
      );
    },
  );
}
