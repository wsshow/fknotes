import 'package:flutter/material.dart';

import '../app.dart';

/// The FKNotes mark: one paper edge flowing into an infinite record.
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
        Radius.circular(23 * unit),
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

    final page = Path()
      ..moveTo(22 * unit, 47 * unit)
      ..lineTo(22 * unit, 27 * unit)
      ..cubicTo(
        22 * unit,
        22.3 * unit,
        24.3 * unit,
        20 * unit,
        29 * unit,
        20 * unit,
      )
      ..lineTo(59 * unit, 20 * unit)
      ..lineTo(78 * unit, 39 * unit)
      ..lineTo(78 * unit, 47 * unit);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.2 * unit
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(page, stroke);

    final fold = Path()
      ..moveTo(59 * unit, 21 * unit)
      ..lineTo(59 * unit, 32 * unit)
      ..cubicTo(
        59 * unit,
        36.7 * unit,
        61.3 * unit,
        39 * unit,
        66 * unit,
        39 * unit,
      )
      ..lineTo(77 * unit, 39 * unit);
    canvas.drawPath(fold, stroke);

    final loop = Path()
      ..moveTo(55 * unit, 66 * unit)
      ..cubicTo(
        66 * unit,
        76 * unit,
        78 * unit,
        73 * unit,
        82 * unit,
        61 * unit,
      )
      ..cubicTo(
        82 * unit,
        49 * unit,
        65 * unit,
        44 * unit,
        51 * unit,
        61 * unit,
      )
      ..cubicTo(
        39 * unit,
        77 * unit,
        22 * unit,
        79 * unit,
        18 * unit,
        64 * unit,
      )
      ..cubicTo(
        18 * unit,
        51 * unit,
        37 * unit,
        44 * unit,
        51 * unit,
        61 * unit,
      );
    canvas.drawPath(loop, stroke);
  }

  @override
  bool shouldRepaint(covariant _BrandMarkPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.surface != surface;
}
