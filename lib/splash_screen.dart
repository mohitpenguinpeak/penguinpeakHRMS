import 'package:flutter/material.dart';

import 'shared/widgets/peak_landscape.dart';

import 'features/auth/presentation/session_gate.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
  }

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) _controller.value = 1;
    _openWorkspace();
  }

  Future<void> _openWorkspace() async {
    try {
      await _controller.forward().orCancel;
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const SessionGate()));
    } on TickerCanceled {
      return;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PeakLandscape(
        child: SafeArea(
          child: Center(
            child: FadeTransition(
              opacity: _controller,
              child: ScaleTransition(
                scale: Tween(begin: .94, end: 1.0).animate(
                  CurvedAnimation(
                    parent: _controller,
                    curve: Curves.easeOutCubic,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/penguinpeak_logo.png',
                      width: 136,
                      height: 100,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'PenguinPeak',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -1.5,
                      ),
                    ),
                    const Text(
                      'HRMS',
                      style: TextStyle(color: Colors.white70, letterSpacing: 4),
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
}

/// High-Resolution Vector Brand Emblem Painter (Renders crystal clear on all screens)
class PenguinPeakVectorLogo extends StatelessWidget {
  final double size;
  const PenguinPeakVectorLogo({super.key, this.size = 100});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LogoPainter()),
    );
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Glowing background circle
    final bgPaint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFFF59E0B), Color(0xFFB85C00)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius * 0.85, bgPaint);

    // Rocket / Mountain Peak Path
    final path = Path();
    path.moveTo(size.width * 0.5, size.height * 0.22);
    path.lineTo(size.width * 0.72, size.height * 0.68);
    path.lineTo(size.width * 0.58, size.height * 0.60);
    path.lineTo(size.width * 0.5, size.height * 0.75);
    path.lineTo(size.width * 0.42, size.height * 0.60);
    path.lineTo(size.width * 0.28, size.height * 0.68);
    path.close();

    final peakPaint = Paint()
      ..color = const Color(0xFF101010)
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, peakPaint);

    // Inner Flame Accent
    final flamePath = Path();
    flamePath.moveTo(size.width * 0.5, size.height * 0.38);
    flamePath.lineTo(size.width * 0.60, size.height * 0.62);
    flamePath.lineTo(size.width * 0.5, size.height * 0.55);
    flamePath.lineTo(size.width * 0.40, size.height * 0.62);
    flamePath.close();

    final flamePaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFFFD580), Color(0xFFF59E0B)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(flamePath, flamePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
