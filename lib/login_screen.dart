import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/auth/presentation/session_gate.dart';
import 'signup_screen.dart';
import 'features/auth/domain/account_access.dart';

enum PenguinState {
  idle,
  typingEmail,
  typingName,
  coveringEyes,
  checkingWatch,
  error,
  success,
  pendingDoorClosed,
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.onAuthenticated});

  final void Function(String userId, AccountAccess access)? onAuthenticated;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _loading = false;
  bool _hidePassword = true;
  PenguinState _mascotState = PenguinState.idle;
  String? _customErrorMessage;

  @override
  void initState() {
    super.initState();
    _emailFocus.addListener(_onFocusChange);
    _passwordFocus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!mounted) return;
    setState(() {
      if (_passwordFocus.hasFocus) {
        _mascotState = PenguinState.coveringEyes;
      } else if (_emailFocus.hasFocus) {
        _mascotState = PenguinState.typingEmail;
      } else if (!_loading &&
          _mascotState != PenguinState.error &&
          _mascotState != PenguinState.success &&
          _mascotState != PenguinState.pendingDoorClosed) {
        _mascotState = PenguinState.idle;
      }
    });
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _mascotState = PenguinState.checkingWatch;
      _customErrorMessage = null;
    });

    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;

      if (response.user == null) {
        throw const AuthException('Login failed. Please check credentials.');
      }

      final profile = await Supabase.instance.client
          .from('profiles')
          .select('approval_status, role')
          .eq('id', response.user!.id)
          .maybeSingle();

      if (!mounted) return;

      final access = AccountAccess.fromProfile(profile);

      if (access.isApproved) {
        setState(() {
          _mascotState = PenguinState.success;
        });

        await Future.delayed(const Duration(milliseconds: 1200));

        if (!mounted) return;
        final uid = response.user!.id;
        if (Supabase.instance.client.auth.currentUser?.id != uid) return;
        if (widget.onAuthenticated != null) {
          widget.onAuthenticated!(uid, access);
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) =>
                  SessionGate(verifiedUserId: uid, verifiedAccess: access),
            ),
          );
        }
      } else {
        await Supabase.instance.client.auth.signOut();
        if (!mounted) return;

        final isRejected = access.isRejected;
        final errText = isRejected
            ? 'Your account was rejected by HR.'
            : 'The door is closed for you right now! 🚪🔒 The key is with HR 🔑—ask HR to approve your account to open the door!';

        setState(() {
          _mascotState = isRejected
              ? PenguinState.error
              : PenguinState.pendingDoorClosed;
          _customErrorMessage = errText;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errText),
            backgroundColor: Colors.orange.shade900,
          ),
        );
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _mascotState = PenguinState.error;
        _customErrorMessage = e.message;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red.shade900,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mascotState = PenguinState.error;
        _customErrorMessage = 'Something went wrong. Please retry!';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red.shade900,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _emailFocus.removeListener(_onFocusChange);
    _passwordFocus.removeListener(_onFocusChange);
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFF59E0B);

    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.2),
            radius: 1.2,
            colors: [Color(0xFF281C0F), Color(0xFF080808)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Full-Body Animated Penguin Mascot
                      PenguinMascotWidget(
                        state: _mascotState,
                        customMessage: _customErrorMessage,
                      ),

                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _emailController,
                        focusNode: _emailFocus,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        style: const TextStyle(color: Colors.white),
                        decoration: _decoration(
                          'Corporate Work Email',
                          Icons.email_outlined,
                        ),
                        validator: (value) {
                          final email = value?.trim() ?? '';
                          if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                              .hasMatch(email)) {
                            return 'Enter a valid corporate email address';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 18),

                      TextFormField(
                        controller: _passwordController,
                        focusNode: _passwordFocus,
                        obscureText: _hidePassword,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _login(),
                        autofillHints: const [AutofillHints.password],
                        style: const TextStyle(color: Colors.white),
                        decoration: _decoration('Password', Icons.lock_outline)
                            .copyWith(
                              suffixIcon: IconButton(
                                onPressed: () => setState(
                                  () => _hidePassword = !_hidePassword,
                                ),
                                icon: Icon(
                                  _hidePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: Colors.white60,
                                ),
                              ),
                            ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Enter your password';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 24),

                      SizedBox(
                        height: 52,
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _loading ? null : _login,
                          style: FilledButton.styleFrom(
                            backgroundColor: orange,
                            foregroundColor: Colors.black,
                            elevation: 4,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _loading
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.black,
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Text(
                                      'Authenticating...',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                )
                              : const Text(
                                  'Sign In to Dashboard',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            "Don't have an account yet? ",
                            style: TextStyle(color: Colors.white60),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const SignupScreen(),
                                ),
                              );
                            },
                            child: const Text(
                              'Sign Up Here',
                              style: TextStyle(
                                color: orange,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: const Color(0xFFF59E0B)),
      labelStyle: const TextStyle(color: Colors.white60),
      filled: true,
      fillColor: const Color(0xFF171512),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF38332C)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF38332C)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFF59E0B), width: 1.5),
      ),
    );
  }
}

