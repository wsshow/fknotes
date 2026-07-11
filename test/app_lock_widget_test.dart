import 'package:fknotes/app.dart';
import 'package:fknotes/pages/app_lock_settings_page.dart';
import 'package:fknotes/providers/app_lock_controller.dart';
import 'package:fknotes/services/app_lock_preferences_service.dart';
import 'package:fknotes/services/device_authentication_service.dart';
import 'package:fknotes/widgets/app_lock_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('lock screen stays visible after cancellation and allows retry', (
    tester,
  ) async {
    final store = _WidgetPreferencesStore(
      const AppLockPreferences(enabled: true),
    );
    final authenticator = _WidgetAuthenticator([
      const DeviceAuthenticationResult(
        DeviceAuthenticationStatus.canceled,
        '身份验证已取消，内容仍处于锁定状态',
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
        child: const MaterialApp(home: AppLockGate(child: Text('私密笔记内容'))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('非空笔记已锁定'), findsOneWidget);
    expect(find.textContaining('仍处于锁定状态'), findsOneWidget);

    await tester.tap(find.byKey(const Key('app-lock-unlock-button')));
    await tester.pumpAndSettle();

    expect(find.text('非空笔记已锁定'), findsNothing);
    expect(find.text('私密笔记内容'), findsOneWidget);
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
