import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/note_entry.dart';
import 'file_storage_service.dart';

enum AttachmentImportStatus { importing, completed, failed, canceled }

class AttachmentImportJob {
  final String id;
  final NoteType type;
  final String fileName;
  final String mimeType;
  final int totalBytes;
  final int copiedBytes;
  final AttachmentImportStatus status;
  final String? filePath;
  final String? thumbnailPath;
  final int? fileSize;
  final String? errorMessage;
  final int? noteId;
  final bool committed;
  final bool ownsNoteDraft;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const AttachmentImportJob({
    required this.id,
    this.type = NoteType.video,
    required this.fileName,
    required this.mimeType,
    required this.totalBytes,
    this.copiedBytes = 0,
    this.status = AttachmentImportStatus.importing,
    this.filePath,
    this.thumbnailPath,
    this.fileSize,
    this.errorMessage,
    this.noteId,
    this.committed = false,
    this.ownsNoteDraft = false,
    this.createdAt,
    this.updatedAt,
  });

  double? get progress =>
      totalBytes > 0 ? (copiedBytes / totalBytes).clamp(0.0, 1.0) : null;

  AttachmentImportJob copyWith({
    int? totalBytes,
    int? copiedBytes,
    AttachmentImportStatus? status,
    String? filePath,
    String? thumbnailPath,
    int? fileSize,
    String? errorMessage,
    int? noteId,
    bool? committed,
    bool? ownsNoteDraft,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearFilePath = false,
    bool clearThumbnailPath = false,
    bool clearErrorMessage = false,
  }) => AttachmentImportJob(
    id: id,
    type: type,
    fileName: fileName,
    mimeType: mimeType,
    totalBytes: totalBytes ?? this.totalBytes,
    copiedBytes: copiedBytes ?? this.copiedBytes,
    status: status ?? this.status,
    filePath: clearFilePath ? null : filePath ?? this.filePath,
    thumbnailPath: clearThumbnailPath
        ? null
        : thumbnailPath ?? this.thumbnailPath,
    fileSize: fileSize ?? this.fileSize,
    errorMessage: clearErrorMessage ? null : errorMessage ?? this.errorMessage,
    noteId: noteId ?? this.noteId,
    committed: committed ?? this.committed,
    ownsNoteDraft: ownsNoteDraft ?? this.ownsNoteDraft,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.dbValue,
    'fileName': fileName,
    'mimeType': mimeType,
    'totalBytes': totalBytes,
    'copiedBytes': copiedBytes,
    'status': status.name,
    'filePath': filePath,
    'thumbnailPath': thumbnailPath,
    'fileSize': fileSize,
    'errorMessage': errorMessage,
    'noteId': noteId,
    'committed': committed,
    'ownsNoteDraft': ownsNoteDraft,
    'createdAt': (createdAt ?? DateTime.now()).toUtc().toIso8601String(),
    'updatedAt': (updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
  };

  factory AttachmentImportJob.fromJson(Map<String, Object?> json) {
    final id = json['id'] as String?;
    if (id == null || id.trim().isEmpty) {
      throw const FormatException('附件导入任务缺少 ID');
    }
    return AttachmentImportJob(
      id: id,
      type: NoteType.fromDb(json['type'] as String? ?? 'document'),
      fileName: json['fileName'] as String? ?? '附件',
      mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? -1,
      copiedBytes: (json['copiedBytes'] as num?)?.toInt() ?? 0,
      status: AttachmentImportStatus.values.firstWhere(
        (value) => value.name == json['status'],
        orElse: () => AttachmentImportStatus.failed,
      ),
      filePath: json['filePath'] as String?,
      thumbnailPath: json['thumbnailPath'] as String?,
      fileSize: (json['fileSize'] as num?)?.toInt(),
      errorMessage: json['errorMessage'] as String?,
      noteId: (json['noteId'] as num?)?.toInt(),
      committed: json['committed'] == true,
      ownsNoteDraft: json['ownsNoteDraft'] == true,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    );
  }
}

class AttachmentImportService extends ChangeNotifier {
  AttachmentImportService._() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static final AttachmentImportService instance = AttachmentImportService._();

  static const _channel = MethodChannel('fknotes/attachment_import');
  final _picker = ImagePicker();
  final _storage = FileStorageService.instance;
  final _uuid = const Uuid();
  final Map<String, AttachmentImportJob> _jobs = {};
  final Map<String, List<MethodCall>> _earlyEvents = {};
  final Set<String> _ignoredJobIds = {};
  Timer? _persistTimer;
  Future<void> _persistence = Future.value();
  bool _restored = false;

