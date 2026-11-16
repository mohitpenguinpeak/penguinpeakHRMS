import '../../../shared/widgets/app_toast.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../login_screen.dart';
import '../../../role_dashboard_screen.dart';
import '../application/session_controller.dart';
import '../data/session_repository.dart';
import '../domain/account_access.dart';

class SessionGate extends StatefulWidget {
  const SessionGate({super.key, this.verifiedUserId, this.verifiedAccess});
  final String? verifiedUserId;
  final AccountAccess? verifiedAccess;

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> with WidgetsBindingObserver {
  late final SessionController _controller;
  StreamSubscription<AuthState>? _authChanges;
  Timer? _recheck;
  bool _foreground = true;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final client = Supabase.instance.client;
    _controller = SessionController(SupabaseSessionRepository(client))
      ..addListener(_changed);
    if (widget.verifiedUserId != null && widget.verifiedAccess != null) {
      _controller.acceptVerified(
        widget.verifiedUserId!,
        widget.verifiedAccess!,
      );
      if (_controller.status == SessionStatus.checking) {
        unawaited(_controller.restore());
      }
    } else {
      unawaited(_controller.restore());
    }
    _authChanges = client.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedOut) {
        _controller.signedOut();
      } else if ((event.event == AuthChangeEvent.tokenRefreshed ||
              event.event == AuthChangeEvent.userUpdated) &&
          _controller.status != SessionStatus.signedOut) {
        // Do not await Supabase operations inside its auth notification callback.
        unawaited(Future<void>(() => _controller.restore(showLoading: false)));
      }
      if (event.event == AuthChangeEvent.signedIn &&
          _controller.status != SessionStatus.signedOut &&
          _controller.userId != event.session?.user.id) {
        unawaited(Future<void>(() => _controller.restore()));
      }
      // Password login validates its profile once, then calls acceptVerified.
    });
    _recheck = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_foreground && _controller.status == SessionStatus.approved) {
        unawaited(_controller.restore(showLoading: false));
      }
    });
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (_controller.status != SessionStatus.approved &&
        _controller.status != SessionStatus.checking) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _controller.status == SessionStatus.approved) return;
        final route = ModalRoute.of(context);
        if (route != null) {
          Navigator.of(context).popUntil((candidate) => candidate == route);
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && _controller.status != SessionStatus.signedOut) {
      unawaited(_controller.restore(showLoading: false));
    }
  }

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    try {
      await _controller.signOut();
    } catch (_) {
      if (mounted) {
        AppToast.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not clear this session. Please retry.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recheck?.cancel();
    _authChanges?.cancel();
    _controller.removeListener(_changed);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (_controller.status) {
      case SessionStatus.approved:
        return RoleDashboardScreen(
          key: ValueKey('${_controller.userId}:${_controller.role}'),
          role: _controller.role!,
        );
      case SessionStatus.signedOut:
        return LoginScreen(onAuthenticated: _controller.acceptVerified);
      case SessionStatus.checking:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case SessionStatus.blocked:
      case SessionStatus.error:
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 40),
                  const SizedBox(height: 16),
                  Text(
                    _controller.status == SessionStatus.blocked
                        ? 'Your account is not approved for access. Contact HR.'
                        : 'Could not verify your account. Check your connection and retry.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    children: [
                      FilledButton(
                        onPressed: _signingOut
                            ? null
                            : () => _controller.restore(),
                        child: const Text('Retry'),
                      ),
                      TextButton(
                        onPressed: _signingOut ? null : _signOut,
                        child: const Text('Sign out'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
    }
  }
}
