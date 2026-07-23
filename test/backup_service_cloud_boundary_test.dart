import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:fknotes/models/note_entry.dart';
import 'package:fknotes/services/backup_service.dart';
import 'package:fknotes/services/database_service.dart';
import 'package:fknotes/services/file_storage_service.dart';
import 'package:fknotes/services/note_service.dart';
import 'package:fknotes/services/search_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory storage;
  late Directory exports;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    storage = await Directory.systemTemp.createTemp('fknotes_backup_data');
    exports = await Directory.systemTemp.createTemp('fknotes_backup_export');
    await FileStorageService.instance.init(baseDir: storage.path);
    await DatabaseService.instance.database;
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    await storage.delete(recursive: true);
    await exports.delete(recursive: true);
  });

  test(
    'cloud-ready backup contains user data but no models or device secrets',
    () async {
      Future<void> write(String relative, String value) async {
        final file = File(p.join(storage.path, relative));
        await file.parent.create(recursive: true);
        await file.writeAsString(value);
      }

      await write('images/photo.jpg', 'user-image');
      await write('models/llm/model.bin', 'downloaded-model');
      await write('settings/cloud-sync.json', 'cloud-secret');
      await write('settings/cloud-sync.json.tmp', 'temporary-cloud-secret');
      await write('settings/app-lock.json', 'device-lock');
      await write('recovery/draft.json', 'temporary-draft');

      final artifact = await BackupService.instance.createBackupArtifact(
        outputDirectory: exports,
      );
      final input = InputFileStream(artifact.file.path);
      final archive = ZipDecoder().decodeStream(input, verify: true);
      await input.close();
      final names = archive
          .where((entry) => entry.isFile)
          .map((entry) => entry.name);

      expect(names, contains('fknotes.db'));
      expect(names, contains('images/photo.jpg'));
      expect(names, isNot(contains('models/llm/model.bin')));
      expect(names, isNot(contains('settings/cloud-sync.json')));
      expect(names, isNot(contains('settings/cloud-sync.json.tmp')));
      expect(names, isNot(contains('settings/app-lock.json')));
      expect(names, isNot(contains('recovery/draft.json')));

      final manifestEntry = archive.firstWhere(
        (entry) => entry.name == 'fknotes-backup.json',
      );
      final manifest =
          jsonDecode(utf8.decode(manifestEntry.readBytes()!))
              as Map<String, dynamic>;
      expect(manifest['contentDigest'], artifact.contentDigest);
      expect(artifact.archiveSha256, hasLength(64));

      await write('settings/cloud-sync.json', 'current-device-secret');
      await write('images/photo.jpg', 'changed-after-snapshot');
      await BackupService.instance.restoreBackupFile(artifact.file);
      expect(
        await File(
          p.join(storage.path, 'settings/cloud-sync.json'),
        ).readAsString(),
        'current-device-secret',
      );
      expect(
        await File(p.join(storage.path, 'images/photo.jpg')).readAsString(),
        'user-image',
      );
    },
  );

  test('managed backups preserve multiple versions and metadata', () async {
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
    expect(records.last.archiveSha256, hasLength(64));
    expect(records.last.contentDigest, hasLength(64));
    expect(records.last.sizeBytes, greaterThan(0));
    expect(
      await BackupService.instance.managedBackupFile(first).exists(),
      isTrue,
    );

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

  test('backup restores rich editor data and its search projection', () async {
    final now = DateTime(2026, 7, 22, 18);
    final image = File(p.join(storage.path, 'images/editor.png'));
    await image.parent.create(recursive: true);
    await image.writeAsBytes([1, 2, 3]);
    const richContent =
        '{"version":2,"blocks":[{"type":"paragraph","text":"探索记录","styles":[{"start":0,"end":2,"bold":true}]},{"type":"attachment","text":"","attachmentPath":"images/editor.png"}]}';
    final noteId = await NoteService.instance.insertEntry(
      NoteEntry(
        type: NoteType.image,
        title: '重构数据契约',
        content: '**探&#32034;**记录\n\n[[附件:images/editor.png]]',
        richContent: richContent,
        attachments: [
          NoteAttachment(
            type: NoteType.image,
            filePath: 'images/editor.png',
            fileName: 'editor.png',
            displayName: '编辑器截图',
            fileSize: 3,
            mimeType: 'image/png',
            createdAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      ),
    );
    final artifact = await BackupService.instance.createBackupArtifact(
      outputDirectory: exports,
    );
    final current = await NoteService.instance.getEntry(noteId);
    await NoteService.instance.updateEntry(
      current!.copyWith(
        content: '已经覆盖的内容',
        clearRichContent: true,
        updatedAt: now.add(const Duration(hours: 1)),
      ),
    );

    await BackupService.instance.restoreBackupFile(artifact.file);

    final restored = await NoteService.instance.getEntry(noteId);
    expect(restored?.content, '**探&#32034;**记录\n\n[[附件:images/editor.png]]');
    expect(restored?.richContent, richContent);
    expect(restored?.plainTextContent, '探索记录\n【附件：编辑器截图】');
    final results = await SearchService.instance.search('探索');
    expect(results.map((result) => result.note?.id), contains(noteId));
  });
}
