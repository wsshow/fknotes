import 'package:fknotes/providers/app_lock_controller.dart';
import 'package:fknotes/services/app_lock_preferences_service.dart';
import 'package:fknotes/services/device_authentication_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('application lock is disabled by default', () async {
    final store = _MemoryPreferencesStore();
    final authenticator = _FakeAuthenticator();
    final controller = AppLockController(
      preferencesStore: store,
      authenticator: authenticator,
      observeLifecycle: false,
    );
    addTearDown(controller.dispose);

    await controller.initialize();

    expect(controller.initialized, isTrue);
    expect(controller.enabled, isFalse);
    expect(controller.locked, isFalse);
    expect(controller.timeout, AppLockTimeout.oneMinute);
    expect(authenticator.authenticationCount, 0);
  });

  test('enabled lock authenticates once automatically on cold start', () async {
    final store = _MemoryPreferencesStore(
      const AppLockPreferences(enabled: true),
    );
    final authenticator = _FakeAuthenticator();
    final controller = AppLockController(
      preferencesStore: store,
      authenticator: authenticator,
      observeLifecycle: false,
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    expect(controller.locked, isTrue);
    expect(controller.shouldAutomaticallyAuthenticate, isTrue);

    final result = await controller.authenticateAutomatically();

    expect(result.authenticated, isTrue);
    expect(controller.locked, isFalse);
    expect(authenticator.authenticationCount, 1);
  });

  test(
    'canceling automatic authentication stays locked without a prompt loop',
    () async {
      final store = _MemoryPreferencesStore(
        const AppLockPreferences(enabled: true),
      );
      final authenticator = _FakeAuthenticator(
        results: [
          const DeviceAuthenticationResult(
            DeviceAuthenticationStatus.canceled,
            '认证已取消',
          ),
          const DeviceAuthenticationResult(
            DeviceAuthenticationStatus.authenticated,
            '',
          ),
        ],
      );
      final controller = AppLockController(
        preferencesStore: store,
        authenticator: authenticator,
        observeLifecycle: false,
      );
      addTearDown(controller.dispose);

      await controller.initialize();
      await controller.authenticateAutomatically();

      expect(controller.locked, isTrue);
      expect(controller.shouldAutomaticallyAuthenticate, isFalse);
      expect(controller.message, '认证已取消');

      await controller.unlock();
      expect(controller.locked, isFalse);
      expect(authenticator.authenticationCount, 2);
    },
  );

  test('background timeout locks only after the selected interval', () async {
    var now = DateTime(2026, 7, 11, 15);
    final store = _MemoryPreferencesStore(
      const AppLockPreferences(enabled: true),
    );
    final controller = AppLockController(
      preferencesStore: store,
      authenticator: _FakeAuthenticator(),
      now: () => now,
      observeLifecycle: false,
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.authenticateAutomatically();
    controller.handleLifecycleState(AppLifecycleState.paused);
    expect(controller.obscured, isTrue);

    now = now.add(const Duration(seconds: 59));
    controller.handleLifecycleState(AppLifecycleState.resumed);
    expect(controller.locked, isFalse);

    controller.handleLifecycleState(AppLifecycleState.paused);
    now = now.add(const Duration(seconds: 60));
    controller.handleLifecycleState(AppLifecycleState.resumed);
    expect(controller.locked, isTrue);
    expect(controller.shouldAutomaticallyAuthenticate, isTrue);
  });

  test(
    'changing lock state requires authentication and persists the setting',
    () async {
      final store = _MemoryPreferencesStore();
      final authenticator = _FakeAuthenticator();
      final controller = AppLockController(
        preferencesStore: store,
        authenticator: authenticator,
        observeLifecycle: false,
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      expect((await controller.setEnabled(true)).authenticated, isTrue);
      expect(controller.enabled, isTrue);
      expect(store.preferences.enabled, isTrue);

      expect(await controller.setTimeout(AppLockTimeout.fiveMinutes), isNull);
      expect(store.preferences.timeout, AppLockTimeout.fiveMinutes);

      expect((await controller.setEnabled(false)).authenticated, isTrue);
      expect(controller.enabled, isFalse);
      expect(store.preferences.enabled, isFalse);
      expect(authenticator.authenticationCount, 2);
    },
  );

  test(
    'cannot enable the lock without system authentication support',
    () async {
      final store = _MemoryPreferencesStore();
      final authenticator = _FakeAuthenticator(supported: false);
      final controller = AppLockController(
        preferencesStore: store,
        authenticator: authenticator,
        observeLifecycle: false,
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      final result = await controller.setEnabled(true);

      expect(result.status, DeviceAuthenticationStatus.unavailable);
      expect(controller.enabled, isFalse);
      expect(store.preferences.enabled, isFalse);
      expect(authenticator.authenticationCount, 0);
    },
  );
}

class _MemoryPreferencesStore implements AppLockPreferencesStore {
  AppLockPreferences preferences;

  _MemoryPreferencesStore([this.preferences = const AppLockPreferences()]);

  @override
  Future<AppLockPreferences> load() async => preferences;

  @override
  Future<void> save(AppLockPreferences preferences) async {
    this.preferences = preferences;
  }
}

class _FakeAuthenticator implements DeviceAuthenticator {
  final bool supported;
  final List<DeviceAuthenticationResult> _results;
  int authenticationCount = 0;

  _FakeAuthenticator({
    this.supported = true,
    List<DeviceAuthenticationResult>? results,
  }) : _results =
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
    final index = authenticationCount.clamp(0, _results.length - 1);
    authenticationCount += 1;
    return _results[index];
  }

  @override
  Future<bool> isSupported() async => supported;
}
