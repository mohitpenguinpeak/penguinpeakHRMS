import 'package:flutter/foundation.dart';

import '../data/session_repository.dart';
import '../domain/account_access.dart';

enum SessionStatus { checking, signedOut, approved, blocked, error }

/// UI access coordinator. Database policies remain the authorization boundary.
class SessionController extends ChangeNotifier {
  SessionController(this.repository);
  final SessionRepository repository;
  SessionStatus status = SessionStatus.checking;
  String? role;
  String? userId;
  bool _disposed = false;
  int _generation = 0;
  Future<void>? _checking;
  String? _checkingUserId;

  Future<void> restore({bool showLoading = true}) {
    if (_disposed) return Future<void>.value();
    final uid = repository.currentUserId;
    if (_checking != null && _checkingUserId == uid) return _checking!;
    final pending = _restore(showLoading);
    _checking = pending;
    _checkingUserId = uid;
    return pending.whenComplete(() {
      if (identical(_checking, pending)) {
        _checking = null;
        _checkingUserId = null;
      }
    });
  }

  Future<void> _restore(bool showLoading) async {
    final uid = repository.currentUserId;
    if (uid == null) {
      signedOut();
      return;
    }
    final generation = ++_generation;
    if (showLoading || userId != uid) {
      status = SessionStatus.checking;
      role = null;
      notifyListeners();
    }
    try {
      final access = await repository.loadAccess(uid);
      if (!_current(generation, uid)) return;
      userId = uid;
      role = access.isApproved ? access.role : null;
      status = access.isApproved
          ? SessionStatus.approved
          : SessionStatus.blocked;
    } catch (_) {
      if (!_current(generation, uid)) return;
      role = null;
      status = SessionStatus.error;
    }
    if (!_disposed) notifyListeners();
  }

  bool _current(int generation, String uid) =>
      !_disposed &&
      generation == _generation &&
      repository.currentUserId == uid;

  /// Accepts only the profile just verified by the login workflow for this session.
  void acceptVerified(String uid, AccountAccess access) {
    if (_disposed || repository.currentUserId != uid) return;
    _generation++;
    _checking = null;
    _checkingUserId = null;
    userId = uid;
    role = access.isApproved ? access.role : null;
    status = access.isApproved ? SessionStatus.approved : SessionStatus.blocked;
    notifyListeners();
  }

  void signedOut() {
    if (_disposed) return;
    final alreadySignedOut =
        status == SessionStatus.signedOut && userId == null && role == null;
    _generation++;
    // A later login can use the same user ID but belongs to a new session.
    // Its access check must not share a request from the signed-out session.
    _checking = null;
    _checkingUserId = null;
    userId = null;
    role = null;
    status = SessionStatus.signedOut;
    // Signup may briefly create and clear a session while login is displayed.
    // Do not pop its success screen for a duplicate signed-out notification.
    if (!alreadySignedOut) notifyListeners();
  }

  Future<void> signOut() async {
    await repository.signOut();
    signedOut();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
