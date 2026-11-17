import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../push_notification_service.dart';
import '../../../task_management_screen.dart';
import '../domain/account_access.dart';

abstract class SessionRepository {
  String? get currentUserId;
  Future<AccountAccess> loadAccess(String userId);
  Future<void> signOut();
}

/// Cleanup is best effort; a transport failure must never prevent local logout.
Future<void> completeLocalSignOut({
  required Future<void> Function() cleanup,
  required Future<void> Function() clearSession,
}) async {
  try {
    await cleanup();
  } catch (_) {
    /* Local logout remains mandatory. */
  }
  await clearSession();
}

class SupabaseSessionRepository implements SessionRepository {
  const SupabaseSessionRepository(this.client);
  final SupabaseClient client;

  @override
  String? get currentUserId => client.auth.currentUser?.id;

  @override
  Future<AccountAccess> loadAccess(String userId) async {
    final row = await client
        .from('profiles')
        .select('approval_status, role')
        .eq('id', userId)
        .maybeSingle();
    return AccountAccess.fromProfile(row);
  }

  @override
  Future<void> signOut() => completeLocalSignOut(
    cleanup: PushNotificationService.instance.unregister,
    clearSession: () async {
      try {
        await client.auth.signOut(scope: SignOutScope.local);
      } catch (_) {
        // The installed GoTrue client removes its local session before remote
        // revocation. Only suppress network errors once that removal succeeded.
        if (client.auth.currentSession != null) rethrow;
      }
      TaskTracker.instance.resetForSignOut();
    },
  );
}
