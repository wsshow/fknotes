import 'package:fknotes/widgets/fk_markdown_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders GFM model output instead of syntax markers', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FkMarkdownView(
            data:
                '# 标题\n\n**重点**\n\n- [ ] 待办\n\n```dart\nfinal ok = true;\n```',
          ),
        ),
      ),
    );

    expect(find.text('标题'), findsOneWidget);
    expect(find.text('重点'), findsOneWidget);
    expect(find.text('待办'), findsOneWidget);
    expect(find.textContaining('final ok = true;'), findsOneWidget);
    expect(find.textContaining('**'), findsNothing);
  });

  testWidgets('does not load remote images from private markdown', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FkMarkdownView(
            data: '![秘密图片](https://example.com/tracker.png)',
          ),
        ),
      ),
    );

    expect(find.text('未加载外部图片：秘密图片'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('external links require an explicit confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FkMarkdownView(data: '[官网](https://example.com/path)'),
        ),
      ),
    );

    await tester.tap(find.text('官网'));
    await tester.pumpAndSettle();
    expect(find.text('打开外部链接？'), findsOneWidget);
    expect(find.textContaining('example.com'), findsOneWidget);
    expect(find.text('继续打开'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('打开外部链接？'), findsNothing);
  });

  testWidgets('unsafe link schemes are rejected', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FkMarkdownView(data: '[危险链接](javascript:alert(1))'),
        ),
      ),
    );

    await tester.tap(find.text('危险链接'));
    await tester.pump();
    expect(find.text('这个链接地址无效或使用了不受支持的协议'), findsOneWidget);
    expect(find.text('打开外部链接？'), findsNothing);
  });
}
