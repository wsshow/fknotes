import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppBuildMetadata {
  static const compiledAt = String.fromEnvironment('FKNOTES_BUILD_TIME');

  final String version;
  final String buildNumber;
  final DateTime? buildTime;

  const AppBuildMetadata({
    required this.version,
    required this.buildNumber,
    required this.buildTime,
  });

  static Future<AppBuildMetadata> load() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return AppBuildMetadata(
      version: packageInfo.version.trim(),
      buildNumber: packageInfo.buildNumber.trim(),
      buildTime: DateTime.tryParse(compiledAt)?.toLocal(),
    );
  }

  String get versionLabel =>
      buildNumber.isEmpty ? '版本号 $version' : '版本号 $version ($buildNumber)';

  String get buildTimeLabel => buildTime == null
      ? '构建时间 未记录'
      : '构建时间 ${DateFormat('yyyy-MM-dd HH:mm').format(buildTime!)}';
}
