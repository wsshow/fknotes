import 'package:fknotes/models/local_chat.dart';
import 'package:fknotes/services/local_chat_tool_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hides complete and streaming partial tool tags', () {
    expect(
      LocalChatToolProtocol.visibleText(
        '我来查找。<fknotes_tool>{"name":"search_notes","query":"预算"}</fknotes_tool>',
      ),
      '我来查找。',
    );
    expect(LocalChatToolProtocol.visibleText('准备检索<fknotes_to'), '准备检索');
  });

  test('parses and validates controlled search and write calls', () {
    final calls = LocalChatToolProtocol.parseCalls(
      '<fknotes_tool>{"name":"search_notes","query":"项目预算"}</fknotes_tool>'
      '<fknotes_tool>{"name":"append_note","noteId":42,"content":"新增结论"}</fknotes_tool>',
    );

    expect(calls, hasLength(2));
    expect(calls.first.name, LocalChatToolName.searchNotes);
    expect(calls.first.query, '项目预算');
    expect(calls.last.name, LocalChatToolName.appendNote);
    expect(calls.last.noteId, 42);
    expect(calls.last.content, '新增结论');
    expect(calls.last.status, LocalChatToolStatus.proposed);
  });

  test('rejects unknown, malformed and incomplete calls', () {
    final calls = LocalChatToolProtocol.parseCalls(
      '<fknotes_tool>{"name":"delete_note","noteId":1}</fknotes_tool>'
      '<fknotes_tool>{"name":"replace_note","content":"缺少目标"}</fknotes_tool>'
      '<fknotes_tool>not-json</fknotes_tool>',
    );

    expect(calls, isEmpty);
  });
}
