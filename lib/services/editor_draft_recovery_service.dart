import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/note_entry.dart';
import 'file_storage_service.dart';

class EditorRecoveryDraft {
  static const formatVersion = 2;

  final int? noteId;
  final DateTime? baseUpdatedAt;
  final DateTime savedAt;
  final String title;
  final String content;
  final String? richContent;
  final List<String> tags;
  final bool isFavorite;
  final bool isPinned;
  final NoteCoverMode coverMode;
  final String? coverAttachmentPath;
  final List<NoteAttachment> attachments;
  final List<NoteAttachment> removedAttachments;

  const EditorRecoveryDraft({
    required this.noteId,
    required this.baseUpdatedAt,
    required this.savedAt,
    required this.title,
    required this.content,
    required this.richContent,
    required this.tags,
    required this.isFavorite,
    required this.isPinned,
    this.coverMode = NoteCoverMode.automatic,
    this.coverAttachmentPath,
    required this.attachments,
    required this.removedAttachments,
  });

  bool get isBlank =>
      title.trim().isEmpty &&
      content.trim().isEmpty &&
      attachments.isEmpty &&
      tags.isEmpty &&
      !isFavorite &&
      !isPinned &&
      coverMode == NoteCoverMode.automatic &&
      coverAttachmentPath == null;

  bool matchesEntry(NoteEntry entry) =>
      title == entry.title &&
      content == (entry.content ?? '') &&
      richContent == entry.richContent &&
      _listEquals(tags, entry.tags) &&
      isFavorite == entry.isFavorite &&
      isPinned == entry.isPinned &&
      coverMode == entry.coverMode &&
      coverAttachmentPath == entry.coverAttachmentPath &&
      _attachmentMapsEqual(attachments, entry.allAttachments);

  Map<String, Object?> toJson() => {
    'formatVersion': formatVersion,
    'noteId': noteId,
    'baseUpdatedAt': baseUpdatedAt?.toUtc().toIso8601String(),
    'savedAt': savedAt.toUtc().toIso8601String(),
    'title': title,
    'content': content,
    'richContent': richContent,
    'tags': tags,
    'isFavorite': isFavorite,
    'isPinned': isPinned,
    'coverMode': coverMode.dbValue,
    'coverAttachmentPath': coverAttachmentPath,
    'attachments': attachments.map((item) => item.toMap()).toList(),
    'removedAttachments': removedAttachments
        .map((item) => item.toMap())
        .toList(),
  };

  factory EditorRecoveryDraft.fromJson(Map<String, Object?> json) {
    final version = json['formatVersion'];
    if (version is! int || version < 1 || version > formatVersion) {
      throw const FormatException('不支持的编辑器恢复草稿版本');
    }
    final savedAt = DateTime.tryParse(json['savedAt'] as String? ?? '');
    if (savedAt == null) throw const FormatException('恢复草稿缺少保存时间');
    return EditorRecoveryDraft(
      noteId: json['noteId'] as int?,
      baseUpdatedAt: DateTime.tryParse(json['baseUpdatedAt'] as String? ?? ''),
      savedAt: savedAt,
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      richContent: json['richContent'] as String?,
      tags: _stringList(json['tags']),
      isFavorite: json['isFavorite'] == true,
      isPinned: json['isPinned'] == true,
      coverMode: version >= 2
          ? NoteCoverMode.fromDb(json['coverMode'] as String?)
          : NoteCoverMode.automatic,
      coverAttachmentPath: version >= 2
          ? json['coverAttachmentPath'] as String?
          : null,
      attachments: _attachmentList(json['attachments']),
      removedAttachments: _attachmentList(json['removedAttachments']),
    );
  }

  static List<String> _stringList(Object? value) => value is List
      ? value.whereType<String>().toList(growable: false)
      : const [];

