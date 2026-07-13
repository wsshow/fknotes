import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:image/image.dart' as img;

import '../debug/app_diagnostics.dart';

class FileStorageService {
  FileStorageService._();
  static final FileStorageService instance = FileStorageService._();

  final _uuid = const Uuid();
  late String _baseDir;

  String get baseDir => _baseDir;

  /// Initialize storage directories
  Future<void> init({String? baseDir}) async {
    final stopwatch = Stopwatch()..start();
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
    if (kDebugMode) {
      AppDiagnostics.info(
        AppLogCategory.storage,
        'file_storage_initialized',
        data: {
          'durationMs': stopwatch.elapsedMilliseconds,
          'customDirectory': baseDir != null,
          'managedDirectoryCount': dirs.length,
        },
      );
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

  /// Validates and normalizes an image before it enters the local multimodal
  /// pipeline. The bounded JPEG keeps EXIF orientation, alpha compositing and
  /// very large camera files from becoming native decoder surprises.
  Future<String> importAssistantImage(File sourceFile) async {
    if (!await sourceFile.exists()) {
      throw const FormatException('选择的图片不存在');
    }
    final sourceBytes = await sourceFile.length();
    if (sourceBytes <= 0 || sourceBytes > 20 * 1024 * 1024) {
      throw const FormatException('图片文件为空或超过 20 MB');
    }
    final relativePath = 'assistant/${_uuid.v4()}.jpg';
    final outputPath = absolutePath(relativePath);
    try {
      await Isolate.run(
        () => _normalizeAssistantImageFile(sourceFile.path, outputPath),
      );
      return relativePath;
    } catch (_) {
      final output = File(outputPath);
      if (await output.exists()) await output.delete();
      rethrow;
    }
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

  Future<OrphanCleanupResult> cleanupOrphanedAttachments({
    required Set<String> referencedPaths,
    Set<String> protectedPaths = const {},
    Duration minimumAge = const Duration(hours: 24),
  }) async {
    const folders = ['images', 'audio', 'video', 'documents', 'thumbnails'];
    final retained = {
      ...referencedPaths.map(_normalizeRelativePath),
      ...protectedPaths.map(_normalizeRelativePath),
    };
    final cutoff = DateTime.now().subtract(minimumAge);
    var deletedFiles = 0;
    var reclaimedBytes = 0;
    for (final folder in folders) {
      final directory = Directory(p.join(_baseDir, folder));
      if (!await directory.exists()) continue;
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File || entity.path.endsWith('.part')) continue;
        final relative = _normalizeRelativePath(
          p.relative(entity.path, from: _baseDir),
        );
        if (retained.contains(relative)) continue;
        try {
          final stat = await entity.stat();
          if (stat.modified.isAfter(cutoff)) continue;
          final bytes = stat.size;
          await entity.delete();
          deletedFiles++;
          reclaimedBytes += bytes;
        } on FileSystemException {
          // A file may still be open or may have been removed concurrently.
        }
      }
    }
    return OrphanCleanupResult(
      deletedFiles: deletedFiles,
      reclaimedBytes: reclaimedBytes,
    );
  }

  String _normalizeRelativePath(String value) => p.posix.normalize(
    value.replaceAll(p.separator, '/').replaceAll('\\', '/'),
  );
}

class OrphanCleanupResult {
  final int deletedFiles;
  final int reclaimedBytes;

  const OrphanCleanupResult({
    required this.deletedFiles,
    required this.reclaimedBytes,
  });
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

void _normalizeAssistantImageFile(String sourcePath, String outputPath) {
  final bytes = File(sourcePath).readAsBytesSync();
  final decoder = img.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (decoder == null || info == null || info.width <= 0 || info.height <= 0) {
    throw const FormatException('暂不支持这种图片格式');
  }
  const maxPixels = 40 * 1000 * 1000;
  if (info.width * info.height > maxPixels ||
      info.width > 16384 ||
      info.height > 16384) {
    throw const FormatException('图片分辨率过高，请选择不超过 4000 万像素的图片');
  }
  final decoded = decoder.decodeFrame(0);
  if (decoded == null) throw const FormatException('图片解码失败');
  var normalized = img.bakeOrientation(decoded);
  const maxLongEdge = 2048;
  if (normalized.width > maxLongEdge || normalized.height > maxLongEdge) {
    normalized = normalized.width >= normalized.height
        ? img.copyResize(normalized, width: maxLongEdge)
        : img.copyResize(normalized, height: maxLongEdge);
  }
  if (normalized.hasAlpha) {
    final background = img.Image(
      width: normalized.width,
      height: normalized.height,
    );
    img.fill(background, color: img.ColorRgb8(255, 255, 255));
    normalized = img.compositeImage(background, normalized);
  }
  File(outputPath).writeAsBytesSync(img.encodeJpg(normalized, quality: 88));
}
