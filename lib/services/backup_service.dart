import 'dart:collection';
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

import '../models/note_document.dart';
import 'file_storage_service.dart';
import 'note_database_service.dart';

/// Backup boundary for the clean Delta application.
///
/// A backup contains one canonical SQLite database and only the note assets
/// referenced by that database. Legacy databases, Markdown payloads, device
/// settings, models, chat data and broad storage directories are rejected.
final class BackupService {
  BackupService._();

  static final BackupService instance = BackupService._();

  static const _manifestName = 'fknotes-backup.json';
  static const _historyIndexName = 'index.json';
  static const _backupKind = 'fknotes.delta-backup';
  static const _backupFormatVersion = 2;
  static const _maxArchiveFiles = 50000;
  static const _maxExpandedBytes = 8 * 1024 * 1024 * 1024;
  static const _stagingName = '.fknotes-restore-staging';
  static const _rollbackName = '.fknotes-restore-rollback';
  static const _noteAssetDirectories = {
    'images',
    'thumbnails',
    'audio',
    'video',
    'files',
  };
  static const _databaseSidecars = {
    '${NoteDatabaseService.databaseFileName}-journal',
    '${NoteDatabaseService.databaseFileName}-shm',
    '${NoteDatabaseService.databaseFileName}-wal',
  };

  final _storage = FileStorageService.instance;
  static const _exportChannel = MethodChannel('fknotes/backup_export');
  var _operationInProgress = false;

  Directory get backupDirectory =>
      Directory(p.join(_storage.baseDir, 'backups'));

  File get _historyIndex =>
      File(p.join(backupDirectory.path, _historyIndexName));

  Future<bool> exportBackup({Rect? sharePositionOrigin}) async {
    final record = await createManagedBackup();
    return shareManagedBackup(record, sharePositionOrigin: sharePositionOrigin);
  }

  /// Resolves a restore transaction interrupted by process termination.
  ///
  /// This must run after file storage initialization and before any feature
  /// opens the note database.
  Future<void> recoverInterruptedRestore() => _exclusive(() async {
    final root = Directory(_storage.baseDir);
    final staging = Directory(p.join(root.path, _stagingName));
    final rollback = Directory(p.join(root.path, _rollbackName));
    if (!await rollback.exists()) {
      if (await staging.exists()) await staging.delete(recursive: true);
      return;
    }

    final liveDatabase = NoteDatabaseService.instance;
    var liveIsValid = false;
    final liveDatabaseFile = File(
      p.join(root.path, NoteDatabaseService.databaseFileName),
    );
    if (await liveDatabaseFile.exists()) {
      try {
        await liveDatabase.validate(assetRoot: root.path);
        liveIsValid = true;
      } catch (_) {
        await liveDatabase.close();
      }
    }

    if (liveIsValid) {
      await rollback.delete(recursive: true);
    } else {
      final rollbackDatabaseFile = File(
        p.join(rollback.path, NoteDatabaseService.databaseFileName),
      );
      if (!await rollbackDatabaseFile.exists()) {
        throw const FormatException('未完成的恢复事务缺少回滚数据库');
      }
      final rollbackDatabase = NoteDatabaseService(
        databasePath: rollbackDatabaseFile.path,
      );
      try {
        await rollbackDatabase.validate(assetRoot: rollback.path);
      } finally {
        await rollbackDatabase.close();
      }
      await liveDatabase.close();
      await _deleteManagedData(root);
      await _moveManagedData(rollback, root);
      await _storage.init(baseDir: root.path);
      await liveDatabase.validate(assetRoot: root.path);
      if (await rollback.exists()) await rollback.delete(recursive: true);
    }
    if (await staging.exists()) await staging.delete(recursive: true);
  });

