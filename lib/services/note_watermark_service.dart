import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:geocoding/geocoding.dart';
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
    this.latitude,
    this.longitude,
    this.accuracy,
    this.placeName,
    required this.capturedAt,
  });

  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final String? placeName;
  final DateTime capturedAt;

  bool get hasCoordinates => latitude != null && longitude != null;

  String? get normalizedPlaceName => normalizeNoteWatermarkPlaceName(placeName);

  String? get coordinateSummary {
    final latitude = this.latitude;
    final longitude = this.longitude;
    if (latitude == null || longitude == null) return null;
    final accuracy = this.accuracy;
    final accuracyLabel = accuracy == null ? '' : '  ±${accuracy.round()}m';
    return 'GPS ${latitude.toStringAsFixed(6)}, '
        '${longitude.toStringAsFixed(6)}$accuracyLabel';
  }

  NoteWatermarkLocation withPlaceName(String value) => NoteWatermarkLocation(
    latitude: latitude,
    longitude: longitude,
    accuracy: accuracy,
    placeName: value,
    capturedAt: capturedAt,
  );
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
      String? placeName;
      try {
        final placemarks = await Geocoding().placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final placemark = placemarks.first;
          placeName = formatNoteWatermarkPlaceName(
            name: placemark.name,
            street: placemark.street,
            country: placemark.country,
            administrativeArea: placemark.administrativeArea,
            locality: placemark.locality,
            subLocality: placemark.subLocality,
            thoroughfare: placemark.thoroughfare,
            subThoroughfare: placemark.subThoroughfare,
          );
        }
      } catch (_) {
        // GPS data is still useful and the location sheet offers manual input
        // when the native reverse-geocoder is unavailable or rate limited.
      }
      return NoteWatermarkLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        placeName: placeName,
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
  ) async {
    final imageWidth = await Isolate.run(() => _watermarkRenderWidth(bytes));
    final panel = await _renderWatermarkPanel(
      imageWidth: imageWidth,
      location: location,
    );
    return Isolate.run(() => _applyWatermark(bytes, panel));
  }
}

String? normalizeNoteWatermarkPlaceName(String? value) {
  final normalized = value?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

String? formatNoteWatermarkPlaceName({
  String? name,
  String? street,
  String? country,
  String? administrativeArea,
  String? locality,
  String? subLocality,
  String? thoroughfare,
  String? subThoroughfare,
}) {
  final parts = <String>[];

  void add(String? value) {
    final normalized = normalizeNoteWatermarkPlaceName(value);
    if (normalized == null) return;
    if (parts.any(
      (part) =>
          part.toLowerCase() == normalized.toLowerCase() ||
          part.contains(normalized),
    )) {
      return;
    }
    parts.add(normalized);
  }

  add(locality ?? administrativeArea);
  add(subLocality);
  add(street ?? thoroughfare);
  add(subThoroughfare);
  add(name);
  if (parts.isEmpty) {
    add(administrativeArea);
    add(country);
  }
  return parts.isEmpty ? null : parts.join(' · ');
}

int _watermarkRenderWidth(Uint8List bytes) {
  if (bytes.isEmpty) throw const FormatException('图片内容为空');
  img.DecodeInfo? info;
  try {
    info = img.findDecoderForData(bytes)?.startDecode(bytes);
  } catch (_) {
    throw const FormatException('图片解码失败');
  }
  if (info == null) throw const FormatException('图片解码失败');
  const maximumPixels = 40 * 1000 * 1000;
  if (info.width * info.height > maximumPixels ||
      info.width > 16384 ||
      info.height > 16384) {
    throw const FormatException('图片分辨率过高');
  }
  const maximumLongEdge = 4096;
  if (info.width <= maximumLongEdge && info.height <= maximumLongEdge) {
    return info.width;
  }
  return info.width >= info.height
      ? maximumLongEdge
      : (info.width * maximumLongEdge / info.height).round();
}

Future<Uint8List> _renderWatermarkPanel({
  required int imageWidth,
  required NoteWatermarkLocation location,
}) async {
  final margin = (imageWidth * .025).round().clamp(10, 96);
  final panelWidth = imageWidth - margin * 2;
  final scale = imageWidth >= 1800
      ? 2.0
      : imageWidth >= 900
      ? 1.35
      : .82;
  final horizontalPadding = (24 * scale).roundToDouble();
  final verticalPadding = (18 * scale).roundToDouble();
  final contentWidth = panelWidth - horizontalPadding * 2;
  final placeName = location.normalizedPlaceName;
  final coordinate = _coordinateDescription(location);

  final title = _watermarkTextPainter(
    'FKNOTES  ·  LOCATION',
    fontSize: 14 * scale,
    fontWeight: FontWeight.w700,
    color: const ui.Color(0xFFC9D7E0),
    letterSpacing: 1.2 * scale,
    maxLines: 1,
  )..layout(maxWidth: contentWidth);
  final place = _watermarkTextPainter(
    placeName ?? coordinate ?? 'LOCATION',
    fontSize: 25 * scale,
    fontWeight: FontWeight.w700,
    color: const ui.Color(0xFFFFFFFF),
    maxLines: 2,
  )..layout(maxWidth: contentWidth);
  final details = _watermarkTextPainter(
    _watermarkDetails(location, includeCoordinate: placeName == null),
    fontSize: 13 * scale,
    fontWeight: FontWeight.w500,
    color: const ui.Color(0xFFD6DEE3),
    maxLines: 1,
  )..layout(maxWidth: contentWidth);
  final firstGap = 9 * scale;
  final secondGap = 12 * scale;
  final panelHeight =
      verticalPadding * 2 +
      title.height +
      firstGap +
      place.height +
      secondGap +
      details.height;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final rect = ui.Rect.fromLTWH(
    0,
    0,
    panelWidth.toDouble(),
    panelHeight.ceilToDouble(),
  );
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(rect, ui.Radius.circular(18 * scale)),
    ui.Paint()..color = const ui.Color(0xCC10242F),
  );
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
      ui.Rect.fromLTWH(
        0,
        verticalPadding,
        5 * scale,
        panelHeight - verticalPadding * 2,
      ),
      ui.Radius.circular(3 * scale),
    ),
    ui.Paint()..color = const ui.Color(0xFFC76543),
  );

  var y = verticalPadding;
  title.paint(canvas, ui.Offset(horizontalPadding, y));
  y += title.height + firstGap;
  place.paint(canvas, ui.Offset(horizontalPadding, y));
  y += place.height + secondGap;
  details.paint(canvas, ui.Offset(horizontalPadding, y));

  final picture = recorder.endRecording();
  final panelImage = await picture.toImage(panelWidth, panelHeight.ceil());
  picture.dispose();
  final data = await panelImage.toByteData(format: ui.ImageByteFormat.png);
  panelImage.dispose();
  if (data == null) throw const FormatException('水印渲染失败');
  return data.buffer.asUint8List();
}

