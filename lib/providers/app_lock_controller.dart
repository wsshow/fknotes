import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../debug/app_diagnostics.dart';
import '../services/app_lock_preferences_service.dart';
import '../services/device_authentication_service.dart';

class AppLockController extends ChangeNotifier with WidgetsBindingObserver {
  final AppLockPreferencesStore _preferencesStore;
  final DeviceAuthenticator _authenticator;
  final DateTime Function() _now;
  final bool _observesLifecycle;

  AppLockController({
    AppLockPreferencesStore? preferencesStore,
    DeviceAuthenticator? authenticator,
    DateTime Function()? now,
    bool observeLifecycle = true,
  }) : _preferencesStore =
           preferencesStore ?? AppLockPreferencesService.instance,
       _authenticator = authenticator ?? SystemDeviceAuthenticator.instance,
       _now = now ?? DateTime.now,
       _observesLifecycle = observeLifecycle {
    if (_observesLifecycle) WidgetsBinding.instance.addObserver(this);
  }

  AppLockPreferences _preferences = const AppLockPreferences();
  bool _initialized = false;
  bool _locked = true;
  bool _obscured = false;
  bool _authenticating = false;
  bool _automaticPromptAttempted = false;
  DateTime? _backgroundedAt;
  String? _message;
  DeviceAuthenticationMessage _messageId = DeviceAuthenticationMessage.none;

  bool get initialized => _initialized;
  bool get enabled => _preferences.enabled;
  AppLockTimeout get timeout => _preferences.timeout;
  bool get locked => enabled && _locked;
  bool get obscured => enabled && _obscured;
  bool get authenticating => _authenticating;
  String? get message => _message;
  DeviceAuthenticationMessage get messageId => _messageId;
  bool get shouldAutomaticallyAuthenticate =>
      _initialized &&
      enabled &&
      _locked &&
      !_obscured &&
      !_authenticating &&
      !_automaticPromptAttempted;

  Future<void> initialize() async {
    _preferences = await _preferencesStore.load();
    _locked = _preferences.enabled;
    _automaticPromptAttempted = false;
    _initialized = true;
    notifyListeners();
    if (kDebugMode) {
      AppDiagnostics.info(
        AppLogCategory.authentication,
        'app_lock_initialized',
        data: {'enabled': enabled, 'timeout': timeout.name},
      );
    }
  }

  Future<DeviceAuthenticationResult> authenticateAutomatically({
    DeviceAuthenticationPrompt prompt = const DeviceAuthenticationPrompt(
      reason: 'Verify your device identity to continue',
    ),
  }) async {
    if (!shouldAutomaticallyAuthenticate) {
      return const DeviceAuthenticationResult(
        DeviceAuthenticationStatus.canceled,
        '',
      );
    }
    _automaticPromptAttempted = true;
    return unlock(prompt: prompt);
  }

  Future<DeviceAuthenticationResult> unlock({
    DeviceAuthenticationPrompt prompt = const DeviceAuthenticationPrompt(
      reason: 'Verify your device identity to continue',
    ),
  }) async {
    if (!enabled || !_locked) {
      return const DeviceAuthenticationResult(
        DeviceAuthenticationStatus.authenticated,
        '',
      );
    }
    return _authenticate(prompt);
  }

  Future<DeviceAuthenticationResult> setEnabled(
    bool value, {
    DeviceAuthenticationPrompt? prompt,
  }) async {
    if (!_initialized || value == enabled) {
      return const DeviceAuthenticationResult(
        DeviceAuthenticationStatus.authenticated,
        '',
      );
    }
    if (!await _authenticator.isSupported()) {
      return const DeviceAuthenticationResult(
        DeviceAuthenticationStatus.unavailable,
        '请先在系统设置中配置锁屏密码、指纹或人脸识别',
        messageId: DeviceAuthenticationMessage.credentialsRequired,
      );
    }
    final result = await _authenticate(
      prompt ??
          DeviceAuthenticationPrompt(
            reason: value
                ? 'Verify your device identity to enable App lock'
                : 'Verify your device identity to disable App lock',
          ),
      unlockOnSuccess: false,
    );
    if (!result.authenticated) return result;

    final previous = _preferences;
    final updated = previous.copyWith(enabled: value);
    try {
      await _preferencesStore.save(updated);
    } catch (_) {
      return const DeviceAuthenticationResult(
        DeviceAuthenticationStatus.failed,
        '应用锁设置保存失败，请检查设备存储空间',
        messageId: DeviceAuthenticationMessage.appLockSaveFailed,
      );
    }
    _preferences = updated;
    _locked = false;
    _obscured = false;
    _automaticPromptAttempted = false;
    _message = null;
    _messageId = DeviceAuthenticationMessage.none;
    notifyListeners();
    if (kDebugMode) {
      AppDiagnostics.info(
        AppLogCategory.authentication,
        'app_lock_enabled_changed',
        data: {'enabled': value},
      );
    }
    return result;
  }

