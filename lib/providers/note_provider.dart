import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/note_entry.dart';
import '../services/file_storage_service.dart';
import '../services/note_service.dart';
import '../services/speech_transcription_service.dart';
import '../services/video_import_service.dart';

class NoteProvider extends ChangeNotifier {
  final NoteService _notes = NoteService.instance;
  final FileStorageService _storage = FileStorageService.instance;
  final AttachmentImportService _attachmentImports =
      AttachmentImportService.instance;
  final SpeechTranscriptionService _transcriptions =
      SpeechTranscriptionService.instance;
  final Set<String> _finalizingImportJobs = {};
  final Set<int> _importDrafts = {};
  final Set<String> _handledTranscriptions = {};
  Future<void> _importFinalization = Future.value();

  List<NoteEntry> _entries = [];
  NoteType? _typeFilter;
  NoteScope _scope = NoteScope.active;
  NoteSort _sort = NoteSort.updated;
  bool _isLoading = false;
  bool _isRepairingThumbnails = false;
  bool _disposed = false;

  NoteProvider() {
    _attachmentImports.addListener(_onAttachmentImportsChanged);
    _transcriptions.addListener(_onTranscriptionsChanged);
  }

  void _onTranscriptionsChanged() {
    for (final job in _transcriptions.jobs) {
      if (job.status != TranscriptionStatus.completed ||
          !_handledTranscriptions.add(job.key)) {
        continue;
      }
      _refreshTranscribedEntry(job.noteId);
    }
  }

  Future<void> _refreshTranscribedEntry(int noteId) async {
    final entry = await _notes.getEntry(noteId);
    if (entry == null) return;
    _replaceEntry(entry, appendIfMissing: true);
    notifyListeners();
  }

