import 'dart:io';

import 'package:fknotes/pages/model_management_page.dart';
import 'package:fknotes/services/file_storage_service.dart';
import 'package:fknotes/services/local_model_manager.dart';
import 'package:fknotes/services/speech_model_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory storageDirectory;

  setUpAll(() async {
    storageDirectory = await Directory.systemTemp.createTemp(
      'fknotes_model_management_test_',
    );
    await FileStorageService.instance.init(baseDir: storageDirectory.path);
    final partial = File(
      p.join(
        storageDirectory.path,
        'models',
        'asr',
        '.sensevoice-download',
        'model.int8.onnx.part',
      ),
    );
    await partial.parent.create(recursive: true);
    await partial.writeAsBytes(List<int>.filled(2048, 1));
    await File(
      p.join(partial.parent.path, 'tokens.txt.part'),
    ).writeAsBytes(List<int>.filled(512, 2));
    await File(
      p.join(partial.parent.path, 'MODEL_LICENSE.txt.part'),
    ).writeAsBytes(List<int>.filled(71, 3));
    await LocalModelManager.instance.initialize(force: true);
  });

  tearDownAll(() async {
    await storageDirectory.delete(recursive: true);
  });

  test('partial size includes every resumable model file', () async {
    expect(await SpeechModelService.instance.partialDownloadBytes(), 2631);
  });

  testWidgets('model manager groups available, built-in and planned models', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: ModelManagementPage()));
    await tester.pumpAndSettle();

    expect(find.text('本地模型'), findsOneWidget);
    expect(find.text('语音模型'), findsOneWidget);
    expect(find.text('SenseVoice Small INT8'), findsOneWidget);
    expect(find.text('继续下载'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();

    expect(find.text('Streaming Zipformer 中文'), findsOneWidget);
    expect(find.text('70.6 MB'), findsOneWidget);
    expect(find.text('下载'), findsWidgets);

    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await tester.pumpAndSettle();

    expect(find.text('视觉模型'), findsOneWidget);
    expect(find.text('ML Kit 中文文字识别'), findsOneWidget);
    expect(find.text('随应用提供'), findsOneWidget);
  });
}
