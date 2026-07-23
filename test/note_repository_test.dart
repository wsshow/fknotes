import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/services/note_repository.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late NoteRepository repository;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        singleInstance: false,
        onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
      ),
    );
    repository = NoteRepository(database);
    await repository.initialize();
  });

  tearDown(() => database.close());

  test(
    'persists a complete Delta note graph without legacy body columns',
    () async {
      final fixture = _noteFixture();

      final created = await repository.create(fixture.note);
      final restored = await repository.get(created.id);

      expect(created.revision, 1);
      expect(restored?.revision, 1);
      expect(
        restored?.document.toDelta().toJson(),
        fixture.note.document.toDelta().toJson(),
      );
      expect(restored?.assets.single.id, fixture.asset.id);
      expect(restored?.coverAttachmentId, fixture.asset.id);
      expect(restored?.tags, ['设计', '离线']);
      expect(restored?.contentProjection.plainText, '正文\n【原图.png】');

      final columns = await database.rawQuery('PRAGMA table_info(notes)');
      final names = columns.map((row) => row['name']).toSet();
      expect(names, containsAll(['document_json', 'search_text', 'revision']));
      expect(names, isNot(contains('content')));
      expect(names, isNot(contains('rich_content')));
      expect(names, isNot(contains('file_path')));
    },
  );

  test('searches projected text, tags and asset intelligence', () async {
    final created = await repository.create(_noteFixture().note);

    for (final query in ['正文', '设计', '原图', '手写会议纪要']) {
      expect((await repository.search(query)).map((note) => note.id), [
        created.id,
      ]);
    }
  });

  test('uses revisions to reject stale automatic saves', () async {
    final original = await repository.create(_noteFixture().note);
    final updated = await repository.update(
      original.copyWith(
        title: '新标题',
        updatedAt: original.updatedAt.add(const Duration(seconds: 1)),
      ),
    );

    expect(updated.revision, 2);
    expect((await repository.get(original.id))?.title, '新标题');
    await expectLater(
      repository.update(original.copyWith(title: '过期写入')),
      throwsA(isA<NoteWriteConflict>()),
    );
    expect((await repository.get(original.id))?.title, '新标题');
  });

  test(
    'keeps trashed notes out of search and cascades permanent deletion',
    () async {
      final original = await repository.create(_noteFixture().note);
      final trashed = await repository.update(
        original.copyWith(
          status: NoteStatus.trashed,
          trashedAt: original.updatedAt.add(const Duration(minutes: 1)),
          updatedAt: original.updatedAt.add(const Duration(minutes: 1)),
        ),
      );

      expect(await repository.search('正文'), isEmpty);
      expect(await repository.list(status: NoteStatus.trashed), hasLength(1));

      await repository.deletePermanently(trashed.id);
      expect(await repository.get(trashed.id), isNull);
      expect(await database.query('note_assets'), isEmpty);
      expect(await database.query('note_tags'), isEmpty);
    },
  );

  test('rejects missing and detached assets before persistence', () {
    final fixture = _noteFixture();

    expect(() => fixture.note.copyWith(assets: const []), throwsArgumentError);

    final detached = NoteAsset(
      id: NoteAttachmentId.generate(),
      kind: NoteAssetKind.file,
      storageKey: 'files/detached.pdf',
      originalName: 'detached.pdf',
      byteLength: 10,
      mimeType: 'application/pdf',
      createdAt: fixture.note.createdAt,
      updatedAt: fixture.note.updatedAt,
    );
    expect(
      () => fixture.note.copyWith(assets: [fixture.asset, detached]),
      throwsArgumentError,
    );
  });

  test('rejects absolute and traversing storage paths', () {
    final now = DateTime.utc(2026, 7, 23);

    for (final path in ['/data/image.png', '../image.png', 'C:/image.png']) {
      expect(
        () => NoteAsset(
          id: NoteAttachmentId.generate(),
          kind: NoteAssetKind.image,
          storageKey: path,
          originalName: 'image.png',
          byteLength: 1,
          mimeType: 'image/png',
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );
    }
  });
}

({Note note, NoteAsset asset}) _noteFixture() {
  final now = DateTime.utc(2026, 7, 23, 10);
  final attachmentId = NoteAttachmentId.parse(
    '3d2be3d5-00c8-4f5c-8e69-e90085dc2873',
  );
  final asset = NoteAsset(
    id: attachmentId,
    kind: NoteAssetKind.image,
    storageKey: 'images/3d2be3d5.png',
    originalName: '原图.png',
    byteLength: 2048,
    mimeType: 'image/png',
    previewStorageKey: 'previews/3d2be3d5.webp',
    ocrText: '手写会议纪要',
    createdAt: now,
    updatedAt: now,
  );
  final document = NoteDocument.fromDelta(
    Delta()
      ..insert('正文\n', {'header': 1})
      ..insert(NoteEmbed.attachment(attachmentId).toDeltaData())
      ..insert('\n'),
  );
  return (
    note: Note(
      id: NoteId.parse('be0afe23-f682-4d98-a942-e6e010a45d07'),
      title: '项目记录',
      document: document,
      tags: const ['设计', ' 离线 ', '设计'],
      coverAttachmentId: attachmentId,
      assets: [asset],
      createdAt: now,
      updatedAt: now,
    ),
    asset: asset,
  );
}
