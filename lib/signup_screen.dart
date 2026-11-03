import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'login_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen>
    with SingleTickerProviderStateMixin {
  static const orange = Color(0xFFF59E0B);
  static const background = Color(0xFF070A0F);

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  final _nameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();

  int _currentStep = 0; // 0: Welcome, 1: Name, 2: Email, 3: Password, 4: Confirm, 5: Submitting, 6: Success
  bool _hidePassword = true;
  bool _hideConfirm = true;
  bool _loading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
  }

  void _nextStep() {
    FocusScope.of(context).unfocus();
    setState(() {
      _errorMessage = null;
    });

    if (_currentStep == 1) {
      if (_nameController.text.trim().length < 2) {
        setState(() => _errorMessage = 'Please enter your full name');
        return;
      }
      setState(() {
        _currentStep = 2;
      });
      Future.delayed(const Duration(milliseconds: 100), () {
        _emailFocus.requestFocus();
      });
    } else if (_currentStep == 2) {
      final email = _emailController.text.trim();
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
        setState(
          () => _errorMessage = 'Please enter a valid work email address',
        );
        return;
      }
      setState(() {
        _currentStep = 3;
      });
      Future.delayed(const Duration(milliseconds: 100), () {
        _passwordFocus.requestFocus();
      });
    } else if (_currentStep == 3) {
      if (_passwordController.text.length < 8) {
        setState(
          () => _errorMessage = 'Password must be at least 8 characters',
        );
        return;
      }
      setState(() {
        _currentStep = 4;
      });
      Future.delayed(const Duration(milliseconds: 100), () {
        _confirmFocus.requestFocus();
      });
    } else if (_currentStep == 4) {
      if (_confirmController.text != _passwordController.text) {
        setState(() => _errorMessage = 'Passwords do not match');
        return;
      }
      _submitSignup();
    }
  }

  void _prevStep() {
    if (_currentStep > 0 && !_loading) {
      FocusScope.of(context).unfocus();
      setState(() {
        _currentStep--;
        _errorMessage = null;
      });
    }
  }

  Future<void> _submitSignup() async {
    setState(() {
      _loading = true;
      _currentStep = 5; // Checking watch
      _errorMessage = null;
    });

    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        data: {'full_name': _nameController.text.trim()},
      );

      if (!mounted) return;

      if (response.session != null) {
        await Supabase.instance.client.auth.signOut();
      }

      setState(() {
        _loading = false;
        _currentStep = 6; // Success
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _currentStep = 4;
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _currentStep = 4;
        _errorMessage = 'Something went wrong. Please try again.';
      });
    }
  }

  @override
  void dispose() {
    _nameFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  PenguinState _getMascotState() {
    switch (_currentStep) {
      case 0:
        return PenguinState.holdingSign;
      case 1:
        return PenguinState.typingName;
      case 2:
        return PenguinState.typingEmail;
      case 3:
      case 4:
        return PenguinState.coveringEyes;
      case 5:
        return PenguinState.checkingWatch;
      case 6:
        return PenguinState.pendingDoorClosed;
      default:
        return PenguinState.idle;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      body: Stack(
        children: [
          // Cosmic Background Stars Gradient
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.4),
                  radius: 1.3,
                  colors: [
                    Color(0xFF0F172A),
                    Color(0xFF080D1A),
                    Color(0xFF030508),
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Top Header Row
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white70,
                        ),
                        onPressed: () {
                          if (_currentStep > 0) {
                            _prevStep();
                          } else {
                            Navigator.of(context).pop();
                          }
                        },
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => const LoginScreen(),
                            ),
                          );
                        },
                        child: const Text(
                          'Already have an account? Sign In',
                          style: TextStyle(
                            color: orange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Center Conversational Content Area
                Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 580),
                      child: Form(
                        key: _formKey,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 380),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, 0.08),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: KeyedSubtree(
                            key: ValueKey<int>(_currentStep),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Full Body Mascot "Peakie"
                                PenguinMascot(state: _getMascotState()),

                                const SizedBox(height: 24),

                                // Dynamic Conversational Card
                                _buildStepContent(),

                                if (_errorMessage != null) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    _errorMessage!,
                                    style: const TextStyle(
                                      color: Colors.redAccent,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                const Spacer(),

                // Bottom Navigation Controls
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (_currentStep > 0 && _currentStep < 5)
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: const BorderSide(color: Colors.white24),
                          ),
                          onPressed: _prevStep,
                          icon: const Icon(Icons.arrow_upward, size: 16),
                          label: const Text('Back'),
                        )
                      else
                        const SizedBox.shrink(),

                      // Step Indicator Dots
                      Row(
                        children: List.generate(
                          5,
                          (idx) => AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: _currentStep == idx + 1 ? 24 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _currentStep == idx + 1
                                  ? orange
                                  : Colors.white24,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),

                      if (_currentStep > 0 && _currentStep < 5)
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: orange,
                            side: const BorderSide(color: orange),
                          ),
                          onPressed: _nextStep,
                          icon: const Icon(Icons.arrow_downward, size: 16),
                          label: const Text('Next'),
                        )
                      else
                        const SizedBox.shrink(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return Column(
          children: [
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFF38BDF8), Color(0xFF818CF8)],
              ).createShader(bounds),
              child: const Text(
                'Oh hey, you made it! 😊',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "I'm Peakie 🐧. And yes... despite being a penguin, I'm super excited to guide you!",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Let's get your employee account ready step by step. ✨",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF38BDF8),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 18,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () {
                setState(() => _currentStep = 1);
                Future.delayed(const Duration(milliseconds: 150), () {
                  _nameFocus.requestFocus();
                });
              },
              icon: const Icon(Icons.auto_awesome, size: 20),
              label: const Text(
                "Alright, let's go →",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );

      case 1:
        return Column(
          children: [
            const Text(
              "First off, what's your full name? ✨",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Let's introduce you to the rest of the Penguin team!",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60, fontSize: 14),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _nameController,
              focusNode: _nameFocus,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              textAlign: TextAlign.center,
              decoration: _conversationalInputDecoration(
                'Enter your full name',
                Icons.person_outline,
              ),
              onSubmitted: (_) => _nextStep(),
            ),
            const SizedBox(height: 24),
            FilledButton(
              style: _actionButtonStyle(),
              onPressed: _nextStep,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text('Press Enter ↵'),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
            ),
          ],
        );

      case 2:
        return Column(
          children: [
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFF34D399), Color(0xFF38BDF8)],
              ).createShader(bounds),
              child: const Text(
                "Before we get into the fun stuff 👀",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Share your work email with us. Let's make sure we stay connected! ✨",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 15),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _emailController,
              focusNode: _emailFocus,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              textAlign: TextAlign.center,
              decoration: _conversationalInputDecoration(
                'e.g. name@company.com',
                Icons.email_outlined,
              ),
              onSubmitted: (_) => _nextStep(),
            ),
            const SizedBox(height: 24),
            FilledButton(
              style: _actionButtonStyle(),
              onPressed: _nextStep,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text('Press Enter ↵'),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
            ),
          ],
        );

      case 3:
        return Column(
          children: [
            const Text(
              "Create a strong secret password 🔑",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Don't worry, I'm covering my eyes—I won't peek! 🙈",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.amberAccent, fontSize: 14),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _passwordController,
              focusNode: _passwordFocus,
              obscureText: _hidePassword,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              textAlign: TextAlign.center,
              decoration: _conversationalInputDecoration(
                'Min 8 characters',
                Icons.lock_outline,
                suffix: IconButton(
                  icon: Icon(
                    _hidePassword ? Icons.visibility : Icons.visibility_off,
                    color: Colors.white60,
                  ),
                  onPressed: () =>
                      setState(() => _hidePassword = !_hidePassword),
                ),
              ),
              onSubmitted: (_) => _nextStep(),
            ),
            const SizedBox(height: 24),
            FilledButton(
              style: _actionButtonStyle(),
              onPressed: _nextStep,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text('Press Enter ↵'),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
            ),
          ],
        );

      case 4:
        return Column(
          children: [
            const Text(
              "Confirm your secret password 🔒",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Still not looking! Lock it in to complete registration. 🙈",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.amberAccent, fontSize: 14),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _confirmController,
              focusNode: _confirmFocus,
              obscureText: _hideConfirm,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              textAlign: TextAlign.center,
              decoration: _conversationalInputDecoration(
                'Re-type password',
                Icons.verified_user_outlined,
                suffix: IconButton(
                  icon: Icon(
                    _hideConfirm ? Icons.visibility : Icons.visibility_off,
                    color: Colors.white60,
                  ),
                  onPressed: () => setState(() => _hideConfirm = !_hideConfirm),
                ),
              ),
              onSubmitted: (_) => _nextStep(),
            ),
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: orange,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 36,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _nextStep,
              child: const Text(
                'Create Account 🎉',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );

      case 5:
        return Column(
          children: const [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(color: orange, strokeWidth: 3),
            ),
            SizedBox(height: 24),
            Text(
              "Checking my watch while registering your account... ⏱️",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              "Connecting to Supabase security servers...",
              style: TextStyle(color: Colors.white60),
            ),
          ],
        );

      case 6:
        return Column(
          children: [
            const Text(
              "The Door is Closed Right Now! 🚪🔒",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.amberAccent,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "The key is with HR 🔑—ask HR to approve your account to unlock the door!",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 15,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: orange,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              },
              child: const Text(
                'Back to Sign In →',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );

      default:
        return const SizedBox.shrink();
    }
  }

  InputDecoration _conversationalInputDecoration(
    String hint,
    IconData icon, {
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: orange),
      suffixIcon: suffix,
      hintStyle: const TextStyle(color: Colors.white38),
      filled: true,
      fillColor: const Color(0xFF131B2A),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFF1E293B)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFF1E293B)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: orange, width: 2),
      ),
    );
  }

  ButtonStyle _actionButtonStyle() {
    return FilledButton.styleFrom(
      backgroundColor: const Color(0xFF1E293B),
      foregroundColor: orange,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: orange),
      ),
    );
  }
}

