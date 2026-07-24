import 'package:flutter/material.dart';

import '../app.dart';

/// The FKNotes geometric monogram used by the Quiet Paper Mechanics shell.
class BrandMark extends StatelessWidget {
  final double size;
  final bool showSurface;

  const BrandMark({super.key, required this.size, this.showSurface = true});

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _BrandMarkPainter(
      color: AppColors.moss,
      surface: showSurface ? AppColors.surface : Colors.transparent,
    ),
  );
}

class _BrandMarkPainter extends CustomPainter {
  final Color color;
  final Color surface;

  const _BrandMarkPainter({required this.color, required this.surface});

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 100;
    if (surface.a > 0) {
      final frame = RRect.fromRectAndRadius(
        Rect.fromLTWH(2 * unit, 2 * unit, 96 * unit, 96 * unit),
        Radius.circular(6 * unit),
      );
      canvas.drawRRect(frame, Paint()..color = surface);
      canvas.drawRRect(
        frame,
        Paint()
          ..color = AppColors.line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    final monogram = Path()
      // F
      ..addRect(Rect.fromLTWH(22 * unit, 24 * unit, 8 * unit, 53 * unit))
      ..addRect(Rect.fromLTWH(30 * unit, 24 * unit, 21 * unit, 8 * unit))
      ..addRect(Rect.fromLTWH(30 * unit, 46 * unit, 17 * unit, 8 * unit))
      // K stem
      ..addRect(Rect.fromLTWH(55 * unit, 24 * unit, 8 * unit, 53 * unit))
      // K upper arm
      ..moveTo(63 * unit, 50 * unit)
      ..lineTo(77 * unit, 24 * unit)
      ..lineTo(86 * unit, 24 * unit)
      ..lineTo(69 * unit, 55 * unit)
      ..close()
      // K lower arm
      ..moveTo(65 * unit, 47 * unit)
      ..lineTo(87 * unit, 77 * unit)
      ..lineTo(77 * unit, 77 * unit)
      ..lineTo(60 * unit, 55 * unit)
      ..close();
    canvas.drawPath(monogram, Paint()..color = color);
    canvas.drawCircle(
      Offset(87 * unit, 84 * unit),
      3 * unit,
      Paint()..color = AppColors.terracotta,
    );
  }

  @override
  bool shouldRepaint(covariant _BrandMarkPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.surface != surface;
}
