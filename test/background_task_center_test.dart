import 'dart:io';

import 'package:fknotes/models/note_entry.dart';
import 'package:fknotes/services/background_task_center.dart';
import 'package:fknotes/services/file_storage_service.dart';
import 'package:fknotes/services/local_inference_coordinator.dart';
import 'package:fknotes/services/video_import_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  final imports = AttachmentImportService.instance;
  final inference = LocalInferenceCoordinator.instance;
  final center = BackgroundTaskCenter.instance;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fknotes_task_center_');
    await FileStorageService.instance.init(baseDir: root.path);
    await imports.resetForTesting(deletePersistence: true);
    inference.resetForTesting();
  });

  tearDown(() async {
    inference.resetForTesting();
    await imports.resetForTesting(deletePersistence: true);
    await root.delete(recursive: true);
  });

  test('aggregates attachment progress and inference ownership', () {
    imports.addJobForTesting(
      const AttachmentImportJob(
        id: 'attachment-task',
        type: NoteType.video,
        fileName: '现场.mp4',
        mimeType: 'video/mp4',
        totalBytes: 100,
        copiedBytes: 40,
      ),
    );
    final lease = inference.acquire(
      type: LocalInferenceTaskType.liveDictation,
      ownerId: 'dictation-task',
    );

    expect(center.activeCount, 2);
    expect(
      center.items
          .where((item) => item.kind == BackgroundTaskKind.attachment)
          .single
          .progress,
      .4,
    );
    expect(
      center.items
          .where((item) => item.kind == BackgroundTaskKind.inference)
          .single
          .title,
      '实时听写',
    );

    lease.release();
    imports.dismiss('attachment-task');
    expect(center.items, isEmpty);
  });

  test('keeps failed jobs visible until the user handles them', () {
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

    expect(center.failedCount, 1);
    expect(center.items.single.description, '磁盘错误');
  });
}
