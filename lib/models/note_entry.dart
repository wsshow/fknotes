import '../utils/markdown_text.dart';

enum NoteType {
  text,
  image,
  audio,
  video,
  document;

  String get label => switch (this) {
    NoteType.text => '文字',
    NoteType.image => '图片',
    NoteType.audio => '音频',
    NoteType.video => '视频',
    NoteType.document => '文档',
  };

  String get dbValue => name;

  static NoteType fromDb(String value) => NoteType.values.firstWhere(
    (type) => type.dbValue == value,
    orElse: () => NoteType.text,
  );
}

enum NoteScope { active, favorites, archived, trash }

enum NoteSort { updated, created, title, size }

class NoteAttachment {
  final int? id;
  final int? noteId;
  final NoteType type;
  final String filePath;
  final String fileName;
  final int fileSize;
  final String mimeType;
  final String? thumbnailPath;
  final int? durationMs;
  final String? ocrText;
  final String? transcript;
  final String? transcriptionModel;
  final DateTime? transcribedAt;
  final int sortOrder;
  final DateTime createdAt;

  const NoteAttachment({
    this.id,
    this.noteId,
    required this.type,
    required this.filePath,
    required this.fileName,
    required this.fileSize,
    required this.mimeType,
    this.thumbnailPath,
    this.durationMs,
    this.ocrText,
    this.transcript,
    this.transcriptionModel,
    this.transcribedAt,
    this.sortOrder = 0,
    required this.createdAt,
  });

  NoteAttachment copyWith({
    int? id,
    int? noteId,
    NoteType? type,
    String? filePath,
    String? fileName,
    int? fileSize,
    String? mimeType,
    String? thumbnailPath,
    int? durationMs,
    String? ocrText,
    String? transcript,
    String? transcriptionModel,
    DateTime? transcribedAt,
    int? sortOrder,
    DateTime? createdAt,
  }) => NoteAttachment(
    id: id ?? this.id,
    noteId: noteId ?? this.noteId,
    type: type ?? this.type,
    filePath: filePath ?? this.filePath,
    fileName: fileName ?? this.fileName,
    fileSize: fileSize ?? this.fileSize,
    mimeType: mimeType ?? this.mimeType,
    thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    durationMs: durationMs ?? this.durationMs,
    ocrText: ocrText ?? this.ocrText,
    transcript: transcript ?? this.transcript,
    transcriptionModel: transcriptionModel ?? this.transcriptionModel,
    transcribedAt: transcribedAt ?? this.transcribedAt,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
  );

  Map<String, dynamic> toMap({int? parentId}) => {
    if (id != null) 'id': id,
    'note_id': parentId ?? noteId,
    'type': type.dbValue,
    'file_path': filePath,
    'file_name': fileName,
    'file_size': fileSize,
    'mime_type': mimeType,
    'thumbnail_path': thumbnailPath,
    'duration_ms': durationMs,
    'ocr_text': ocrText,
    'transcript': transcript,
    'transcription_model': transcriptionModel,
    'transcribed_at': transcribedAt?.toIso8601String(),
    'sort_order': sortOrder,
    'created_at': createdAt.toIso8601String(),
  };

