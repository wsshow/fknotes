import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' hide XFile;

import 'database_service.dart';
import 'file_storage_service.dart';

class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  static const _manifestName = 'fknotes-backup.json';
  static const _historyIndexName = 'index.json';
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
  static const _exportChannel = MethodChannel('fknotes/backup_export');

  Directory get backupDirectory =>
      Directory(p.join(_storage.baseDir, 'backups'));

  File get _historyIndex =>
      File(p.join(backupDirectory.path, _historyIndexName));

  Future<bool> exportBackup({Rect? sharePositionOrigin}) async {
    final record = await createManagedBackup();
    return shareManagedBackup(record, sharePositionOrigin: sharePositionOrigin);
  }

  Future<BackupRecord> createManagedBackup({
    String? label,
    String? description,
  }) async {
    final directory = backupDirectory;
    await directory.create(recursive: true);
    final artifact = await createBackupArtifact(
      outputDirectory: directory,
      cleanTemporaryArtifacts: false,
      label: label,
      description: description,
    );
    final normalizedLabel = label?.trim();
    final record = BackupRecord(
      fileName: p.basename(artifact.file.path),
      label: normalizedLabel == null || normalizedLabel.isEmpty
          ? _defaultLabel(artifact.createdAt.toLocal())
          : normalizedLabel,
      description: description?.trim() ?? '',
      contentDigest: artifact.contentDigest,
      archiveSha256: artifact.archiveSha256,
      sizeBytes: artifact.sizeBytes,
      createdAt: artifact.createdAt,
      formatVersion: _backupFormatVersion,
    );
    final records = await listManagedBackups();
    await _writeHistory([record, ...records]);
    return record;
  }

  Future<List<BackupRecord>> listManagedBackups() async {
    await backupDirectory.create(recursive: true);
    if (!await _historyIndex.exists()) return const [];
    try {
      final decoded = jsonDecode(await _historyIndex.readAsString());
      if (decoded is! Map || decoded['records'] is! List) return const [];
      final records = <BackupRecord>[];
      for (final raw in decoded['records'] as List) {
        if (raw is! Map) continue;
        final record = BackupRecord.fromJson(Map<String, Object?>.from(raw));
        if (!_isSafeBackupFileName(record.fileName)) continue;
        if (await File(
          p.join(backupDirectory.path, record.fileName),
        ).exists()) {
          records.add(record);
        }
      }
      records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return List.unmodifiable(records);
    } on FormatException {
      return const [];
    } on FileSystemException {
      return const [];
    }
  }

  Future<void> deleteManagedBackup(BackupRecord record) async {
    if (!_isSafeBackupFileName(record.fileName)) {
      throw const FormatException('备份文件名不安全');
    }
    final file = managedBackupFile(record);
    if (await file.exists()) await file.delete();
    final records = await listManagedBackups();
    await _writeHistory(
      records.where((item) => item.fileName != record.fileName).toList(),
    );
  }

  File managedBackupFile(BackupRecord record) {
    if (!_isSafeBackupFileName(record.fileName)) {
      throw const FormatException('备份文件名不安全');
    }
    return File(p.join(backupDirectory.path, record.fileName));
  }

  Future<bool> shareManagedBackup(
    BackupRecord record, {
    Rect? sharePositionOrigin,
  }) async {
    final file = managedBackupFile(record);
    if (!await file.exists()) throw const FormatException('备份文件不存在');
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(file.path, mimeType: 'application/zip', name: record.fileName),
        ],
        title: '保存非空笔记备份',
        subject: '非空笔记完整备份',
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
    return result.status != ShareResultStatus.dismissed;
  }

  Future<bool> saveManagedBackupCopy(BackupRecord record) async {
    final source = managedBackupFile(record);
    if (!await source.exists()) throw const FormatException('备份文件不存在');
    if (!kIsWeb && Platform.isAndroid) {
      return await _exportChannel.invokeMethod<bool>('saveFile', {
            'sourcePath': source.path,
            'suggestedName': record.fileName,
            'mimeType': 'application/zip',
          }) ??
          false;
    }
    const type = XTypeGroup(
      label: 'FKNotes Backup',
      extensions: ['zip'],
      mimeTypes: ['application/zip'],
    );
    final location = await getSaveLocation(
      acceptedTypeGroups: const [type],
      suggestedName: record.fileName,
    );
    if (location == null) return false;
    await XFile(
      source.path,
      mimeType: 'application/zip',
      name: record.fileName,
    ).saveTo(location.path);
    return true;
  }

  /// Creates a verified snapshot containing user data only. Downloaded
  /// models, inference caches, app-lock state and cloud credentials are never
  /// included.
  Future<BackupArtifact> createBackupArtifact({
    Directory? outputDirectory,
    bool cleanTemporaryArtifacts = true,
    String? label,
    String? description,
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
      if (cleanTemporaryArtifacts) {
        await _cleanupOldArtifacts(exportDir, now);
      }
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
              if (label?.trim().isNotEmpty == true) 'label': label!.trim(),
              if (description?.trim().isNotEmpty == true)
                'description': description!.trim(),
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
    final selected = await chooseBackupFile();
    if (selected == null) return false;
    await restoreBackupFile(selected);
    return true;
  }

  Future<File?> chooseBackupFile() async {
    const group = XTypeGroup(label: 'FK Notes Backup', extensions: ['zip']);
    final selected = await openFile(acceptedTypeGroups: [group]);
    return selected == null ? null : File(selected.path);
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

  Future<void> _writeHistory(List<BackupRecord> records) async {
    await backupDirectory.create(recursive: true);
    final temporary = File('${_historyIndex.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'formatVersion': 1,
        'records': records.map((record) => record.toJson()).toList(),
      }),
      flush: true,
    );
    try {
      await temporary.rename(_historyIndex.path);
    } on FileSystemException {
      if (await _historyIndex.exists()) await _historyIndex.delete();
      await temporary.rename(_historyIndex.path);
    }
  }

  bool _isSafeBackupFileName(String value) =>
      value == p.basename(value) &&
      value.endsWith('.fknotes.zip') &&
      value.isNotEmpty;

  String _defaultLabel(DateTime createdAt) =>
      'FKNotes ${createdAt.year}-${_two(createdAt.month)}-${_two(createdAt.day)} '
      '${_two(createdAt.hour)}:${_two(createdAt.minute)}';

  String _two(int value) => value.toString().padLeft(2, '0');
}