/// Full-Body Animated Penguin Mascot ("Peakie") with Interactive Speech Reactions
class PenguinMascotWidget extends StatelessWidget {
  final PenguinState state;
  final String? customMessage;

  const PenguinMascotWidget({
    super.key,
    required this.state,
    this.customMessage,
  });

  String _getSpeechText() {
    if (customMessage != null && customMessage!.isNotEmpty) {
      return customMessage!;
    }
    switch (state) {
      case PenguinState.coveringEyes:
        return "Shh... I'm covering my eyes! Enter your secret password, I won't peek! 🙈";
      case PenguinState.typingEmail:
        return "Checking your corporate email address... 📧";
      case PenguinState.typingName:
        return "Nice to meet a new Penguin! What's your full name? ✨";
      case PenguinState.checkingWatch:
        return "Checking my wrist watch while connecting to server... ⏱️";
      case PenguinState.error:
        return "Oops! Those credentials didn't match. Give it another try! 😅";
      case PenguinState.success:
        return "Woohoo! Credentials verified! Welcome aboard! 🚀";
      case PenguinState.pendingDoorClosed:
        return "The door is closed for you right now! 🚪🔒 The key is with HR 🔑—tell HR to approve your account to open!";
      case PenguinState.idle:
        return "Welcome to PenguinPeak! Ready to sign in to your workspace? 🐧";
    }
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFF59E0B);
    final speechText = _getSpeechText();
    final isCovering = state == PenguinState.coveringEyes;
    final isCheckingWatch = state == PenguinState.checkingWatch;
    final isSuccess = state == PenguinState.success;
    final isError = state == PenguinState.error;
    final isDoorClosed = state == PenguinState.pendingDoorClosed;

    return Column(
      children: [
        // Interactive Speech Bubble
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: isDoorClosed
                ? const Color(0xFF78350F).withOpacity(0.95)
                : isError
                ? Colors.red.shade900.withOpacity(0.85)
                : isSuccess
                ? Colors.green.shade900.withOpacity(0.85)
                : const Color(0xFF1F1A14).withOpacity(0.9),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDoorClosed
                  ? orange
                  : isError
                  ? Colors.redAccent
                  : isSuccess
                  ? Colors.greenAccent
                  : orange.withOpacity(0.5),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color:
                    (isDoorClosed
                            ? orange
                            : isError
                            ? Colors.red
                            : isSuccess
                            ? Colors.green
                            : orange)
                        .withOpacity(0.25),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Text(
            speechText,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ),

        // Speech Tail Pointer
        Icon(
          Icons.arrow_drop_down,
          color: isDoorClosed
              ? const Color(0xFF78350F)
              : isError
              ? Colors.red.shade900
              : isSuccess
              ? Colors.green.shade900
              : orange.withOpacity(0.5),
          size: 24,
        ),

        const SizedBox(height: 4),

        // Full Body Animated Penguin ("Peakie") with Closed Door Support
        SizedBox(
          width: 160,
          height: 180,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Penguin Feet
              Positioned(bottom: 4, left: 42, child: _penguinFoot()),
              Positioned(bottom: 4, right: 42, child: _penguinFoot()),

              // Full Body
              Positioned(
                bottom: 20,
                child: Container(
                  width: 96,
                  height: 110,
                  decoration: BoxDecoration(
                    color: const Color(0xFF141A22),
                    borderRadius: BorderRadius.circular(48),
                    border: Border.all(color: Colors.grey.shade800),
                  ),
                ),
              ),

              // White Belly
              Positioned(
                bottom: 24,
                child: Container(
                  width: 62,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(36),
                  ),
                ),
              ),

              // Gold Bow Tie
              Positioned(
                top: 76,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: orange,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.star, size: 10, color: Colors.black),
                ),
              ),

