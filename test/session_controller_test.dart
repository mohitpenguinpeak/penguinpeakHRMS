import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:penguinpeak_hrms/features/auth/application/session_controller.dart';
import 'package:penguinpeak_hrms/features/auth/data/session_repository.dart';
import 'package:penguinpeak_hrms/features/auth/domain/account_access.dart';

class FakeSessions implements SessionRepository {
  String? uid;
  int reads = 0;
  AccountAccess access = const AccountAccess(
    status: 'approved',
    role: 'employee',
  );
  Completer<AccountAccess>? pending;
  bool fail = false;
  @override
  String? get currentUserId => uid;
  @override
  Future<AccountAccess> loadAccess(String id) async {
    reads++;
    if (fail) throw StateError('Offline');
    return pending == null ? access : pending!.future;
  }

  @override
  Future<void> signOut() async {
    uid = null;
  }
}

void main() {
  test(
    'startup without a session opens login without a profile request',
    () async {
      final source = FakeSessions();
      final controller = SessionController(source);
      addTearDown(controller.dispose);
      await controller.restore();
      expect(controller.status, SessionStatus.signedOut);
      expect(source.reads, 0);
    },
  );
  test('restored session uses approved role from the database', () async {
    final source = FakeSessions()..uid = 'employee';
    final controller = SessionController(source);
    addTearDown(controller.dispose);
    await controller.restore();
    expect(controller.status, SessionStatus.approved);
    expect(controller.role, 'employee');
    source.access = const AccountAccess(status: 'approved', role: 'hr');
    await controller.restore(showLoading: false);
    expect(controller.role, 'hr');
  });
  test(
    'revoked or missing approval hides the previously visible dashboard',
    () async {
      final source = FakeSessions()..uid = 'employee';
      final controller = SessionController(source);
      addTearDown(controller.dispose);
      await controller.restore();
      source.access = const AccountAccess(status: 'rejected', role: 'employee');
      await controller.restore(showLoading: false);
      expect(controller.status, SessionStatus.blocked);
      expect(controller.role, isNull);
    },
  );
  test('network failure is an error state, never approval', () async {
    final source = FakeSessions()
      ..uid = 'employee'
      ..fail = true;
    final controller = SessionController(source);
    addTearDown(controller.dispose);
    await controller.restore();
    expect(controller.status, SessionStatus.error);
    expect(controller.role, isNull);
    source.fail = false;
    await controller.restore();
    expect(controller.status, SessionStatus.approved);
  });
  test('simultaneous session checks share one profile lookup', () async {
    final source = FakeSessions()
      ..uid = 'employee'
      ..pending = Completer<AccountAccess>();
    final controller = SessionController(source);
    addTearDown(controller.dispose);
    final first = controller.restore();
    final second = controller.restore();
    source.pending!.complete(source.access);
    await Future.wait([first, second]);
    expect(source.reads, 1);
  });
  test('late lookup cannot reopen access after logout', () async {
    final source = FakeSessions()
      ..uid = 'employee'
      ..pending = Completer<AccountAccess>();
    final controller = SessionController(source);
    addTearDown(controller.dispose);
    final checking = controller.restore();
    await controller.signOut();
    source.pending!.complete(source.access);
    await checking;
    expect(controller.status, SessionStatus.signedOut);
    expect(controller.role, isNull);
  });
  test('verified login rejects stale user identity without another query', () {
    final source = FakeSessions()..uid = 'new-account';
    final controller = SessionController(source);
    addTearDown(controller.dispose);
    controller.acceptVerified('old-account', source.access);
    expect(controller.status, SessionStatus.checking);
    controller.acceptVerified('new-account', source.access);
    expect(controller.status, SessionStatus.approved);
    expect(source.reads, 0);
  });
  test('same-account relogin does not reuse a signed-out lookup', () async {
    final stale = Completer<AccountAccess>();
    final source = FakeSessions()
      ..uid = 'employee'
      ..pending = stale;
    final controller = SessionController(source);
    addTearDown(controller.dispose);
    final old = controller.restore();
    await controller.signOut();
    source
      ..uid = 'employee'
      ..pending = null
      ..access = const AccountAccess(status: 'rejected', role: 'employee');
    final fresh = controller.restore();
    expect(source.reads, 2);
    await fresh;
    expect(controller.status, SessionStatus.blocked);
    stale.complete(const AccountAccess(status: 'approved', role: 'hr'));
    await old;
    expect(controller.status, SessionStatus.blocked);
    expect(controller.role, isNull);
  });
  test('verified login permits fresh recheck before old lookup finishes', () async {
    final stale = Completer<AccountAccess>();
    final source = FakeSessions()
      ..uid = 'employee'
      ..pending = stale;
    final controller = SessionController(source);
    addTearDown(controller.dispose);
    final old = controller.restore();
    controller.acceptVerified('employee', source.access);
    final current = Completer<AccountAccess>();
    source.pending = current;
    final fresh = controller.restore(showLoading: false);
    expect(source.reads, 2);
    stale.complete(source.access);
    await old;
    final shared = controller.restore(showLoading: false);
    expect(source.reads, 2);
    current.complete(const AccountAccess(status: 'rejected', role: 'employee'));
    await Future.wait([fresh, shared]);
    expect(controller.status, SessionStatus.blocked);
    expect(controller.role, isNull);
  });
  test(
    'account change starts a new lookup and ignores the old response',
    () async {
      final firstRead = Completer<AccountAccess>();
      final source = FakeSessions()
        ..uid = 'first'
        ..pending = firstRead;
      final controller = SessionController(source);
      addTearDown(controller.dispose);
      final old = controller.restore();
      source.uid = 'second';
      source.pending = null;
      source.access = const AccountAccess(status: 'approved', role: 'hr');
      await controller.restore();
      firstRead.complete(
        const AccountAccess(status: 'approved', role: 'employee'),
      );
      await old;
      expect(controller.userId, 'second');
      expect(controller.role, 'hr');
      expect(source.reads, 2);
    },
  );
  test('disposed controller ignores late account responses', () async {
    final source = FakeSessions()
      ..uid = 'first'
      ..pending = Completer<AccountAccess>();
    final controller = SessionController(source);
    final old = controller.restore();
    controller.dispose();
    source.pending!.complete(source.access);
    await old;
    await controller.restore();
    expect(source.reads, 1);
  });
  test('duplicate signed-out events do not interrupt the signup route', () {
    final controller = SessionController(FakeSessions());
    addTearDown(controller.dispose);
    var changes = 0;
    controller.addListener(() => changes++);
    controller.signedOut();
    controller.signedOut();
    expect(changes, 1);
  });
  test('best effort cleanup failure does not prevent local logout', () async {
    var cleared = false;
    await completeLocalSignOut(
      cleanup: () async => throw StateError('Cleanup offline'),
      clearSession: () async => cleared = true,
    );
    expect(cleared, isTrue);
  });
  test('a failed session clear is not falsely reported successful', () async {
    await expectLater(
      completeLocalSignOut(
        cleanup: () async {},
        clearSession: () async => throw StateError('Local storage failure'),
      ),
      throwsStateError,
    );
  });
}
