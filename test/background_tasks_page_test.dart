import 'dart:io';

import 'package:fknotes/models/note_entry.dart';
import 'package:fknotes/pages/background_tasks_page.dart';
import 'package:fknotes/providers/note_provider.dart';
import 'package:fknotes/services/file_storage_service.dart';
import 'package:fknotes/services/local_inference_coordinator.dart';
import 'package:fknotes/services/video_import_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late NoteProvider provider;
  final imports = AttachmentImportService.instance;
  final inference = LocalInferenceCoordinator.instance;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fknotes_tasks_page_');
    await FileStorageService.instance.init(baseDir: root.path);
    await imports.resetForTesting(deletePersistence: true);
    inference.resetForTesting();
    provider = NoteProvider();
  });

  tearDown(() async {
    provider.dispose();
    inference.resetForTesting();
    await imports.resetForTesting(deletePersistence: true);
    await root.delete(recursive: true);
  });

  testWidgets('separates running and failed tasks and clears only failures', (
    tester,
  ) async {
    final handledTaskIds = <String>[];
    imports.addJobForTesting(
      const AttachmentImportJob(
        id: 'running-task',
        type: NoteType.video,
        fileName: '现场.mp4',
        mimeType: 'video/mp4',
        totalBytes: 100,
        copiedBytes: 40,
      ),
    );
    imports.addJobForTesting(
      const AttachmentImportJob(
        id: 'failed-task',
        type: NoteType.document,
        fileName: '失败.pdf',
        mimeType: 'application/pdf',
        totalBytes: 10,
        status: AttachmentImportStatus.failed,
        errorMessage: '磁盘错误',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BackgroundTasksPage(
          provider: provider,
          taskActionOverride: (item) async => handledTaskIds.add(item.id),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('进行中'), findsNWidgets(2));
    expect(find.text('需要处理'), findsNWidgets(2));
    expect(find.text('现场.mp4'), findsOneWidget);
    expect(find.text('失败.pdf'), findsOneWidget);

    await tester.tap(find.byKey(const Key('clear-failed-background-tasks')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('清除失败任务记录？'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('confirm-clear-failed-background-tasks')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(handledTaskIds, ['failed-task']);
    expect(find.text('失败.pdf'), findsOneWidget);
    expect(find.text('现场.mp4'), findsOneWidget);
  });

  testWidgets('shows a calm empty state when no work needs attention', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: BackgroundTasksPage(provider: provider)),
    );
    await tester.pump();

    expect(find.text('所有任务均已完成'), findsOneWidget);
    expect(find.text('当前没有正在运行或需要处理的任务'), findsOneWidget);
  });
}
