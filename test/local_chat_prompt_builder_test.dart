import 'package:fknotes/models/local_chat.dart';
import 'package:fknotes/models/local_llm.dart';
import 'package:fknotes/services/local_chat_prompt_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LocalChatMessage message(
    String id,
    LocalChatRole role,
    String content, {
    LocalChatMessageStatus status = LocalChatMessageStatus.complete,
  }) => LocalChatMessage(
    id: id,
    role: role,
    content: content,
    createdAt: DateTime(2026),
    status: status,
  );

  test('includes the custom system role and multi-turn history', () {
    final request = LocalChatPromptBuilder.build(
      systemPrompt: '你是一位严谨的代码审查员',
      messages: [
        message('1', LocalChatRole.user, '审查这段代码'),
        message('2', LocalChatRole.assistant, '请提供代码'),
        message('3', LocalChatRole.user, '先说检查步骤'),
      ],
    );

    expect(request.messages.first.role, LocalLlmRole.system);
    expect(request.messages.first.content, contains('你是一位严谨的代码审查员'));
    expect(
      request.messages.first.content,
      contains('GitHub Flavored Markdown'),
    );
    expect(request.messages.first.content, contains('LaTeX'));
    expect(request.messages.first.content, contains(r'行内公式用 $...$'));
    expect(request.messages.map((item) => item.role), [
      LocalLlmRole.system,
      LocalLlmRole.user,
      LocalLlmRole.assistant,
      LocalLlmRole.user,
    ]);
  });

  test('keeps recent context within the mobile budget', () {
    final request = LocalChatPromptBuilder.build(
      systemPrompt: List.filled(2000, '角').join(),
      messages: [
        message('1', LocalChatRole.user, List.filled(2500, '旧').join()),
        message('2', LocalChatRole.assistant, List.filled(1000, '答').join()),
        message('3', LocalChatRole.user, '最新问题'),
      ],
    );

    expect(
      request.messages.fold<int>(0, (sum, item) => sum + item.content.length),
      lessThanOrEqualTo(LocalChatPromptBuilder.maxContextCharacters),
    );
    expect(request.messages.last.content, '最新问题');
  });

  test('does not feed a stopped partial answer back to the model', () {
    final request = LocalChatPromptBuilder.build(
      systemPrompt: '',
      messages: [
        message('1', LocalChatRole.user, '继续'),
        message(
          '2',
          LocalChatRole.assistant,
          '不完整回答',
          status: LocalChatMessageStatus.stopped,
        ),
        message('3', LocalChatRole.user, '重新回答'),
      ],
    );

    expect(request.messages.skip(1).map((item) => item.content), [
      '继续',
      '重新回答',
    ]);
  });

  test('preserves image inputs for a future multimodal runtime', () {
    final request = LocalChatPromptBuilder.build(
      systemPrompt: '',
      messages: [
        LocalChatMessage(
          id: 'image',
          role: LocalChatRole.user,
          content: '这张图里有什么？',
          createdAt: DateTime(2026),
          attachments: [
            LocalChatAttachment(
              id: 'attachment',
              type: LocalChatAttachmentType.image,
              filePath: 'assistant/example.jpg',
              fileName: 'example.jpg',
              mimeType: 'image/jpeg',
              createdAt: DateTime(2026),
            ),
          ],
        ),
      ],
    );

    expect(request.messages.last.attachments, hasLength(1));
    expect(
      request.messages.last.attachments.single.path,
      'assistant/example.jpg',
    );
    expect(request.messages.last.attachments.single.mimeType, 'image/jpeg');
  });
}
