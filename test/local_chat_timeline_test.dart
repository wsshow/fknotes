import 'package:fknotes/pages/local_chat_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat date labels distinguish today, yesterday and older messages', () {
    final now = DateTime(2026, 7, 12, 16, 30);

    expect(LocalChatTimeLabel.date(DateTime(2026, 7, 12), now: now), '今天');
    expect(LocalChatTimeLabel.date(DateTime(2026, 7, 11), now: now), '昨天');
    expect(LocalChatTimeLabel.date(DateTime(2026, 7, 1), now: now), '7月1日');
    expect(
      LocalChatTimeLabel.date(DateTime(2025, 12, 31), now: now),
      '2025年12月31日',
    );
    expect(LocalChatTimeLabel.time(DateTime(2026, 7, 12, 8, 5)), '08:05');
  });

  test('streaming follows only while the user remains near the bottom', () {
    expect(LocalChatScrollFollowPolicy.shouldFollow(0), isTrue);
    expect(LocalChatScrollFollowPolicy.shouldFollow(72), isTrue);
    expect(LocalChatScrollFollowPolicy.shouldFollow(72.1), isFalse);
    expect(LocalChatScrollFollowPolicy.shouldFollow(500), isFalse);
  });
}
