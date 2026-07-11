import 'package:fknotes/services/app_build_metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats the version, build number and build time for display', () {
    final metadata = AppBuildMetadata(
      version: '2.3.4',
      buildNumber: '57',
      buildTime: DateTime(2026, 7, 11, 21, 30),
    );

    expect(metadata.versionLabel, '版本号 2.3.4 (57)');
    expect(metadata.buildTimeLabel, '构建时间 2026-07-11 21:30');
  });

  test('reports when a direct build did not inject a build time', () {
    const metadata = AppBuildMetadata(
      version: '1.0.0',
      buildNumber: '',
      buildTime: null,
    );

    expect(metadata.versionLabel, '版本号 1.0.0');
    expect(metadata.buildTimeLabel, '构建时间 未记录');
  });
}
