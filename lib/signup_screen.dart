import 'package:flutter/material.dart';

import 'shared/widgets/peak_landscape.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'login_screen.dart';
import 'shared/widgets/adaptive_layout.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  static const orange = Color(0xFF9BDDD7);
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

  @override
  Widget build(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).width < 600 ||
        MediaQuery.viewInsetsOf(context).bottom > 0;
    Widget formArea(Widget child) => compact ? Expanded(child: child) : child;
    return Scaffold(
      backgroundColor: background,
      body: Stack(
        children: [
          // Cosmic Background Stars Gradient
          Positioned.fill(child: const PeakLandscape(child: SizedBox.shrink())),

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
                      Flexible(
                        child: TextButton(
                          onPressed: () {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) => const LoginScreen(),
                              ),
                            );
                          },
                          child: Text(
                            compact
                                ? 'Sign In'
                                : 'Already have an account? Sign In',
                            style: TextStyle(
                              color: orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                if (!compact) const Spacer(),
                // Center Conversational Content Area
                formArea(
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
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 380),
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
                                  Image.asset(
                                    'assets/images/penguinpeak_logo.png',
                                    height: 72,
                                  ),

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
                ),

                if (!compact) const Spacer(),
                // Bottom Navigation Controls
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  child: AdaptiveRow(
                    breakpoint: compact ? 600 : 0,
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
                'Create your account',
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
              "Join your PenguinPeak workspace with your work email.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
                height: 1.4,
              ),
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
                "Get started",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );

      case 1:
        return Column(
          children: [
            const Text(
              "Your full name",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "This name appears on your employee profile.",
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
                  Text('Continue'),
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
                "Your work email",
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
              "Use the address you will sign in with.",
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
                  Text('Continue'),
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
              "Create a password",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Use at least eight characters.",
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
                  Text('Continue'),
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
              "Confirm your password",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Enter the same password again.",
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
                'Create Account',
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
              "Creating your account…",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              "Submitting your details.",
              style: TextStyle(color: Colors.white60),
            ),
          ],
        );

      case 6:
        return Column(
          children: [
            const Text(
              "Awaiting HR approval",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.amberAccent,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "You can sign in once HR approves your account.",
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
