import 'package:fknotes/pages/local_chat_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('user message selection stays visible on the coral bubble', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: LocalChatUserMessageText(content: '选择这段用户消息')),
      ),
    );

    final selectable = find.byType(SelectableText);
    final selectionTheme = TextSelectionTheme.of(tester.element(selectable));
    final text = tester.widget<SelectableText>(selectable);

    expect(
      selectionTheme.selectionColor,
      LocalChatUserMessageText.selectionColor,
    );
    expect(
      selectionTheme.selectionHandleColor,
      LocalChatUserMessageText.selectionHandleColor,
    );
    expect(text.style?.color, Colors.white);
    expect(tester.takeException(), isNull);
  });
}
