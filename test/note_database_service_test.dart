import 'dart:io';

import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/services/file_storage_service.dart';
import 'package:fknotes/services/note_database_service.dart';
import 'package:fknotes/services/note_repository.dart';
import 'package:flutter_quill/quill_delta.dart';
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
    expect(
      (await (await service.database).rawQuery(
        'PRAGMA journal_mode',
      )).single.values.single,
      'wal',
    );
  });

  test(
    'shares one repository initialization across concurrent callers',
    () async {
      final repositories = await Future.wait(
        List.generate(12, (_) => service.repository),
      );

      expect(repositories.toSet(), hasLength(1));
      expect(await service.repository, same(repositories.first));
    },
  );

  test('upgrades the legacy v1 note table without losing its graph', () async {
    final databasePath = p.join(
      directory.path,
      NoteDatabaseService.databaseFileName,
    );
    final noteId = NoteId.parse('be0afe23-f682-4d98-a942-e6e010a45d07');
    final assetId = NoteAttachmentId.parse(
      '3d2be3d5-00c8-4f5c-8e69-e90085dc2873',
    );
    final document = NoteDocument.fromDelta(
      Delta()
        ..insert('迁移正文\n')
        ..insert(NoteEmbed.attachment(assetId).toDeltaData())
        ..insert('\n'),
    );
    final legacy = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        singleInstance: false,
        onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
        onCreate: (database, _) => _createLegacyV1Schema(database),
      ),
    );
    await legacy.transaction((transaction) async {
      await transaction.insert('notes', {
        'id': noteId.value,
        'title': '保留旧笔记',
        'document_json': document.toJsonString(),
        'search_text': '保留旧笔记 迁移正文 旧标签 迁移图片',
        'status': 'active',
        'is_favorite': 1,
        'is_pinned': 1,
        'cover_attachment_id': null,
        'revision': 4,
        'created_at': DateTime.utc(2026, 7, 22).millisecondsSinceEpoch,
        'updated_at': DateTime.utc(2026, 7, 23).millisecondsSinceEpoch,
        'trashed_at': null,
      });
      await transaction.insert('note_assets', {
        'id': assetId.value,
        'note_id': noteId.value,
        'kind': 'image',
        'storage_key': 'notes/images/legacy.png',
        'original_name': '迁移图片.png',
        'display_name': null,
        'byte_length': 3,
        'mime_type': 'image/png',
        'preview_storage_key': 'notes/thumbnails/legacy.jpg',
        'duration_ms': null,
        'ocr_text': null,
        'transcript': null,
        'transcription_engine': null,
        'transcribed_at': null,
        'created_at': DateTime.utc(2026, 7, 22).millisecondsSinceEpoch,
        'updated_at': DateTime.utc(2026, 7, 23).millisecondsSinceEpoch,
      });
      await transaction.insert('note_tags', {
        'note_id': noteId.value,
        'position': 0,
        'value': '旧标签',
        'normalized_value': '旧标签',
      });
      await transaction.update(
        'notes',
        {'cover_attachment_id': assetId.value},
        where: 'id = ?',
        whereArgs: [noteId.value],
      );
    });
    await legacy.close();

    final repository = await service.repository;
    final migrated = await repository.get(noteId);
    final database = await service.database;
    final noteColumns = (await database.rawQuery(
      'PRAGMA table_info(notes)',
    )).map((row) => row['name']).toSet();

    expect(
      (await database.rawQuery('PRAGMA user_version')).single.values.single,
      NoteDatabaseService.schemaVersion,
    );
    expect(
      noteColumns,
      isNot(containsAll(['status', 'is_favorite', 'trashed_at'])),
    );
    expect(migrated?.title, '保留旧笔记');
    expect(migrated?.revision, 4);
    expect(migrated?.isPinned, isTrue);
    expect(migrated?.tags, ['旧标签']);
    expect(migrated?.assets.single.id, assetId);
    expect(migrated?.coverAttachmentId, assetId);
    expect(migrated?.document, document);
    expect((await repository.search('迁移正文')).single.id, noteId);

    final fresh = await repository.create(
      Note.newDraft(now: DateTime.utc(2026, 7, 24)).copyWith(title: '升级后新笔记'),
    );
    expect(fresh.revision, 1);
  });

  test(
    'accepts the already canonical v1 table during the v2 upgrade',
    () async {
      final databasePath = p.join(
        directory.path,
        NoteDatabaseService.databaseFileName,
      );
      final versionOne = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 1,
          singleInstance: false,
          onConfigure: (database) =>
              database.execute('PRAGMA foreign_keys = ON'),
          onCreate: (database, _) => NoteRepository(database).initialize(),
        ),
      );
      final original = await NoteRepository(versionOne).create(
        Note.newDraft(now: DateTime.utc(2026, 7, 23)).copyWith(title: '已经是新结构'),
      );
      await versionOne.close();

      final repository = await service.repository;

      expect((await repository.get(original.id))?.title, '已经是新结构');
      expect(
        (await (await service.database).rawQuery(
          'PRAGMA user_version',
        )).single.values.single,
        NoteDatabaseService.schemaVersion,
      );
    },
  );

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

  test('rejects a database asset that escapes its kind directory', () async {
    final now = DateTime.utc(2026, 7, 23);
    final assetId = NoteAttachmentId.parse(
      '3d2be3d5-00c8-4f5c-8e69-e90085dc2873',
    );
    const storageKey = 'notes/images/asset.png';
    await File(
      FileStorageService.instance.absolutePath(storageKey),
    ).writeAsBytes([1, 2, 3]);
    final repository = await service.repository;
    await repository.create(
      Note(
        id: NoteId.parse('be0afe23-f682-4d98-a942-e6e010a45d07'),
        title: '图片',
        document: NoteDocument.fromDelta(
          Delta()
            ..insert(NoteEmbed.attachment(assetId).toDeltaData())
            ..insert('\n'),
        ),
        assets: [
          NoteAsset(
            id: assetId,
            kind: NoteAssetKind.image,
            storageKey: storageKey,
            originalName: 'asset.png',
            byteLength: 3,
            mimeType: 'image/png',
            createdAt: now,
            updatedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      ),
    );
    await (await service.database).update('note_assets', {
      'storage_key': 'notes/files/wrong-kind.png',
    });

    await expectLater(service.validate(), throwsFormatException);
  });
}

Future<void> _createLegacyV1Schema(Database database) async {
  await database.execute('''
    CREATE TABLE notes (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      document_json TEXT NOT NULL,
      search_text TEXT NOT NULL,
      status TEXT NOT NULL CHECK(status IN ('active', 'archived', 'trashed')),
      is_favorite INTEGER NOT NULL CHECK(is_favorite IN (0, 1)),
      is_pinned INTEGER NOT NULL CHECK(is_pinned IN (0, 1)),
      cover_attachment_id TEXT,
      revision INTEGER NOT NULL CHECK(revision > 0),
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      trashed_at INTEGER,
      CHECK(
        (status = 'trashed' AND trashed_at IS NOT NULL) OR
        (status != 'trashed' AND trashed_at IS NULL)
      ),
      FOREIGN KEY(cover_attachment_id) REFERENCES note_assets(id)
        ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED
    )
  ''');
  await database.execute('''
    CREATE TABLE note_assets (
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
  await database.execute('''
    CREATE TABLE note_tags (
      note_id TEXT NOT NULL,
      position INTEGER NOT NULL CHECK(position >= 0),
      value TEXT NOT NULL,
      normalized_value TEXT NOT NULL,
      PRIMARY KEY(note_id, normalized_value),
      UNIQUE(note_id, position),
      FOREIGN KEY(note_id) REFERENCES notes(id) ON DELETE CASCADE
    )
  ''');
}
