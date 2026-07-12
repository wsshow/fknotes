import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:image/image.dart' as img;

class FileStorageService {
  FileStorageService._();
  static final FileStorageService instance = FileStorageService._();

  final _uuid = const Uuid();
  late String _baseDir;

  String get baseDir => _baseDir;

  /// Initialize storage directories
  Future<void> init({String? baseDir}) async {
    final appDir = baseDir == null
        ? await getApplicationSupportDirectory()
        : Directory(baseDir);
    _baseDir = appDir.path;

    final dirs = [
      p.join(_baseDir, 'images'),
      p.join(_baseDir, 'audio'),
      p.join(_baseDir, 'video'),
      p.join(_baseDir, 'documents'),
      p.join(_baseDir, 'thumbnails'),
      p.join(_baseDir, 'exports'),
      p.join(_baseDir, 'assistant'),
      p.join(_baseDir, 'models', 'asr'),
      p.join(_baseDir, 'transcription_temp'),
    ];

    for (final dir in dirs) {
      await Directory(dir).create(recursive: true);
    }
    for (final folder in ['images', 'audio', 'video', 'documents']) {
      await for (final entity in Directory(
        p.join(_baseDir, folder),
      ).list(followLinks: false)) {
        if (entity is File && entity.path.endsWith('.part')) {
          await entity.delete();
        }
      }
    }
    final transcriptionTemp = Directory(p.join(_baseDir, 'transcription_temp'));
    await for (final entity in transcriptionTemp.list(followLinks: false)) {
      if (entity is File) {
        try {
          await entity.delete();
        } on FileSystemException {
          // A previous process may still be releasing the temporary decoder.
        }
      }
    }
  }

  /// Get absolute path from relative file path
  String absolutePath(String relativePath) {
    final normalized = p.normalize(relativePath);
    if (relativePath.trim().isEmpty ||
        p.isAbsolute(relativePath) ||
        normalized == '..' ||
        normalized.startsWith('..${p.separator}')) {
      throw const FormatException('文件路径不安全');
    }
    final resolved = p.normalize(p.join(_baseDir, normalized));
    if (!p.isWithin(_baseDir, resolved)) {
      throw const FormatException('文件路径不安全');
    }
    return resolved;
  }

  /// Copy a file into the Feikong storage and return relative path
  Future<String> copyFile(File sourceFile, String subDir) async {
    final ext = p.extension(sourceFile.path);
    final filename = '${_uuid.v4()}$ext';
    final relativePath = '$subDir/$filename';
    final destPath = absolutePath(relativePath);

    await sourceFile.copy(destPath);
    return relativePath;
  }

  /// Move an app-owned temporary file into managed storage. This is normally
  /// an atomic rename and falls back to copy-and-delete across file systems.
  Future<String> moveTemporaryFile(File sourceFile, String subDir) async {
    final ext = p.extension(sourceFile.path);
    final filename = '${_uuid.v4()}$ext';
    final relativePath = '$subDir/$filename';
    final destination = File(absolutePath(relativePath));
    try {
      await sourceFile.rename(destination.path);
    } on FileSystemException {
      await sourceFile.copy(destination.path);
      await sourceFile.delete();
    }
    return relativePath;
  }

  /// Copy a file while reporting byte-level progress. Used as a non-Android
  /// fallback where the native content URI importer is unavailable.
  Future<String> copyFileWithProgress(
    File sourceFile,
    String subDir, {
    required void Function(int copiedBytes, int totalBytes) onProgress,
    bool Function()? shouldCancel,
  }) async {
    final ext = p.extension(sourceFile.path);
    final filename = '${_uuid.v4()}$ext';
    final relativePath = '$subDir/$filename';
    final destination = File(absolutePath(relativePath));
    final totalBytes = await sourceFile.length();
    final input = await sourceFile.open();
    final output = await destination.open(mode: FileMode.write);
    var copiedBytes = 0;
    try {
      onProgress(0, totalBytes);
      while (true) {
        if (shouldCancel?.call() == true) {
          throw const FileSystemException('附件导入已取消');
        }
        final chunk = await input.read(256 * 1024);
        if (chunk.isEmpty) break;
        await output.writeFrom(chunk);
        copiedBytes += chunk.length;
        onProgress(copiedBytes, totalBytes);
      }
      await output.flush();
      return relativePath;
    } catch (_) {
      if (await destination.exists()) await destination.delete();
      rethrow;
    } finally {
      await input.close();
      await output.close();
    }
  }

  /// Keep image decoding and JPEG encoding away from the UI isolate on
  /// platforms that do not provide the native sampled thumbnail path.
  Future<String> generateThumbnailInBackground(String imagePath) async {
    final sourcePath = absolutePath(imagePath);
    if (!await File(sourcePath).exists()) return '';
    final thumbFilename = '${_uuid.v4()}_thumb.jpg';
    final relativePath = 'thumbnails/$thumbFilename';
    final outputPath = absolutePath(relativePath);
    final generated = await Isolate.run(
      () => _generateThumbnailFile(sourcePath, outputPath),
    );
    return generated ? relativePath : '';
  }

  /// Delete a stored file by relative path
  Future<void> deleteFile(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) return;
    final path = absolutePath(relativePath);
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Get file size in bytes
  Future<int> getFileSize(String relativePath) async {
    final path = absolutePath(relativePath);
    final file = File(path);
    if (await file.exists()) {
      return await file.length();
    }
    return 0;
  }

  /// Check if a file exists
  Future<bool> fileExists(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) return false;
    final path = absolutePath(relativePath);
    return File(path).exists();
  }

  Future<int> storageSize() async {
    var total = 0;
    final root = Directory(_baseDir);
    if (!await root.exists()) return 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } on FileSystemException {
          // A file can be removed while the storage scan is in progress.
        }
      }
    }
    return total;
  }

  /// Size of content that belongs to the user, excluding downloaded models,
  /// inference caches, application settings and temporary working files.
  Future<int> userDataSize() async {
    const directoryNames = {
      'images',
      'audio',
      'video',
      'documents',
      'thumbnails',
      'exports',
      'assistant',
    };
    const fileNames = {
      'fknotes.db',
      'fknotes.db-journal',
      'fknotes.db-shm',
      'fknotes.db-wal',
    };
    var total = 0;
    for (final name in directoryNames) {
      final directory = Directory(p.join(_baseDir, name));
      if (!await directory.exists()) continue;
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        try {
          total += await entity.length();
        } on FileSystemException {
          // Content may be removed while the data page refreshes.
        }
      }
    }
    for (final name in fileNames) {
      final file = File(p.join(_baseDir, name));
      try {
        if (await file.exists()) total += await file.length();
      } on FileSystemException {
        // Database sidecar files can disappear after a checkpoint.
      }
    }
    return total;
  }
}

bool _generateThumbnailFile(String sourcePath, String outputPath) {
  try {
    final decoded = img.decodeImage(File(sourcePath).readAsBytesSync());
    if (decoded == null) return false;
    final thumbnail = decoded.width >= decoded.height
        ? img.copyResize(decoded, width: 300)
        : img.copyResize(decoded, height: 300);
    File(outputPath).writeAsBytesSync(img.encodeJpg(thumbnail, quality: 86));
    return true;
  } catch (_) {
    return false;
  }
}