enum PenguinState {
  holdingSign,
  typingName,
  typingEmail,
  coveringEyes,
  checkingWatch,
  success,
  pendingDoorClosed,
  idle,
}

/// Ultra-Smooth Vector Penguin Mascot ("Peakie")
class PenguinMascot extends StatelessWidget {
  final PenguinState state;

  const PenguinMascot({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFF59E0B);
    final isCovering = state == PenguinState.coveringEyes;
    final isCheckingWatch = state == PenguinState.checkingWatch;
    final isSuccess = state == PenguinState.success;
    final isSign = state == PenguinState.holdingSign;

    return Column(
      children: [
        SizedBox(
          width: 180,
          height: 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Welcome Wood Sign (Step 0)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                top: isSign ? 8 : -80,
                right: 12,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: isSign ? 1.0 : 0.0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF92400E),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFFF59E0B),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.46),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Text(
                      'Welcome! 🚀',
                      style: TextStyle(
                        color: Colors.amberAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),

              // Feet
              Positioned(bottom: 6, left: 52, child: _penguinFoot()),
              Positioned(bottom: 6, right: 52, child: _penguinFoot()),

              // Main Body
              Positioned(
                bottom: 22,
                child: Container(
                  width: 110,
                  height: 126,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(56),
                    border: Border.all(color: Colors.grey.shade800, width: 1.5),
                  ),
                ),
              ),

              // White Belly
              Positioned(
                bottom: 26,
                child: Container(
                  width: 72,
                  height: 94,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(42),
                  ),
                ),
              ),

