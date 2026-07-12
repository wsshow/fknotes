import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fknotes/models/cloud_sync.dart';
import 'package:fknotes/services/backup_service.dart';
import 'package:fknotes/services/cloud_remote_storage.dart';
import 'package:fknotes/services/cloud_sync_service.dart';
import 'package:fknotes/services/cloud_sync_settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'manual sync uploads, downloads and detects two-sided conflicts',
    () async {
      final root = await Directory.systemTemp.createTemp('fknotes_cloud_sync');
      final settingsService = CloudSyncSettingsService(
        settingsPath: p.join(root.path, 'settings.json'),
      );
      final initialized = await settingsService.load();
      await settingsService.save(
        initialized.copyWith(
          webDav: const WebDavSyncConfig(
            serverUrl: 'https://dav.example.com',
            username: 'alice',
            password: 'secret',
          ),
        ),
      );
      final remote = _MemoryRemoteStorage();
      final backups = _FakeBackupAdapter(root);
      final service = CloudSyncService(
        settingsService: settingsService,
        backupAdapter: backups,
        remoteBuilder: (_) => remote,
        temporaryDirectoryProvider: () async => root,
      );
      try {
        backups.setLocal('local-1');
        expect(
          (await service.synchronize()).type,
          CloudSyncResultType.uploaded,
        );
        expect(remote.objects.keys, contains(startsWith('snapshots/')));

        expect(
          (await service.synchronize()).type,
          CloudSyncResultType.unchanged,
        );

        backups.setLocal('local-2');
        expect(
          (await service.synchronize()).type,
          CloudSyncResultType.uploaded,
        );

        final remoteBytes = utf8.encode('remote-3');
        final remoteDigest = _digest('remote-3');
        remote.putSnapshot(
          bytes: remoteBytes,
          metadata: _metadata(
            revision: 'remote-3',
            contentDigest: remoteDigest,
            bytes: remoteBytes,
          ),
        );
        backups.restoredDigests[utf8.decode(remoteBytes)] = remoteDigest;
        expect(
          (await service.synchronize()).type,
          CloudSyncResultType.downloaded,
        );
        expect(backups.restoreCount, 1);
        expect(backups.contentDigest, remoteDigest);

        backups.setLocal('local-4');
        final conflictBytes = utf8.encode('remote-5');
        final conflictDigest = _digest('remote-5');
        remote.putSnapshot(
          bytes: conflictBytes,
          metadata: _metadata(
            revision: 'remote-5',
            contentDigest: conflictDigest,
            bytes: conflictBytes,
          ),
        );
        final conflict = await service.synchronize();
        expect(conflict.type, CloudSyncResultType.conflict);
        expect(backups.restoreCount, 1);

        backups.restoredDigests[utf8.decode(conflictBytes)] = conflictDigest;
        final resolved = await service.resolveConflict(
          CloudSyncConflictResolution.useRemote,
        );
        expect(resolved.type, CloudSyncResultType.downloaded);
        expect(backups.restoreCount, 2);
        expect(backups.contentDigest, conflictDigest);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'changing the remote target clears only synchronization state',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'fknotes_cloud_target',
      );
      final settingsService = CloudSyncSettingsService(
        settingsPath: p.join(root.path, 'settings.json'),
      );
      final initial = (await settingsService.load()).copyWith(
        webDav: const WebDavSyncConfig(
          serverUrl: 'https://one.example.com/dav',
          username: 'alice',
          password: 'secret',
        ),
        lastSyncedContentDigest: _digest('old'),
        lastRemoteRevision: 'old-revision',
        lastSyncedAt: DateTime.utc(2026, 7, 12),
      );
      await settingsService.save(initial);
      final service = CloudSyncService(
        settingsService: settingsService,
        backupAdapter: _FakeBackupAdapter(root),
        remoteBuilder: (_) => _MemoryRemoteStorage(),
        temporaryDirectoryProvider: () async => root,
      );
      try {
        final changed = await service.saveConfiguration(
          initial.copyWith(
            webDav: const WebDavSyncConfig(
              serverUrl: 'https://two.example.com/dav',
              username: 'alice',
              password: 'secret',
            ),
          ),
        );
        expect(changed.lastSyncedContentDigest, isNull);
        expect(changed.lastRemoteRevision, isNull);
        expect(changed.webDav.password, 'secret');
        expect(changed.deviceId, initial.deviceId);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}

class _FakeBackupAdapter implements CloudSyncBackupAdapter {
  _FakeBackupAdapter(this.root);

  final Directory root;
  final Map<String, String> restoredDigests = {};
  late List<int> localBytes;
  late String contentDigest;
  int restoreCount = 0;

  void setLocal(String value) {
    localBytes = utf8.encode(value);
    contentDigest = _digest(value);
  }

  @override
  Future<BackupArtifact> createArtifact() async {
    final file = File(
      p.join(root.path, 'local-${DateTime.now().microsecondsSinceEpoch}.zip'),
    );
    await file.writeAsBytes(localBytes);
    return BackupArtifact(
      file: file,
      contentDigest: contentDigest,
      archiveSha256: sha256.convert(localBytes).toString(),
      sizeBytes: localBytes.length,
      createdAt: DateTime.utc(2026, 7, 12),
    );
  }

  @override
  Future<void> restore(File backup) async {
    final value = utf8.decode(await backup.readAsBytes());
    localBytes = utf8.encode(value);
    contentDigest = restoredDigests[value] ?? _digest(value);
    restoreCount++;
  }
}

class _MemoryRemoteStorage implements CloudRemoteStorage {
  final Map<String, List<int>> objects = {};

  void putSnapshot({
    required List<int> bytes,
    required CloudSnapshotMetadata metadata,
  }) {
    objects[metadata.archiveKey] = List.of(bytes);
    objects['latest.json'] = utf8.encode(jsonEncode(metadata));
  }

  @override
  Future<void> testConnection() async {}

  @override
  Future<Uint8List?> readBytes(String key) async {
    final value = objects[key];
    return value == null ? null : Uint8List.fromList(value);
  }

  @override
  Future<void> uploadBytes(String key, List<int> bytes) async {
    objects[key] = List.of(bytes);
  }

  @override
  Future<void> uploadFile(String key, File file, {String? sha256Digest}) async {
    objects[key] = await file.readAsBytes();
  }

  @override
  Future<void> downloadFile(
    String key,
    File destination, {
    int? expectedBytes,
  }) async {
    await destination.parent.create(recursive: true);
    await destination.writeAsBytes(objects[key]!);
  }

  @override
  Future<void> delete(String key) async {
    objects.remove(key);
  }

  @override
  void close() {}
}

CloudSnapshotMetadata _metadata({
  required String revision,
  required String contentDigest,
  required List<int> bytes,
}) => CloudSnapshotMetadata(
  revision: revision,
  archiveKey: 'snapshots/$revision.fknotes.zip',
  deviceId: 'other-device',
  createdAt: DateTime.utc(2026, 7, 12),
  contentDigest: contentDigest,
  archiveSha256: sha256.convert(bytes).toString(),
  sizeBytes: bytes.length,
);

String _digest(String value) => sha256.convert(utf8.encode(value)).toString();