  List<NoteEntry> get allEntries => List.unmodifiable(_entries);
  List<NoteEntry> get activeEntries => _entries
      .where((entry) => !entry.isDeleted && !entry.isArchived)
      .toList(growable: false);
  List<NoteEntry> get recentlyUpdatedEntries {
    final result = activeEntries;
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  List<NoteEntry> get entries {
    Iterable<NoteEntry> result = switch (_scope) {
      NoteScope.active => _entries.where((e) => !e.isDeleted && !e.isArchived),
      NoteScope.favorites => _entries.where(
        (e) => !e.isDeleted && !e.isArchived && e.isFavorite,
      ),
      NoteScope.archived => _entries.where((e) => !e.isDeleted && e.isArchived),
      NoteScope.trash => _entries.where((e) => e.isDeleted),
    };
    if (_typeFilter != null) {
      result = result.where((e) => e.containsType(_typeFilter!));
    }
    final list = result.toList();
    list.sort((a, b) {
      if (_scope != NoteScope.trash && a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      return switch (_sort) {
        NoteSort.updated => b.updatedAt.compareTo(a.updatedAt),
        NoteSort.created => b.createdAt.compareTo(a.createdAt),
        NoteSort.title => a.title.toLowerCase().compareTo(
          b.title.toLowerCase(),
        ),
        NoteSort.size => b.totalAttachmentSize.compareTo(a.totalAttachmentSize),
      };
    });
    return list;
  }

  NoteType? get typeFilter => _typeFilter;
  NoteScope get scope => _scope;
  NoteSort get sort => _sort;
  bool get isLoading => _isLoading;
  int get favoriteCount => activeEntries.where((e) => e.isFavorite).length;
  int get archiveCount =>
      _entries.where((e) => e.isArchived && !e.isDeleted).length;
  int get trashCount => _entries.where((e) => e.isDeleted).length;
  int get attachmentCount =>
      activeEntries.fold(0, (sum, entry) => sum + entry.allAttachments.length);
  int get totalFileSize =>
      _entries.fold(0, (sum, entry) => sum + entry.totalAttachmentSize);

  int countForType(NoteType type) =>
      activeEntries.where((entry) => entry.containsType(type)).length;

  AttachmentImportJob? attachmentImportJob(String id) =>
      _attachmentImports.jobById(id);

  List<AttachmentImportJob> attachmentImportsForNote(int noteId) =>
      _attachmentImports.jobsForNote(noteId);

  AttachmentImportJob? videoImportJob(String id) => attachmentImportJob(id);

  List<AttachmentImportJob> videoImportsForNote(int noteId) =>
      attachmentImportsForNote(
        noteId,
      ).where((job) => job.type == NoteType.video).toList(growable: false);

  Future<void> loadEntries() async {
    _isLoading = true;
    notifyListeners();
    try {
      await _attachmentImports.restoreJobs();
      _importDrafts.addAll(
        _attachmentImports.jobs
            .where(
              (job) =>
                  job.ownsNoteDraft && !job.committed && job.noteId != null,
            )
            .map((job) => job.noteId!),
      );
      _entries = [...await _notes.getAllEntries()];
      _scheduleCompletedImportJobs();
      await _importFinalization;
      final referencedPaths = await _notes.referencedAttachmentPaths();
      await _storage.cleanupOrphanedAttachments(
        referencedPaths: referencedPaths,
        protectedPaths: _attachmentImports.protectedFilePaths,
      );
      _scheduleThumbnailRepair();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _scheduleThumbnailRepair() {
    if (_isRepairingThumbnails) return;
    _isRepairingThumbnails = true;
    unawaited(_runThumbnailRepair());
  }

  Future<void> _runThumbnailRepair() async {
    try {
      await _repairImageThumbnails();
    } catch (error, stackTrace) {
      // Thumbnail repair is best-effort. The original attachment stays usable.
      debugPrint('Thumbnail repair skipped: $error\n$stackTrace');
    } finally {
      _isRepairingThumbnails = false;
    }
  }

  Future<void> _repairImageThumbnails() async {
    var changed = false;
    for (final entry in List<NoteEntry>.from(_entries)) {
      if (_disposed || entry.id == null) return;
      final obsoleteThumbnails = <String>[];
      var entryChanged = false;
      final attachments = <NoteAttachment>[];
      for (final attachment in entry.allAttachments) {
        if (attachment.type != NoteType.image ||
            !_thumbnailNeedsUpgrade(attachment)) {
          attachments.add(attachment);
          continue;
        }
        final source = File(_storage.absolutePath(attachment.filePath));
        if (!await source.exists()) {
          attachments.add(attachment);
          continue;
        }
        final generated = await _storage.generateThumbnailInBackground(
          attachment.filePath,
        );
        if (generated.isEmpty) {
          attachments.add(attachment);
          continue;
        }
        if (attachment.thumbnailPath?.isNotEmpty == true) {
          obsoleteThumbnails.add(attachment.thumbnailPath!);
        }
        attachments.add(attachment.copyWith(thumbnailPath: generated));
        entryChanged = true;
      }
      if (!entryChanged) continue;
      final repaired = entry.copyWith(
        attachments: attachments,
        updatedAt: entry.updatedAt,
      );
      await _notes.updateEntry(repaired);
      _replaceEntry(repaired);
      changed = true;
      for (final path in obsoleteThumbnails) {
        await _storage.deleteFile(path);
      }
    }
    if (changed && !_disposed) notifyListeners();
  }

  bool _thumbnailNeedsUpgrade(NoteAttachment attachment) {
    final thumbnailPath = attachment.thumbnailPath;
    if (thumbnailPath == null || thumbnailPath.isEmpty) return true;
    final thumbnail = File(_storage.absolutePath(thumbnailPath));
    return !thumbnail.existsSync() ||
        !p.basenameWithoutExtension(thumbnailPath).endsWith('_thumb_v2');
  }

  void setTypeFilter(NoteType? type) {
    _typeFilter = type;
    notifyListeners();
  }

  void setScope(NoteScope scope) {
    _scope = scope;
    _typeFilter = null;
    notifyListeners();
  }

  void setSort(NoteSort sort) {
    _sort = sort;
    notifyListeners();
  }

  NoteEntry? getEntryById(int id) {
    for (final entry in _entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  Future<int> addEntry(NoteEntry entry) async {
    final id = await _notes.insertEntry(entry);
    _replaceEntry(_withPersistedIdentity(entry, id), appendIfMissing: true);
    notifyListeners();
    return id;
  }

  Future<void> updateEntry(NoteEntry entry) async {
    var entryToSave = entry;
    if (entry.id != null) {
      final protectedPaths = _attachmentImports.jobs
          .where(
            (job) =>
                job.noteId == entry.id &&
                job.status == AttachmentImportStatus.completed &&
                job.filePath != null,
          )
          .map((job) => job.filePath!)
          .toSet();
      final current = getEntryById(entry.id!);
      if (current != null && protectedPaths.isNotEmpty) {
        final incomingPaths = entry.allAttachments
            .map((item) => item.filePath)
            .toSet();
        entryToSave = entry.copyWith(
          attachments: [
            ...entry.allAttachments,
            for (final attachment in current.allAttachments)
              if (protectedPaths.contains(attachment.filePath) &&
                  !incomingPaths.contains(attachment.filePath))
                attachment,
          ],
        );
      }
    }
    await _notes.updateEntry(entryToSave);
    if (entryToSave.id != null) {
      _replaceEntry(_withPersistedIdentity(entryToSave, entryToSave.id!));
      notifyListeners();
    }
  }

  Future<List<AttachmentImportJob>> startAttachmentImport(
    NoteType type, {
    int? noteId,
    bool camera = false,
  }) async {
    final started = await _attachmentImports.pickAndImport(
      type,
      camera: camera,
    );
    if (started.isEmpty) return const [];
    final now = DateTime.now();
    final firstTitle = p
        .basenameWithoutExtension(started.first.fileName)
        .trim();
    final targetNoteId =
        noteId ??
        await addEntry(
          NoteEntry(
            type: type,
            title: firstTitle.isEmpty ? '${type.label}笔记' : firstTitle,
            createdAt: now,
            updatedAt: now,
            attachments: const [],
          ),
        );
    if (noteId == null) _importDrafts.add(targetNoteId);
    for (final job in started) {
      _attachmentImports.assignToNote(
        job.id,
        targetNoteId,
        ownsNoteDraft: noteId == null,
      );
    }
    _scheduleCompletedImportJobs();
    return started
        .map((job) => _attachmentImports.jobById(job.id)!)
        .toList(growable: false);
  }

  Future<AttachmentImportJob?> startVideoImport({int? noteId}) async {
    final jobs = await startAttachmentImport(NoteType.video, noteId: noteId);
    return jobs.firstOrNull;
  }

  Future<void> cancelAttachmentImport(String jobId) =>
      _attachmentImports.cancel(jobId);

  void acknowledgeAttachmentImport(String jobId) =>
      _attachmentImports.dismiss(jobId);

  Future<void> removeAttachmentImport(String jobId) async {
    final job = _attachmentImports.jobById(jobId);
    if (job == null) return;
    if (job.status == AttachmentImportStatus.importing) {
      await _attachmentImports.cancel(jobId);
    }
    if (!job.committed && job.filePath != null) {
      await _storage.deleteFile(job.filePath);
      await _storage.deleteFile(job.thumbnailPath);
    }
    _attachmentImports.dismiss(jobId);
    final noteId = job.noteId;
    if (noteId != null &&
        _importDrafts.contains(noteId) &&
        _attachmentImports.jobsForNote(noteId).isEmpty) {
      final draft = getEntryById(noteId);
      if (draft != null &&
          draft.allAttachments.isEmpty &&
          (draft.content?.trim().isEmpty ?? true)) {
        await _notes.deleteEntry(noteId);
        _entries.removeWhere((entry) => entry.id == noteId);
        _importDrafts.remove(noteId);
        notifyListeners();
      }
    }
  }

  Future<void> cancelVideoImport(String jobId) => cancelAttachmentImport(jobId);

  void acknowledgeVideoImport(String jobId) =>
      acknowledgeAttachmentImport(jobId);

  Future<void> removeVideoImport(String jobId) => removeAttachmentImport(jobId);

  void _onAttachmentImportsChanged() {
    notifyListeners();
    _scheduleCompletedImportJobs();
  }

  void _scheduleCompletedImportJobs() {
    for (final job in _attachmentImports.jobs) {
      if (job.status == AttachmentImportStatus.completed &&
          !job.committed &&
          job.noteId != null &&
          _finalizingImportJobs.add(job.id)) {
        _importFinalization = _importFinalization.then(
          (_) => _finalizeAttachmentImport(job),
        );
      }
    }
  }

  Future<void> _finalizeAttachmentImport(AttachmentImportJob job) async {
    try {
      final noteId = job.noteId;
      final filePath = job.filePath;
      if (noteId == null || filePath == null) return;
      var entry = getEntryById(noteId);
      entry ??= await _notes.getEntry(noteId);
      if (entry == null) {
        await _storage.deleteFile(job.filePath);
        await _storage.deleteFile(job.thumbnailPath);
        _attachmentImports.dismiss(job.id);
        return;
      }
      if (entry.allAttachments.any((item) => item.filePath == filePath)) {
        _importDrafts.remove(noteId);
        _attachmentImports.markCommitted(job.id);
        return;
      }
      final attachment = NoteAttachment(
        noteId: noteId,
        type: job.type,
        filePath: filePath,
        fileName: job.fileName,
        fileSize: job.fileSize ?? job.copiedBytes,
        mimeType: job.mimeType,
        thumbnailPath: job.thumbnailPath,
        sortOrder: entry.allAttachments.length,
        createdAt: DateTime.now(),
      );
      final persisted = await _notes.insertAttachment(noteId, attachment);
      _importDrafts.remove(noteId);
      final updated = entry.copyWith(
        type: entry.allAttachments.isEmpty ? job.type : entry.type,
        attachments: [...entry.allAttachments, persisted],
        updatedAt: DateTime.now(),
      );
      _replaceEntry(_withPersistedIdentity(updated, noteId));
      _attachmentImports.markCommitted(job.id);
      notifyListeners();
    } catch (error) {
      _attachmentImports.markFailed(job.id, '保存到笔记失败：$error');
    } finally {
      _finalizingImportJobs.remove(job.id);
    }
  }

  NoteEntry _withPersistedIdentity(NoteEntry entry, int id) => entry.copyWith(
    id: id,
    attachments: [
      for (final attachment in entry.allAttachments)
        attachment.copyWith(noteId: id),
    ],
  );

  void _replaceEntry(NoteEntry entry, {bool appendIfMissing = false}) {
    final index = _entries.indexWhere((item) => item.id == entry.id);
    if (index >= 0) {
      _entries[index] = entry;
    } else if (appendIfMissing) {
      _entries.add(entry);
    }
  }

  Future<void> toggleFavorite(NoteEntry entry) => updateEntry(
    entry.copyWith(isFavorite: !entry.isFavorite, updatedAt: DateTime.now()),
  );

  Future<void> togglePinned(NoteEntry entry) => updateEntry(
    entry.copyWith(isPinned: !entry.isPinned, updatedAt: DateTime.now()),
  );

  Future<void> toggleArchived(NoteEntry entry) => updateEntry(
    entry.copyWith(
      isArchived: !entry.isArchived,
      isPinned: false,
      updatedAt: DateTime.now(),
    ),
  );

  Future<void> moveToTrash(NoteEntry entry) => updateEntry(
    entry.copyWith(
      isDeleted: true,
      isPinned: false,
      deletedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
  );

  Future<void> restore(NoteEntry entry) => updateEntry(
    entry.copyWith(
      isDeleted: false,
      isArchived: false,
      clearDeletedAt: true,
      updatedAt: DateTime.now(),
    ),
  );

  Future<void> deletePermanently(NoteEntry entry) async {
    if (entry.id == null) return;
    await _notes.deleteEntry(entry.id!);
    _entries.removeWhere((item) => item.id == entry.id);
    notifyListeners();
    await _deleteAttachmentFilesBestEffort(entry);
  }

  Future<void> emptyTrash() async {
    final trashed = _entries.where((e) => e.isDeleted).toList();
    for (final entry in trashed) {
      if (entry.id != null) await _notes.deleteEntry(entry.id!);
      _entries.removeWhere((item) => item.id == entry.id);
      notifyListeners();
      await _deleteAttachmentFilesBestEffort(entry);
    }
  }

  Future<void> _deleteAttachmentFilesBestEffort(NoteEntry entry) async {
    for (final attachment in entry.allAttachments) {
      try {
        await _storage.deleteFile(attachment.filePath);
        await _storage.deleteFile(attachment.thumbnailPath);
      } on FileSystemException {
        // Database deletion is authoritative. A later orphan sweep can safely
        // reclaim a file that the platform still has open.
      } on FormatException {
        // Never follow an invalid path found in restored or legacy metadata.
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _attachmentImports.removeListener(_onAttachmentImportsChanged);
    _transcriptions.removeListener(_onTranscriptionsChanged);
    super.dispose();
  }
}
