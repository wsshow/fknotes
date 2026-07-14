import 'package:fknotes/services/local_chat_citation_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('single-source answers hide raw citation markers', () {
    expect(
      LocalChatCitationFormatter.normalize(
        '笔记内容是 Controlled write works。[N1]\n\n[N1]',
        sourceCount: 1,
      ),
      '笔记内容是 Controlled write works。',
    );
  });

  test(
    'multi-source answers keep inline citations but remove marker lines',
    () {
      expect(
        LocalChatCitationFormatter.normalize(
          '预算为 20 万元 [N1]\n\n[N1]\n\n风险是测试时间不足 [N2]',
          sourceCount: 2,
        ),
        '预算为 20 万元 [N1]\n\n风险是测试时间不足 [N2]',
      );
    },
  );

  test('answers without note sources are unchanged', () {
    expect(
      LocalChatCitationFormatter.normalize('普通回答 [N1]', sourceCount: 0),
      '普通回答 [N1]',
    );
  });
}
