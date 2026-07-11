import 'package:fknotes/services/realtime_dictation_text_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('chooseRealtimeRefinement', () {
    test('accepts punctuation and formatting normalization', () {
      final decision = chooseRealtimeRefinement(
        streamingText: '今天是二零二六年七月十一日 test one two three',
        refinedText: '今天是二零二六年七月十一日，test one two three。',
      );

      expect(decision.accepted, isTrue);
      expect(decision.text, '今天是二零二六年七月十一日，test one two three。');
    });

    test('rejects a Chinese-to-English language drift', () {
      final decision = chooseRealtimeRefinement(
        streamingText: '这是 FKNotes 的中英文实时语音识别测试',
        refinedText: 'this is a foreign English transcription result',
      );

      expect(decision.accepted, isFalse);
      expect(decision.text, '这是 FKNotes 的中英文实时语音识别测试');
    });

    test('accepts a compatible recognition correction', () {
      final decision = chooseRealtimeRefinement(
        streamingText: '今天的天气非常好我们一起出去散布',
        refinedText: '今天的天气非常好，我们一起出去散步。',
      );

      expect(decision.accepted, isTrue);
      expect(decision.text, '今天的天气非常好，我们一起出去散步。');
    });

    test('rejects abnormal symbols and repeated hallucinations', () {
      final symbols = chooseRealtimeRefinement(
        streamingText: '这是一段正确的识别文本',
        refinedText: '♬♬♬@@@ wrong symbols',
      );
      final repeated = chooseRealtimeRefinement(
        streamingText: '这是一次正常的实时语音识别结果',
        refinedText: '错误内容错误内容错误内容错误内容',
      );

      expect(symbols.accepted, isFalse);
      expect(repeated.accepted, isFalse);
    });

    test('uses a valid offline result when streaming produced nothing', () {
      final decision = chooseRealtimeRefinement(
        streamingText: '',
        refinedText: '补充识别结果。',
      );

      expect(decision.accepted, isTrue);
      expect(decision.text, '补充识别结果。');
    });
  });

  group('mergeDictationSegment', () {
    test('ignores exact and already committed repetitions', () {
      final exact = mergeDictationSegment('你好世界', '你好世界');
      final suffix = mergeDictationSegment('第一段。你好世界', '你好世界');

      expect(exact.changed, isFalse);
      expect(exact.text, '你好世界');
      expect(suffix.changed, isFalse);
      expect(suffix.text, '第一段。你好世界');
    });

    test('trims Chinese and English boundary overlaps', () {
      final chinese = mergeDictationSegment('今天天气很好', '很好我们出去吧');
      final english = mergeDictationSegment(
        'hello streaming world',
        'world is working',
      );

      expect(chinese.text, '今天天气很好我们出去吧');
      expect(chinese.droppedPrefixLength, 2);
      expect(english.text, 'hello streaming world is working');
      expect(english.droppedPrefixLength, 5);
    });

    test('uses a cumulative segment instead of appending it', () {
      final result = mergeDictationSegment('这是实时识别', '这是实时识别的完整结果');

      expect(result.text, '这是实时识别的完整结果');
      expect(result.reason, contains('累计'));
    });

    test('keeps independent segments separated', () {
      final result = mergeDictationSegment('第一句话', '第二句话');

      expect(result.text, '第一句话。第二句话');
    });
  });
}