              // Gold Star Tie
              Positioned(
                top: 86,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: orange,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.star, size: 10, color: Colors.black),
                ),
              ),

              // Head
              Positioned(
                top: 16,
                child: Container(
                  width: 94,
                  height: 82,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(42),
                  ),
                ),
              ),

              // White Face Patch
              Positioned(
                top: 28,
                child: Container(
                  width: 72,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(32),
                  ),
                ),
              ),

              // Eyes
              Positioned(
                top: 42,
                left: 50,
                child: _penguinEye(closed: isCovering),
              ),
              Positioned(
                top: 42,
                right: 50,
                child: _penguinEye(closed: isCovering),
              ),

              // Beak
              Positioned(
                top: 54,
                child: Container(
                  width: 18,
                  height: 14,
                  decoration: const BoxDecoration(
                    color: orange,
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(8),
                      bottomRight: Radius.circular(8),
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(4),
                    ),
                  ),
                ),
              ),

              // LEFT FLIPPER (WING)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                top: isCovering
                    ? 32
                    : isCheckingWatch
                    ? 42
                    : isSuccess
                    ? 22
                    : 76,
                left: isCovering
                    ? 48
                    : isCheckingWatch
                    ? 38
                    : isSuccess
                    ? 14
                    : 16,
                child: AnimatedRotation(
                  turns: isCovering
                      ? 0.16
                      : isCheckingWatch
                      ? 0.22
                      : isSuccess
                      ? -0.22
                      : 0.05,
                  duration: const Duration(milliseconds: 350),
                  child: Container(
                    width: 28,
                    height: 58,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.grey.shade800),
                    ),
                    child: isCheckingWatch
                        ? const Center(
                            child: Icon(
                              Icons.watch_later_outlined,
                              size: 14,
                              color: orange,
                            ),
                          )
                        : null,
                  ),
                ),
              ),

              // RIGHT FLIPPER (WING)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                top: isCovering
                    ? 32
                    : isSuccess
                    ? 22
                    : 76,
                right: isCovering
                    ? 48
                    : isSuccess
                    ? 14
                    : 16,
                child: AnimatedRotation(
                  turns: isCovering
                      ? -0.16
                      : isSuccess
                      ? 0.22
                      : -0.05,
                  duration: const Duration(milliseconds: 350),
                  child: Container(
                    width: 28,
                    height: 58,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.grey.shade800),
                    ),
                  ),
                ),
              ),

              // CLOSED DOOR OVERLAY WHEN PENDING HR APPROVAL
              if (state == PenguinState.pendingDoorClosed)
                Positioned(
                  bottom: 0,
                  child: Container(
                    width: 130,
                    height: 140,
                    decoration: BoxDecoration(
                      color: const Color(0xFF78350F),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(22),
                        topRight: Radius.circular(22),
                      ),
                      border: Border.all(color: orange, width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.6),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(right: 14),
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: orange,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.lock,
                                size: 16,
                                color: Colors.black,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.vpn_key, color: orange, size: 12),
                              SizedBox(width: 4),
                              Text(
                                'KEY WITH HR 🔑',
                                style: TextStyle(
                                  color: orange,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _penguinEye({required bool closed}) {
    if (closed) {
      return Container(
        width: 12,
        height: 3,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(2),
        ),
      );
    }
    return Container(
      width: 12,
      height: 12,
      decoration: const BoxDecoration(
        color: Colors.black,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Container(
          width: 4,
          height: 4,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  Widget _penguinFoot() {
    return Container(
      width: 28,
      height: 14,
      decoration: const BoxDecoration(
        color: Color(0xFFF59E0B),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(10),
          topRight: Radius.circular(10),
          bottomLeft: Radius.circular(4),
          bottomRight: Radius.circular(4),
        ),
      ),
    );
  }
}
