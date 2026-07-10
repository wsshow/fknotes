import 'dart:io';
import 'dart:ui';

import 'package:archive/archive_io.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' hide XFile;

import 'database_service.dart';
import 'file_storage_service.dart';

class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  static const _managedRoots = {
    'images',
    'audio',
    'video',
    'documents',
    'thumbnails',
    'exports',
    'fknotes.db',
    'fknotes.db-journal',
    'fknotes.db-shm',
    'fknotes.db-wal',
  };

  final _storage = FileStorageService.instance;

  Future<bool> exportBackup({Rect? sharePositionOrigin}) async {
    final now = DateTime.now();
    final name =
        'fknotes_${now.year}${_two(now.month)}${_two(now.day)}_${_two(now.hour)}${_two(now.minute)}.fknotes.zip';
    await DatabaseService.instance.close();
    try {
      final sourceArchive = createArchiveFromDirectory(
        Directory(_storage.baseDir),
        includeDirName: false,
      );
      final archive = Archive();
      for (final entry in sourceArchive) {
        // Empty folders can be recreated from file paths. Omitting directory
        // records also avoids non-standard zero-byte compressed entries.
        if (entry.isFile && _isManagedPath(_safeName(entry.name))) {
          archive.add(entry);
        }
      }
      final bytes = ZipEncoder().encode(archive);
      final exportDir = Directory(
        p.join((await getTemporaryDirectory()).path, 'fknotes_exports'),
      );
      if (await exportDir.exists()) await exportDir.delete(recursive: true);
      await exportDir.create(recursive: true);
      final output = File(p.join(exportDir.path, name));
      await output.writeAsBytes(bytes, flush: true);

      // Android does not implement file_selector's save-location API. The
      // native share sheet includes Files/Drive and works consistently across
      // Android and iOS without requesting broad storage permissions.
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(output.path, mimeType: 'application/zip', name: name)],
          title: '保存非空笔记备份',
          subject: '非空笔记完整备份',
          sharePositionOrigin: sharePositionOrigin,
        ),
      );
      return result.status != ShareResultStatus.dismissed;
    } finally {
      // Keep the app usable even while the generated ZIP remains in the
      // temporary directory for the receiving system app to consume.
      await DatabaseService.instance.database;
    }
  }

  Future<bool> restoreBackup() async {
    const group = XTypeGroup(label: 'FK Notes Backup', extensions: ['zip']);
    final selected = await openFile(acceptedTypeGroups: [group]);
    if (selected == null) return false;
    final archive = ZipDecoder().decodeBytes(
      await selected.readAsBytes(),
      verify: true,
    );
    final files = archive.where((entry) => entry.isFile).toList();
    final names = files.map((entry) => _safeName(entry.name)).toList();
    if (!names.contains('fknotes.db')) {
      throw const FormatException('这不是有效的非空笔记备份');
    }
    if (names.any((name) => !_isManagedPath(name))) {
      throw const FormatException('备份中包含不属于非空笔记的数据');
    }

    await DatabaseService.instance.close();
    final root = Directory(_storage.baseDir);
    final previous = Directory('${root.path}.fknotes-previous');
    if (await previous.exists()) await previous.delete(recursive: true);
    await previous.create(recursive: true);
    await _moveManagedData(root, previous);
    await root.create(recursive: true);
    try {
      for (var index = 0; index < files.length; index++) {
        final entry = files[index];
        final relative = names[index];
        final output = File(p.join(root.path, relative));
        await output.parent.create(recursive: true);
        final bytes = entry.readBytes();
        if (bytes == null) throw const FormatException('备份文件不完整');
        await output.writeAsBytes(bytes, flush: true);
      }
      await _storage.init();
      await previous.delete(recursive: true);
      return true;
    } catch (_) {
      await _deleteManagedData(root);
      await _moveManagedData(previous, root);
      if (await previous.exists()) await previous.delete(recursive: true);
      await _storage.init();
      rethrow;
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

  String _two(int value) => value.toString().padLeft(2, '0');
}