              // Penguin Head
              Positioned(
                top: 12,
                child: Container(
                  width: 82,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFF141A22),
                    borderRadius: BorderRadius.circular(36),
                  ),
                ),
              ),

              // Head White Face Patch
              Positioned(
                top: 24,
                child: Container(
                  width: 60,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
              ),

              // Eyes
              Positioned(
                top: 36,
                left: 42,
                child: _penguinEye(closed: isCovering, error: isError),
              ),
              Positioned(
                top: 36,
                right: 42,
                child: _penguinEye(closed: isCovering, error: isError),
              ),

              // Beak
              Positioned(
                top: 48,
                child: Container(
                  width: 16,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF59E0B),
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
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutBack,
                top: isCovering
                    ? 28
                    : isCheckingWatch
                    ? 36
                    : isSuccess
                    ? 18
                    : 68,
                left: isCovering
                    ? 38
                    : isCheckingWatch
                    ? 30
                    : isSuccess
                    ? 10
                    : 12,
                child: AnimatedRotation(
                  turns: isCovering
                      ? 0.15
                      : isCheckingWatch
                      ? 0.22
                      : isSuccess
                      ? -0.2
                      : 0.05,
                  duration: const Duration(milliseconds: 280),
                  child: Container(
                    width: 26,
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFF141A22),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade800),
                    ),
                    child: isCheckingWatch
                        ? const Center(
                            child: Icon(
                              Icons.watch_later_outlined,
                              size: 14,
                              color: Color(0xFFF59E0B),
                            ),
                          )
                        : null,
                  ),
                ),
              ),

              // RIGHT FLIPPER (WING)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutBack,
                top: isCovering
                    ? 28
                    : isSuccess
                    ? 18
                    : 68,
                right: isCovering
                    ? 38
                    : isSuccess
                    ? 10
                    : 12,
                child: AnimatedRotation(
                  turns: isCovering
                      ? -0.15
                      : isSuccess
                      ? 0.2
                      : -0.05,
                  duration: const Duration(milliseconds: 280),
                  child: Container(
                    width: 26,
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFF141A22),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade800),
                    ),
                  ),
                ),
              ),

              // CLOSED DOOR OVERLAY WHEN PENDING HR APPROVAL
              if (isDoorClosed)
                Positioned(
                  bottom: 0,
                  child: Container(
                    width: 120,
                    height: 130,
                    decoration: BoxDecoration(
                      color: const Color(0xFF78350F),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
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

  Widget _penguinEye({required bool closed, required bool error}) {
    if (closed) {
      return Container(
        width: 10,
        height: 3,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(2),
        ),
      );
    }
    return Container(
      width: 10,
      height: 10,
      decoration: const BoxDecoration(
        color: Colors.black,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Container(
          width: 3,
          height: 3,
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
      width: 24,
      height: 12,
      decoration: const BoxDecoration(
        color: Color(0xFFF59E0B),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(8),
          topRight: Radius.circular(8),
          bottomLeft: Radius.circular(4),
          bottomRight: Radius.circular(4),
        ),
      ),
    );
  }
}
