import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/services/backup_service.dart';
import 'package:fknotes/services/file_storage_service.dart';
import 'package:fknotes/services/note_database_service.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory storage;
  late Directory exports;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await NoteDatabaseService.instance.close();
    storage = await Directory.systemTemp.createTemp('fknotes_backup_data');
    exports = await Directory.systemTemp.createTemp('fknotes_backup_export');
    await FileStorageService.instance.init(baseDir: storage.path);
    await NoteDatabaseService.instance.repository;
  });

  tearDown(() async {
    await NoteDatabaseService.instance.close();
    await storage.delete(recursive: true);
    await exports.delete(recursive: true);
  });

  test(
    'backup contains only the canonical Delta graph and restores it',
    () async {
      Future<void> write(String relative, List<int> bytes) async {
        final file = File(
          p.joinAll([storage.path, ...p.posix.split(relative)]),
        );
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes, flush: true);
      }

      final note = await _createRichNote(write: write);
      await write('notes/images/orphan.png', [9, 9, 9]);
      await write('images/legacy.png', [7]);
      await write('models/llm/model.bin', [6]);
      await write('settings/cloud-sync.json', utf8.encode('device-secret'));
      await write('recovery/draft.json', utf8.encode('temporary-draft'));

      final artifact = await BackupService.instance.createBackupArtifact(
        outputDirectory: exports,
      );
      final input = InputFileStream(artifact.file.path);
      final archive = ZipDecoder().decodeStream(input, verify: true);
      await input.close();
      final names = archive
          .where((entry) => entry.isFile)
          .map((entry) => entry.name)
          .toSet();

      expect(names, contains(NoteDatabaseService.databaseFileName));
      expect(names, contains('notes/images/editor.png'));
      expect(names, contains('notes/thumbnails/editor-preview.jpg'));
      expect(names, contains('fknotes-backup.json'));
      expect(names, isNot(contains('notes/images/orphan.png')));
      expect(names, isNot(contains('images/legacy.png')));
      expect(names, isNot(contains('models/llm/model.bin')));
      expect(names, isNot(contains('settings/cloud-sync.json')));
      expect(names, isNot(contains('recovery/draft.json')));

      final manifest =
          jsonDecode(
                utf8.decode(
                  archive
                      .firstWhere(
                        (entry) => entry.name == 'fknotes-backup.json',
                      )
                      .readBytes()!,
                ),
              )
              as Map<String, dynamic>;
      expect(manifest['kind'], 'fknotes.delta-backup');
      expect(manifest['formatVersion'], 2);
      expect(
        manifest['databaseSchemaVersion'],
        NoteDatabaseService.schemaVersion,
      );
      expect(manifest['documentSchemaVersion'], 1);
      expect(manifest['noteCount'], 1);
      expect(manifest['assetCount'], 1);
      expect(manifest['contentDigest'], artifact.contentDigest);
      expect(artifact.archiveSha256, hasLength(64));

      final repository = await NoteDatabaseService.instance.repository;
      final persisted = (await repository.get(note.id))!;
      await repository.update(
        persisted.copyWith(
          title: '已经覆盖的标题',
          updatedAt: DateTime.utc(2026, 7, 23, 19),
        ),
      );
      await write('notes/images/editor.png', [8, 8, 8, 8]);
      await write(
        'settings/cloud-sync.json',
        utf8.encode('current-device-secret'),
      );

      await BackupService.instance.restoreBackupFile(artifact.file);

      final restoredRepository = await NoteDatabaseService.instance.repository;
      final restored = await restoredRepository.get(note.id);
      expect(restored?.title, '重构数据契约');
      expect(restored?.tags, ['设计', 'Delta']);
      expect(
        restored?.document.toDelta().toJson(),
        note.document.toDelta().toJson(),
      );
      expect(restored?.contentProjection.plainText, '探索记录\n【编辑器截图】');
      expect(
        (await restoredRepository.search('探索')).map((item) => item.id),
        contains(note.id),
      );
      expect(
        await File(
          p.join(storage.path, 'notes/images/editor.png'),
        ).readAsBytes(),
        [1, 2, 3, 4],
      );
      expect(
        await File(
          p.join(storage.path, 'settings/cloud-sync.json'),
        ).readAsString(),
        'current-device-secret',
      );
      expect(
        await File(p.join(storage.path, 'images/legacy.png')).readAsBytes(),
        [7],
      );
    },
  );

  test('managed backups preserve multiple new-format versions', () async {
    final first = await BackupService.instance.createManagedBackup(
      label: '换机前',
      description: '包含最新项目资料',
    );
    final second = await BackupService.instance.createManagedBackup();

    final records = await BackupService.instance.listManagedBackups();
    expect(records, hasLength(2));
    expect(records.first.fileName, second.fileName);
    expect(records.last.label, '换机前');
    expect(records.last.description, '包含最新项目资料');
    expect(records.last.formatVersion, 2);
    expect(records.last.archiveSha256, hasLength(64));
    expect(records.last.contentDigest, hasLength(64));
    expect(records.last.sizeBytes, greaterThan(0));

    final input = InputFileStream(
      BackupService.instance.managedBackupFile(first).path,
    );
    final archive = ZipDecoder().decodeStream(input, verify: true);
    await input.close();
    final manifest =
        jsonDecode(
              utf8.decode(
                archive
                    .firstWhere((entry) => entry.name == 'fknotes-backup.json')
                    .readBytes()!,
              ),
            )
            as Map<String, dynamic>;
    expect(manifest['label'], '换机前');
    expect(manifest['description'], '包含最新项目资料');

    await BackupService.instance.deleteManagedBackup(first);
    expect(
      (await BackupService.instance.listManagedBackups()).map(
        (record) => record.fileName,
      ),
      [second.fileName],
    );
    expect(
      await BackupService.instance.managedBackupFile(first).exists(),
      isFalse,
    );
  });

  test(
    'strictly rejects a legacy backup without touching live notes',
    () async {
      final repository = await NoteDatabaseService.instance.repository;
      final live = await repository.create(
        Note(
          id: NoteId.generate(),
          title: '当前的新笔记',
          document: NoteDocument.fromPlainText('不会被旧备份覆盖'),
          createdAt: DateTime.utc(2026, 7, 23),
          updatedAt: DateTime.utc(2026, 7, 23),
        ),
      );
      final legacy = File(p.join(exports.path, 'legacy.fknotes.zip'));
      final encoder = ZipFileEncoder()..create(legacy.path);
      encoder.addArchiveFile(
        ArchiveFile.string('fknotes.db', 'legacy-database'),
      );
      encoder.addArchiveFile(
        ArchiveFile.string(
          'fknotes-backup.json',
          jsonEncode({'formatVersion': 1, 'files': <String, Object?>{}}),
        ),
      );
      await encoder.close();

      await expectLater(
        BackupService.instance.restoreBackupFile(legacy),
        throwsA(isA<FormatException>()),
      );
      expect((await repository.get(live.id))?.title, '当前的新笔记');
    },
  );

  test('rejects a tampered asset before replacing the live database', () async {
    Future<void> write(String relative, List<int> bytes) async {
      final file = File(p.joinAll([storage.path, ...p.posix.split(relative)]));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    }

    final original = await _createRichNote(write: write);
    final artifact = await BackupService.instance.createBackupArtifact(
      outputDirectory: exports,
    );
    final repository = await NoteDatabaseService.instance.repository;
    final current = (await repository.get(original.id))!;
    await repository.update(
      current.copyWith(
        title: '当前设备上的更新',
        updatedAt: DateTime.utc(2026, 7, 23, 20),
      ),
    );

    final input = InputFileStream(artifact.file.path);
    final archive = ZipDecoder().decodeStream(input, verify: true);
    final tampered = File(p.join(exports.path, 'tampered.fknotes.zip'));
    final encoder = ZipFileEncoder()..create(tampered.path);
    for (final entry in archive.where((item) => item.isFile)) {
      final bytes = entry.readBytes()!;
      final content = entry.name == 'notes/images/editor.png'
          ? <int>[0, 0, 0, 0]
          : bytes;
      encoder.addArchiveFile(ArchiveFile(entry.name, content.length, content));
    }
    await encoder.close();
    await input.close();

    await expectLater(
      BackupService.instance.restoreBackupFile(tampered),
      throwsA(isA<FormatException>()),
    );
    final untouched = await repository.get(original.id);
    expect(untouched?.title, '当前设备上的更新');
    expect(
      await File(p.join(storage.path, 'notes/images/editor.png')).readAsBytes(),
      [1, 2, 3, 4],
    );
  });

  test(
    'recovers a restore transaction interrupted before database swap',
    () async {
      final repository = await NoteDatabaseService.instance.repository;
      final note = await repository.create(
        Note(
          id: NoteId.generate(),
          title: '中断前的数据',
          document: NoteDocument.fromPlainText('必须自动恢复'),
          createdAt: DateTime.utc(2026, 7, 23),
          updatedAt: DateTime.utc(2026, 7, 23),
        ),
      );
      await NoteDatabaseService.instance.close();
      final rollback = Directory(
        p.join(storage.path, '.fknotes-restore-rollback'),
      );
      await rollback.create(recursive: true);
      await File(
        p.join(storage.path, NoteDatabaseService.databaseFileName),
      ).rename(p.join(rollback.path, NoteDatabaseService.databaseFileName));
      await Directory(
        p.join(storage.path, 'notes'),
      ).rename(p.join(rollback.path, 'notes'));
      final staging = Directory(
        p.join(storage.path, '.fknotes-restore-staging'),
      );
      await staging.create(recursive: true);
      await File(p.join(staging.path, 'partial')).writeAsString('incomplete');

      await BackupService.instance.recoverInterruptedRestore();

      final restoredRepository = await NoteDatabaseService.instance.repository;
      expect((await restoredRepository.get(note.id))?.title, '中断前的数据');
      expect(await rollback.exists(), isFalse);
      expect(await staging.exists(), isFalse);
    },
  );
}

Future<Note> _createRichNote({
  required Future<void> Function(String relative, List<int> bytes) write,
}) async {
  const storageKey = 'notes/images/editor.png';
  const previewKey = 'notes/thumbnails/editor-preview.jpg';
  await write(storageKey, [1, 2, 3, 4]);
  await write(previewKey, [5, 6]);
  final attachmentId = NoteAttachmentId.generate();
  final document = NoteDocument.fromDelta(
    Delta()
      ..insert('探索', {'bold': true})
      ..insert('记录\n')
      ..insert(NoteEmbed.attachment(attachmentId).toDeltaData())
      ..insert('\n'),
  );
  final timestamp = DateTime.utc(2026, 7, 23, 18);
  final note = Note(
    id: NoteId.generate(),
    title: '重构数据契约',
    document: document,
    tags: const ['设计', 'Delta'],
    assets: [
      NoteAsset(
        id: attachmentId,
        kind: NoteAssetKind.image,
        storageKey: storageKey,
        originalName: 'editor.png',
        displayName: '编辑器截图',
        byteLength: 4,
        mimeType: 'image/png',
        previewStorageKey: previewKey,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    ],
    coverAttachmentId: attachmentId,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
  return (await NoteDatabaseService.instance.repository).create(note);
}
