import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
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
  }) => AttachmentImportJob(
    id: id,
    type: type,
    fileName: fileName,
    mimeType: mimeType,
    totalBytes: totalBytes ?? this.totalBytes,
    copiedBytes: copiedBytes ?? this.copiedBytes,
    status: status ?? this.status,
    filePath: filePath ?? this.filePath,
    thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    fileSize: fileSize ?? this.fileSize,
    errorMessage: errorMessage ?? this.errorMessage,
    noteId: noteId ?? this.noteId,
    committed: committed ?? this.committed,
  );
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

  List<AttachmentImportJob> get jobs => List.unmodifiable(_jobs.values);

  AttachmentImportJob? jobById(String id) => _jobs[id];

  @visibleForTesting
  void addJobForTesting(AttachmentImportJob job) {
    _jobs[job.id] = job;
    notifyListeners();
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
      );
      _jobs[id] = job;
      jobs.add(job);
      unawaited(_copyFallback(id, source));
    }
    notifyListeners();
    return jobs;
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
          _jobs[id] = current.copyWith(copiedBytes: copied, totalBytes: total);
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
      );
      notifyListeners();
    } catch (error) {
      final job = _jobs[id];
      if (job == null || job.status == AttachmentImportStatus.canceled) return;
      _jobs[id] = job.copyWith(
        status: AttachmentImportStatus.failed,
        errorMessage: error.toString(),
      );
      notifyListeners();
    }
  }

  void assignToNote(String jobId, int noteId) {
    final job = _jobs[jobId];
    if (job == null) return;
    _jobs[jobId] = job.copyWith(noteId: noteId);
    notifyListeners();
  }

  void markCommitted(String jobId) {
    final job = _jobs[jobId];
    if (job == null) return;
    _jobs[jobId] = job.copyWith(committed: true);
    notifyListeners();
  }

  void markFailed(String jobId, String message) {
    final job = _jobs[jobId];
    if (job == null) return;
    _jobs[jobId] = job.copyWith(
      status: AttachmentImportStatus.failed,
      errorMessage: message,
    );
    notifyListeners();
  }

  Future<void> cancel(String jobId) async {
    final job = _jobs[jobId];
    if (job == null || job.status != AttachmentImportStatus.importing) return;
    _jobs[jobId] = job.copyWith(status: AttachmentImportStatus.canceled);
    notifyListeners();
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('cancelImport', {'jobId': jobId});
    }
  }

  void dismiss(String jobId) {
    _ignoredJobIds.add(jobId);
    _jobs.remove(jobId);
    _earlyEvents.remove(jobId);
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
        );
      case 'completed':
        _jobs[id] = job.copyWith(
          status: AttachmentImportStatus.completed,
          filePath: arguments['filePath'] as String?,
          thumbnailPath: arguments['thumbnailPath'] as String?,
          fileSize: (arguments['fileSize'] as num?)?.toInt(),
          copiedBytes: (arguments['fileSize'] as num?)?.toInt(),
        );
      case 'failed':
        _jobs[id] = job.copyWith(
          status: AttachmentImportStatus.failed,
          errorMessage: arguments['message'] as String? ?? '附件导入失败',
        );
      case 'canceled':
        _jobs[id] = job.copyWith(status: AttachmentImportStatus.canceled);
      default:
        return;
    }
    notifyListeners();
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
