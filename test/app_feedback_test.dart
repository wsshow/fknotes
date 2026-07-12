import 'package:fknotes/widgets/app_feedback.dart';
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
}
