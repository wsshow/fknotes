import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/widgets/quiet_paper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('index reading stays in a single-line capsule', (tester) async {
    await tester.pumpWidget(
      const _IndexTicksTestApp(locale: Locale('zh'), index: 9, count: 10),
    );

    expect(find.text('10 / 10'), findsNothing);
    expect(find.text('10'), findsNWidgets(2));
    expect(
      find.byKey(const Key('index-ticks-reading-divider')),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const Key('index-ticks-reading'))).width,
      60,
    );
    expect(
      tester.getCenter(find.byKey(const Key('index-ticks-current'))).dy,
      tester.getCenter(find.byKey(const Key('index-ticks-total'))).dy,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('index reading keeps full large counts', (tester) async {
    await tester.pumpWidget(
      const _IndexTicksTestApp(locale: Locale('zh'), index: 4320, count: 10000),
    );

    expect(find.text('4321'), findsOneWidget);
    expect(find.text('10000'), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(IndexTicks)).getSemanticsData().value,
      '4321 / 10000',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('index reading uses full counts in every locale', (tester) async {
    await tester.pumpWidget(
      const _IndexTicksTestApp(locale: Locale('en'), index: 4319, count: 10000),
    );

    expect(find.text('4320'), findsOneWidget);
    expect(find.text('10000'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

final class _IndexTicksTestApp extends StatelessWidget {
  const _IndexTicksTestApp({
    required this.locale,
    required this.index,
    required this.count,
  });

  final Locale locale;
  final int index;
  final int count;

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 100,
          height: 320,
          child: IndexTicks(index: index, count: count, onDrag: null),
        ),
      ),
    ),
  );
}
