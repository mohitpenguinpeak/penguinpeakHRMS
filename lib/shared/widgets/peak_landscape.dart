import 'package:flutter/material.dart';

/// Decorative landscape sized to the viewport, independent of form scrolling.
class PeakLandscape extends StatelessWidget {
  const PeakLandscape({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const RepaintBoundary(child: CustomPaint(painter: _LandscapePainter())),
      child,
    ],
  );
}

class _LandscapePainter extends CustomPainter {
  const _LandscapePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(.7, -.65),
          radius: 1.45,
          colors: [Color(0xff456475), Color(0xff273850), Color(0xff111926)],
        ).createShader(bounds),
    );
    canvas.scale(size.width, size.height);
    for (var layer = 0; layer < 4; layer++) {
      final y = .52 + layer * .095;
      final ridge = Path()
        ..moveTo(0, y)
        ..cubicTo(.18, y - .18, .32, y + .24, .53, y + .04)
        ..cubicTo(.74, y - .15, .83, y - .24, 1, y - .17)
        ..lineTo(1, 1)
        ..lineTo(0, 1)
        ..close();
      canvas.drawPath(
        ridge,
        Paint()
          ..color = const [
            Color(0xff426174),
            Color(0xff304b63),
            Color(0xff24384f),
            Color(0xff182839),
          ][layer],
      );
    }
  }

  @override
  bool shouldRepaint(_LandscapePainter oldDelegate) => false;
}
