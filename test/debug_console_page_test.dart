import 'package:fknotes/debug/app_diagnostics.dart';
import 'package:fknotes/debug/debug_console_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('debug console filters and opens structured event details', (
    tester,
  ) async {
    AppDiagnostics.info(
      AppLogCategory.modelManagement,
      'debug_console_test_event',
      data: {'modelId': 'test-model'},
    );
    await tester.pumpWidget(const MaterialApp(home: DebugConsolePage()));

    expect(find.text('调试中心'), findsOneWidget);
    expect(find.text('debug_console_test_event'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'not-present');
    await tester.pump();
    expect(find.text('没有符合筛选条件的日志'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'debug_console_test_event');
    await tester.pump();
    await tester.tap(find.text('debug_console_test_event').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('test-model'), findsOneWidget);
  });
}
