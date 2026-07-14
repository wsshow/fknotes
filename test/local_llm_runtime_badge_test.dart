import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/models/local_llm.dart';
import 'package:fknotes/widgets/local_llm_runtime_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const model = LocalLlmModelDescriptor(
    id: 'model-a',
    name: 'Model A',
    configPath: '/model',
    nativeContextTokens: 4096,
  );

  testWidgets('shows detecting while the matching model loads', (tester) async {
    await _pumpBadge(
      tester,
      const LocalLlmRuntimeSnapshot(
        state: LocalLlmEngineState.loading,
        model: model,
        requestedBackend: LocalLlmBackend.openCl,
      ),
    );

    expect(find.text('检测中'), findsOneWidget);
  });

  testWidgets('shows the actual GPU backend', (tester) async {
    await _pumpBadge(
      tester,
      const LocalLlmRuntimeSnapshot(
        state: LocalLlmEngineState.ready,
        model: model,
        requestedBackend: LocalLlmBackend.openCl,
        activeBackend: LocalLlmBackend.openCl,
      ),
    );

    expect(find.text('GPU'), findsOneWidget);
    expect(find.bySemanticsLabel('当前运行后端：OpenCL · GPU'), findsOneWidget);
  });

  testWidgets('shows CPU after an accelerated backend falls back', (
    tester,
  ) async {
    const snapshot = LocalLlmRuntimeSnapshot(
      state: LocalLlmEngineState.ready,
      model: model,
      requestedBackend: LocalLlmBackend.openCl,
      activeBackend: LocalLlmBackend.cpu,
    );
    await _pumpBadge(tester, snapshot);

    expect(snapshot.usedBackendFallback, isTrue);
    expect(find.text('CPU'), findsOneWidget);
    expect(find.bySemanticsLabel('当前运行后端：CPU'), findsOneWidget);
  });

  testWidgets('hides the badge when the model is not installed', (
    tester,
  ) async {
    await _pumpBadge(
      tester,
      const LocalLlmRuntimeSnapshot(state: LocalLlmEngineState.idle),
      installed: false,
    );

    expect(find.byKey(const Key('local-llm-runtime-badge')), findsNothing);
  });
}

Future<void> _pumpBadge(
  WidgetTester tester,
  LocalLlmRuntimeSnapshot snapshot, {
  bool installed = true,
}) => tester.pumpWidget(
  MaterialApp(
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(
      body: LocalLlmRuntimeBadge(
        snapshot: snapshot,
        modelId: 'model-a',
        installed: installed,
      ),
    ),
  ),
);
