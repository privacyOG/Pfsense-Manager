import 'package:flutter/material.dart';

class PfSenseBrandMark extends StatelessWidget {
  const PfSenseBrandMark({
    super.key,
    this.size = 88,
    this.elevation = true,
  });

  final double size;
  final bool elevation;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary,
            const Color(0xFF00A878),
            const Color(0xFF12B5CB),
          ],
        ),
        boxShadow: elevation
            ? [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.28),
                  blurRadius: size * 0.22,
                  offset: Offset(0, size * 0.10),
                ),
              ]
            : null,
      ),
      child: CustomPaint(
        painter: _BrandMarkPainter(
          foreground: Colors.white,
          shadow: Colors.black.withValues(alpha: 0.16),
        ),
      ),
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  const _BrandMarkPainter({
    required this.foreground,
    required this.shadow,
  });

  final Color foreground;
  final Color shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.shortestSide / 100;
    final center = Offset(size.width / 2, size.height / 2);
    final shield = Path()
      ..moveTo(center.dx, 14 * unit)
      ..cubicTo(
          68 * unit, 17 * unit, 78 * unit, 23 * unit, 84 * unit, 29 * unit)
      ..lineTo(78 * unit, 64 * unit)
      ..cubicTo(
          75 * unit, 79 * unit, 63 * unit, 88 * unit, center.dx, 93 * unit)
      ..cubicTo(
          37 * unit, 88 * unit, 25 * unit, 79 * unit, 22 * unit, 64 * unit)
      ..lineTo(16 * unit, 29 * unit)
      ..cubicTo(
          22 * unit, 23 * unit, 32 * unit, 17 * unit, center.dx, 14 * unit)
      ..close();

    canvas.drawPath(
      shield.shift(Offset(0, 2.5 * unit)),
      Paint()..color = shadow,
    );
    canvas.drawPath(
      shield,
      Paint()
        ..color = foreground
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6 * unit
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    final linePaint = Paint()
      ..color = foreground
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7 * unit
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
        Offset(34 * unit, 40 * unit), Offset(66 * unit, 40 * unit), linePaint);
    canvas.drawLine(
        Offset(34 * unit, 55 * unit), Offset(58 * unit, 55 * unit), linePaint);
    canvas.drawLine(
        Offset(34 * unit, 70 * unit), Offset(50 * unit, 70 * unit), linePaint);

    final pulse = Path()
      ..moveTo(58 * unit, 70 * unit)
      ..lineTo(64 * unit, 61 * unit)
      ..lineTo(70 * unit, 73 * unit)
      ..lineTo(78 * unit, 52 * unit);
    canvas.drawPath(pulse, linePaint);
  }

  @override
  bool shouldRepaint(covariant _BrandMarkPainter oldDelegate) {
    return oldDelegate.foreground != foreground || oldDelegate.shadow != shadow;
  }
}
