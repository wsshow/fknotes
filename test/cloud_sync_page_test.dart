import 'dart:io';

import 'package:fknotes/pages/cloud_sync_page.dart';
import 'package:fknotes/models/cloud_sync.dart';
import 'package:fknotes/services/file_storage_service.dart';
import 'package:fknotes/services/cloud_sync_settings_service.dart';
import 'package:fknotes/services/cloud_sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fknotes_cloud_page');
    await FileStorageService.instance.init(baseDir: root.path);
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  testWidgets('offers manual WebDAV and S3 configuration without auto sync', (
    tester,
  ) async {
    final settings = CloudSyncSettingsService(
      settingsPath: '${root.path}/page-settings.json',
    );
    final service = CloudSyncService(settingsService: settings);
    await tester.pumpWidget(
      MaterialApp(
        home: CloudSyncPage(
          service: service,
          initialSettings: const CloudSyncSettings(deviceId: 'test-device'),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('仅手动同步用户数据'), findsOneWidget);
    expect(find.text('服务器地址'), findsOneWidget);

    await tester.tap(find.text('S3'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Endpoint'), findsOneWidget);
    expect(find.text('Access Key ID'), findsOneWidget);
    expect(find.text('Path-style 地址'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('立即同步'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('测试连接'), findsOneWidget);
    expect(find.text('立即同步'), findsOneWidget);
    expect(find.textContaining('只有手动点击'), findsOneWidget);
  });
}
