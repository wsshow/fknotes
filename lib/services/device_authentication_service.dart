import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';

enum DeviceAuthenticationStatus {
  authenticated,
  canceled,
  unavailable,
  lockedOut,
  failed,
}

class DeviceAuthenticationResult {
  final DeviceAuthenticationStatus status;
  final String message;

  const DeviceAuthenticationResult(this.status, this.message);

  bool get authenticated => status == DeviceAuthenticationStatus.authenticated;
}

abstract interface class DeviceAuthenticator {
  Future<bool> isSupported();

  Future<DeviceAuthenticationResult> authenticate({required String reason});
}

class SystemDeviceAuthenticator implements DeviceAuthenticator {
  SystemDeviceAuthenticator._();

  static final SystemDeviceAuthenticator instance =
      SystemDeviceAuthenticator._();

  final LocalAuthentication _authentication = LocalAuthentication();

  @override
  Future<bool> isSupported() async {
    try {
      return await _authentication.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<DeviceAuthenticationResult> authenticate({
    required String reason,
  }) async {
    try {
      final authenticated = await _authentication.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        sensitiveTransaction: true,
        persistAcrossBackgrounding: true,
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: '验证身份',
            signInHint: '',
            cancelButton: '取消',
          ),
          IOSAuthMessages(cancelButton: '取消', localizedFallbackTitle: '使用设备密码'),
        ],
      );
      return authenticated
          ? const DeviceAuthenticationResult(
              DeviceAuthenticationStatus.authenticated,
              '',
            )
          : const DeviceAuthenticationResult(
              DeviceAuthenticationStatus.failed,
              '身份验证未通过，请重试',
            );
    } on LocalAuthException catch (error) {
      return _resultForException(error);
    } catch (_) {
      return const DeviceAuthenticationResult(
        DeviceAuthenticationStatus.failed,
        '暂时无法调用系统身份验证，请稍后重试',
      );
    }
  }

  DeviceAuthenticationResult _resultForException(LocalAuthException error) {
    switch (error.code) {
      case LocalAuthExceptionCode.userCanceled:
      case LocalAuthExceptionCode.systemCanceled:
      case LocalAuthExceptionCode.timeout:
        return const DeviceAuthenticationResult(
          DeviceAuthenticationStatus.canceled,
          '认证已取消',
        );
      case LocalAuthExceptionCode.noCredentialsSet:
      case LocalAuthExceptionCode.noBiometricsEnrolled:
        return const DeviceAuthenticationResult(
          DeviceAuthenticationStatus.unavailable,
          '请先在系统设置中配置锁屏密码、指纹或人脸识别',
        );
      case LocalAuthExceptionCode.noBiometricHardware:
      case LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable:
        return const DeviceAuthenticationResult(
          DeviceAuthenticationStatus.unavailable,
          '当前设备无法使用系统身份验证',
        );
      case LocalAuthExceptionCode.temporaryLockout:
      case LocalAuthExceptionCode.biometricLockout:
        return const DeviceAuthenticationResult(
          DeviceAuthenticationStatus.lockedOut,
          '尝试次数过多，请使用设备密码或稍后重试',
        );
      case LocalAuthExceptionCode.authInProgress:
        return const DeviceAuthenticationResult(
          DeviceAuthenticationStatus.failed,
          '系统身份验证正在进行',
        );
      case LocalAuthExceptionCode.uiUnavailable:
        return const DeviceAuthenticationResult(
          DeviceAuthenticationStatus.failed,
          '暂时无法显示系统身份验证界面',
        );
      case LocalAuthExceptionCode.userRequestedFallback:
      case LocalAuthExceptionCode.deviceError:
      default:
        return const DeviceAuthenticationResult(
          DeviceAuthenticationStatus.failed,
          '系统身份验证失败，请重试',
        );
    }
  }
}
