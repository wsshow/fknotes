import '../models/local_chat.dart';
import '../models/local_llm.dart';

class LocalChatPromptBuilder {
  static const maxContextCharacters = 2800;
  static const maxSystemPromptCharacters = 2000;
  static const markdownRenderingInstruction =
      '回答可使用标准 GitHub Flavored Markdown（标题、列表、引用、表格、链接和三反引号代码块）。'
      '不要输出用于布局的 HTML 标签；当前界面不渲染 LaTeX，公式请改用普通文本或代码块。'
      '表格必须包含表头和分隔行。';

  static LocalLlmGenerationRequest build({
    required String systemPrompt,
    required List<LocalChatMessage> messages,
  }) {
    final role = systemPrompt.trim();
    final system = _bounded(
      role.isEmpty
          ? markdownRenderingInstruction
          : '$role\n\n$markdownRenderingInstruction',
      maxSystemPromptCharacters,
    );
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
