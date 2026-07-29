import 'dart:isolate';
import 'dart:typed_data';

import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;

enum NoteWatermarkLocationFailure {
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  unavailable,
}

final class NoteWatermarkLocationException implements Exception {
  const NoteWatermarkLocationException(this.failure);

  final NoteWatermarkLocationFailure failure;
}

final class NoteWatermarkLocation {
  const NoteWatermarkLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.capturedAt,
  });

  final double latitude;
  final double longitude;
  final double accuracy;
  final DateTime capturedAt;
}

typedef NoteWatermarkLocationProvider =
    Future<NoteWatermarkLocation> Function();
typedef NoteImageWatermarker =
    Future<Uint8List> Function(Uint8List bytes, NoteWatermarkLocation location);

final class NoteWatermarkService {
  NoteWatermarkService._();

  static final NoteWatermarkService instance = NoteWatermarkService._();

  Future<NoteWatermarkLocation> currentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const NoteWatermarkLocationException(
        NoteWatermarkLocationFailure.serviceDisabled,
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const NoteWatermarkLocationException(
        NoteWatermarkLocationFailure.permissionDeniedForever,
      );
    }
    if (permission == LocationPermission.denied) {
      throw const NoteWatermarkLocationException(
        NoteWatermarkLocationFailure.permissionDenied,
      );
    }
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return NoteWatermarkLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        capturedAt: DateTime.now(),
      );
    } catch (_) {
      throw const NoteWatermarkLocationException(
        NoteWatermarkLocationFailure.unavailable,
      );
    }
  }

  Future<Uint8List> applyLocationWatermark(
    Uint8List bytes,
    NoteWatermarkLocation location,
  ) => Isolate.run(() => _applyLocationWatermark(bytes, location));
}

Uint8List _applyLocationWatermark(
  Uint8List bytes,
  NoteWatermarkLocation location,
) {
  if (bytes.isEmpty) throw const FormatException('图片内容为空');
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    throw const FormatException('图片解码失败');
  }
  if (decoded == null) throw const FormatException('图片解码失败');
  var image = img.bakeOrientation(decoded);
  const maximumPixels = 40 * 1000 * 1000;
  if (image.width * image.height > maximumPixels ||
      image.width > 16384 ||
      image.height > 16384) {
    throw const FormatException('图片分辨率过高');
  }
  const maximumLongEdge = 4096;
  if (image.width > maximumLongEdge || image.height > maximumLongEdge) {
    image = image.width >= image.height
        ? img.copyResize(image, width: maximumLongEdge)
        : img.copyResize(image, height: maximumLongEdge);
  }

  final font = image.width >= 1800
      ? img.arial48
      : image.width >= 900
      ? img.arial24
      : img.arial14;
  final margin = (image.width * .025).round().clamp(10, 96);
  final lineHeight = font.lineHeight;
  final panelHeight = lineHeight * 3 + margin * 2;
  final top = (image.height - panelHeight - margin).clamp(0, image.height - 1);
  img.fillRect(
    image,
    x1: margin,
    y1: top,
    x2: image.width - margin - 1,
    y2: image.height - margin - 1,
    radius: (margin * .45).round(),
    color: img.ColorRgba8(0, 0, 0, 166),
  );

  final localTime = location.capturedAt.toLocal();
  final date =
      '${localTime.year.toString().padLeft(4, '0')}-'
      '${localTime.month.toString().padLeft(2, '0')}-'
      '${localTime.day.toString().padLeft(2, '0')} '
      '${localTime.hour.toString().padLeft(2, '0')}:'
      '${localTime.minute.toString().padLeft(2, '0')}:'
      '${localTime.second.toString().padLeft(2, '0')}';
  final coordinate =
      'GPS ${location.latitude.toStringAsFixed(6)}, '
      '${location.longitude.toStringAsFixed(6)} '
      '+/- ${location.accuracy.round()}m';
  final textLeft = margin * 2;
  final textTop = top + margin;
  for (final (index, line) in [
    'FKNOTES LOCATION WATERMARK',
    date,
    coordinate,
  ].indexed) {
    img.drawString(
      image,
      line,
      font: font,
      x: textLeft,
      y: textTop + index * lineHeight,
      color: img.ColorRgb8(255, 255, 255),
    );
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 92));
}
