import 'dart:typed_data';

import 'package:fknotes/services/note_watermark_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('burns location, accuracy and time panel into camera bytes', () async {
    final source = img.Image(width: 1000, height: 700);
    img.fill(source, color: img.ColorRgb8(210, 120, 60));

    final output = await NoteWatermarkService.instance.applyLocationWatermark(
      Uint8List.fromList(img.encodeJpg(source, quality: 100)),
      NoteWatermarkLocation(
        latitude: 31.230416,
        longitude: 121.473701,
        accuracy: 8.4,
        capturedAt: DateTime(2026, 7, 29, 14, 5, 9),
      ),
    );
    final decoded = img.decodeJpg(output);

    expect(decoded, isNotNull);
    expect(decoded!.width, 1000);
    expect(decoded.height, 700);
    final untouched = decoded.getPixel(500, 100);
    final panel = decoded.getPixel(500, 620);
    expect(untouched.r, greaterThan(190));
    expect(panel.r, lessThan(untouched.r - 40));
    expect(output, isNotEmpty);
  });

  test('rejects undecodable watermark input', () async {
    await expectLater(
      NoteWatermarkService.instance.applyLocationWatermark(
        Uint8List.fromList([1, 2, 3]),
        NoteWatermarkLocation(
          latitude: 0,
          longitude: 0,
          accuracy: 0,
          capturedAt: DateTime(2026),
        ),
      ),
      throwsFormatException,
    );
  });
}
