import '../models/local_chat.dart';
import '../models/local_llm.dart';

class LocalChatPromptBuilder {
  static const maxContextCharacters = 2800;
  static const maxSystemPromptCharacters = 2000;

  static LocalLlmGenerationRequest build({
    required String systemPrompt,
    required List<LocalChatMessage> messages,
  }) {
    final system = _bounded(systemPrompt.trim(), maxSystemPromptCharacters);
    var remaining = maxContextCharacters - system.length;
    final selected = <LocalLlmMessage>[];

    for (final message in messages.reversed) {
      if (message.content.trim().isEmpty && message.attachments.isEmpty) {
        continue;
      }
      if (message.role == LocalChatRole.assistant &&
          message.status != LocalChatMessageStatus.complete) {
        continue;
      }
      if (remaining <= 0) break;
      final content = _bounded(message.content.trim(), remaining);
      selected.add(
        LocalLlmMessage(
          role: message.role == LocalChatRole.user
              ? LocalLlmRole.user
              : LocalLlmRole.assistant,
          content: content,
          attachments: [
            for (final attachment in message.attachments)
              LocalLlmAttachment(
                path: attachment.filePath,
                mimeType: attachment.mimeType,
              ),
          ],
        ),
      );
      remaining -= content.length;
    }

    return LocalLlmGenerationRequest(
      messages: [
        if (system.isNotEmpty)
          LocalLlmMessage(role: LocalLlmRole.system, content: system),
        ...selected.reversed,
      ],
      options: const LocalLlmGenerationOptions(maxNewTokens: 768),
    );
  }

  static String _bounded(String value, int limit) {
    if (value.length <= limit) return value;
    const marker = '\n[较早内容已省略]\n';
    if (limit <= marker.length) return value.substring(value.length - limit);
    final available = limit - marker.length;
    final leading = available ~/ 2;
    final trailing = available - leading;
    return '${value.substring(0, leading)}$marker'
        '${value.substring(value.length - trailing)}';
  }
}
