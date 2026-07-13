import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../debug/app_diagnostics.dart';

enum OcrStatus { recognized, noText, failed }

class OcrResult {
  final OcrStatus status;
  final String text;
  final String? errorMessage;

  const OcrResult._({required this.status, this.text = '', this.errorMessage});

  factory OcrResult.recognized(String text) =>
      OcrResult._(status: OcrStatus.recognized, text: text);

  const OcrResult.noText() : this._(status: OcrStatus.noText);

  factory OcrResult.failed(String message) =>
      OcrResult._(status: OcrStatus.failed, errorMessage: message);

  bool get hasText => status == OcrStatus.recognized;
  bool get didFail => status == OcrStatus.failed;
}

class OcrService {
  OcrService._();
  static final OcrService instance = OcrService._();

  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.chinese,
  );

  /// Extract text from an image file and preserve the difference between an
  /// image without text and a recognition failure.
  Future<OcrResult> recognizeText(String imagePath) async {
    final stopwatch = Stopwatch()..start();
    if (kDebugMode) {
      AppDiagnostics.info(AppLogCategory.media, 'ocr_started');
    }
    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        return OcrResult.failed('图片文件不存在');
      }

      final inputImage = InputImage.fromFile(file);
      final recognizedText = await _textRecognizer.processImage(inputImage);
      final text = recognizedText.text.trim();
      if (kDebugMode) {
        AppDiagnostics.info(
          AppLogCategory.media,
          'ocr_completed',
          data: {
            'durationMs': stopwatch.elapsedMilliseconds,
            'characterCount': text.length,
            'hasText': text.isNotEmpty,
          },
        );
      }
      return text.isEmpty
          ? const OcrResult.noText()
          : OcrResult.recognized(text);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        AppDiagnostics.error(
          AppLogCategory.media,
          'ocr_failed',
          data: {'durationMs': stopwatch.elapsedMilliseconds},
          error: error,
          stackTrace: stackTrace,
        );
      }
      return OcrResult.failed('文字识别暂时不可用，请稍后重试');
    }
  }

  /// Release resources
  Future<void> dispose() async {
    await _textRecognizer.close();
  }
}
