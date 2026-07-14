import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/services/realtime_dictation_service.dart';
import 'package:fknotes/widgets/realtime_dictation_provider_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prefers platform hardware execution providers', () {
    expect(
      RealtimeDictationExecutionPolicy.preferredFor(
        isAndroid: true,
        isIOS: false,
      ),
      RealtimeDictationExecutionProvider.nnapi,
    );
    expect(
      RealtimeDictationExecutionPolicy.preferredFor(
        isAndroid: false,
        isIOS: true,
      ),
      RealtimeDictationExecutionProvider.coreMl,
    );
    expect(
      RealtimeDictationExecutionPolicy.preferredFor(
        isAndroid: false,
        isIOS: false,
      ),
      RealtimeDictationExecutionProvider.cpu,
    );
  });

  test('maps sherpa provider names to stable runtime values', () {
    expect(
      RealtimeDictationExecutionPolicy.fromSherpaName('nnapi'),
      RealtimeDictationExecutionProvider.nnapi,
    );
    expect(
      RealtimeDictationExecutionPolicy.fromSherpaName('CoreML'),
      RealtimeDictationExecutionProvider.coreMl,
    );
    expect(
      RealtimeDictationExecutionPolicy.fromSherpaName('unknown'),
      RealtimeDictationExecutionProvider.cpu,
    );
  });

  testWidgets('shows an accelerated provider with an accessible detail', (
    tester,
  ) async {
    await _pumpBadge(tester, RealtimeDictationExecutionProvider.nnapi);

    expect(find.text('NNAPI'), findsOneWidget);
    expect(find.bySemanticsLabel('实时语音执行器：NNAPI'), findsOneWidget);
  });

  testWidgets('explains a CPU fallback', (tester) async {
    await _pumpBadge(
      tester,
      RealtimeDictationExecutionProvider.cpu,
      fallback: true,
    );

    expect(find.text('CPU'), findsOneWidget);
    expect(find.bySemanticsLabel('硬件加速不可用，实时语音已回退至 CPU'), findsOneWidget);
  });
}

Future<void> _pumpBadge(
  WidgetTester tester,
  RealtimeDictationExecutionProvider provider, {
  bool fallback = false,
}) => tester.pumpWidget(
  MaterialApp(
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(
      body: RealtimeDictationProviderBadge(
        provider: provider,
        fallback: fallback,
      ),
    ),
  ),
);
