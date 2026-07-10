import 'dart:io';
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
    ];

    for (final dir in dirs) {
      await Directory(dir).create(recursive: true);
    }
  }

  /// Get absolute path from relative file path
  String absolutePath(String relativePath) {
    return p.join(_baseDir, relativePath);
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

  /// Generate thumbnail for an image, return relative thumbnail path
  Future<String> generateThumbnail(String imagePath) async {
    final absPath = absolutePath(imagePath);
    final file = File(absPath);

    if (!await file.exists()) return '';

    try {
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return '';

      final thumb = img.copyResize(decoded, width: 300);
      final thumbBytes = img.encodeJpg(thumb);

      final thumbFilename = '${_uuid.v4()}_thumb.jpg';
      final thumbRelativePath = 'thumbnails/$thumbFilename';
      final thumbPath = absolutePath(thumbRelativePath);

      await File(thumbPath).writeAsBytes(thumbBytes);
      return thumbRelativePath;
    } catch (e) {
      return '';
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
}
