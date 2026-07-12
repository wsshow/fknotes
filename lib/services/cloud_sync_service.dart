import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/cloud_sync.dart';
import 'backup_service.dart';
import 'cloud_remote_storage.dart';
import 'cloud_sync_settings_service.dart';

typedef CloudRemoteStorageBuilder =
    CloudRemoteStorage Function(CloudSyncSettings settings);

abstract class CloudSyncBackupAdapter {
  Future<BackupArtifact> createArtifact();
  Future<void> restore(File backup);
}

class CloudSyncService {
  CloudSyncService({
    CloudSyncSettingsService? settingsService,
    CloudSyncBackupAdapter? backupAdapter,
    CloudRemoteStorageBuilder? remoteBuilder,
    Future<Directory> Function()? temporaryDirectoryProvider,
  }) : _settings = settingsService ?? CloudSyncSettingsService.instance,
       _backups = backupAdapter ?? const _DefaultCloudSyncBackupAdapter(),
       _remoteBuilder = remoteBuilder ?? CloudRemoteStorageFactory.create,
       _temporaryDirectoryProvider =
           temporaryDirectoryProvider ?? getTemporaryDirectory;

  static final CloudSyncService instance = CloudSyncService();

  static const _metadataKey = 'latest.json';

  final CloudSyncSettingsService _settings;
  final CloudSyncBackupAdapter _backups;
  final CloudRemoteStorageBuilder _remoteBuilder;
  final Future<Directory> Function() _temporaryDirectoryProvider;
  bool _busy = false;

  bool get busy => _busy;

  Future<CloudSyncSettings> loadSettings() => _settings.load();

  Future<CloudSyncSettings> saveConfiguration(
    CloudSyncSettings candidate,
  ) async {
    final problem = candidate.configurationProblem;
    if (problem != null) throw StateError(problem);
    final current = await _settings.load();
    final targetChanged =
        _targetIdentity(current) != _targetIdentity(candidate);
    final saved = candidate.copyWith(
      deviceId: current.deviceId,
      lastSyncedContentDigest: current.lastSyncedContentDigest,
      lastRemoteRevision: current.lastRemoteRevision,
      lastSyncedAt: current.lastSyncedAt,
      clearSyncState: targetChanged,
    );
    await _settings.save(saved);
    return saved;
  }

  Future<void> testConnection(CloudSyncSettings settings) async {
    final problem = settings.configurationProblem;
    if (problem != null) throw StateError(problem);
    final remote = _remoteBuilder(settings);
    try {
      await remote.testConnection();
    } finally {
      remote.close();
    }
  }

  Future<CloudSyncResult> synchronize() => _run(() async {
    final settings = await _configuredSettings();
    final remote = _remoteBuilder(settings);
    try {
      final local = await _backups.createArtifact();
      try {
        final cloud = await _readMetadata(remote);
        if (cloud == null) {
          final uploaded = await _upload(remote, settings, local);
          return CloudSyncResult(
            CloudSyncResultType.uploaded,
            remote: uploaded,
          );
        }
        if (cloud.contentDigest == local.contentDigest) {
          await _saveSyncState(settings, cloud);
          return CloudSyncResult(CloudSyncResultType.unchanged, remote: cloud);
        }

        final previousDigest = settings.lastSyncedContentDigest;
        final previousRevision = settings.lastRemoteRevision;
        if (previousDigest == null || previousRevision == null) {
          return CloudSyncResult(CloudSyncResultType.conflict, remote: cloud);
        }
        final localChanged = local.contentDigest != previousDigest;
        final remoteChanged = cloud.revision != previousRevision;
        if (!localChanged && remoteChanged) {
          await _downloadAndRestore(remote, settings, cloud);
          return CloudSyncResult(CloudSyncResultType.downloaded, remote: cloud);
        }
        if (localChanged && !remoteChanged) {
          final uploaded = await _upload(remote, settings, local);
          return CloudSyncResult(
            CloudSyncResultType.uploaded,
            remote: uploaded,
          );
        }
        return CloudSyncResult(CloudSyncResultType.conflict, remote: cloud);
      } finally {
        await _deleteArtifact(local);
      }
    } finally {
      remote.close();
    }
  });

  Future<CloudSyncResult> resolveConflict(
    CloudSyncConflictResolution resolution,
  ) => _run(() async {
    final settings = await _configuredSettings();
    final remote = _remoteBuilder(settings);
    try {
      switch (resolution) {
        case CloudSyncConflictResolution.keepLocal:
          final local = await _backups.createArtifact();
          try {
            final uploaded = await _upload(remote, settings, local);
            return CloudSyncResult(
              CloudSyncResultType.uploaded,
              remote: uploaded,
            );
          } finally {
            await _deleteArtifact(local);
          }
        case CloudSyncConflictResolution.useRemote:
          final cloud = await _readMetadata(remote);
          if (cloud == null) {
            throw const CloudStorageException('云端目前没有可恢复的数据');
          }
          await _downloadAndRestore(remote, settings, cloud);
          return CloudSyncResult(CloudSyncResultType.downloaded, remote: cloud);
      }
    } finally {
      remote.close();
    }
  });

