import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:fknotes/services/backup_service.dart';
import 'package:fknotes/services/database_service.dart';
import 'package:fknotes/services/file_storage_service.dart';
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
}
