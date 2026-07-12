enum LocalChatRole { user, assistant }

enum LocalChatMessageStatus { complete, stopped }

class LocalChatMessage {
  final String id;
  final LocalChatRole role;
  final String content;
  final DateTime createdAt;
  final LocalChatMessageStatus status;

  const LocalChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.status = LocalChatMessageStatus.complete,
  });

  LocalChatMessage copyWith({
    String? content,
    LocalChatMessageStatus? status,
  }) => LocalChatMessage(
    id: id,
    role: role,
    content: content ?? this.content,
    createdAt: createdAt,
    status: status ?? this.status,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'role': role.name,
    'content': content,
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
      status: json['status'] == 'stopped'
          ? LocalChatMessageStatus.stopped
          : LocalChatMessageStatus.complete,
    );
  }
}

class LocalChatSession {
  final String id;
  final String title;
  final String systemPrompt;
  final List<LocalChatMessage> messages;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LocalChatSession({
    required this.id,
    required this.title,
    required this.systemPrompt,
    required this.messages,
    required this.createdAt,
    required this.updatedAt,
  });

  LocalChatSession copyWith({
    String? title,
    String? systemPrompt,
    List<LocalChatMessage>? messages,
    DateTime? updatedAt,
  }) => LocalChatSession(
    id: id,
    title: title ?? this.title,
    systemPrompt: systemPrompt ?? this.systemPrompt,
    messages: messages ?? this.messages,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
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
