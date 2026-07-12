import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' hide XFile;

import 'database_service.dart';
import 'file_storage_service.dart';

class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  static const _manifestName = 'fknotes-backup.json';
  static const _backupFormatVersion = 1;
  static const _maxArchiveFiles = 100000;
  static const _maxExpandedBytes = 128 * 1024 * 1024 * 1024;
  static const _appLockPath = 'settings/app-lock.json';
  static const _cloudSyncSettingsPath = 'settings/cloud-sync.json';
  static const _recoveryRoot = 'recovery';

  static const _managedRoots = {
    'images',
    'audio',
    'video',
    'documents',
    'thumbnails',
    'exports',
    'assistant',
    'settings',
    _recoveryRoot,
    'fknotes.db',
    'fknotes.db-journal',
    'fknotes.db-shm',
    'fknotes.db-wal',
  };

  final _storage = FileStorageService.instance;

  Future<bool> exportBackup({Rect? sharePositionOrigin}) async {
    final artifact = await createBackupArtifact();
    final name = p.basename(artifact.file.path);
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(artifact.file.path, mimeType: 'application/zip', name: name),
        ],
        title: '保存非空笔记备份',
        subject: '非空笔记完整备份',
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
    return result.status != ShareResultStatus.dismissed;
  }

  /// Creates a verified snapshot containing user data only. Downloaded
  /// models, inference caches, app-lock state and cloud credentials are never
  /// included.
  Future<BackupArtifact> createBackupArtifact({
    Directory? outputDirectory,
  }) async {
    final now = DateTime.now();
    final name =
        'fknotes_${now.year}${_two(now.month)}${_two(now.day)}_'
        '${_two(now.hour)}${_two(now.minute)}${_two(now.second)}_'
        '${now.microsecondsSinceEpoch}.fknotes.zip';
    await DatabaseService.instance.close();
    try {
      final exportDir =
          outputDirectory ??
          Directory(
            p.join((await getTemporaryDirectory()).path, 'fknotes_exports'),
          );
      await exportDir.create(recursive: true);
      await _cleanupOldArtifacts(exportDir, now);
      final output = File(p.join(exportDir.path, name));
      final root = Directory(_storage.baseDir);
      final files = <({File file, String relative})>[];
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final relative = _safeName(
          p.posix.fromUri(p.toUri(p.relative(entity.path, from: root.path))),
        );
        if (_isIncludedBackupPath(relative)) {
          files.add((file: entity, relative: relative));
        }
      }
      files.sort((left, right) => left.relative.compareTo(right.relative));
      final encoder = ZipFileEncoder()..create(output.path);
      var encoderOpen = true;
      late String contentDigest;
      try {
        final manifestFiles = <String, Object?>{};
        for (final item in files) {
          final size = await item.file.length();
          final digest = await sha256.bind(item.file.openRead()).first;
          manifestFiles[item.relative] = {
            'size': size,
            'sha256': digest.toString(),
          };
          await encoder.addFile(item.file, item.relative);
        }
        contentDigest = sha256
            .convert(utf8.encode(jsonEncode(manifestFiles)))
            .toString();
        encoder.addArchiveFile(
          ArchiveFile.string(
            _manifestName,
            jsonEncode({
              'formatVersion': _backupFormatVersion,
              'createdAt': now.toUtc().toIso8601String(),
              'contentDigest': contentDigest,
              'files': manifestFiles,
            }),
          ),
        );
        await encoder.close();
        encoderOpen = false;
      } finally {
        if (encoderOpen) {
          try {
            await encoder.close();
          } catch (_) {
            // Preserve the original export failure.
          }
        }
      }
      final archiveDigest = await sha256.bind(output.openRead()).first;
      return BackupArtifact(
        file: output,
        contentDigest: contentDigest,
        archiveSha256: archiveDigest.toString(),
        sizeBytes: await output.length(),
        createdAt: now.toUtc(),
      );
    } finally {
      await DatabaseService.instance.database;
    }
  }

  Future<bool> restoreBackup() async {
    const group = XTypeGroup(label: 'FK Notes Backup', extensions: ['zip']);
    final selected = await openFile(acceptedTypeGroups: [group]);
    if (selected == null) return false;
    await restoreBackupFile(File(selected.path));
    return true;
  }

  Future<void> restoreBackupFile(File backup) async {
    if (!await backup.exists()) throw const FormatException('备份文件不存在');
    final input = InputFileStream(backup.path);
    late final Archive archive;
    try {
      archive = ZipDecoder().decodeStream(input, verify: true);
    } catch (_) {
      await input.close();
      rethrow;
    }
    final entries = archive.where((entry) => entry.isFile).toList();
    if (entries.length > _maxArchiveFiles ||
        entries.fold<int>(0, (sum, entry) => sum + entry.size) >
            _maxExpandedBytes) {
      await input.close();
      throw const FormatException('备份文件数量或容量异常');
    }
    final names = entries.map((entry) => _safeName(entry.name)).toList();
    if (names.toSet().length != names.length) {
      await input.close();
      throw const FormatException('备份中包含重复路径');
    }
    final manifestIndex = names.indexOf(_manifestName);
    Map<String, Object?>? manifest;
    try {
      manifest = manifestIndex < 0
          ? null
          : _decodeManifest(entries[manifestIndex]);
    } catch (_) {
      await input.close();
      rethrow;
    }
    final files = <ArchiveFile>[];
    final fileNames = <String>[];
    for (var index = 0; index < entries.length; index++) {
      if (index == manifestIndex) continue;
      files.add(entries[index]);
      fileNames.add(names[index]);
    }
    if (!fileNames.contains('fknotes.db')) {
      await input.close();
      throw const FormatException('这不是有效的非空笔记备份');
    }
    if (fileNames.any((name) => !_isIncludedBackupPath(name))) {
      await input.close();
      throw const FormatException('备份中包含不属于非空笔记的数据');
    }

    await DatabaseService.instance.close();
    final root = Directory(_storage.baseDir);
    final previous = Directory('${root.path}.fknotes-previous');
    if (await previous.exists()) await previous.delete(recursive: true);
    await previous.create(recursive: true);
    var moveCompleted = false;
    try {
      await _moveManagedData(root, previous);
      moveCompleted = true;
      await root.create(recursive: true);
      for (var index = 0; index < files.length; index++) {
        final entry = files[index];
        final relative = fileNames[index];
        final output = File(p.join(root.path, relative));
        await output.parent.create(recursive: true);
        final stream = OutputFileStream(output.path);
        try {
          entry.writeContent(stream);
        } finally {
          stream.closeSync();
        }
      }
      await _preserveDeviceOnlySettings(previous, root);
      await _storage.init(baseDir: root.path);
      if (manifest != null) await _validateManifest(manifest, root, fileNames);
      await DatabaseService.instance.validateUserData();
      try {
        await previous.delete(recursive: true);
      } on FileSystemException {
        // The restored data is already validated; stale rollback data can be
        // removed on the next restore attempt.
      }
      return;
    } catch (_) {
      await DatabaseService.instance.close();
      if (moveCompleted) await _deleteManagedData(root);
      await _moveManagedData(previous, root);
      if (await previous.exists()) await previous.delete(recursive: true);
      await _storage.init(baseDir: root.path);
      await DatabaseService.instance.database;
      rethrow;
    } finally {
      await input.close();
    }
  }

  Map<String, Object?> _decodeManifest(ArchiveFile entry) {
    if (entry.size > 1024 * 1024) {
      throw const FormatException('备份清单异常');
    }
    final bytes = entry.readBytes();
    if (bytes == null) throw const FormatException('备份清单不完整');
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map || decoded['formatVersion'] != _backupFormatVersion) {
      throw const FormatException('不支持的备份版本');
    }
    return Map<String, Object?>.from(decoded);
  }

  Future<void> _validateManifest(
    Map<String, Object?> manifest,
    Directory root,
    List<String> fileNames,
  ) async {
    final rawFiles = manifest['files'];
    if (rawFiles is! Map ||
        rawFiles.length != fileNames.length ||
        !rawFiles.keys.toSet().containsAll(fileNames)) {
      throw const FormatException('备份清单与文件不匹配');
    }
    for (final relative in fileNames) {
      final metadata = rawFiles[relative];
      if (metadata is! Map) throw const FormatException('备份清单损坏');
      final file = File(p.join(root.path, relative));
      final expectedSize = metadata['size'];
      final expectedDigest = metadata['sha256'];
      if (expectedSize is! int ||
          expectedDigest is! String ||
          await file.length() != expectedSize ||
          (await sha256.bind(file.openRead()).first).toString() !=
              expectedDigest) {
        throw FormatException('备份文件校验失败：$relative');
      }
    }
  }

  Future<void> _preserveDeviceOnlySettings(
    Directory previous,
    Directory root,
  ) async {
    for (final relative in const [_appLockPath, _cloudSyncSettingsPath]) {
      final source = File(p.join(previous.path, relative));
      if (!await source.exists()) continue;
      final destination = File(p.join(root.path, relative));
      await destination.parent.create(recursive: true);
      await source.copy(destination.path);
    }
  }

  String _safeName(String value) {
    final normalized = p.posix.normalize(value.replaceAll('\\', '/'));
    if (p.posix.isAbsolute(normalized) ||
        normalized.startsWith('../') ||
        normalized == '..') {
      throw const FormatException('备份中包含不安全路径');
    }
    return normalized;
  }

  bool _isManagedPath(String relativePath) {
    final rootName = p.posix.split(relativePath).firstOrNull;
    return rootName != null && _managedRoots.contains(rootName);
  }

  bool _isIncludedBackupPath(String relativePath) =>
      !_isDeviceOnlySetting(relativePath) &&
      p.posix.split(relativePath).firstOrNull != _recoveryRoot &&
      _isManagedPath(relativePath);

  bool _isDeviceOnlySetting(String relativePath) =>
      relativePath == _appLockPath ||
      relativePath.startsWith('$_appLockPath.') ||
      relativePath == _cloudSyncSettingsPath ||
      relativePath.startsWith('$_cloudSyncSettingsPath.');

  Future<void> _moveManagedData(Directory source, Directory target) async {
    await target.create(recursive: true);
    for (final name in _managedRoots) {
      final sourcePath = p.join(source.path, name);
      final targetPath = p.join(target.path, name);
      switch (await FileSystemEntity.type(sourcePath, followLinks: false)) {
        case FileSystemEntityType.file:
          await File(sourcePath).rename(targetPath);
        case FileSystemEntityType.directory:
          await Directory(sourcePath).rename(targetPath);
        default:
          break;
      }
    }
  }

  Future<void> _deleteManagedData(Directory root) async {
    for (final name in _managedRoots) {
      final path = p.join(root.path, name);
      switch (await FileSystemEntity.type(path, followLinks: false)) {
        case FileSystemEntityType.file:
          await File(path).delete();
        case FileSystemEntityType.directory:
          await Directory(path).delete(recursive: true);
        default:
          break;
      }
    }
  }

  Future<void> _cleanupOldArtifacts(Directory directory, DateTime now) async {
    final cutoff = now.subtract(const Duration(days: 1));
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.fknotes.zip')) continue;
      try {
        if ((await entity.lastModified()).isBefore(cutoff)) {
          await entity.delete();
        }
      } on FileSystemException {
        // Temporary exports may still be held by a receiving system app.
      }
    }
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}

class BackupArtifact {
  final File file;
  final String contentDigest;
  final String archiveSha256;
  final int sizeBytes;
  final DateTime createdAt;

  const BackupArtifact({
    required this.file,
    required this.contentDigest,
    required this.archiveSha256,
    required this.sizeBytes,
    required this.createdAt,
  });
}
