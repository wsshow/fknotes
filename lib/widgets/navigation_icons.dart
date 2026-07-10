import 'package:flutter/material.dart';

/// Three upright volumes, matching the library metaphor used by the product.
class LibrarySpinesIcon extends StatelessWidget {
  final double size;

  const LibrarySpinesIcon({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    return CustomPaint(
      size: Size.square(size),
      painter: _LibrarySpinesPainter(
        color: iconTheme.color ?? const Color(0xFF28231F),
      ),
    );
  }
}

class _LibrarySpinesPainter extends CustomPainter {
  final Color color;

  const _LibrarySpinesPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 24;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.65 * unit
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(2.5 * unit, 4 * unit, 4.5 * unit, 16 * unit),
        Radius.circular(0.8 * unit),
      ),
      stroke,
    );
    canvas.drawLine(
      Offset(4.2 * unit, 7 * unit),
      Offset(5.3 * unit, 7 * unit),
      stroke,
    );
    canvas.drawLine(
      Offset(4.2 * unit, 17 * unit),
      Offset(5.3 * unit, 17 * unit),
      stroke,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(9 * unit, 3 * unit, 5 * unit, 17 * unit),
        Radius.circular(0.8 * unit),
      ),
      stroke,
    );
    canvas.drawLine(
      Offset(11 * unit, 6 * unit),
      Offset(12.1 * unit, 6 * unit),
      stroke,
    );
    canvas.drawLine(
      Offset(11 * unit, 17 * unit),
      Offset(12.1 * unit, 17 * unit),
      stroke,
    );

    final thirdBook = Path()
      ..moveTo(16.1 * unit, 4.2 * unit)
      ..lineTo(20 * unit, 3.7 * unit)
      ..lineTo(21.6 * unit, 19.1 * unit)
      ..lineTo(17.6 * unit, 19.7 * unit)
      ..close();
    canvas.drawPath(thirdBook, stroke);
    canvas.drawLine(
      Offset(17 * unit, 7 * unit),
      Offset(20.4 * unit, 6.6 * unit),
      stroke,
    );
    canvas.drawLine(
      Offset(18.1 * unit, 16.8 * unit),
      Offset(21 * unit, 16.4 * unit),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _LibrarySpinesPainter oldDelegate) =>
      oldDelegate.color != color;
}
