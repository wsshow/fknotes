import 'dart:async';

import 'package:fknotes/app.dart';
import 'package:fknotes/pages/app_lock_settings_page.dart';
import 'package:fknotes/providers/app_lock_controller.dart';
import 'package:fknotes/services/app_lock_preferences_service.dart';
import 'package:fknotes/services/device_authentication_service.dart';
import 'package:fknotes/widgets/app_lock_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('lock screen stays visible after cancellation and allows retry', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final store = _WidgetPreferencesStore(
      const AppLockPreferences(enabled: true),
    );
    final authenticator = _WidgetAuthenticator([
      const DeviceAuthenticationResult(
        DeviceAuthenticationStatus.canceled,
        '认证已取消',
      ),
      const DeviceAuthenticationResult(
        DeviceAuthenticationStatus.authenticated,
        '',
      ),
    ]);
    final controller = AppLockController(
      preferencesStore: store,
      authenticator: authenticator,
      observeLifecycle: false,
    );
    await controller.initialize();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(360, 800),
              textScaler: TextScaler.linear(3.2),
            ),
            child: AppLockGate(child: Text('私密笔记内容')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('应用已锁定'), findsOneWidget);
    expect(find.text('认证已取消'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('app-lock-unlock-button')));
    await tester.pumpAndSettle();

    expect(find.text('应用已锁定'), findsNothing);
    expect(find.text('私密笔记内容'), findsOneWidget);
  });

  testWidgets('lock now waits for an explicit unlock action before auth', (
    tester,
  ) async {
    final store = _WidgetPreferencesStore(
      const AppLockPreferences(enabled: true),
    );
    final authenticator = _DeferredWidgetAuthenticator();
    final controller = AppLockController(
      preferencesStore: store,
      authenticator: authenticator,
      observeLifecycle: false,
    );
    await controller.initialize();
    await controller.authenticateAutomatically();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(home: AppLockGate(child: Text('私密笔记内容'))),
      ),
    );
    expect(find.text('私密笔记内容'), findsOneWidget);

    final pending = authenticator.deferNextAuthentication();
    controller.lockNow();
    await tester.pump();

    expect(find.text('应用已锁定'), findsOneWidget);
    expect(find.byKey(const Key('app-lock-unlock-button')), findsOneWidget);
    expect(authenticator.authenticationCount, 1);

    await tester.tap(find.byKey(const Key('app-lock-unlock-button')));
    await tester.pump();

    expect(find.text('等待系统验证'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(authenticator.authenticationCount, 2);

    pending.complete(
      const DeviceAuthenticationResult(
        DeviceAuthenticationStatus.authenticated,
        '',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('私密笔记内容'), findsOneWidget);
  });

  testWidgets('lock now covers the active settings route immediately', (
    tester,
  ) async {
    final store = _WidgetPreferencesStore(
      const AppLockPreferences(enabled: true),
    );
    final authenticator = _WidgetAuthenticator();
    final controller = AppLockController(
      preferencesStore: store,
      authenticator: authenticator,
      observeLifecycle: false,
    );
    await controller.initialize();
    await controller.authenticateAutomatically();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          builder: (context, child) =>
              AppLockGate(child: child ?? const SizedBox.shrink()),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const Key('open-app-lock-settings'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AppLockSettingsPage(),
                  ),
                ),
                child: const Text('打开应用锁设置'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-app-lock-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('app-lock-lock-now-button')));
    await tester.pump();

    expect(find.text('应用已锁定'), findsOneWidget);
    expect(find.byType(AppLockSettingsPage), findsOneWidget);
    expect(authenticator.authenticationCount, 1);
    final title = tester.renderObject<RenderParagraph>(find.text('应用已锁定'));
    expect(title.text.style?.decoration, isNot(TextDecoration.underline));
  });

  testWidgets('settings enable the lock through system authentication', (
    tester,
  ) async {
    final store = _WidgetPreferencesStore();
    final controller = AppLockController(
      preferencesStore: store,
      authenticator: _WidgetAuthenticator(),
      observeLifecycle: false,
    );
    await controller.initialize();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          theme: ThemeData(colorSchemeSeed: AppColors.moss),
          home: const AppLockSettingsPage(),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('app-lock-enabled-switch')));
    await tester.pumpAndSettle();

    expect(controller.enabled, isTrue);
    expect(store.preferences.enabled, isTrue);
    expect(find.text('离开应用后自动锁定'), findsOneWidget);
    expect(find.text('1 分钟后'), findsOneWidget);
  });
}

void _usePhoneViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(1080, 2400);
  addTearDown(tester.view.reset);
}

class _WidgetPreferencesStore implements AppLockPreferencesStore {
  AppLockPreferences preferences;

  _WidgetPreferencesStore([this.preferences = const AppLockPreferences()]);

  @override
  Future<AppLockPreferences> load() async => preferences;

  @override
  Future<void> save(AppLockPreferences preferences) async {
    this.preferences = preferences;
  }
}

class _WidgetAuthenticator implements DeviceAuthenticator {
  final List<DeviceAuthenticationResult> _results;
  int _index = 0;

  _WidgetAuthenticator([List<DeviceAuthenticationResult>? results])
    : _results =
          results ??
          [
            const DeviceAuthenticationResult(
              DeviceAuthenticationStatus.authenticated,
              '',
            ),
          ];

  int get authenticationCount => _index;

  @override
  Future<DeviceAuthenticationResult> authenticate({
    required String reason,
  }) async {
    final result = _results[_index.clamp(0, _results.length - 1)];
    _index += 1;
    return result;
  }

  @override
  Future<bool> isSupported() async => true;
}

class _DeferredWidgetAuthenticator implements DeviceAuthenticator {
  Completer<DeviceAuthenticationResult>? _pending;
  int authenticationCount = 0;

  Completer<DeviceAuthenticationResult> deferNextAuthentication() {
    return _pending = Completer<DeviceAuthenticationResult>();
  }

  @override
  Future<DeviceAuthenticationResult> authenticate({
    required String reason,
  }) async {
    authenticationCount += 1;
    final pending = _pending;
    if (pending != null) {
      _pending = null;
      return pending.future;
    }
    return const DeviceAuthenticationResult(
      DeviceAuthenticationStatus.authenticated,
      '',
    );
  }

  @override
  Future<bool> isSupported() async => true;
}
