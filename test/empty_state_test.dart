import 'package:fknotes/widgets/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('supports lifting an empty state within its content area', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: EmptyState(
              icon: Icons.folder_open_rounded,
              message: '当前筛选下没有内容',
              alignment: Alignment(0, -0.32),
            ),
          ),
        ),
      ),
    );

    final align = tester.widget<Align>(
      find.descendant(
        of: find.byType(EmptyState),
        matching: find.byType(Align),
      ),
    );
    expect(align.alignment, const Alignment(0, -0.32));
    expect(
      tester.getCenter(find.text('当前筛选下没有内容')).dy,
      lessThan(tester.getSize(find.byType(Scaffold)).height / 2),
    );
    expect(tester.takeException(), isNull);
  });
}