  factory NoteAttachment.fromMap(Map<String, dynamic> map) => NoteAttachment(
    id: map['id'] as int?,
    noteId: map['note_id'] as int?,
    type: NoteType.fromDb(map['type'] as String? ?? 'document'),
    filePath: map['file_path'] as String? ?? '',
    fileName: map['file_name'] as String? ?? '',
    fileSize: map['file_size'] as int? ?? 0,
    mimeType: map['mime_type'] as String? ?? 'application/octet-stream',
    thumbnailPath: map['thumbnail_path'] as String?,
    durationMs: map['duration_ms'] as int?,
    ocrText: map['ocr_text'] as String?,
    transcript: map['transcript'] as String?,
    transcriptionModel: map['transcription_model'] as String?,
    transcribedAt: map['transcribed_at'] == null
        ? null
        : DateTime.tryParse(map['transcribed_at'] as String),
    sortOrder: map['sort_order'] as int? ?? 0,
    createdAt:
        DateTime.tryParse(map['created_at'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );
}

class NoteEntry {
  final int? id;
  final NoteType type;
  final String title;
  final String? content;
  final String? richContent;
  final String? filePath;
  final String? fileName;
  final int? fileSize;
  final String? mimeType;
  final String? thumbnailPath;
  final int? durationMs;
  final String? ocrText;
  final List<String> tags;
  final bool isFavorite;
  final bool isPinned;
  final bool isArchived;
  final bool isDeleted;
  final DateTime? deletedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<NoteAttachment> attachments;
  final bool attachmentsLoaded;

  const NoteEntry({
    this.id,
    required this.type,
    this.title = '',
    this.content,
    this.richContent,
    this.filePath,
    this.fileName,
    this.fileSize,
    this.mimeType,
    this.thumbnailPath,
    this.durationMs,
    this.ocrText,
    this.tags = const [],
    this.isFavorite = false,
    this.isPinned = false,
    this.isArchived = false,
    this.isDeleted = false,
    this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
    this.attachments = const [],
    this.attachmentsLoaded = false,
  });

  NoteEntry copyWith({
    int? id,
    NoteType? type,
    String? title,
    String? content,
    String? richContent,
    String? filePath,
    String? fileName,
    int? fileSize,
    String? mimeType,
    String? thumbnailPath,
    int? durationMs,
    String? ocrText,
    List<String>? tags,
    bool? isFavorite,
    bool? isPinned,
    bool? isArchived,
    bool? isDeleted,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<NoteAttachment>? attachments,
    bool? attachmentsLoaded,
  }) {
    return NoteEntry(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      content: content ?? this.content,
      richContent: richContent ?? this.richContent,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      mimeType: mimeType ?? this.mimeType,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      durationMs: durationMs ?? this.durationMs,
      ocrText: ocrText ?? this.ocrText,
      tags: tags ?? this.tags,
      isFavorite: isFavorite ?? this.isFavorite,
      isPinned: isPinned ?? this.isPinned,
      isArchived: isArchived ?? this.isArchived,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      attachments: attachments ?? this.attachments,
      attachmentsLoaded: attachments != null
          ? true
          : attachmentsLoaded ?? this.attachmentsLoaded,
    );
  }

  List<NoteAttachment> get allAttachments {
    if (attachments.isNotEmpty) return attachments;
    if (attachmentsLoaded) return const [];
    if (filePath?.isNotEmpty != true) return const [];
    return [
      NoteAttachment(
        noteId: id,
        type: type,
        filePath: filePath!,
        fileName: fileName ?? type.label,
        fileSize: fileSize ?? 0,
        mimeType: mimeType ?? 'application/octet-stream',
        thumbnailPath: thumbnailPath,
        durationMs: durationMs,
        ocrText: ocrText,
        createdAt: createdAt,
      ),
    ];
  }

  NoteAttachment? get primaryAttachment =>
      allAttachments.isEmpty ? null : allAttachments.first;

  NoteType get primaryType => primaryAttachment?.type ?? NoteType.text;

  bool containsType(NoteType candidate) {
    if (candidate == NoteType.text) {
      return allAttachments.isEmpty || (content?.trim().isNotEmpty ?? false);
    }
    return allAttachments.any((attachment) => attachment.type == candidate);
  }

  int attachmentCountFor(NoteType candidate) =>
      allAttachments.where((attachment) => attachment.type == candidate).length;

  String get attachmentSummary {
    final items = allAttachments;
    if (items.isEmpty) {
      final count = plainTextContent.replaceAll('\n', '').runes.length;
      return '文字 · $count 字';
    }
    final types = items.map((item) => item.type).toSet();
    if (types.length > 1 || (content?.trim().isNotEmpty ?? false)) {
      return '混合 · ${items.length} 项';
    }
    final only = types.first;
    final count = items.length;
    return switch (only) {
      NoteType.image => '图片 · $count 张',
      NoteType.audio => '录音 · $count 段',
      NoteType.video => '视频 · $count 个',
      NoteType.document => '文件 · $count 个',
      NoteType.text => '文字',
    };
  }

  String get aggregateOcr => allAttachments
      .map((attachment) => attachment.ocrText?.trim() ?? '')
      .where((text) => text.isNotEmpty)
      .join('\n');

  String get aggregateTranscripts => allAttachments
      .map((attachment) => attachment.transcript?.trim() ?? '')
      .where((text) => text.isNotEmpty)
      .join('\n');

  int get totalAttachmentSize =>
      allAttachments.fold(0, (sum, item) => sum + item.fileSize);

  Map<String, dynamic> toMap() {
    final primary = primaryAttachment;
    return {
      if (id != null) 'id': id,
      'type': primaryType.dbValue,
      'title': title,
      'content': content,
      'rich_content': richContent,
      'file_path': primary?.filePath,
      'file_name': primary?.fileName,
      'file_size': primary?.fileSize,
      'mime_type': primary?.mimeType,
      'thumbnail_path': primary?.thumbnailPath,
      'duration_ms': primary?.durationMs,
      'ocr_text': primary?.ocrText,
      'tags': tags.join('|'),
      'is_favorite': isFavorite ? 1 : 0,
      'is_pinned': isPinned ? 1 : 0,
      'is_archived': isArchived ? 1 : 0,
      'is_deleted': isDeleted ? 1 : 0,
      'deleted_at': deletedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toPortableMap() => {
    ...toMap(),
    'attachments': allAttachments.map((item) => item.toMap()).toList(),
  };

  factory NoteEntry.fromMap(Map<String, dynamic> map) {
    final rawTags = map['tags'] as String? ?? '';
    return NoteEntry(
      id: map['id'] as int?,
      type: NoteType.fromDb(map['type'] as String? ?? 'text'),
      title: map['title'] as String? ?? '',
      content: map['content'] as String?,
      richContent: map['rich_content'] as String?,
      filePath: map['file_path'] as String?,
      fileName: map['file_name'] as String?,
      fileSize: map['file_size'] as int?,
      mimeType: map['mime_type'] as String?,
      thumbnailPath: map['thumbnail_path'] as String?,
      durationMs: map['duration_ms'] as int?,
      ocrText: map['ocr_text'] as String?,
      tags: rawTags.isEmpty
          ? const []
          : rawTags.split('|').where((tag) => tag.trim().isNotEmpty).toList(),
      isFavorite: (map['is_favorite'] as int? ?? 0) == 1,
      isPinned: (map['is_pinned'] as int? ?? 0) == 1,
      isArchived: (map['is_archived'] as int? ?? 0) == 1,
      isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
      deletedAt: map['deleted_at'] == null
          ? null
          : DateTime.tryParse(map['deleted_at'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  String get previewText {
    if (plainTextContent.isNotEmpty) return plainTextContent;
    if (aggregateOcr.isNotEmpty) return aggregateOcr;
    if (aggregateTranscripts.isNotEmpty) return aggregateTranscripts;
    if (ocrText?.trim().isNotEmpty ?? false) return ocrText!;
    return '';
  }

  String get readableContent {
    final source = content?.trim() ?? '';
    if (source.isEmpty) return '';
    final attachmentsByPath = {
      for (final attachment in allAttachments)
        attachment.filePath: attachment.fileName,
    };
    return source.replaceAllMapped(
      RegExp(r'^\[\[附件:(.+)\]\]$', multiLine: true),
      (match) {
        final path = match.group(1) ?? '';
        final name = attachmentsByPath[path];
        return name == null ? '【附件已移除】' : '【附件：$name】';
      },
    );
  }

  String get plainTextContent => MarkdownText.toPlainText(readableContent);

  bool get hasMedia => allAttachments.isNotEmpty;
}