TextPainter _watermarkTextPainter(
  String text, {
  required double fontSize,
  required FontWeight fontWeight,
  required ui.Color color,
  required int maxLines,
  double? letterSpacing,
}) => TextPainter(
  text: TextSpan(
    text: text,
    style: TextStyle(
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontFamilyFallback: const [
        'Noto Sans CJK SC',
        'Noto Sans SC',
        'PingFang SC',
        'Microsoft YaHei',
        'Arial Unicode MS',
      ],
      height: 1.18,
      letterSpacing: letterSpacing,
    ),
  ),
  textDirection: ui.TextDirection.ltr,
  maxLines: maxLines,
  ellipsis: '…',
);

String _watermarkDetails(
  NoteWatermarkLocation location, {
  required bool includeCoordinate,
}) {
  final localTime = location.capturedAt.toLocal();
  final date =
      '${localTime.year.toString().padLeft(4, '0')}-'
      '${localTime.month.toString().padLeft(2, '0')}-'
      '${localTime.day.toString().padLeft(2, '0')}  '
      '${localTime.hour.toString().padLeft(2, '0')}:'
      '${localTime.minute.toString().padLeft(2, '0')}:'
      '${localTime.second.toString().padLeft(2, '0')}';
  final coordinate = _coordinateDescription(location);
  return includeCoordinate && coordinate != null
      ? '$date  ·  $coordinate'
      : date;
}

String? _coordinateDescription(NoteWatermarkLocation location) {
  return location.coordinateSummary;
}

Uint8List _applyWatermark(Uint8List bytes, Uint8List panelBytes) {
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
  final panel = img.decodePng(panelBytes);
  if (panel == null) throw const FormatException('水印合成失败');
  final margin = (image.width * .025).round().clamp(10, 96);
  final panelWidth = image.width - margin * 2;
  final panelHeight = (panel.height * panelWidth / panel.width).round();
  img.compositeImage(
    image,
    panel,
    dstX: margin,
    dstY: (image.height - panelHeight - margin).clamp(0, image.height - 1),
    dstW: panelWidth,
    dstH: panelHeight,
  );
  return Uint8List.fromList(img.encodeJpg(image, quality: 92));
}
