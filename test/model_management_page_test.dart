import 'dart:io';

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
    expect(find.text('实时听写设置'), findsOneWidget);
    expect(find.text('热词增强'), findsOneWidget);
    expect(find.text('结束后精修'), findsOneWidget);
    expect(find.text('实时降噪'), findsOneWidget);
    final noiseSuppressionSwitch = tester.widget<Switch>(
      find.byKey(const Key('live-dictation-noise-suppression-switch')),
    );
    expect(noiseSuppressionSwitch.value, isFalse);
    expect(noiseSuppressionSwitch.onChanged, isNull);
    expect(
      tester
          .widget<Switch>(
            find.byKey(const Key('live-dictation-two-pass-switch')),
          )
          .value,
      isFalse,
    );

    await tester.tap(find.byKey(const Key('live-dictation-hotwords-card')));
    await tester.pumpAndSettle();
    expect(find.text('实时听写热词'), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.enterText(
      find.byKey(const Key('live-dictation-hotwords-field')),
      'FKNotes\n非空笔记\nfknotes',
    );
    tester.testTextInput.hide();
    await tester.ensureVisible(
      find.byKey(const Key('save-live-dictation-hotwords')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('save-live-dictation-hotwords')).hitTestable(),
      findsOneWidget,
    );
    final saveButton = tester.widget<FilledButton>(
      find.byKey(const Key('save-live-dictation-hotwords')),
    );
    await tester.runAsync(() async {
      await (saveButton.onPressed as dynamic)();
    });
    await tester.pumpAndSettle();
    expect(find.text('实时听写热词'), findsNothing);
    expect(find.text('已保存 2 个热词'), findsOneWidget);
    expect(find.text('2 个热词 · 强度 2.0'), findsOneWidget);
    expect(
      tester
          .widget<Switch>(
            find.byKey(const Key('live-dictation-two-pass-switch')),
          )
          .value,
      isFalse,
    );

    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();

    expect(find.text('Streaming Zipformer 中文'), findsOneWidget);
    expect(find.text('159.6 MB'), findsOneWidget);
    expect(find.text('当前听写'), findsOneWidget);
    expect(find.text('下载'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('Streaming Zipformer 中英双语'),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Streaming Zipformer 中英双语'), findsOneWidget);
    expect(find.text('189.1 MB'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Silero VAD INT8'),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Silero VAD INT8'), findsOneWidget);
    expect(find.text('207.9 KB'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('DPDFNet 实时降噪'),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('DPDFNet 实时降噪'), findsOneWidget);
    expect(find.text('8.4 MB'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Pyannote + 3D-Speaker'),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Pyannote + 3D-Speaker'), findsOneWidget);
    expect(find.text('44.4 MB'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Kokoro 中英双语 INT8'),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Kokoro 中英双语 INT8'), findsOneWidget);
    expect(find.text('140.2 MB'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await tester.pumpAndSettle();

    expect(find.text('视觉模型'), findsOneWidget);
    expect(find.text('ML Kit 中文文字识别'), findsOneWidget);
    expect(find.text('随应用提供'), findsOneWidget);
  });
}
