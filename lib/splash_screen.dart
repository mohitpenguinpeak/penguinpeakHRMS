import 'package:flutter/material.dart';

import 'features/auth/presentation/session_gate.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.7, curve: Curves.easeIn),
    );

    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.8, curve: Curves.easeOutCubic),
      ),
    );

    _glowAnimation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _controller.forward();
    _openHomeScreen();
  }

  Future<void> _openHomeScreen() async {
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const SessionGate()));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.2),
                radius: 1.1,
                colors: [
                  Color.lerp(
                    const Color(0xFF1F150A),
                    const Color(0xFF38230D),
                    _glowAnimation.value,
                  )!,
                  const Color(0xFF0C0A08),
                  const Color(0xFF050505),
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  const Spacer(flex: 3),

                  // Brand Emblem & Logo
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: ScaleTransition(
                      scale: _scaleAnimation,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 24,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF141210).withOpacity(0.8),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: const Color(0xFFF59E0B).withOpacity(0.3),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFF59E0B)
                                  .withOpacity(0.25 * _glowAnimation.value),
                              blurRadius: 80,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Try loading PNG logo asset; fallback to vector logo
                            Image.asset(
                              'assets/images/penguinpeak_logo.png',
                              width: 220,
                              height: 120,
                              filterQuality: FilterQuality.high,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return const PenguinPeakVectorLogo(size: 100);
                              },
                            ),
                            const SizedBox(height: 12),
                            ShaderMask(
                              shaderCallback: (bounds) => const LinearGradient(
                                colors: [
                                  Color(0xFFFBBF24),
                                  Color(0xFFF59E0B),
                                  Color(0xFFD97706),
                                ],
                              ).createShader(bounds),
                              child: const Text(
                                'PENGUINPEAK',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  letterSpacing: 4.0,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'HUMAN RESOURCE MANAGEMENT SYSTEM',
                              style: TextStyle(
                                color: Color(0xFFD4CEB8),
                                fontSize: 9,
                                letterSpacing: 2.0,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Tagline
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: const Text(
                      'PEOPLE  •  PROGRESS  •  POSSIBILITY',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFFE2DCCE),
                        fontSize: 11,
                        letterSpacing: 3.0,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                  const Spacer(flex: 2),

                  // Smooth Progress Bar
                  SizedBox(
                    width: 120,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: const LinearProgressIndicator(
                        minHeight: 4,
                        backgroundColor: Color(0xFF26201A),
                        color: Color(0xFFF59E0B),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  const Text(
                    'POWERED BY PENGUINPEAK TECHNOLOGIES',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF888177),
                      fontSize: 9,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  const SizedBox(height: 28),
                ],
              ),
            ),
          );
        },
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
