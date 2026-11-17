import 'package:flutter/material.dart';

/// Scalable brand artwork. The ridge stays anchored to the trailing edge,
/// leaving the leading side of a banner clear for text.
class AlpineLandscape extends StatelessWidget {
  const AlpineLandscape({super.key, required this.child, this.subdued = false});

  final Widget child;
  final bool subdued;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: RepaintBoundary(
          child: CustomPaint(painter: _AlpinePainter(subdued)),
        ),
      ),
      child,
    ],
  );
}

class _AlpinePainter extends CustomPainter {
  const _AlpinePainter(this.subdued);
  final bool subdued;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(bounds, Paint()..shader = const LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [Color(0xff0b2036), Color(0xff204e64), Color(0xff88c7c8)],
    ).createShader(bounds));

    final height = size.height.clamp(0.0, subdued ? 360.0 : 240.0);
    if (height == 0) return;
    final scale = height / 200;
    canvas.save();
    canvas.translate(size.width - 460 * scale, size.height - height);
    canvas.scale(scale);
    final paint = Paint();
    const sun = Offset(362, 48);
    canvas.drawCircle(sun, 40, paint..color = const Color(0x227deedf));
    canvas.drawCircle(sun, 29, paint..color = const Color(0xffb9f4e2));
    void facet(Color color, List<Offset> points) {
      canvas.drawPath(Path()..addPolygon(points, true), paint..color = color);
    }
    facet(const Color(0xff578ca0), const [
      Offset(50,200), Offset(187,77), Offset(228,105), Offset(292,31),
      Offset(395,133), Offset(460,91), Offset(460,200),
    ]);
    facet(const Color(0xffb7dcdb), const [
      Offset(244,87), Offset(292,31), Offset(329,68), Offset(303,58),
      Offset(307,77), Offset(286,58), Offset(275,72), Offset(274,62),
    ]);
    facet(const Color(0xff366879), const [
      Offset(292,31), Offset(395,133), Offset(343,152), Offset(306,76),
      Offset(303,58), Offset(329,68),
    ]);
    facet(const Color(0xff25576a), const [
      Offset(0,200), Offset(93,145), Offset(141,153), Offset(201,104),
      Offset(246,136), Offset(313,108), Offset(364,143), Offset(460,72),
      Offset(460,200),
    ]);
    facet(const Color(0xff11394b), const [
      Offset(0,200), Offset(130,177), Offset(210,182), Offset(302,143),
      Offset(352,155), Offset(460,118), Offset(460,200),
    ]);
    canvas.restore();
    canvas.drawRect(bounds, Paint()..shader = LinearGradient(
      colors: subdued
          ? const [Color(0xee0a1727), Color(0xd00a1727)]
          : const [Color(0xf00b2036), Color(0xaa0b2036), Color(0x100b2036)],
      stops: subdued ? null : const [0, .48, 1],
    ).createShader(bounds));
  }

  @override
  bool shouldRepaint(_AlpinePainter oldDelegate) => oldDelegate.subdued != subdued;
}
