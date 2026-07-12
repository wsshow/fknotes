import 'package:fknotes/pages/search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('search page uses a cancel action instead of a back icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SearchPage()),
                ),
                child: const Text('打开搜索'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开搜索'));
    await tester.pumpAndSettle();

    expect(find.text('搜索你的本地知识库'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
    expect(find.text('笔记'), findsOneWidget);
    expect(find.text('附件'), findsOneWidget);
    expect(find.text('对话'), findsOneWidget);
    expect(find.text('本地对话'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('打开搜索'), findsOneWidget);
    expect(find.byType(SearchPage), findsNothing);
  });
}