  String get _persistencePath =>
      p.join(_storage.baseDir, 'recovery', 'attachment-import-jobs.json');

  List<AttachmentImportJob> get jobs => List.unmodifiable(_jobs.values);

  AttachmentImportJob? jobById(String id) => _jobs[id];

  @visibleForTesting
  void addJobForTesting(AttachmentImportJob job) {
    _jobs[job.id] = job;
    notifyListeners();
  }

  @visibleForTesting
  Future<void> flushPersistenceForTesting() async {
    _persistTimer?.cancel();
    if (_persistTimer != null) _enqueuePersistence();
    await _persistence;
  }

  @visibleForTesting
  Future<void> resetForTesting({bool deletePersistence = false}) async {
    _persistTimer?.cancel();
    _persistTimer = null;
    try {
      await _persistence;
    } catch (_) {
      // Reset even if a deliberately broken test path failed to persist.
    }
    _jobs.clear();
    _earlyEvents.clear();
    _ignoredJobIds.clear();
    _restored = false;
    if (deletePersistence) {
      final file = File(_persistencePath);
      if (await file.exists()) await file.delete();
      final temporary = File('${file.path}.tmp');
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Set<String> get protectedFilePaths => {
    for (final job in _jobs.values)
      if (!job.committed) ...[
        if (job.filePath != null) job.filePath!,
        if (job.thumbnailPath != null) job.thumbnailPath!,
      ],
  };

  Future<void> restoreJobs() async {
    if (_restored) return;
    _restored = true;
    final file = File(_persistencePath);
    final temporary = File('${file.path}.tmp');
    try {
      final temporaryJobs = await _readPersistedJobs(temporary);
      final persistedJobs = temporaryJobs ?? await _readPersistedJobs(file);
      if (persistedJobs == null) return;
      if (temporaryJobs != null) {
        try {
          if (await file.exists()) await file.delete();
          await temporary.rename(file.path);
        } on FileSystemException {
          // The parsed snapshot remains usable and will be rewritten below.
        }
      }
      for (final raw in persistedJobs) {
        if (raw is! Map) continue;
        final job = AttachmentImportJob.fromJson(
          raw.map((key, value) => MapEntry(key.toString(), value)),
        );
        if (job.committed || job.status == AttachmentImportStatus.canceled) {
          continue;
        }
        final recovered = await _recoverPersistedJob(job);
        if (recovered != null) _jobs[recovered.id] = recovered;
      }
      _schedulePersistence(immediate: true);
      notifyListeners();
    } on FileSystemException {
      // The app can continue without restoring transient import UI state.
    }
  }

  List<AttachmentImportJob> jobsForNote(int noteId) =>
      _jobs.values.where((job) => job.noteId == noteId).toList(growable: false);

  Future<List<AttachmentImportJob>> pickAndImport(
    NoteType type, {
    bool camera = false,
  }) async {
    if (camera) {
      final image = await _picker.pickImage(source: ImageSource.camera);
      if (image == null) return const [];
      return _importSelectedFiles([image], NoteType.image);
    }
    if (Platform.isAndroid) return _pickAndImportOnAndroid(type);
    final selected = await _pickWithFlutter(type);
    if (selected.isEmpty) return const [];
    return _importSelectedFiles(selected, type);
  }

  Future<List<AttachmentImportJob>> _pickAndImportOnAndroid(
    NoteType type,
  ) async {
    final result = await _channel.invokeListMethod<dynamic>('pickAndImport', {
      'type': type.dbValue,
    });
    if (result == null) return const [];
    return _registerNativeJobs(result);
  }

  Future<List<AttachmentImportJob>> _importSelectedFiles(
    List<XFile> selected,
    NoteType type,
  ) async {
    if (Platform.isAndroid) {
      final result = await _channel.invokeListMethod<dynamic>(
        'importLocalFiles',
        {
          'type': type.dbValue,
          'files': [
            for (final file in selected)
              {
                'path': file.path,
                'name': file.name,
                'mimeType': lookupMimeType(file.path) ?? _fallbackMime(type),
              },
          ],
        },
      );
      if (result == null) return const [];
      return _registerNativeJobs(result);
    }

    if (Platform.isIOS) {
      var totalBytes = 0;
      for (final file in selected) {
        totalBytes += await File(file.path).length();
      }
      await _ensureFallbackCapacity(totalBytes);
    }

    final jobs = <AttachmentImportJob>[];
    for (final file in selected) {
      final source = File(file.path);
      final id = _uuid.v4();
      final totalBytes = await source.length();
      final job = AttachmentImportJob(
        id: id,
        type: type,
        fileName: file.name,
        mimeType: lookupMimeType(file.path) ?? _fallbackMime(type),
        totalBytes: totalBytes,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      _jobs[id] = job;
      jobs.add(job);
      unawaited(_copyFallback(id, source));
    }
    _schedulePersistence(immediate: true);
    notifyListeners();
    return jobs;
  }

  Future<void> _ensureFallbackCapacity(int contentBytes) async {
    final available = await _channel.invokeMethod<int>('availableStorageBytes');
    if (available == null) return;
    const minimumHeadroom = 32 * 1024 * 1024;
    final required =
        contentBytes +
        (contentBytes ~/ 10 > minimumHeadroom
            ? contentBytes ~/ 10
            : minimumHeadroom);
    if (available >= required) return;
    String megabytes(int bytes) => '${(bytes / 1048576).toStringAsFixed(1)} MB';
    throw PlatformException(
      code: 'storage_space_insufficient',
      message:
          '存储空间不足：导入至少需要 ${megabytes(required)}，'
          '当前可用 ${megabytes(available)}',
    );
  }

  List<AttachmentImportJob> _registerNativeJobs(List<dynamic> values) {
    final jobs = <AttachmentImportJob>[];
    for (final value in values) {
      final result = Map<String, dynamic>.from(value as Map);
      final id = result['jobId'] as String;
      final type = NoteType.fromDb(result['type'] as String? ?? 'document');
      final job = AttachmentImportJob(
        id: id,
        type: type,
        fileName: result['fileName'] as String? ?? type.label,
        mimeType: result['mimeType'] as String? ?? _fallbackMime(type),
        totalBytes: (result['totalBytes'] as num?)?.toInt() ?? -1,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      _jobs[id] = job;
      jobs.add(job);
      final buffered = _earlyEvents.remove(id);
      if (buffered != null) {
        for (final call in buffered) {
          _applyNativeCall(call);
        }
      }
    }
    _schedulePersistence(immediate: true);
    notifyListeners();
    return jobs.map((job) => _jobs[job.id]!).toList(growable: false);
  }

  Future<List<XFile>> _pickWithFlutter(NoteType type) async {
    switch (type) {
      case NoteType.image:
        return _picker.pickMultiImage();
      case NoteType.video:
        final file = await _picker.pickVideo(source: ImageSource.gallery);
        return file == null ? const [] : [file];
      case NoteType.audio:
        const group = XTypeGroup(label: 'Audio', mimeTypes: ['audio/*']);
        final file = await openFile(acceptedTypeGroups: [group]);
        return file == null ? const [] : [file];
      case NoteType.document:
      case NoteType.text:
        const group = XTypeGroup(
          label: 'Documents',
          extensions: [
            'pdf',
            'txt',
            'md',
            'doc',
            'docx',
            'xls',
            'xlsx',
            'ppt',
            'pptx',
            'zip',
          ],
        );
        final file = await openFile(acceptedTypeGroups: [group]);
        return file == null ? const [] : [file];
    }
  }

  Future<void> _copyFallback(String id, File source) async {
    try {
      final job = _jobs[id]!;
      final relativePath = await _storage.copyFileWithProgress(
        source,
        _folder(job.type),
        shouldCancel: () =>
            _jobs[id]?.status == AttachmentImportStatus.canceled,
        onProgress: (copied, total) {
          final current = _jobs[id];
          if (current == null ||
              current.status != AttachmentImportStatus.importing) {
            return;
          }
          _jobs[id] = current.copyWith(
            copiedBytes: copied,
            totalBytes: total,
            updatedAt: DateTime.now(),
          );
          _schedulePersistence();
          notifyListeners();
        },
      );
      final current = _jobs[id];
      if (current == null ||
          current.status == AttachmentImportStatus.canceled) {
        await _storage.deleteFile(relativePath);
        return;
      }
      final thumbnail = current.type == NoteType.image
          ? await _storage.generateThumbnailInBackground(relativePath)
          : null;
      _jobs[id] = current.copyWith(
        status: AttachmentImportStatus.completed,
        filePath: relativePath,
        thumbnailPath: thumbnail,
        fileSize: current.totalBytes,
        copiedBytes: current.totalBytes,
        updatedAt: DateTime.now(),
        clearErrorMessage: true,
      );
      _schedulePersistence(immediate: true);
      notifyListeners();
    } catch (error) {
      final job = _jobs[id];
      if (job == null || job.status == AttachmentImportStatus.canceled) return;
      _jobs[id] = job.copyWith(
        status: AttachmentImportStatus.failed,
        errorMessage: error.toString(),
        updatedAt: DateTime.now(),
      );
      _schedulePersistence(immediate: true);
      notifyListeners();
    }
  }

  void assignToNote(String jobId, int noteId, {bool ownsNoteDraft = false}) {
    final job = _jobs[jobId];
    if (job == null) return;
    _jobs[jobId] = job.copyWith(
      noteId: noteId,
      ownsNoteDraft: ownsNoteDraft,
      updatedAt: DateTime.now(),
    );
    _schedulePersistence(immediate: true);
    notifyListeners();
  }

  void markCommitted(String jobId) {
    final job = _jobs[jobId];
    if (job == null) return;
    _jobs[jobId] = job.copyWith(committed: true, updatedAt: DateTime.now());
    _schedulePersistence(immediate: true);
    notifyListeners();
  }

  void markFailed(String jobId, String message) {
    final job = _jobs[jobId];
    if (job == null) return;
    _jobs[jobId] = job.copyWith(
      status: AttachmentImportStatus.failed,
      errorMessage: message,
      updatedAt: DateTime.now(),
    );
    _schedulePersistence(immediate: true);
    notifyListeners();
  }

  Future<void> cancel(String jobId) async {
    final job = _jobs[jobId];
    if (job == null || job.status != AttachmentImportStatus.importing) return;
    _jobs[jobId] = job.copyWith(
      status: AttachmentImportStatus.canceled,
      updatedAt: DateTime.now(),
    );
    _schedulePersistence(immediate: true);
    notifyListeners();
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('cancelImport', {'jobId': jobId});
    }
  }

  void dismiss(String jobId) {
    _ignoredJobIds.add(jobId);
    _jobs.remove(jobId);
    _earlyEvents.remove(jobId);
    _schedulePersistence(immediate: true);
    notifyListeners();
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    final arguments = Map<String, dynamic>.from(call.arguments as Map);
    final id = arguments['jobId'] as String?;
    if (id == null || _ignoredJobIds.contains(id)) return;
    if (!_jobs.containsKey(id)) {
      _earlyEvents.putIfAbsent(id, () => []).add(call);
      return;
    }
    _applyNativeCall(call);
  }

  void _applyNativeCall(MethodCall call) {
    final arguments = Map<String, dynamic>.from(call.arguments as Map);
    final id = arguments['jobId'] as String;
    final job = _jobs[id];
    if (job == null) return;
    switch (call.method) {
      case 'progress':
        if (job.status != AttachmentImportStatus.importing) return;
        _jobs[id] = job.copyWith(
          copiedBytes: (arguments['copiedBytes'] as num?)?.toInt() ?? 0,
          totalBytes:
              (arguments['totalBytes'] as num?)?.toInt() ?? job.totalBytes,
          updatedAt: DateTime.now(),
        );
        _schedulePersistence();
      case 'completed':
        _jobs[id] = job.copyWith(
          status: AttachmentImportStatus.completed,
          filePath: arguments['filePath'] as String?,
          thumbnailPath: arguments['thumbnailPath'] as String?,
          fileSize: (arguments['fileSize'] as num?)?.toInt(),
          copiedBytes: (arguments['fileSize'] as num?)?.toInt(),
          updatedAt: DateTime.now(),
          clearErrorMessage: true,
        );
        _schedulePersistence(immediate: true);
      case 'failed':
        _jobs[id] = job.copyWith(
          status: AttachmentImportStatus.failed,
          errorMessage: arguments['message'] as String? ?? '附件导入失败',
          updatedAt: DateTime.now(),
        );
        _schedulePersistence(immediate: true);
      case 'canceled':
        _jobs[id] = job.copyWith(
          status: AttachmentImportStatus.canceled,
          updatedAt: DateTime.now(),
        );
        _schedulePersistence(immediate: true);
      default:
        return;
    }
    notifyListeners();
  }

  Future<AttachmentImportJob?> _recoverPersistedJob(
    AttachmentImportJob job,
  ) async {
    var filePath = job.filePath;
    if (filePath == null && job.status == AttachmentImportStatus.importing) {
      final directory = Directory(p.join(_storage.baseDir, _folder(job.type)));
      if (await directory.exists()) {
        await for (final entity in directory.list(followLinks: false)) {
          if (entity is! File || entity.path.endsWith('.part')) continue;
          final name = p.basename(entity.path);
          if (name.startsWith('${job.id}.')) {
            filePath = p.posix.join(_folder(job.type), name);
            break;
          }
        }
      }
    }
    String? thumbnailPath = job.thumbnailPath;
    if (thumbnailPath == null && job.type == NoteType.image) {
      final candidate = 'thumbnails/${job.id}_thumb.jpg';
      if (await _storage.fileExists(candidate)) thumbnailPath = candidate;
    }
    final fileExists = filePath != null && await _storage.fileExists(filePath);
    if (job.noteId == null) {
      if (fileExists) await _storage.deleteFile(filePath);
      await _storage.deleteFile(thumbnailPath);
      return null;
    }
    if (fileExists) {
      final size = await _storage.getFileSize(filePath);
      return job.copyWith(
        status: AttachmentImportStatus.completed,
        filePath: filePath,
        thumbnailPath: thumbnailPath,
        fileSize: size,
        totalBytes: job.totalBytes > 0 ? job.totalBytes : size,
        copiedBytes: size,
        updatedAt: DateTime.now(),
        clearErrorMessage: true,
      );
    }
    if (job.status == AttachmentImportStatus.importing ||
        job.status == AttachmentImportStatus.completed) {
      return job.copyWith(
        status: AttachmentImportStatus.failed,
        errorMessage: '导入因应用退出而中断，请重试',
        updatedAt: DateTime.now(),
        clearFilePath: true,
        clearThumbnailPath: true,
      );
    }
    return job;
  }

  void _schedulePersistence({bool immediate = false}) {
    if (!_restored && !immediate) return;
    _persistTimer?.cancel();
    if (!immediate) {
      _persistTimer = Timer(
        const Duration(milliseconds: 300),
        () => _enqueuePersistence(),
      );
      return;
    }
    _enqueuePersistence();
  }

  void _enqueuePersistence() {
    _persistTimer = null;
    final jobs = _jobs.values
        .where(
          (job) =>
              !job.committed && job.status != AttachmentImportStatus.canceled,
        )
        .map((job) => job.toJson())
        .toList(growable: false);
    _persistence = _persistence
        .catchError((_) {})
        .then((_) => _writePersistedJobs(jobs));
    unawaited(
      _persistence.catchError((Object error) {
        debugPrint('无法保存附件导入任务：$error');
      }),
    );
  }

  Future<void> _writePersistedJobs(List<Map<String, Object?>> jobs) async {
    final destination = File(_persistencePath);
    if (jobs.isEmpty) {
      if (await destination.exists()) await destination.delete();
      final temporary = File('${destination.path}.tmp');
      if (await temporary.exists()) await temporary.delete();
      return;
    }
    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'formatVersion': 1,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'jobs': jobs,
      }),
      flush: true,
    );
    try {
      await temporary.rename(destination.path);
    } on FileSystemException {
      if (await destination.exists()) await destination.delete();
      await temporary.rename(destination.path);
    }
  }

  Future<List<Object?>?> _readPersistedJobs(File file) async {
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map ||
          decoded['formatVersion'] != 1 ||
          decoded['jobs'] is! List) {
        throw const FormatException('附件导入任务日志无效');
      }
      return List<Object?>.from(decoded['jobs'] as List);
    } on FormatException {
      await file.delete();
      return null;
    }
  }

  static String _folder(NoteType type) => switch (type) {
    NoteType.image => 'images',
    NoteType.audio => 'audio',
    NoteType.video => 'video',
    NoteType.document || NoteType.text => 'documents',
  };

  static String _fallbackMime(NoteType type) => switch (type) {
    NoteType.image => 'image/jpeg',
    NoteType.audio => 'audio/mpeg',
    NoteType.video => 'video/mp4',
    NoteType.document || NoteType.text => 'application/octet-stream',
  };
}

// Compatibility aliases for existing callers while the import subsystem is
// generalized from video-only jobs to all attachment types.
typedef VideoImportService = AttachmentImportService;
typedef VideoImportJob = AttachmentImportJob;
typedef VideoImportStatus = AttachmentImportStatus;
