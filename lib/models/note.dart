import 'dart:collection';

import 'package:uuid/uuid.dart';

import 'note_document.dart';

final class NoteId {
  NoteId._(this.value);

  factory NoteId.generate() => NoteId._(const Uuid().v4());

  factory NoteId.parse(String value) {
    if (!_uuidPattern.hasMatch(value)) {
      throw FormatException('Invalid canonical note ID: $value');
    }
    return NoteId._(value);
  }

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is NoteId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

enum NoteAssetKind { image, audio, video, file }

final class NoteAsset {
  NoteAsset({
    required this.id,
    required this.kind,
    required this.storageKey,
    required this.originalName,
    this.displayName,
    required this.byteLength,
    required this.mimeType,
    this.previewStorageKey,
    this.durationMs,
    this.ocrText,
    this.transcript,
    this.transcriptionEngine,
    DateTime? transcribedAt,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : transcribedAt = transcribedAt?.toUtc(),
       createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc() {
    _validateStorageKey(
      storageKey,
      field: 'storageKey',
      root: switch (kind) {
        NoteAssetKind.image => 'notes/images',
        NoteAssetKind.audio => 'notes/audio',
        NoteAssetKind.video => 'notes/video',
        NoteAssetKind.file => 'notes/files',
      },
    );
    final preview = previewStorageKey;
    if (preview != null) {
      _validateStorageKey(
        preview,
        field: 'previewStorageKey',
        root: 'notes/thumbnails',
      );
    }
    if (originalName.trim().isEmpty) {
      throw ArgumentError.value(originalName, 'originalName');
    }
    if (byteLength < 0) {
      throw ArgumentError.value(byteLength, 'byteLength');
    }
    if (mimeType.trim().isEmpty) {
      throw ArgumentError.value(mimeType, 'mimeType');
    }
    if (durationMs != null && durationMs! < 0) {
      throw ArgumentError.value(durationMs, 'durationMs');
    }
  }

  final NoteAttachmentId id;
  final NoteAssetKind kind;
  final String storageKey;
  final String originalName;
  final String? displayName;
  final int byteLength;
  final String mimeType;
  final String? previewStorageKey;
  final int? durationMs;
  final String? ocrText;
  final String? transcript;
  final String? transcriptionEngine;
  final DateTime? transcribedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get displayTitle {
    final custom = displayName?.trim() ?? '';
    return custom.isEmpty ? originalName : custom;
  }

  NoteAsset copyWith({
    NoteAssetKind? kind,
    String? storageKey,
    String? originalName,
    Object? displayName = _unchanged,
    int? byteLength,
    String? mimeType,
    Object? previewStorageKey = _unchanged,
    Object? durationMs = _unchanged,
    Object? ocrText = _unchanged,
    Object? transcript = _unchanged,
    Object? transcriptionEngine = _unchanged,
    Object? transcribedAt = _unchanged,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => NoteAsset(
    id: id,
    kind: kind ?? this.kind,
    storageKey: storageKey ?? this.storageKey,
    originalName: originalName ?? this.originalName,
    displayName: identical(displayName, _unchanged)
        ? this.displayName
        : displayName as String?,
    byteLength: byteLength ?? this.byteLength,
    mimeType: mimeType ?? this.mimeType,
    previewStorageKey: identical(previewStorageKey, _unchanged)
        ? this.previewStorageKey
        : previewStorageKey as String?,
    durationMs: identical(durationMs, _unchanged)
        ? this.durationMs
        : durationMs as int?,
    ocrText: identical(ocrText, _unchanged) ? this.ocrText : ocrText as String?,
    transcript: identical(transcript, _unchanged)
        ? this.transcript
        : transcript as String?,
    transcriptionEngine: identical(transcriptionEngine, _unchanged)
        ? this.transcriptionEngine
        : transcriptionEngine as String?,
    transcribedAt: identical(transcribedAt, _unchanged)
        ? this.transcribedAt
        : transcribedAt as DateTime?,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  static void _validateStorageKey(
    String value, {
    required String field,
    required String root,
  }) {
    final normalized = value.replaceAll('\\', '/').trim();
    if (normalized != value ||
        !normalized.startsWith('$root/') ||
        normalized.length == root.length + 1 ||
        normalized.split('/').contains('..') ||
        normalized.split('/').contains('.') ||
        normalized.contains('//')) {
      throw ArgumentError.value(
        value,
        field,
        'Must be a canonical key inside $root',
      );
    }
  }
}

final class Note {
  Note({
    required this.id,
    required this.title,
    required this.document,
    Iterable<String> tags = const [],
    this.isPinned = false,
    this.coverAttachmentId,
    Iterable<NoteAsset> assets = const [],
    this.revision = 0,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : tags = List.unmodifiable(_normalizeTags(tags)),
       assets = List.unmodifiable(assets),
       createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc() {
    if (revision < 0) throw ArgumentError.value(revision, 'revision');
    _validateAssetGraph();
  }

  factory Note.newDraft({DateTime? now}) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    return Note(
      id: NoteId.generate(),
      title: '',
      document: NoteDocument.empty(),
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  final NoteId id;
  final String title;
  final NoteDocument document;
  final List<String> tags;
  final bool isPinned;
  final NoteAttachmentId? coverAttachmentId;
  final List<NoteAsset> assets;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;

  UnmodifiableMapView<NoteAttachmentId, NoteAsset> get assetsById =>
      UnmodifiableMapView({for (final asset in assets) asset.id: asset});

  NoteDocumentProjection get contentProjection {
    final byId = assetsById;
    return document.project(
      resolveEmbedText: (embed) {
        if (embed.kind == NoteEmbedKind.divider) return '——';
        final asset = byId[embed.attachmentId];
        return asset == null ? '' : '【${asset.displayTitle}】';
      },
    );
  }

  String get searchText {
    final values = <String>[
      title,
      contentProjection.plainText,
      ...tags,
      for (final asset in assets) ...[
        asset.displayTitle,
        asset.originalName,
        asset.ocrText ?? '',
        asset.transcript ?? '',
      ],
    ];
    return values
        .where((value) => value.trim().isNotEmpty)
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool get isMeaningfullyEmpty =>
      title.trim().isEmpty && contentProjection.isVisuallyEmpty;

  Note copyWith({
    String? title,
    NoteDocument? document,
    Iterable<String>? tags,
    bool? isPinned,
    Object? coverAttachmentId = _unchanged,
    Iterable<NoteAsset>? assets,
    int? revision,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Note(
    id: id,
    title: title ?? this.title,
    document: document ?? this.document,
    tags: tags ?? this.tags,
    isPinned: isPinned ?? this.isPinned,
    coverAttachmentId: identical(coverAttachmentId, _unchanged)
        ? this.coverAttachmentId
        : coverAttachmentId as NoteAttachmentId?,
    assets: assets ?? this.assets,
    revision: revision ?? this.revision,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  void _validateAssetGraph() {
    final byId = <NoteAttachmentId, NoteAsset>{};
    for (final asset in assets) {
      if (byId[asset.id] != null) {
        throw ArgumentError('Duplicate note asset ID: ${asset.id}');
      }
      byId[asset.id] = asset;
    }
    final referenced = document.project().referencedAttachmentIds.toSet();
    final missing = referenced.difference(byId.keys.toSet());
    if (missing.isNotEmpty) {
      throw ArgumentError('Document references missing assets: $missing');
    }
    final detached = byId.keys.toSet().difference(referenced);
    if (detached.isNotEmpty) {
      throw ArgumentError('Note contains detached assets: $detached');
    }
    final coverId = coverAttachmentId;
    if (coverId != null && !byId.containsKey(coverId)) {
      throw ArgumentError('Cover must reference an asset in the note.');
    }
  }

  static List<String> _normalizeTags(Iterable<String> values) {
    final result = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final tag = value.trim();
      if (tag.isEmpty || !seen.add(tag.toLowerCase())) continue;
      result.add(tag);
    }
    return result;
  }
}

const Object _unchanged = Object();
