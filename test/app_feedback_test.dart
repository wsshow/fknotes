import 'package:fknotes/widgets/app_feedback.dart';
import 'package:fknotes/widgets/app_feedback_navigator_observer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('new feedback replaces stale feedback instead of queueing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                AppFeedback.show(context, '第一条提示');
                AppFeedback.success(context, '最新提示');
              },
              child: const Text('显示提示'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('显示提示'));
    await tester.pump();

    expect(find.byKey(const Key('app-feedback')), findsOneWidget);
    expect(find.text('最新提示'), findsOneWidget);
    expect(find.text('第一条提示'), findsNothing);
    expect(
      tester.widget<SnackBar>(find.byType(SnackBar)).behavior,
      SnackBarBehavior.floating,
    );
    expect(
      tester.widget<SnackBar>(find.byType(SnackBar)).showCloseIcon,
      isTrue,
    );
  });

  testWidgets('action feedback exposes a single immediate action', (
    tester,
  ) async {
    var actionCalled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => AppFeedback.action(
                context,
                '已移到回收站',
                actionLabel: '撤销',
                onAction: () => actionCalled = true,
              ),
              child: const Text('删除'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('撤销'));

    expect(actionCalled, isTrue);
  });

  testWidgets('feedback has an explicit close affordance', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => AppFeedback.show(context, '可关闭提示'),
              child: const Text('显示提示'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('显示提示'));
    await tester.pumpAndSettle();
    expect(find.text('可关闭提示'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('可关闭提示'), findsNothing);
  });

  testWidgets('feedback is dismissed when navigating to another page', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [AppFeedbackNavigatorObserver()],
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () => AppFeedback.show(context, '当前页提示'),
                  child: const Text('显示提示'),
                ),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(body: Text('下一页')),
                    ),
                  ),
                  child: const Text('打开下一页'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('显示提示'));
    await tester.pumpAndSettle();
    expect(find.text('当前页提示'), findsOneWidget);

    await tester.tap(find.text('打开下一页'));
    await tester.pumpAndSettle();
    expect(find.text('下一页'), findsOneWidget);
    expect(find.text('当前页提示'), findsNothing);
  });
}
