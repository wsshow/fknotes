import 'package:fknotes/widgets/app_popup_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('an anchored menu opens below a top trigger without overlap', (
    tester,
  ) async {
    await _pumpMenu(tester, alignment: Alignment.topCenter, tooltip: '顶部菜单');

    final trigger = find.byTooltip('顶部菜单');
    final triggerRect = tester.getRect(trigger);
    await tester.tap(trigger);
    await tester.pumpAndSettle();

    final items = find.byType(MenuItemButton);
    expect(items, findsNWidgets(2));
    final menuTop = tester.getRect(items.first).top;
    expect(menuTop, greaterThan(triggerRect.bottom));
  });

  testWidgets('an anchored menu flips above a bottom trigger without overlap', (
    tester,
  ) async {
    await _pumpMenu(tester, alignment: Alignment.bottomCenter, tooltip: '底部菜单');

    final trigger = find.byTooltip('底部菜单');
    final triggerRect = tester.getRect(trigger);
    await tester.tap(trigger);
    await tester.pumpAndSettle();

    final items = find.byType(MenuItemButton);
    expect(items, findsNWidgets(2));
    final menuBottom = tester.getRect(items.last).bottom;
    expect(menuBottom, lessThan(triggerRect.top));
  });
}

Future<void> _pumpMenu(
  WidgetTester tester, {
  required Alignment alignment,
  required String tooltip,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: alignment,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: AppAnchoredMenuButton<String>(
              tooltip: tooltip,
              icon: const Icon(Icons.more_vert_rounded),
              actions: const [
                AppMenuAction(
                  value: 'first',
                  icon: Icons.edit_outlined,
                  label: '第一项',
                ),
                AppMenuAction(
                  value: 'second',
                  icon: Icons.delete_outline_rounded,
                  label: '第二项',
                ),
              ],
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