  Future<T> _run<T>(Future<T> Function() operation) async {
    if (_busy) throw StateError('云同步任务正在进行');
    _busy = true;
    try {
      return await operation();
    } finally {
      _busy = false;
    }
  }

  Future<CloudSyncSettings> _configuredSettings() async {
    final settings = await _settings.load();
    final problem = settings.configurationProblem;
    if (problem != null) throw StateError(problem);
    return settings;
  }

  Future<CloudSnapshotMetadata?> _readMetadata(
    CloudRemoteStorage remote,
  ) async {
    final bytes = await remote.readBytes(_metadataKey);
    if (bytes == null) return null;
    try {
      return CloudSnapshotMetadata.fromJson(
        jsonDecode(utf8.decode(bytes, allowMalformed: false)),
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('云端同步清单损坏');
    }
  }

  Future<CloudSnapshotMetadata> _upload(
    CloudRemoteStorage remote,
    CloudSyncSettings settings,
    BackupArtifact artifact,
  ) async {
    final deviceLabel = settings.deviceId.length <= 8
        ? settings.deviceId
        : settings.deviceId.substring(0, 8);
    final revision =
        '${DateTime.now().toUtc().microsecondsSinceEpoch}-$deviceLabel';
    final metadata = CloudSnapshotMetadata(
      revision: revision,
      archiveKey: 'snapshots/$revision.fknotes.zip',
      deviceId: settings.deviceId,
      createdAt: artifact.createdAt,
      contentDigest: artifact.contentDigest,
      archiveSha256: artifact.archiveSha256,
      sizeBytes: artifact.sizeBytes,
    );
    final previous = await _readMetadata(remote);
    await remote.uploadFile(
      metadata.archiveKey,
      artifact.file,
      sha256Digest: artifact.archiveSha256,
    );
    await remote.uploadBytes(_metadataKey, utf8.encode(jsonEncode(metadata)));
    await _saveSyncState(settings, metadata);
    if (previous != null && previous.archiveKey != metadata.archiveKey) {
      try {
        await remote.delete(previous.archiveKey);
      } catch (_) {
        // The new pointer is already valid. A stale snapshot is safer than
        // failing a completed synchronization because cleanup was denied.
      }
    }
    return metadata;
  }

  Future<void> _downloadAndRestore(
    CloudRemoteStorage remote,
    CloudSyncSettings settings,
    CloudSnapshotMetadata metadata,
  ) async {
    const maxArchiveBytes = 128 * 1024 * 1024 * 1024;
    if (metadata.sizeBytes > maxArchiveBytes) {
      throw const FormatException('云端备份容量异常');
    }
    final temporaryRoot = Directory(
      p.join((await _temporaryDirectoryProvider()).path, 'fknotes_cloud_sync'),
    );
    await temporaryRoot.create(recursive: true);
    final downloaded = File(
      p.join(temporaryRoot.path, '${metadata.revision}.fknotes.zip'),
    );
    try {
      await remote.downloadFile(
        metadata.archiveKey,
        downloaded,
        expectedBytes: metadata.sizeBytes,
      );
      if (await downloaded.length() != metadata.sizeBytes) {
        throw const FormatException('云端备份大小与清单不一致');
      }
      final digest = await sha256.bind(downloaded.openRead()).first;
      if (digest.toString() != metadata.archiveSha256) {
        throw const FormatException('云端备份完整性校验失败');
      }
      await _backups.restore(downloaded);
      await _saveSyncState(settings, metadata);
    } finally {
      if (await downloaded.exists()) await downloaded.delete();
    }
  }

  Future<void> _saveSyncState(
    CloudSyncSettings settings,
    CloudSnapshotMetadata metadata,
  ) => _settings.save(
    settings.copyWith(
      lastSyncedContentDigest: metadata.contentDigest,
      lastRemoteRevision: metadata.revision,
      lastSyncedAt: DateTime.now().toUtc(),
    ),
  );

  Future<void> _deleteArtifact(BackupArtifact artifact) async {
    try {
      if (await artifact.file.exists()) await artifact.file.delete();
    } on FileSystemException {
      // The temporary directory cleanup can reclaim it later.
    }
  }

  String _targetIdentity(CloudSyncSettings settings) =>
      switch (settings.provider) {
        CloudSyncProvider.webDav => jsonEncode({
          'provider': 'webDav',
          'url': settings.webDav.serverUrl.trim(),
          'username': settings.webDav.username.trim(),
          'folder': settings.webDav.remoteFolder.trim(),
        }),
        CloudSyncProvider.s3 => jsonEncode({
          'provider': 's3',
          'endpoint': settings.s3.endpoint.trim(),
          'region': settings.s3.region.trim(),
          'bucket': settings.s3.bucket.trim(),
          'accessKey': settings.s3.accessKeyId.trim(),
          'prefix': settings.s3.prefix.trim(),
          'pathStyle': settings.s3.pathStyle,
        }),
      };
}

class _DefaultCloudSyncBackupAdapter implements CloudSyncBackupAdapter {
  const _DefaultCloudSyncBackupAdapter();

  @override
  Future<BackupArtifact> createArtifact() =>
      BackupService.instance.createBackupArtifact();

  @override
  Future<void> restore(File backup) =>
      BackupService.instance.restoreBackupFile(backup);
}
