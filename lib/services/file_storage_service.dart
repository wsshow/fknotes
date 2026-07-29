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
  var _initialized = false;

  String get baseDir => _baseDir;
  String? get baseDirOrNull => _initialized ? _baseDir : null;

  /// Initialize storage directories
  Future<void> init({String? baseDir}) async {
    final stopwatch = Stopwatch()..start();
    final appDir = baseDir == null
        ? await getApplicationSupportDirectory()
        : Directory(baseDir);
    _baseDir = appDir.path;

    final noteDirectories = [
      p.join(_baseDir, 'notes', 'images'),
      p.join(_baseDir, 'notes', 'thumbnails'),
      p.join(_baseDir, 'notes', 'audio'),
      p.join(_baseDir, 'notes', 'video'),
      p.join(_baseDir, 'notes', 'files'),
    ];
    final dirs = [
      ...noteDirectories,
      p.join(_baseDir, 'backups'),
      p.join(_baseDir, 'assistant'),
      p.join(_baseDir, 'models', 'asr'),
      p.join(_baseDir, 'transcription_temp'),
    ];

    for (final dir in dirs) {
      await Directory(dir).create(recursive: true);
    }
    for (final directory in noteDirectories) {
      await for (final entity in Directory(
        directory,
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
    _initialized = true;
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

  /// Writes trusted in-memory content into managed storage.
  Future<String> _writeBytes(
    Uint8List bytes,
    String subDir, {
    required String extension,
  }) async {
    if (bytes.isEmpty) throw const FormatException('文件内容为空');
    final safeExtension = extension.startsWith('.')
        ? extension.toLowerCase()
        : '.${extension.toLowerCase()}';
    if (!RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(safeExtension)) {
      throw const FormatException('文件扩展名无效');
    }
    final relativePath = '$subDir/${_uuid.v4()}$safeExtension';
    final destination = File(absolutePath(relativePath));
    await destination.writeAsBytes(bytes, flush: true);
    return relativePath;
  }

  /// Validates and normalizes an image and creates its note thumbnail.
  ///
  /// A single decode outside the UI isolate feeds both outputs. Screenshots
  /// with an alpha channel stay PNG; photos use a high-quality bounded JPEG.
  Future<StoredNoteImage> importNoteImageBytes(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
      throw const FormatException('图片文件为空或超过 20 MB');
    }
    final processed = await Isolate.run(() => _processNoteImageBytes(bytes));
    String? storageKey;
    String? previewStorageKey;
    try {
      storageKey = await _writeBytes(
        processed.bytes,
        p.posix.join('notes', 'images'),
        extension: processed.extension,
      );
      previewStorageKey = await _writeNoteThumbnailBytes(
        processed.thumbnailBytes,
      );
      return StoredNoteImage(
        storageKey: storageKey,
        mimeType: processed.mimeType,
        byteLength: processed.bytes.length,
        previewStorageKey: previewStorageKey,
      );
    } catch (_) {
      await deleteFile(storageKey);
      await deleteFile(previewStorageKey);
      rethrow;
    }
  }

  Future<String> _writeNoteThumbnailBytes(Uint8List bytes) async {
    if (bytes.isEmpty) throw const FormatException('缩略图内容为空');
    final relativePath = p.posix.join(
      'notes',
      'thumbnails',
      '${_uuid.v4()}_thumb_v3.jpg',
    );
    await File(absolutePath(relativePath)).writeAsBytes(bytes, flush: true);
    return relativePath;
  }

  /// Copies a completed recording into the canonical note audio tree.
  ///
  /// The temporary `.part` file keeps interrupted copies out of the note
  /// graph. Only formats produced by the in-app recorder are accepted here.
  Future<StoredNoteAudio> importNoteAudioFile(File source) async {
    if (!await source.exists()) {
      throw const FormatException('录音文件不存在');
    }
    final byteLength = await source.length();
    if (byteLength <= 0 || byteLength > 512 * 1024 * 1024) {
      throw const FormatException('录音文件为空或超过 512 MB');
    }
    final extension = p.extension(source.path).toLowerCase();
    final mimeType = switch (extension) {
      '.m4a' => 'audio/mp4',
      '.aac' => 'audio/aac',
      '.wav' => 'audio/wav',
      _ => throw const FormatException('暂不支持这种录音格式'),
    };
    final relativePath = p.posix.join(
      'notes',
      'audio',
      '${_uuid.v4()}$extension',
    );
    final destination = File(absolutePath(relativePath));
    final partial = File('${destination.path}.part');
    try {
      await source.openRead().pipe(partial.openWrite());
      final copiedLength = await partial.length();
      if (copiedLength != byteLength) {
        throw const FileSystemException('录音文件复制不完整');
      }
      await partial.rename(destination.path);
      return StoredNoteAudio(
        storageKey: relativePath,
        mimeType: mimeType,
        byteLength: copiedLength,
      );
    } catch (_) {
      if (await partial.exists()) await partial.delete();
      if (await destination.exists()) await destination.delete();
      rethrow;
    }
  }

  /// Generates a preview inside the isolated Delta-note storage tree.
  Future<String> generateNoteThumbnailInBackground(String imagePath) async {
    return _generateThumbnailInBackground(
      imagePath,
      p.posix.join('notes', 'thumbnails'),
    );
  }

  Future<String> _generateThumbnailInBackground(
    String imagePath,
    String subDirectory,
  ) async {
    final sourcePath = absolutePath(imagePath);
    if (!await File(sourcePath).exists()) return '';
    final thumbFilename = '${_uuid.v4()}_thumb_v3.jpg';
    final relativePath = p.join(subDirectory, thumbFilename);
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
    const directoryNames = {'notes', 'assistant', 'backups'};
    const fileNames = {
      'fknotes.db',
      'fknotes.db-journal',
      'fknotes.db-shm',
      'fknotes.db-wal',
      'fknotes-chat.db',
      'fknotes-chat.db-journal',
      'fknotes-chat.db-shm',
      'fknotes-chat.db-wal',
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

class StoredNoteImage {
  const StoredNoteImage({
    required this.storageKey,
    required this.mimeType,
    required this.byteLength,
    required this.previewStorageKey,
  });

  final String storageKey;
  final String mimeType;
  final int byteLength;
  final String previewStorageKey;
}

class StoredNoteAudio {
  const StoredNoteAudio({
    required this.storageKey,
    required this.mimeType,
    required this.byteLength,
  });

  final String storageKey;
  final String mimeType;
  final int byteLength;
}

bool _generateThumbnailFile(String sourcePath, String outputPath) {
  try {
    final decoded = img.decodeImage(File(sourcePath).readAsBytesSync());
    if (decoded == null) return false;
    final oriented = img.bakeOrientation(decoded);
    File(outputPath).writeAsBytesSync(_encodeNoteThumbnail(oriented));
    return true;
  } catch (_) {
    return false;
  }
}

void _normalizeAssistantImageFile(String sourcePath, String outputPath) {
  final bytes = File(sourcePath).readAsBytesSync();
  final (decoder, info) = _inspectImage(bytes);
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

({Uint8List bytes, String extension, String mimeType, Uint8List thumbnailBytes})
_processNoteImageBytes(Uint8List bytes) {
  final (decoder, info) = _inspectImage(bytes);
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
  const maxLongEdge = 4096;
  if (normalized.width > maxLongEdge || normalized.height > maxLongEdge) {
    normalized = normalized.width >= normalized.height
        ? img.copyResize(normalized, width: maxLongEdge)
        : img.copyResize(normalized, height: maxLongEdge);
  }
  final thumbnailBytes = _encodeNoteThumbnail(normalized);
  if (normalized.hasAlpha) {
    return (
      bytes: Uint8List.fromList(img.encodePng(normalized, level: 6)),
      extension: 'png',
      mimeType: 'image/png',
      thumbnailBytes: thumbnailBytes,
    );
  }
  return (
    bytes: Uint8List.fromList(img.encodeJpg(normalized, quality: 92)),
    extension: 'jpg',
    mimeType: 'image/jpeg',
    thumbnailBytes: thumbnailBytes,
  );
}

Uint8List _encodeNoteThumbnail(img.Image source) {
  const width = 640;
  const height = 640;
  final scale = [
    width / source.width,
    height / source.height,
    1.0,
  ].reduce((current, candidate) => current < candidate ? current : candidate);
  final preview = img.copyResize(
    source,
    width: (source.width * scale).round().clamp(1, width).toInt(),
    height: (source.height * scale).round().clamp(1, height).toInt(),
  );
  final flattened = img.Image(width: preview.width, height: preview.height);
  img.fill(flattened, color: img.ColorRgb8(250, 247, 242));
  img.compositeImage(flattened, preview);
  return Uint8List.fromList(img.encodeJpg(flattened, quality: 86));
}

(img.Decoder?, img.DecodeInfo?) _inspectImage(Uint8List bytes) {
  try {
    final decoder = img.findDecoderForData(bytes);
    return (decoder, decoder?.startDecode(bytes));
  } on FormatException {
    rethrow;
  } catch (_) {
    // Some decoders throw implementation-specific range/state errors for
    // truncated headers. Do not leak those details through the editor API.
    throw const FormatException('暂不支持这种图片格式');
  }
}
