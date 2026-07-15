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

  testWidgets('shows starting while the matching model loads', (tester) async {
    await _pumpBadge(
      tester,
      const LocalLlmRuntimeSnapshot(
        state: LocalLlmEngineState.loading,
        model: model,
        requestedBackend: LocalLlmBackend.openCl,
      ),
    );

    expect(find.text('启动中'), findsOneWidget);
    expect(find.bySemanticsLabel('正在启动本地模型，首次启动可能需要一点时间。'), findsOneWidget);
  });

  testWidgets('names the backend while it starts', (tester) async {
    await _pumpBadge(
      tester,
      const LocalLlmRuntimeSnapshot(
        state: LocalLlmEngineState.loading,
        model: model,
        requestedBackend: LocalLlmBackend.openCl,
        progress: LocalLlmRuntimeProgress(
          kind: LocalLlmRuntimeProgressKind.starting,
          backend: LocalLlmBackend.openCl,
        ),
      ),
    );

    expect(find.text('GPU 启动中'), findsOneWidget);
    expect(find.bySemanticsLabel('正在启动 OpenCL · GPU…'), findsOneWidget);
  });

  testWidgets('explains a GPU to CPU fallback while it is happening', (
    tester,
  ) async {
    const liteRtModel = LocalLlmModelDescriptor(
      engine: LocalLlmEngineKind.liteRtLm,
      id: 'model-a',
      name: 'Model A',
      configPath: '/model',
      nativeContextTokens: 4096,
    );
    await _pumpBadge(
      tester,
      const LocalLlmRuntimeSnapshot(
        state: LocalLlmEngineState.loading,
        model: liteRtModel,
        requestedBackend: LocalLlmBackend.openCl,
        progress: LocalLlmRuntimeProgress(
          kind: LocalLlmRuntimeProgressKind.switching,
          backend: LocalLlmBackend.cpu,
          previousBackend: LocalLlmBackend.openCl,
        ),
      ),
    );

    expect(find.text('切换 CPU'), findsOneWidget);
    expect(find.bySemanticsLabel('GPU 不可用，正在切换到 CPU…'), findsOneWidget);
  });

  testWidgets('shows that the interrupted message is retried on CPU', (
    tester,
  ) async {
    await _pumpBadge(
      tester,
      const LocalLlmRuntimeSnapshot(
        state: LocalLlmEngineState.generating,
        model: model,
        requestedBackend: LocalLlmBackend.openCl,
        activeBackend: LocalLlmBackend.cpu,
        progress: LocalLlmRuntimeProgress(
          kind: LocalLlmRuntimeProgressKind.retrying,
          backend: LocalLlmBackend.cpu,
          previousBackend: LocalLlmBackend.openCl,
        ),
      ),
    );

    expect(find.text('CPU 重试中'), findsOneWidget);
    expect(find.bySemanticsLabel('已切换到 CPU，正在重试这条消息…'), findsOneWidget);
  });

  testWidgets('explains that a standby model starts automatically', (
    tester,
  ) async {
    await _pumpBadge(
      tester,
      const LocalLlmRuntimeSnapshot(state: LocalLlmEngineState.idle),
    );

    expect(find.text('待命'), findsOneWidget);
    expect(
      find.bySemanticsLabel('发送消息时会自动启动；空闲 2 分钟后自动释放，以节省内存。'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('local-llm-runtime-badge')));
    await tester.pump();
    expect(find.text('发送消息时会自动启动；空闲 2 分钟后自动释放，以节省内存。'), findsOneWidget);
  });

  testWidgets('shows releasing before a stale backend label', (tester) async {
    await _pumpBadge(
      tester,
      const LocalLlmRuntimeSnapshot(
        state: LocalLlmEngineState.unloading,
        model: model,
        activeBackend: LocalLlmBackend.openCl,
      ),
    );

    expect(find.text('释放中'), findsOneWidget);
    expect(find.text('GPU'), findsNothing);
  });

  testWidgets('shows a failed state before a stale backend label', (
    tester,
  ) async {
    await _pumpBadge(
      tester,
      const LocalLlmRuntimeSnapshot(
        state: LocalLlmEngineState.failed,
        model: model,
        activeBackend: LocalLlmBackend.openCl,
      ),
    );

    expect(find.text('启动失败'), findsOneWidget);
    expect(find.text('GPU'), findsNothing);
  });

  testWidgets('does not describe an unavailable runtime as standby', (
    tester,
  ) async {
    await _pumpBadge(
      tester,
      const LocalLlmRuntimeSnapshot(state: LocalLlmEngineState.unavailable),
    );

    expect(find.text('不可用'), findsOneWidget);
    expect(find.text('待命'), findsNothing);
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

  testWidgets('does not claim a specific GPU API for LiteRT-LM', (
    tester,
  ) async {
    const liteRtModel = LocalLlmModelDescriptor(
      engine: LocalLlmEngineKind.liteRtLm,
      id: 'model-a',
      name: 'Model A',
      configPath: '/model',
      nativeContextTokens: 4096,
    );
    await _pumpBadge(
      tester,
      const LocalLlmRuntimeSnapshot(
        state: LocalLlmEngineState.ready,
        model: liteRtModel,
        requestedBackend: LocalLlmBackend.openCl,
        activeBackend: LocalLlmBackend.openCl,
      ),
    );

    expect(find.text('GPU'), findsOneWidget);
    expect(find.bySemanticsLabel('当前运行后端：GPU'), findsOneWidget);
    expect(find.textContaining('OpenCL'), findsNothing);
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