  Future<BackupRecord> createManagedBackup({
    String? label,
    String? description,
  }) async {
    await backupDirectory.create(recursive: true);
    final artifact = await createBackupArtifact(
      outputDirectory: backupDirectory,
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
      if (decoded is! Map ||
          decoded['formatVersion'] != _backupFormatVersion ||
          decoded['records'] is! List) {
        return const [];
      }
      final records = <BackupRecord>[];
      for (final raw in decoded['records'] as List) {
        if (raw is! Map) continue;
        final record = BackupRecord.fromJson(Map<String, Object?>.from(raw));
        if (record.formatVersion != _backupFormatVersion ||
            !_isSafeBackupFileName(record.fileName)) {
          continue;
        }
        if (await managedBackupFile(record).exists()) records.add(record);
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

  Future<BackupArtifact> createBackupArtifact({
    Directory? outputDirectory,
    bool cleanTemporaryArtifacts = true,
    String? label,
    String? description,
  }) => _exclusive(() async {
    final now = DateTime.now();
    final outputName =
        'fknotes_${now.year}${_two(now.month)}${_two(now.day)}_'
        '${_two(now.hour)}${_two(now.minute)}${_two(now.second)}_'
        '${now.microsecondsSinceEpoch}.fknotes.zip';
    final liveDatabase = NoteDatabaseService.instance;
    await liveDatabase.repository;
    final database = await liveDatabase.database;
    await database.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    await liveDatabase.close();

    try {
      final databasePath = p.join(
        _storage.baseDir,
        NoteDatabaseService.databaseFileName,
      );
      final snapshotDatabase = NoteDatabaseService(databasePath: databasePath);
      late final _BackupGraph graph;
      try {
        await snapshotDatabase.validate(assetRoot: _storage.baseDir);
        graph = await _readBackupGraph(snapshotDatabase);
      } finally {
        await snapshotDatabase.close();
      }

      final exportDirectory =
          outputDirectory ??
          Directory(
            p.join((await getTemporaryDirectory()).path, 'fknotes_exports'),
          );
      await exportDirectory.create(recursive: true);
      if (cleanTemporaryArtifacts) {
        await _cleanupOldArtifacts(exportDirectory, now);
      }
      final output = File(p.join(exportDirectory.path, outputName));
      final files = <String, File>{
        NoteDatabaseService.databaseFileName: File(databasePath),
        for (final key in graph.assetKeys)
          key: File(_storage.absolutePath(key)),
      };
      final sortedNames = files.keys.toList()..sort();
      final manifestFiles = SplayTreeMap<String, Object?>();
      for (final name in sortedNames) {
        final file = files[name]!;
        manifestFiles[name] = {
          'size': await file.length(),
          'sha256': (await sha256.bind(file.openRead()).first).toString(),
        };
      }
      final contentDigest = _manifestFilesDigest(manifestFiles);
      final encoder = ZipFileEncoder()..create(output.path);
      var encoderOpen = true;
      try {
        for (final name in sortedNames) {
          await encoder.addFile(files[name]!, name);
        }
        encoder.addArchiveFile(
          ArchiveFile.string(
            _manifestName,
            jsonEncode({
              'kind': _backupKind,
              'formatVersion': _backupFormatVersion,
              'databaseSchemaVersion': NoteDatabaseService.schemaVersion,
              'documentSchemaVersion': NoteDocument.schemaVersion,
              'createdAt': now.toUtc().toIso8601String(),
              if (label?.trim().isNotEmpty == true) 'label': label!.trim(),
              if (description?.trim().isNotEmpty == true)
                'description': description!.trim(),
              'noteCount': graph.noteCount,
              'assetCount': graph.assetCount,
              'contentDigest': contentDigest,
              'files': manifestFiles,
            }),
          ),
        );
        await encoder.close();
        encoderOpen = false;
      } catch (_) {
        if (await output.exists()) await output.delete();
        rethrow;
      } finally {
        if (encoderOpen) {
          try {
            await encoder.close();
          } catch (_) {
            // Preserve the original snapshot error.
          }
        }
      }
      return BackupArtifact(
        file: output,
        contentDigest: contentDigest,
        archiveSha256: (await sha256.bind(output.openRead()).first).toString(),
        sizeBytes: await output.length(),
        createdAt: now.toUtc(),
      );
    } finally {
      await liveDatabase.repository;
    }
  });

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

  Future<void> restoreBackupFile(File backup) => _exclusive(() async {
    if (!await backup.exists()) throw const FormatException('备份文件不存在');
    final input = InputFileStream(backup.path);
    final root = Directory(_storage.baseDir);
    final staging = Directory(p.join(root.path, _stagingName));
    final rollback = Directory(p.join(root.path, _rollbackName));
    var swapStarted = false;
    var restoreCompleted = false;
    try {
      final Archive archive;
      try {
        archive = ZipDecoder().decodeStream(input, verify: true);
      } catch (_) {
        throw const FormatException('备份压缩包损坏');
      }
      final entries = archive.where((entry) => entry.isFile).toList();
      final expandedBytes = entries.fold<int>(
        0,
        (total, entry) => total + entry.size,
      );
      if (entries.length > _maxArchiveFiles ||
          expandedBytes > _maxExpandedBytes) {
        throw const FormatException('备份文件数量或容量异常');
      }
      final names = entries.map((entry) => _safeName(entry.name)).toList();
      if (names.toSet().length != names.length) {
        throw const FormatException('备份中包含重复路径');
      }
      final manifestIndexes = <int>[
        for (var index = 0; index < names.length; index++)
          if (names[index] == _manifestName) index,
      ];
      if (manifestIndexes.length != 1) {
        throw const FormatException('这不是新版非空笔记备份');
      }
      final manifestIndex = manifestIndexes.single;
      final manifest = _decodeManifest(entries[manifestIndex]);
      final files = <ArchiveFile>[];
      final fileNames = <String>[];
      for (var index = 0; index < entries.length; index++) {
        if (index == manifestIndex) continue;
        final name = names[index];
        if (!_isAllowedArchivePath(name)) {
          throw FormatException('备份包含新数据边界之外的内容：$name');
        }
        files.add(entries[index]);
        fileNames.add(name);
      }
      if (!fileNames.contains(NoteDatabaseService.databaseFileName)) {
        throw const FormatException('备份缺少笔记数据库');
      }

      await _resetInternalDirectory(staging);
      await _resetInternalDirectory(rollback);
      for (var index = 0; index < files.length; index++) {
        final output = File(
          p.joinAll([staging.path, ...p.posix.split(fileNames[index])]),
        );
        await output.parent.create(recursive: true);
        final stream = OutputFileStream(output.path);
        try {
          files[index].writeContent(stream);
        } finally {
          stream.closeSync();
        }
      }
      await _validateManifest(manifest, staging, fileNames);

      final stagedDatabase = NoteDatabaseService(
        databasePath: p.join(
          staging.path,
          NoteDatabaseService.databaseFileName,
        ),
      );
      late final _BackupGraph stagedGraph;
      try {
        await stagedDatabase.validate(assetRoot: staging.path);
        stagedGraph = await _readBackupGraph(stagedDatabase);
      } finally {
        await stagedDatabase.close();
      }
      final expectedNames = <String>{
        NoteDatabaseService.databaseFileName,
        ...stagedGraph.assetKeys,
      };
      if (!expectedNames.containsAll(fileNames) ||
          !fileNames.toSet().containsAll(expectedNames)) {
        throw const FormatException('备份附件与数据库引用不一致');
      }
      if (manifest['noteCount'] != stagedGraph.noteCount ||
          manifest['assetCount'] != stagedGraph.assetCount) {
        throw const FormatException('备份数据计数校验失败');
      }

      final liveDatabase = NoteDatabaseService.instance;
      await liveDatabase.close();
      await _moveManagedData(root, rollback);
      swapStarted = true;
      await _moveManagedData(staging, root);
      await _storage.init(baseDir: root.path);
      await liveDatabase.validate(assetRoot: root.path);
      await liveDatabase.repository;
      restoreCompleted = true;
      try {
        await rollback.delete(recursive: true);
      } on FileSystemException {
        // The restored graph is valid; stale rollback data is cleaned later.
      }
    } catch (error, stackTrace) {
      if (swapStarted) {
        try {
          final liveDatabase = NoteDatabaseService.instance;
          await liveDatabase.close();
          await _deleteManagedData(root);
          await _moveManagedData(rollback, root);
          await _storage.init(baseDir: root.path);
          await liveDatabase.validate(assetRoot: root.path);
          await liveDatabase.repository;
          swapStarted = false;
        } catch (rollbackError) {
          throw StateError('恢复失败且自动回滚未完成：$rollbackError');
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      await input.close();
      if (await staging.exists()) {
        try {
          await staging.delete(recursive: true);
        } on FileSystemException {
          // A decoder may release a file handle shortly after this operation.
        }
      }
      if ((restoreCompleted || !swapStarted) && await rollback.exists()) {
        try {
          await rollback.delete(recursive: true);
        } on FileSystemException {
          // Never let cleanup hide the restore result.
        }
      }
    }
  });

  Map<String, Object?> _decodeManifest(ArchiveFile entry) {
    if (entry.size > 1024 * 1024) {
      throw const FormatException('备份清单异常');
    }
    final bytes = entry.readBytes();
    if (bytes == null) throw const FormatException('备份清单不完整');
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map ||
        decoded['kind'] != _backupKind ||
        decoded['formatVersion'] != _backupFormatVersion ||
        decoded['databaseSchemaVersion'] != NoteDatabaseService.schemaVersion ||
        decoded['documentSchemaVersion'] != NoteDocument.schemaVersion ||
        DateTime.tryParse(decoded['createdAt']?.toString() ?? '') == null ||
        decoded['noteCount'] is! int ||
        decoded['assetCount'] is! int ||
        decoded['contentDigest'] is! String ||
        decoded['files'] is! Map) {
      throw const FormatException('不支持的备份格式或数据版本');
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
    final normalizedFiles = SplayTreeMap<String, Object?>();
    for (final relative in fileNames) {
      final metadata = rawFiles[relative];
      if (metadata is! Map) throw const FormatException('备份清单损坏');
      final expectedSize = metadata['size'];
      final expectedDigest = metadata['sha256'];
      if (expectedSize is! int || expectedDigest is! String) {
        throw const FormatException('备份清单损坏');
      }
      final file = File(p.joinAll([root.path, ...p.posix.split(relative)]));
      if (!await file.exists() ||
          await file.length() != expectedSize ||
          (await sha256.bind(file.openRead()).first).toString() !=
              expectedDigest) {
        throw FormatException('备份文件校验失败：$relative');
      }
      normalizedFiles[relative] = {
        'size': expectedSize,
        'sha256': expectedDigest,
      };
    }
    if (_manifestFilesDigest(normalizedFiles) != manifest['contentDigest']) {
      throw const FormatException('备份内容摘要校验失败');
    }
  }

  Future<_BackupGraph> _readBackupGraph(NoteDatabaseService service) async {
    final database = await service.database;
    final noteCount =
        (await database.rawQuery(
              'SELECT COUNT(*) AS count FROM notes',
            )).single['count']!
            as int;
    final rows = await database.query(
      'note_assets',
      columns: ['storage_key', 'preview_storage_key'],
    );
    final keys = <String>{};
    for (final row in rows) {
      for (final value in [row['storage_key'], row['preview_storage_key']]) {
        if (value == null) continue;
        final key = value as String;
        if (!_isCanonicalNoteAssetPath(key)) {
          throw FormatException('笔记附件不属于新数据空间：$key');
        }
        keys.add(key);
      }
    }
    final sortedKeys = keys.toList()..sort();
    return _BackupGraph(
      noteCount: noteCount,
      assetCount: rows.length,
      assetKeys: List.unmodifiable(sortedKeys),
    );
  }

  String _manifestFilesDigest(Map<String, Object?> files) => sha256
      .convert(utf8.encode(jsonEncode(SplayTreeMap<String, Object?>.of(files))))
      .toString();

  String _safeName(String value) {
    final normalized = p.posix.normalize(value.replaceAll('\\', '/'));
    if (normalized.isEmpty ||
        normalized == '.' ||
        p.posix.isAbsolute(normalized) ||
        normalized.startsWith('../') ||
        normalized == '..') {
      throw const FormatException('备份中包含不安全路径');
    }
    return normalized;
  }

  bool _isAllowedArchivePath(String value) =>
      value == NoteDatabaseService.databaseFileName ||
      _isCanonicalNoteAssetPath(value);

  bool _isCanonicalNoteAssetPath(String value) {
    final normalized = p.posix.normalize(value.replaceAll('\\', '/'));
    final parts = p.posix.split(normalized);
    return normalized == value &&
        parts.length >= 3 &&
        parts.first == 'notes' &&
        _noteAssetDirectories.contains(parts[1]) &&
        !parts.contains('..');
  }

  Future<void> _moveManagedData(Directory source, Directory target) async {
    await target.create(recursive: true);
    for (final name in {
      'notes',
      NoteDatabaseService.databaseFileName,
      ..._databaseSidecars,
    }) {
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
    for (final name in {
      'notes',
      NoteDatabaseService.databaseFileName,
      ..._databaseSidecars,
    }) {
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

  Future<void> _resetInternalDirectory(Directory directory) async {
    if (await directory.exists()) await directory.delete(recursive: true);
    await directory.create(recursive: true);
  }

  Future<T> _exclusive<T>(Future<T> Function() operation) async {
    if (_operationInProgress) {
      throw StateError('已有备份或恢复任务正在执行');
    }
    _operationInProgress = true;
    try {
      return await operation();
    } finally {
      _operationInProgress = false;
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
        'formatVersion': _backupFormatVersion,
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

final class _BackupGraph {
  const _BackupGraph({
    required this.noteCount,
    required this.assetCount,
    required this.assetKeys,
  });

  final int noteCount;
  final int assetCount;
  final List<String> assetKeys;
}

final class BackupRecord {
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

  final String fileName;
  final String label;
  final String description;
  final String contentDigest;
  final String archiveSha256;
  final int sizeBytes;
  final DateTime createdAt;
  final int formatVersion;

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

final class BackupArtifact {
  const BackupArtifact({
    required this.file,
    required this.contentDigest,
    required this.archiveSha256,
    required this.sizeBytes,
    required this.createdAt,
  });

  final File file;
  final String contentDigest;
  final String archiveSha256;
  final int sizeBytes;
  final DateTime createdAt;
}