class BackupRecord {
  final String fileName;
  final String label;
  final String description;
  final String contentDigest;
  final String archiveSha256;
  final int sizeBytes;
  final DateTime createdAt;
  final int formatVersion;

  const BackupRecord({
    required this.fileName,
    required this.label,
    required this.description,
    required this.contentDigest,
    required this.archiveSha256,
    required this.sizeBytes,
    required this.createdAt,
    required this.formatVersion,
  });

  factory BackupRecord.fromJson(Map<String, Object?> json) {
    final fileName = json['fileName'];
    final label = json['label'];
    final description = json['description'];
    final contentDigest = json['contentDigest'];
    final archiveSha256 = json['archiveSha256'];
    final sizeBytes = json['sizeBytes'];
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    final formatVersion = json['formatVersion'];
    if (fileName is! String ||
        label is! String ||
        description is! String ||
        contentDigest is! String ||
        archiveSha256 is! String ||
        sizeBytes is! int ||
        createdAt == null ||
        formatVersion is! int) {
      throw const FormatException('备份历史记录损坏');
    }
    return BackupRecord(
      fileName: fileName,
      label: label,
      description: description,
      contentDigest: contentDigest,
      archiveSha256: archiveSha256,
      sizeBytes: sizeBytes,
      createdAt: createdAt.toUtc(),
      formatVersion: formatVersion,
    );
  }

  Map<String, Object?> toJson() => {
    'fileName': fileName,
    'label': label,
    'description': description,
    'contentDigest': contentDigest,
    'archiveSha256': archiveSha256,
    'sizeBytes': sizeBytes,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'formatVersion': formatVersion,
  };
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