  Future<String?> setTimeout(AppLockTimeout value) async {
    if (value == timeout) return null;
    final updated = _preferences.copyWith(timeout: value);
    try {
      await _preferencesStore.save(updated);
    } catch (_) {
      return '自动锁定时间保存失败，请检查设备存储空间';
    }
    _preferences = updated;
    notifyListeners();
    if (kDebugMode) {
      AppDiagnostics.info(
        AppLogCategory.authentication,
        'app_lock_timeout_changed',
        data: {'timeout': value.name},
      );
    }
    return null;
  }

  void lockNow() {
    if (!enabled) return;
    _lock(allowAutomaticPrompt: false);
  }

  Future<DeviceAuthenticationResult> _authenticate(
    DeviceAuthenticationPrompt prompt, {
    bool unlockOnSuccess = true,
  }) async {
    if (_authenticating) {
      return const DeviceAuthenticationResult(
        DeviceAuthenticationStatus.failed,
        '系统身份验证正在进行',
        messageId: DeviceAuthenticationMessage.inProgress,
      );
    }
    _authenticating = true;
    _message = null;
    _messageId = DeviceAuthenticationMessage.none;
    notifyListeners();
    if (kDebugMode) {
      AppDiagnostics.info(
        AppLogCategory.authentication,
        'device_authentication_started',
        data: {'unlockOnSuccess': unlockOnSuccess},
      );
    }
    final result = await _authenticator.authenticate(prompt: prompt);
    _authenticating = false;
    if (result.authenticated) {
      if (unlockOnSuccess) _locked = false;
      _message = null;
      _messageId = DeviceAuthenticationMessage.none;
      _backgroundedAt = null;
    } else {
      _message = result.message;
      _messageId = result.messageId;
    }
    notifyListeners();
    if (kDebugMode) {
      AppDiagnostics.instance.record(
        result.authenticated ? AppLogLevel.info : AppLogLevel.warning,
        AppLogCategory.authentication,
        'device_authentication_completed',
        data: {
          'status': result.status.name,
          'messageId': result.messageId.name,
          'unlockOnSuccess': unlockOnSuccess,
        },
      );
    }
    return result;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    handleLifecycleState(state);
  }

  void handleLifecycleState(AppLifecycleState state) {
    if (kDebugMode) {
      AppDiagnostics.debug(
        AppLogCategory.application,
        'application_lifecycle_changed',
        data: {'state': state.name, 'lockEnabled': enabled, 'locked': locked},
      );
    }
    switch (state) {
      case AppLifecycleState.resumed:
        final backgroundedAt = _backgroundedAt;
        _backgroundedAt = null;
        _obscured = false;
        if (enabled && !_authenticating && backgroundedAt != null) {
          final elapsed = _now().difference(backgroundedAt);
          if (elapsed.inSeconds >= timeout.seconds) {
            _lock(allowAutomaticPrompt: true, notify: false);
          }
        }
        notifyListeners();
      case AppLifecycleState.inactive:
        if (enabled) {
          _obscured = true;
          notifyListeners();
        }
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        if (enabled) {
          _obscured = true;
          if (!_authenticating) _backgroundedAt ??= _now();
          notifyListeners();
        }
    }
  }

  void _lock({required bool allowAutomaticPrompt, bool notify = true}) {
    _locked = true;
    _message = null;
    _messageId = DeviceAuthenticationMessage.none;
    _automaticPromptAttempted = !allowAutomaticPrompt;
    if (notify) notifyListeners();
    if (kDebugMode) {
      AppDiagnostics.info(
        AppLogCategory.authentication,
        'application_locked',
        data: {'automaticPromptAllowed': allowAutomaticPrompt},
      );
    }
  }

  @override
  void dispose() {
    if (_observesLifecycle) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
