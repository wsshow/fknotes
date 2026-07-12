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

class NoteAssistantAction {
  final NoteAssistantTask? task;
  final String? instruction;

  const NoteAssistantAction.preset(NoteAssistantTask this.task)
    : instruction = null;

  NoteAssistantAction.custom(String instruction)
    : task = null,
      instruction = instruction.trim();

  bool get isCustom => task == null;

  String get label => task?.label ?? '自定义指令';

  String get resultHeading => task?.resultHeading ?? 'AI 生成内容';
}

class NoteAssistantPromptBuilder {
  // Conservative for Chinese text: leaves room for instructions and up to 768
  // generated tokens inside the mobile runtime's default 4096-token context.
  static const maxInputCharacters = 2800;

  static LocalLlmGenerationRequest build({
    required NoteAssistantAction action,
    required String title,
    required String content,
  }) {
    final rawInstruction = switch (action.task) {
      NoteAssistantTask.summarize =>
        '请用简洁的中文总结这篇笔记。先给出一句核心结论，再列出不超过 5 个要点。'
            '不要添加原文没有的信息，不要输出思考过程。',
      NoteAssistantTask.extractTodos =>
        '请从笔记中提取明确可执行的待办事项。每行使用“☐ ”开头。'
            '不要臆造任务；如果没有待办，只回答“没有发现明确待办”。不要输出思考过程。',
      NoteAssistantTask.polish =>
        '请在不改变事实、数字、专有名词和中英文含义的前提下润色这篇笔记。'
            '保留原有段落结构，直接输出润色稿，不要解释修改过程。',
      null => action.instruction!,
    };
    final instruction = _fitText(
      rawInstruction,
      maxInputCharacters,
      '\n\n[指令中间内容因移动端上下文限制已省略]\n\n',
    );
    final note = _boundedNote(
      title: title,
      content: content,
      maxCharacters: maxInputCharacters - instruction.length,
    );
    final noteSection = note.isEmpty
        ? '当前笔记为空，请直接根据用户指令回答。'
        : '--- 笔记开始 ---\n$note\n--- 笔记结束 ---';
    return LocalLlmGenerationRequest(
      messages: [
        const LocalLlmMessage(
          role: LocalLlmRole.system,
          content:
              '你是 FKNotes 的本地笔记助手。所有内容只在设备上处理。'
              '按照用户指令处理笔记，直接给出可用结果，不要输出思考过程。'
              '不得将臆测写成笔记中已存在的事实。',
        ),
        LocalLlmMessage(
          role: LocalLlmRole.user,
          content: '用户指令：\n$instruction\n\n$noteSection',
        ),
      ],
      options: LocalLlmGenerationOptions(
        maxNewTokens: action.isCustom || action.task == NoteAssistantTask.polish
            ? 768
            : 512,
      ),
    );
  }

  static String _boundedNote({
    required String title,
    required String content,
    required int maxCharacters,
  }) {
    final source = [
      if (title.trim().isNotEmpty) '标题：${title.trim()}',
      if (content.trim().isNotEmpty) '正文：\n${content.trim()}',
    ].join('\n\n');
    return _fitText(source, maxCharacters, '\n\n[笔记中间内容因移动端上下文限制已省略]\n\n');
  }

  static String _fitText(String source, int maxCharacters, String marker) {
    if (maxCharacters <= 0 || source.isEmpty) return '';
    if (source.length <= maxCharacters) return source;
    if (maxCharacters <= marker.length) {
      return source.substring(0, maxCharacters);
    }
    final available = maxCharacters - marker.length;
    final leading = available ~/ 2;
    final trailing = available - leading;
    return '${source.substring(0, leading)}$marker'
        '${source.substring(source.length - trailing)}';
  }
}
