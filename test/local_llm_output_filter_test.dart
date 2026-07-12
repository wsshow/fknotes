import 'package:fknotes/services/local_llm/local_llm_output_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('removes model reasoning, controls and stray layout wrappers', () {
    expect(
      LocalLlmOutputFilter.visibleText(
        '\n<div>\n回答\u0000内容\n</div>\n<think>内部推理</think>',
      ),
      '回答内容\n',
    );
  });

  test('preserves HTML examples inside fenced code blocks', () {
    const source = '```html\n<div>\n内容\n</div>\n```';
    expect(LocalLlmOutputFilter.visibleText(source), source);
  });

  test('does not erase indentation from the first content line', () {
    expect(LocalLlmOutputFilter.visibleText('    indented'), '    indented');
  });
}
