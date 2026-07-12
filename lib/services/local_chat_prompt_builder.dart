import '../models/local_chat.dart';
import '../models/local_llm.dart';

class LocalChatPromptBuilder {
  static const maxContextCharacters = 2800;
  static const maxSystemPromptCharacters = 2000;
  static const maxMultimodalAttachments = 4;
  static const markdownRenderingInstruction =
      '回答可使用标准 GitHub Flavored Markdown（标题、列表、引用、表格、链接和三反引号代码块）。'
      r'数学公式使用 LaTeX：行内公式用 $...$，独立公式块用 $$ 单独占行包围。'
      '不要输出用于布局的 HTML 标签。'
      '表格必须包含表头和分隔行。';
  static const englishMarkdownRenderingInstruction =
      'You may use standard GitHub Flavored Markdown: headings, lists, quotes, tables, links, and fenced code blocks. '
      r'Use LaTeX for math: $...$ inline and $$ on separate lines for display equations. '
      'Do not emit HTML for layout. Tables must include a header and separator row.';
  static const englishDefaultSystemPrompt =
      'You are FKNotes’ on-device assistant. Answer accurately and clearly. '
      'State uncertainty explicitly and never invent facts.';

  static LocalLlmGenerationRequest build({
    required String systemPrompt,
    required List<LocalChatMessage> messages,
    String languageCode = 'zh',
  }) {
    final useEnglish = languageCode.toLowerCase().startsWith('en');
    final rawRole = systemPrompt.trim();
    final role =
        useEnglish &&
            (rawRole.isEmpty || rawRole == LocalChatPersona.defaultSystemPrompt)
        ? englishDefaultSystemPrompt
        : rawRole;
    final renderingInstruction = useEnglish
        ? englishMarkdownRenderingInstruction
        : markdownRenderingInstruction;
    final system = _bounded(
      role.isEmpty ? renderingInstruction : '$role\n\n$renderingInstruction',
      maxSystemPromptCharacters,
    );
    var remaining = maxContextCharacters - system.length;
    var remainingAttachments = maxMultimodalAttachments;
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
      final attachments = message.attachments
          .take(remainingAttachments)
          .map(
            (attachment) => LocalLlmAttachment(
              path: attachment.filePath,
              mimeType: attachment.mimeType,
            ),
          )
          .toList(growable: false);
      if (content.isEmpty && attachments.isEmpty) continue;
      selected.add(
        LocalLlmMessage(
          role: message.role == LocalChatRole.user
              ? LocalLlmRole.user
              : LocalLlmRole.assistant,
          content: content,
          attachments: attachments,
        ),
      );
      remaining -= content.length;
      remainingAttachments -= attachments.length;
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
    final marker =
        '\n${value.contains(RegExp(r'[\u4e00-\u9fff]')) ? '[较早内容已省略]' : '[Earlier content omitted]'}\n';
    if (limit <= marker.length) return value.substring(value.length - limit);
    final available = limit - marker.length;
    final leading = available ~/ 2;
    final trailing = available - leading;
    return '${value.substring(0, leading)}$marker'
        '${value.substring(value.length - trailing)}';
  }
}
