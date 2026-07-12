import '../models/local_llm.dart';

enum NoteAssistantTask { summarize, extractTodos, polish }

extension NoteAssistantTaskInfo on NoteAssistantTask {
  String get label => switch (this) {
    NoteAssistantTask.summarize => '总结笔记',
    NoteAssistantTask.extractTodos => '提取待办',
    NoteAssistantTask.polish => '润色内容',
  };

  String get resultHeading => switch (this) {
    NoteAssistantTask.summarize => '本地助手摘要',
    NoteAssistantTask.extractTodos => '本地助手待办',
    NoteAssistantTask.polish => '本地助手润色稿',
  };
}

class NoteAssistantPromptBuilder {
  // Conservative for Chinese text: leaves room for instructions and up to 768
  // generated tokens inside the mobile runtime's default 4096-token context.
  static const maxInputCharacters = 2800;

  static LocalLlmGenerationRequest build({
    required NoteAssistantTask task,
    required String title,
    required String content,
  }) {
    final note = _boundedNote(title: title, content: content);
    final instruction = switch (task) {
      NoteAssistantTask.summarize =>
        '请用简洁的中文总结这篇笔记。先给出一句核心结论，再列出不超过 5 个要点。'
            '不要添加原文没有的信息，不要输出思考过程。',
      NoteAssistantTask.extractTodos =>
        '请从笔记中提取明确可执行的待办事项。每行使用“☐ ”开头。'
            '不要臆造任务；如果没有待办，只回答“没有发现明确待办”。不要输出思考过程。',
      NoteAssistantTask.polish =>
        '请在不改变事实、数字、专有名词和中英文含义的前提下润色这篇笔记。'
            '保留原有段落结构，直接输出润色稿，不要解释修改过程。',
    };
    return LocalLlmGenerationRequest(
      messages: [
        const LocalLlmMessage(
          role: LocalLlmRole.system,
          content: '你是 FKNotes 的本地笔记助手。所有内容只在设备上处理。回答必须忠于用户笔记。',
        ),
        LocalLlmMessage(
          role: LocalLlmRole.user,
          content: '$instruction\n\n--- 笔记开始 ---\n$note\n--- 笔记结束 ---',
        ),
      ],
      options: LocalLlmGenerationOptions(
        maxNewTokens: task == NoteAssistantTask.polish ? 768 : 512,
      ),
    );
  }

  static String _boundedNote({required String title, required String content}) {
    final source = [
      if (title.trim().isNotEmpty) '标题：${title.trim()}',
      if (content.trim().isNotEmpty) '正文：\n${content.trim()}',
    ].join('\n\n');
    if (source.length <= maxInputCharacters) return source;
    const marker = '\n\n[中间内容因移动端上下文限制已省略]\n\n';
    final available = maxInputCharacters - marker.length;
    final leading = available ~/ 2;
    final trailing = available - leading;
    return '${source.substring(0, leading)}$marker'
        '${source.substring(source.length - trailing)}';
  }
}
