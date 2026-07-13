import 'dart:io';

import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/models/local_model.dart';
import 'package:fknotes/pages/model_management_page.dart';
import 'package:fknotes/services/file_storage_service.dart';
import 'package:fknotes/services/local_model_manager.dart';
import 'package:fknotes/services/kokoro_tts_model_service.dart';
import 'package:fknotes/services/speech_model_service.dart';
import 'package:fknotes/services/speaker_diarization_model_service.dart';
import 'package:fknotes/services/speech_denoiser_model_service.dart';
import 'package:fknotes/services/voice_activity_model_service.dart';
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
    final vadPartial = File(
      p.join(
        storageDirectory.path,
        'models',
        'audio',
        'silero-vad-int8-16khz',
        '.download',
        '${VoiceActivityModelService.modelFileName}.part',
      ),
    );
    await vadPartial.parent.create(recursive: true);
    await vadPartial.writeAsBytes(List<int>.filled(123, 4));
    final denoiserPartial = File(
      p.join(
        storageDirectory.path,
        'models',
        'audio',
        SpeechDenoiserModelService.modelId,
        '.download',
        '${SpeechDenoiserModelService.modelFileName}.part',
      ),
    );
    await denoiserPartial.parent.create(recursive: true);
    await denoiserPartial.writeAsBytes(List<int>.filled(456, 6));
    final speakerDownload = Directory(
      p.join(
        storageDirectory.path,
        'models',
        'audio',
        SpeakerDiarizationModelService.modelId,
        '.download',
      ),
    );
    await speakerDownload.create(recursive: true);
    await File(
      p.join(
        speakerDownload.path,
        '${SpeakerDiarizationModelService.segmentationArchiveName}.part',
      ),
    ).writeAsBytes(List<int>.filled(111, 7));
    await File(
      p.join(
        speakerDownload.path,
        '${SpeakerDiarizationModelService.embeddingFileName}.part',
      ),
    ).writeAsBytes(List<int>.filled(222, 8));
    final ttsPartial = File(
      p.join(
        storageDirectory.path,
        'models',
        'tts',
        KokoroTtsModelService.modelId,
        '.download',
        '${KokoroTtsModelService.archiveFileName}.part',
      ),
    );
    await ttsPartial.parent.create(recursive: true);
    await ttsPartial.writeAsBytes(List<int>.filled(321, 5));
    await LocalModelManager.instance.initialize(force: true);
  });

  tearDownAll(() async {
    await storageDirectory.delete(recursive: true);
  });

  test('partial size includes every resumable model file', () async {
    expect(await SpeechModelService.instance.partialDownloadBytes(), 2631);
    expect(
      await VoiceActivityModelService.instance.partialDownloadBytes(),
      123,
    );
    expect(await KokoroTtsModelService.instance.partialDownloadBytes(), 321);
    expect(
      await SpeechDenoiserModelService.instance.partialDownloadBytes(),
      456,
    );
    expect(
      await SpeakerDiarizationModelService.instance.partialDownloadBytes(),
      333,
    );
  });

  testWidgets('overview only shows active models and category navigation', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: ModelManagementPage()));
    await tester.pumpAndSettle();

    expect(find.text('本地模型'), findsOneWidget);
    expect(find.text('正在使用'), findsOneWidget);
    expect(find.text('分类管理'), findsOneWidget);
    expect(
      find.byKey(const Key('model-download-source-setting')),
      findsNothing,
    );
    expect(find.text('语言模型'), findsOneWidget);
    expect(find.text('语音模型'), findsOneWidget);
    expect(find.text('视觉模型'), findsOneWidget);
    expect(find.text('下载与存储'), findsOneWidget);
    expect(find.text('ML Kit 中文文字识别'), findsOneWidget);
    expect(find.text('Qwen3.5 2B INT4'), findsNothing);
    expect(find.byIcon(Icons.download_rounded), findsNothing);
    expect(find.byIcon(Icons.folder_open_rounded), findsNothing);
  });

  testWidgets('speech configuration owns live dictation settings', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: ModelManagementPage(category: LocalModelCategory.speech),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('语音模型'), findsOneWidget);
    expect(find.text('实时听写设置'), findsOneWidget);
    expect(find.text('热词增强'), findsNothing);

    await tester.tap(find.text('实时听写设置'));
    await tester.pumpAndSettle();
    expect(find.text('热词增强'), findsOneWidget);
    expect(find.text('结束后精修'), findsOneWidget);
    expect(find.text('实时降噪'), findsOneWidget);

    await tester.tap(find.byKey(const Key('live-dictation-hotwords-card')));
    await tester.pumpAndSettle();
    expect(find.text('实时听写热词'), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('download actions fill the model card width on phones', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: ModelManagementPage(category: LocalModelCategory.language),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('可获取'));
    await tester.pumpAndSettle();

    final modelId = LocalModelManager.qwen3Vl4BId;
    final importFinder = find.byKey(Key('model-import-$modelId'));
    await tester.scrollUntilVisible(
      importFinder,
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final card = tester.getRect(find.byKey(Key('model-card-$modelId')));
    final importButton = tester.getRect(importFinder);
    final downloadButton = tester.getRect(
      find.byKey(Key('model-download-$modelId')),
    );

    expect(importButton.left, closeTo(card.left + 16, 1.1));
    expect(downloadButton.right, closeTo(card.right - 16, 1.1));
    expect(importButton.width, closeTo(downloadButton.width, 1.1));
    expect(downloadButton.left - importButton.right, closeTo(10, 1.1));
  });

  testWidgets('focused model entry opens its category and availability', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: ModelManagementPage(focusModelId: LocalModelManager.qwen3Vl4BId),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('语言模型'), findsOneWidget);
    expect(find.text('可获取'), findsOneWidget);
    expect(find.text('Qwen3-VL 4B Instruct INT4'), findsOneWidget);
    expect(find.text('正在使用'), findsNothing);
  });

  testWidgets('model catalog renders localized English metadata', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ModelManagementPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Local models'), findsOneWidget);
    expect(find.text('In use'), findsOneWidget);
    expect(find.text('Manage by category'), findsOneWidget);
    expect(find.text('Language models'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Downloads and storage'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Downloads and storage'), findsOneWidget);
    expect(find.text('Model download source'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
