import 'dart:io';

import 'package:fknotes/models/cloud_sync.dart';
import 'package:fknotes/services/cloud_sync_settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('requires HTTPS for WebDAV and S3 credentials', () {
    const webDav = CloudSyncSettings(
      webDav: WebDavSyncConfig(
        serverUrl: 'http://nas.local/dav',
        username: 'alice',
        password: 'secret',
      ),
    );
    expect(webDav.configurationProblem, contains('HTTPS'));

    const s3 = CloudSyncSettings(
      provider: CloudSyncProvider.s3,
      s3: S3SyncConfig(
        endpoint: 'https://s3.example.com',
        region: 'cn-east-1',
        bucket: 'fknotes',
        accessKeyId: 'key',
        secretAccessKey: 'secret',
      ),
    );
    expect(s3.configured, isTrue);
    expect(
      s3
          .copyWith(
            s3: const S3SyncConfig(
              endpoint: 'https://s3.example.com',
              region: 'cn-east-1',
              bucket: 'fknotes',
              accessKeyId: 'key',
              secretAccessKey: 'secret',
              prefix: '../outside',
            ),
          )
          .configurationProblem,
      contains('前缀'),
    );
  });

  test(
    'stores credentials and stable device state in a device-only file',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'fknotes_cloud_config',
      );
      final path = p.join(root.path, 'cloud-sync.json');
      final service = CloudSyncSettingsService(settingsPath: path);
      try {
        final initialized = await service.load();
        expect(initialized.deviceId, isNotEmpty);
        final digest = List.filled(64, 'a').join();
        final saved = initialized.copyWith(
          provider: CloudSyncProvider.s3,
          s3: const S3SyncConfig(
            endpoint: 'https://s3.example.com',
            region: 'us-east-1',
            bucket: 'notes',
            accessKeyId: 'AKID',
            secretAccessKey: 'SECRET',
          ),
          lastSyncedContentDigest: digest,
          lastRemoteRevision: 'revision-1',
          lastSyncedAt: DateTime.utc(2026, 7, 12),
        );
        await service.save(saved);

        final restored = await service.load();
        expect(restored.deviceId, initialized.deviceId);
        expect(restored.s3.secretAccessKey, 'SECRET');
        expect(restored.lastSyncedContentDigest, digest);
        expect(restored.lastSyncedAt, DateTime.utc(2026, 7, 12));
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test('rejects unsafe cloud snapshot pointers', () {
    final digest = List.filled(64, 'a').join();
    expect(
      () => CloudSnapshotMetadata.fromJson({
        'formatVersion': 1,
        'revision': '../outside',
        'archiveKey': 'snapshots/safe.fknotes.zip',
        'deviceId': 'other',
        'createdAt': '2026-07-12T00:00:00Z',
        'contentDigest': digest,
        'archiveSha256': digest,
        'sizeBytes': 10,
      }),
      throwsFormatException,
    );
  });
}
