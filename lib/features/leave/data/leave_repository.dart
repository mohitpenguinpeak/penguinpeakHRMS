import 'package:supabase_flutter/supabase_flutter.dart';

class LeaveRepository {
  const LeaveRepository(this.client);
  final SupabaseClient client;

  Future<void> approveRange({
    required String id,
    required String firstDay,
    required String lastDay,
    required String comment,
  }) async {
    await client.rpc(
      'review_leave_by_hr_range',
      params: {
        'p_request_id': id,
        'p_decision': 'approved',
        'p_comment': comment,
        'p_approved_start_date': firstDay,
        'p_approved_end_date': lastDay,
      },
    );
  }

  Future<void> cancel(String id, String reason) async {
    await client.rpc(
      'cancel_leave_request',
      params: {'p_request_id': id, 'p_reason': reason},
    );
  }

  Future<List<Map<String, dynamic>>> history(String id) async {
    final rows = await client
        .from('leave_request_history')
        .select('actor_id, action, created_at, details')
        .eq('request_id', id)
        .order('created_at');
    return List<Map<String, dynamic>>.from(rows);
  }
}
