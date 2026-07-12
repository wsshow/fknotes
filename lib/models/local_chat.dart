enum LocalChatRole { user, assistant }

enum LocalChatMessageStatus { complete, stopped }

enum LocalChatAttachmentType { image }

class LocalChatAttachment {
  final String id;
  final LocalChatAttachmentType type;
  final String filePath;
  final String fileName;
  final String mimeType;
  final DateTime createdAt;

  const LocalChatAttachment({
    required this.id,
    required this.type,
    required this.filePath,
    required this.fileName,
    required this.mimeType,
    required this.createdAt,
  });

  Map<String, Object> toJson() => {
    'id': id,
    'type': type.name,
    'filePath': filePath,
    'fileName': fileName,
    'mimeType': mimeType,
    'createdAt': createdAt.toIso8601String(),
  };

  factory LocalChatAttachment.fromJson(Map<String, Object?> json) {
    final id = json['id'] as String?;
    final filePath = json['filePath'] as String?;
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    if (id == null ||
        id.isEmpty ||
        filePath == null ||
        filePath.isEmpty ||
        createdAt == null) {
      throw const FormatException('聊天附件格式不正确');
    }
    return LocalChatAttachment(
      id: id,
      type: LocalChatAttachmentType.values.firstWhere(
        (value) => value.name == json['type'],
        orElse: () => LocalChatAttachmentType.image,
      ),
      filePath: filePath,
      fileName: json['fileName'] as String? ?? '图片',
      mimeType: json['mimeType'] as String? ?? 'image/*',
      createdAt: createdAt,
    );
  }
}

class LocalChatPersona {
  static const defaultId = 'default';
  static const defaultSystemPrompt =
      '你是 FKNotes 的本地助手。请准确、清晰地回答用户问题；不确定时应明确说明，不要编造事实。';

  final String id;
  final String name;
  final String description;
  final String systemPrompt;
  final bool builtIn;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LocalChatPersona({
    required this.id,
    required this.name,
    required this.description,
    required this.systemPrompt,
    required this.builtIn,
    required this.createdAt,
    required this.updatedAt,
  });

  LocalChatPersona copyWith({
    String? name,
    String? description,
    String? systemPrompt,
    DateTime? updatedAt,
  }) => LocalChatPersona(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    systemPrompt: systemPrompt ?? this.systemPrompt,
    builtIn: builtIn,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

class LocalChatMessage {
  final String id;
  final LocalChatRole role;
  final String content;
  final List<LocalChatAttachment> attachments;
  final DateTime createdAt;
  final LocalChatMessageStatus status;

  const LocalChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.attachments = const [],
    this.status = LocalChatMessageStatus.complete,
  });

  LocalChatMessage copyWith({
    String? content,
    List<LocalChatAttachment>? attachments,
    LocalChatMessageStatus? status,
  }) => LocalChatMessage(
    id: id,
    role: role,
    content: content ?? this.content,
    createdAt: createdAt,
    attachments: attachments ?? this.attachments,
    status: status ?? this.status,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'role': role.name,
    'content': content,
    'attachments': attachments
        .map((attachment) => attachment.toJson())
        .toList(),
    'createdAt': createdAt.toIso8601String(),
    'status': status.name,
  };

  factory LocalChatMessage.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final content = json['content'];
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    if (id is! String ||
        id.isEmpty ||
        content is! String ||
        createdAt == null) {
      throw const FormatException('聊天消息格式不正确');
    }
    return LocalChatMessage(
      id: id,
      role: switch (json['role']) {
        'user' => LocalChatRole.user,
        'assistant' => LocalChatRole.assistant,
        _ => throw const FormatException('聊天消息角色不正确'),
      },
      content: content,
      createdAt: createdAt,
      attachments: (json['attachments'] as List? ?? const [])
          .map(
            (attachment) => LocalChatAttachment.fromJson(
              Map<String, Object?>.from(attachment as Map),
            ),
          )
          .toList(growable: false),
      status: json['status'] == 'stopped'
          ? LocalChatMessageStatus.stopped
          : LocalChatMessageStatus.complete,
    );
  }
}

class LocalChatSession {
  final String id;
  final String title;
  final String personaId;
  final String systemPrompt;
  final List<LocalChatMessage> messages;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LocalChatSession({
    required this.id,
    required this.title,
    this.personaId = LocalChatPersona.defaultId,
    required this.systemPrompt,
    required this.messages,
    required this.createdAt,
    required this.updatedAt,
  });

  LocalChatSession copyWith({
    String? title,
    String? personaId,
    String? systemPrompt,
    List<LocalChatMessage>? messages,
    DateTime? updatedAt,
  }) => LocalChatSession(
    id: id,
    title: title ?? this.title,
    personaId: personaId ?? this.personaId,
    systemPrompt: systemPrompt ?? this.systemPrompt,
    messages: messages ?? this.messages,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'personaId': personaId,
    'systemPrompt': systemPrompt,
    'messages': messages.map((message) => message.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory LocalChatSession.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final title = json['title'];
    final systemPrompt = json['systemPrompt'];
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    final updatedAt = DateTime.tryParse(json['updatedAt'] as String? ?? '');
    final messages = json['messages'];
    if (id is! String ||
        id.isEmpty ||
        title is! String ||
        systemPrompt is! String ||
        createdAt == null ||
        updatedAt == null ||
        messages is! List) {
      throw const FormatException('聊天会话格式不正确');
    }
    return LocalChatSession(
      id: id,
      title: title,
      personaId: json['personaId'] as String? ?? LocalChatPersona.defaultId,
      systemPrompt: systemPrompt,
      messages: messages
          .map(
            (message) => LocalChatMessage.fromJson(
              Map<String, Object?>.from(message as Map),
            ),
          )
          .toList(growable: false),
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