  static List<NoteAttachment> _attachmentList(Object? value) => value is List
      ? value
            .whereType<Map>()
            .map(
              (item) => NoteAttachment.fromMap(
                item.map((key, value) => MapEntry(key.toString(), value)),
              ),
            )
            .where((item) => item.filePath.isNotEmpty)
            .toList(growable: false)
      : const [];

  static bool _listEquals<T>(List<T> left, List<T> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  static bool _attachmentMapsEqual(
    List<NoteAttachment> left,
    List<NoteAttachment> right,
  ) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (jsonEncode(left[index].toMap()) != jsonEncode(right[index].toMap())) {
        return false;
      }
    }
    return true;
  }
}

class EditorDraftRecoveryService {
  EditorDraftRecoveryService._();

  static final EditorDraftRecoveryService instance =
      EditorDraftRecoveryService._();

  Future<void> _operations = Future.value();

  @visibleForTesting
  bool bypassForTesting = false;

  String get _directory =>
      p.join(FileStorageService.instance.baseDir, 'recovery', 'editor-drafts');

  File _fileFor(int? noteId) => File(
    p.join(_directory, noteId == null ? 'new-note.json' : 'note-$noteId.json'),
  );

  Future<EditorRecoveryDraft?> load(int? noteId) async {
    if (bypassForTesting) return null;
    try {
      await _operations;
    } catch (_) {
      // A failed earlier write must not prevent a later recovery attempt.
    }
    final file = _fileFor(noteId);
    final temporary = File('${file.path}.tmp');
    final primaryDraft = await _readDraft(file, noteId);
    final temporaryDraft = await _readDraft(temporary, noteId);
    if (temporaryDraft == null) return primaryDraft;
    if (primaryDraft != null &&
        !temporaryDraft.savedAt.isAfter(primaryDraft.savedAt)) {
      await _deleteIfPresent(temporary);
      return primaryDraft;
    }
    try {
      await _deleteIfPresent(file);
      await temporary.rename(file.path);
    } on FileSystemException {
      // The parsed in-memory draft is still safe to offer for this session.
    }
    return temporaryDraft;
  }

  Future<void> save(EditorRecoveryDraft draft) {
    if (bypassForTesting) return Future.value();
    return _enqueue(() async {
      await Directory(_directory).create(recursive: true);
      final destination = _fileFor(draft.noteId);
      final temporary = File('${destination.path}.tmp');
      await temporary.writeAsString(jsonEncode(draft.toJson()), flush: true);
      try {
        await temporary.rename(destination.path);
      } on FileSystemException {
        await _deleteIfPresent(destination);
        await temporary.rename(destination.path);
      }
    });
  }

  Future<void> clear(int? noteId) {
    if (bypassForTesting) return Future.value();
    return _enqueue(() => _deleteIfPresent(_fileFor(noteId)));
  }

  Future<void> clearAfterCreation(int noteId) {
    if (bypassForTesting) return Future.value();
    return _enqueue(() async {
      await _deleteIfPresent(_fileFor(null));
      await _deleteIfPresent(_fileFor(noteId));
    });
  }

  Future<void> clearAll() {
    if (bypassForTesting) return Future.value();
    return _enqueue(() async {
      final directory = Directory(_directory);
      if (await directory.exists()) await directory.delete(recursive: true);
    });
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _operations.then(
      (_) => operation(),
      onError: (Object _, StackTrace _) => operation(),
    );
    _operations = result;
    return result;
  }

  Future<void> _deleteIfPresent(File file) async {
    if (await file.exists()) await file.delete();
  }

  Future<EditorRecoveryDraft?> _readDraft(File file, int? noteId) async {
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) throw const FormatException('恢复草稿格式无效');
      final draft = EditorRecoveryDraft.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (draft.noteId != noteId) {
        throw const FormatException('恢复草稿与笔记不匹配');
      }
      return draft;
    } on FormatException {
      await _deleteIfPresent(file);
      return null;
    } on FileSystemException {
      return null;
    }
  }
}
