import 'shared/widgets/app_toast.dart';

import 'package:flutter/material.dart';

import 'shared/widgets/peak_landscape.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/auth/presentation/session_gate.dart';
import 'signup_screen.dart';
import 'features/auth/domain/account_access.dart';

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
  String? _customErrorMessage;

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
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
            : 'Your account is awaiting HR approval.';

        setState(() {
          _customErrorMessage = errText;
        });

        AppToast.of(context).showSnackBar(
          SnackBar(
            content: Text(errText),
            backgroundColor: Colors.orange.shade900,
          ),
        );
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _customErrorMessage = e.message;
      });
      AppToast.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red.shade900,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _customErrorMessage = 'Something went wrong. Please retry!';
      });
      AppToast.of(context).showSnackBar(
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
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFF9BDDD7);

    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      body: PeakLandscape(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Container(
                  padding: EdgeInsets.all(
                    MediaQuery.sizeOf(context).width < 420 ? 16 : 28,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xf51a2434),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Workspace identity
                        Image.asset(
                          'assets/images/penguinpeak_logo.png',
                          height: 66,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Sign in',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -1.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _customErrorMessage ??
                              (_loading
                                  ? 'Signing in…'
                                  : 'PenguinPeak workspace'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
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
                          decoration:
                              _decoration(
                                'Password',
                                Icons.lock_outline,
                              ).copyWith(
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

                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
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
      ),
    );
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: const Color(0xFF9BDDD7)),
      labelStyle: const TextStyle(color: Colors.white60),
      filled: true,
      fillColor: const Color(0xFF111C2B),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF405468)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF405468)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF9BDDD7), width: 1.5),
      ),
    );
  }
}
