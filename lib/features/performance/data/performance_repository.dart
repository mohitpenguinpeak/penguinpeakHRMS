import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/performance_report.dart';

abstract class PerformanceRepository {
  String? get currentUserId;
  Future<PerformanceReport> load(
    PerformancePeriod period, {
    DateTime? anchor,
    String? employeeId,
  });
}

class SupabasePerformanceRepository implements PerformanceRepository {
  SupabasePerformanceRepository(this.client);
  final SupabaseClient client;
  @override
  String? get currentUserId => client.auth.currentUser?.id;

  @override
  Future<PerformanceReport> load(
    PerformancePeriod period, {
    DateTime? anchor,
    String? employeeId,
  }) async {
    final result = await client.rpc(
      'performance_scorecards',
      params: {
        'p_period': period.name,
        'p_anchor': anchor == null ? null : performanceDate(anchor),
        'p_employee': employeeId,
      },
    );
    return PerformanceReport.fromJson(Map<String, dynamic>.from(result as Map));
  }
}
