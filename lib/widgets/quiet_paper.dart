import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app.dart';

/// Shared structural pieces for the Quiet Paper Mechanics visual language.
///
/// These widgets deliberately keep the paper metaphor in the page structure.
/// Standard controls inside them remain regular Material controls so their
/// interaction and accessibility semantics stay predictable.
final class PaperShell extends StatelessWidget {
  const PaperShell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.canvas,
    child: CustomPaint(painter: const _PaperBackdropPainter(), child: child),
  );
}

final class BrandSpine extends StatelessWidget {
  const BrandSpine({required this.label, required this.itemLabel, super.key});

  final String label;
  final String itemLabel;

  @override
  Widget build(BuildContext context) {
    final isCjk = RegExp(r'[\u3400-\u9fff]').hasMatch(label);
    return Semantics(
      container: true,
      label: label,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: Container(
                key: const Key('brand-spine-paper-tab'),
                width: double.infinity,
                height: math.min(282.0, constraints.maxHeight),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.paperPrimary.withValues(alpha: .82),
                      AppColors.paperSecondary.withValues(alpha: .97),
                    ],
                  ),
                  border: Border.all(
                    color: AppColors.line.withValues(alpha: .82),
                    width: .75,
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomRight: Radius.circular(10),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x18263847),
                      blurRadius: 12,
                      offset: Offset(2, 4),
                    ),
                    BoxShadow(
                      color: Color(0x0A263847),
                      blurRadius: 2,
                      offset: Offset(1, 1),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: CustomPaint(
                  painter: const _BrandSpineTexturePainter(),
                  child: Padding(
                    padding: const EdgeInsets.only(
                      top: 42,
                      right: 8,
                      bottom: 10,
                      left: 8,
                    ),
                    child: Column(
                      children: [
                        const SizedBox(
                          width: 30,
                          height: 28,
                          child: CustomPaint(painter: _SpineMonogramPainter()),
                        ),
                        const SizedBox(height: 14),
                        const _SpineLocator(),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 80,
                          child: Center(
                            child: isCjk
                                ? Text(
                                    label.split('').join('\n'),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: AppColors.ink,
                                      fontFamily: 'Songti SC',
                                      fontFamilyFallback: [
                                        'Noto Serif CJK SC',
                                        'serif',
                                      ],
                                      fontSize: 15,
                                      height: 1.33,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  )
                                : RotatedBox(
                                    quarterTurns: 1,
                                    child: Text(
                                      label.toUpperCase(),
                                      maxLines: 1,
                                      style: const TextStyle(
                                        color: AppColors.ink,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 2.1,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const _SpineTerminal(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (constraints.maxHeight > 330)
              Positioned(
                right: 5,
                bottom: 18,
                left: 5,
                child: Text(
                  itemLabel,
                  key: const Key('brand-spine-item-count'),
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

final class SearchPullHandle extends StatelessWidget {
  const SearchPullHandle({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: AppColors.paperPrimary,
      border: Border.fromBorderSide(BorderSide(color: AppColors.line)),
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      boxShadow: AppShadows.paperEdge,
    ),
    padding: const EdgeInsets.fromLTRB(10, 7, 10, 9),
    child: child,
  );
}

final class SearchPullTab extends StatelessWidget {
  const SearchPullTab({
    required this.label,
    required this.onTap,
    required this.onVerticalDragUpdate,
    required this.onVerticalDragEnd,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final GestureDragUpdateCallback onVerticalDragUpdate;
  final GestureDragEndCallback onVerticalDragEnd;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onVerticalDragUpdate: onVerticalDragUpdate,
      onVerticalDragEnd: onVerticalDragEnd,
      child: SizedBox(
        height: 44,
        child: CustomPaint(
          painter: const _SearchPullTabPainter(),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: 30,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 10,
                    height: 6,
                    child: CustomPaint(painter: _SearchPullChevronPainter()),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontFamily: 'Songti SC',
                      fontFamilyFallback: ['Noto Serif CJK SC', 'serif'],
                      fontSize: 10,
                      height: 1,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

final class ToolNodeButton extends StatelessWidget {
  const ToolNodeButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.buttonKey,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: AppColors.paperPrimary,
      shape: const CircleBorder(side: BorderSide(color: AppColors.line)),
      elevation: 0,
      shadowColor: AppColors.shadow.withValues(alpha: .08),
      child: InkWell(
        key: buttonKey,
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox.square(
          dimension: 48,
          child: Icon(icon, size: 21, color: AppColors.mechanicalBlue),
        ),
      ),
    ),
  );
}

final class CreateArcButton extends StatelessWidget {
  const CreateArcButton({
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: tooltip,
    child: Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.mechanicalBlue,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: const SizedBox.square(
            dimension: 56,
            child: Icon(
              Icons.add_rounded,
              color: AppColors.paperPrimary,
              size: 28,
              weight: 300,
            ),
          ),
        ),
      ),
    ),
  );
}

final class IndexTicks extends StatelessWidget {
  const IndexTicks({
    required this.index,
    required this.count,
    required this.onDrag,
    super.key,
  });

  final int index;
  final int count;
  final ValueChanged<double>? onDrag;

  @override
  Widget build(BuildContext context) => Semantics(
    label: count == 0 ? '0 / 0' : '${index + 1} / $count',
    value: count == 0 ? '0 / 0' : '${index + 1} / $count',
    child: LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: onDrag == null
            ? null
            : (details) => _update(details.localPosition.dy, constraints),
        onVerticalDragUpdate: onDrag == null
            ? null
            : (details) => _update(details.localPosition.dy, constraints),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: TweenAnimationBuilder<double>(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                tween: Tween<double>(end: count == 0 ? 0 : index.toDouble()),
                builder: (context, position, _) => CustomPaint(
                  key: const Key('index-ticks-dial'),
                  painter: _IndexTicksPainter(position: position, count: count),
                ),
              ),
            ),
            const Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                key: Key('index-ticks-pointer'),
                width: 22,
                height: 12,
                child: CustomPaint(painter: _IndexPointerPainter()),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                key: const Key('index-ticks-reading'),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                color: AppColors.canvas.withValues(alpha: .92),
                child: Text(
                  count == 0 ? '0 / 0' : '${index + 1} / $count',
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  void _update(double dy, BoxConstraints constraints) {
    final height = constraints.maxHeight;
    if (height <= 0 || !height.isFinite) return;
    onDrag?.call((dy / height).clamp(0, 1));
  }
}

final class PaperTag extends StatelessWidget {
  const PaperTag({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.transparent,
      border: Border.all(
        color: AppColors.mechanicalBlue.withValues(alpha: .65),
      ),
      borderRadius: BorderRadius.circular(AppRadius.pill),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: AppColors.ink,
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

final class PaperSection extends StatelessWidget {
  const PaperSection({
    required this.child,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.paperPrimary,
      border: Border.all(color: AppColors.line),
      borderRadius: const BorderRadius.all(Radius.circular(AppRadius.small)),
      boxShadow: AppShadows.paperEdge,
    ),
    clipBehavior: Clip.antiAlias,
    child: Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Padding(padding: padding, child: child),
          const Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            width: 3,
            child: ColoredBox(color: AppColors.mechanicalBlue),
          ),
        ],
      ),
    ),
  );
}

final class _SpineLocator extends StatelessWidget {
  const _SpineLocator();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 14,
    height: 40,
    child: CustomPaint(painter: _SpineLocatorPainter()),
  );
}

final class _SpineLocatorPainter extends CustomPainter {
  const _SpineLocatorPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.mechanicalBlue
      ..strokeWidth = 1;
    final x = size.width / 2;
    canvas.drawLine(Offset(x, 0), Offset(x, 22), paint);
    canvas.drawCircle(Offset(x, 32), 2.6, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

final class _SpineTerminal extends StatelessWidget {
  const _SpineTerminal();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 14,
    height: 46,
    child: CustomPaint(painter: _SpineTerminalPainter()),
  );
}

final class _SpineTerminalPainter extends CustomPainter {
  const _SpineTerminalPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.mechanicalBlue
      ..strokeWidth = 1;
    final x = size.width / 2;
    canvas.drawLine(Offset(x, 0), Offset(x, 23), paint);
    canvas.drawLine(Offset(x - 3.5, 31), Offset(x + 3.5, 31), paint);
    canvas.drawLine(Offset(x - 3.5, 37), Offset(x + 3.5, 37), paint);
    canvas.drawCircle(
      Offset(x, 44),
      2,
      Paint()
        ..color = AppColors.mechanicalBlue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

final class _SpineMonogramPainter extends CustomPainter {
  const _SpineMonogramPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / 30;
    final scaleY = size.height / 28;
    final monogram = Path()
      // F, with lightly cut ends to keep the mark mechanical rather than
      // typographic.
      ..moveTo(0, 0)
      ..lineTo(14, 0)
      ..lineTo(12.5, 4.5)
      ..lineTo(4.5, 4.5)
      ..lineTo(4.5, 11)
      ..lineTo(12, 11)
      ..lineTo(10.5, 15.5)
      ..lineTo(4.5, 15.5)
      ..lineTo(4.5, 28)
      ..lineTo(0, 28)
      ..close()
      // K stem.
      ..addRect(const Rect.fromLTWH(15, 0, 4.5, 28))
      // K upper and lower arms.
      ..moveTo(19, 13)
      ..lineTo(26.5, 0)
      ..lineTo(30, 0)
      ..lineTo(22, 15)
      ..close()
      ..moveTo(19, 12)
      ..lineTo(22.2, 10)
      ..lineTo(30, 28)
      ..lineTo(25.5, 28)
      ..lineTo(19, 15.5)
      ..close();
    canvas.save();
    canvas.scale(scaleX, scaleY);
    canvas.drawPath(
      monogram,
      Paint()
        ..color = AppColors.mechanicalBlue
        ..isAntiAlias = true,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

final class _BrandSpineTexturePainter extends CustomPainter {
  const _BrandSpineTexturePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final horizontalFiber = Paint()
      ..color = AppColors.ink.withValues(alpha: .012)
      ..strokeWidth = .45;
    for (var y = 7.0; y < size.height; y += 17) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y + (y % 3) * .12),
        horizontalFiber,
      );
    }

    final verticalFiber = Paint()
      ..color = Colors.white.withValues(alpha: .16)
      ..strokeWidth = .35;
    for (var x = 5.0; x < size.width; x += 13) {
      canvas.drawLine(Offset(x, 0), Offset(x + .5, size.height), verticalFiber);
    }

    final fleck = Paint()..color = AppColors.ink.withValues(alpha: .018);
    for (var index = 0; index < 26; index++) {
      final x = ((index * 37) % 101) / 101 * size.width;
      final y = ((index * 67) % 283) / 283 * size.height;
      canvas.drawCircle(Offset(x, y), .32, fleck);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

final class _IndexTicksPainter extends CustomPainter {
  const _IndexTicksPainter({required this.position, required this.count});

  final double position;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    if (count <= 1) return;
    final paint = Paint()
      ..color = AppColors.line
      ..strokeWidth = 1;
    final centerY = size.height / 2;
    final gap = math.max(1.0, (centerY - 6) / (count - 1));
    for (var ordinal = 0; ordinal < count; ordinal++) {
      final y = centerY + (ordinal - position) * gap;
      if (y < 5 || y > size.height - 5) continue;
      final length = ordinal % 4 == 0 ? 10.0 : 6.0;
      canvas.drawLine(Offset(2, y), Offset(2 + length, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _IndexTicksPainter oldDelegate) =>
      oldDelegate.position != position || oldDelegate.count != count;
}

final class _IndexPointerPainter extends CustomPainter {
  const _IndexPointerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final marker = Paint()..color = AppColors.mechanicalBlue;
    canvas.drawRect(Rect.fromLTWH(1, centerY - 2, 11, 4), marker);
    final triangle = Path()
      ..moveTo(15, centerY)
      ..lineTo(21, centerY - 5)
      ..lineTo(21, centerY + 5)
      ..close();
    canvas.drawPath(triangle, marker);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

final class _SearchPullTabPainter extends CustomPainter {
  const _SearchPullTabPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const visibleHeight = 30.0;
    final shoulder = size.width * .19;
    final bottomLeft = size.width * .36;
    final bottomRight = size.width * .64;
    final outline = Path()
      ..moveTo(0, 0)
      ..lineTo(shoulder, 0)
      ..cubicTo(shoulder + 8, 0, shoulder + 10, 3, shoulder + 12, 7)
      ..cubicTo(
        shoulder + 16,
        18,
        bottomLeft - 10,
        27,
        bottomLeft,
        visibleHeight - 1,
      )
      ..cubicTo(
        bottomLeft + 7,
        visibleHeight,
        bottomRight - 7,
        visibleHeight,
        bottomRight,
        visibleHeight - 1,
      )
      ..cubicTo(
        bottomRight + 10,
        27,
        size.width - shoulder - 16,
        18,
        size.width - shoulder - 12,
        7,
      )
      ..cubicTo(
        size.width - shoulder - 10,
        3,
        size.width - shoulder - 8,
        0,
        size.width - shoulder,
        0,
      )
      ..lineTo(size.width, 0);
    canvas.drawPath(
      outline,
      Paint()
        ..color = AppColors.mechanicalBlue.withValues(alpha: .7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .55,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

final class _SearchPullChevronPainter extends CustomPainter {
  const _SearchPullChevronPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.mechanicalBlue
      ..strokeWidth = .8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(.5, .5)
      ..lineTo(size.width / 2, size.height - .5)
      ..lineTo(size.width - .5, .5);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

final class _PaperBackdropPainter extends CustomPainter {
  const _PaperBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.ink.withValues(alpha: .012)
      ..strokeWidth = .5;
    const step = 44.0;
    for (var y = 18.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 3), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
