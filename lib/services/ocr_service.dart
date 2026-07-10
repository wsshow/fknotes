import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

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
    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        return OcrResult.failed('图片文件不存在');
      }

      final inputImage = InputImage.fromFile(file);
      final recognizedText = await _textRecognizer.processImage(inputImage);
      final text = recognizedText.text.trim();
      return text.isEmpty
          ? const OcrResult.noText()
          : OcrResult.recognized(text);
    } catch (error, stackTrace) {
      debugPrint('OCR recognition failed: $error\n$stackTrace');
      return OcrResult.failed('文字识别暂时不可用，请稍后重试');
    }
  }

  /// Release resources
  Future<void> dispose() async {
    await _textRecognizer.close();
  }
}
