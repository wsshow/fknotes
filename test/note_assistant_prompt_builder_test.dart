import 'package:fknotes/models/local_llm.dart';
import 'package:fknotes/services/local_llm/local_llm_output_filter.dart';
import 'package:fknotes/services/note_assistant_prompt_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('summary prompt preserves title and note content', () {
    final request = NoteAssistantPromptBuilder.build(
      task: NoteAssistantTask.summarize,
      title: '周会',
      content: '下周发布 1.0 版本。',
    );

    expect(request.messages.first.role, LocalLlmRole.system);
    expect(request.messages.last.content, contains('标题：周会'));
    expect(request.messages.last.content, contains('下周发布 1.0 版本。'));
    expect(request.options.maxNewTokens, 512);
  });

  test('todo prompt requires parseable unchecked todo lines', () {
    final request = NoteAssistantPromptBuilder.build(
      task: NoteAssistantTask.extractTodos,
      title: '',
      content: '明天提交报告',
    );

    expect(request.messages.last.content, contains('每行使用“☐ ”开头'));
  });

  test('long notes keep both ends within the mobile context budget', () {
    final content = '开' * 4000 + '中' * 4000 + '尾' * 4000;
    final request = NoteAssistantPromptBuilder.build(
      task: NoteAssistantTask.polish,
      title: '',
      content: content,
    );
    final prompt = request.messages.last.content;

    expect(prompt, contains('中间内容因移动端上下文限制已省略'));
    expect(prompt, contains('开' * 100));
    expect(prompt, contains('尾' * 100));
    expect(request.options.maxNewTokens, 768);
  });

  test('reasoning blocks never reach assistant output', () {
    expect(
      LocalLlmOutputFilter.visibleText(
        '<think>private reasoning</think>\n用户可见内容',
      ),
      '用户可见内容',
    );
    expect(LocalLlmOutputFilter.visibleText('开头\n<think>尚未结束'), '开头\n');
    expect(
      LocalLlmOutputFilter.visibleText('回答一<think>内部</think>回答二'),
      '回答一回答二',
    );
  });
}
