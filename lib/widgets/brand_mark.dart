import 'package:flutter/material.dart';

import '../app.dart';

/// The FKNotes mark: a warm, bound notebook with two content lines.
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

    final notebook = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(23 * unit, 20 * unit, 56 * unit, 60 * unit),
          Radius.circular(10 * unit),
        ),
      );

    final cutouts = Path()
      ..moveTo(35.5 * unit, 20 * unit)
      ..cubicTo(
        39 * unit,
        31 * unit,
        39 * unit,
        69 * unit,
        35.5 * unit,
        80 * unit,
      )
      ..lineTo(39 * unit, 80 * unit)
      ..cubicTo(
        42.5 * unit,
        69 * unit,
        42.5 * unit,
        31 * unit,
        39 * unit,
        20 * unit,
      )
      ..close()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(47 * unit, 41 * unit, 25 * unit, 6 * unit),
          Radius.circular(3 * unit),
        ),
      )
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(47 * unit, 54 * unit, 19 * unit, 6 * unit),
          Radius.circular(3 * unit),
        ),
      );

    canvas.drawPath(
      Path.combine(PathOperation.difference, notebook, cutouts),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _BrandMarkPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.surface != surface;
}
