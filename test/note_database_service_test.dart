import 'dart:io';

import 'package:fknotes/models/note.dart';
import 'package:fknotes/services/file_storage_service.dart';
import 'package:fknotes/services/note_database_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory directory;
  late NoteDatabaseService service;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fknotes_quill_db_');
    await FileStorageService.instance.init(baseDir: directory.path);
    service = NoteDatabaseService(
      databasePath: p.join(
        directory.path,
        NoteDatabaseService.databaseFileName,
      ),
    );
  });

  tearDown(() async {
    await service.close();
    await directory.delete(recursive: true);
  });

  test('creates the single canonical Delta database', () async {
    final repository = await service.repository;
    final created = await repository.create(
      Note.newDraft(now: DateTime.utc(2026, 7, 23)),
    );

    expect((await repository.get(created.id))?.document, created.document);
    expect(
      await File(
        p.join(directory.path, NoteDatabaseService.databaseFileName),
      ).exists(),
      isTrue,
    );
    expect(
      await File(p.join(directory.path, 'fknotes-quill.db')).exists(),
      isFalse,
    );
  });

  test(
    'has only the canonical note body and stable attachment schema',
    () async {
      final database = await service.database;
      await service.repository;

      final noteColumns = (await database.rawQuery(
        'PRAGMA table_info(notes)',
      )).map((row) => row['name']).toSet();
      final assetColumns = (await database.rawQuery(
        'PRAGMA table_info(note_assets)',
      )).map((row) => row['name']).toSet();

      expect(noteColumns, containsAll(['id', 'document_json', 'revision']));
      expect(noteColumns, isNot(contains('content')));
      expect(noteColumns, isNot(contains('rich_content')));
      expect(assetColumns, containsAll(['id', 'note_id', 'storage_key']));
      expect(assetColumns, isNot(contains('file_path')));
    },
  );

  test('validates Delta envelopes and managed attachment files', () async {
    await service.repository;

    await expectLater(service.validate(), completes);
  });
}
