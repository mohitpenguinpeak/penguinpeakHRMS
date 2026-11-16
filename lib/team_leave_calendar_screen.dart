import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/leave/domain/leave_request.dart';
import 'features/leave/presentation/team_leave_calendar.dart';

class TeamLeaveCalendarScreen extends StatefulWidget {
  final String role;
  const TeamLeaveCalendarScreen({super.key, required this.role});

  @override
  State<TeamLeaveCalendarScreen> createState() =>
      _TeamLeaveCalendarScreenState();
}

class _TeamLeaveCalendarScreenState extends State<TeamLeaveCalendarScreen> {
  final SupabaseClient _db = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _approvedLeaves = [];
  List<Map<String, dynamic>> _profiles = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profilesRes = await _db
          .from('profiles')
          .select('id, full_name, department, role')
          .eq('approval_status', 'approved')
          .order('full_name');
      _profiles = List<Map<String, dynamic>>.from(profilesRes);

      // Query only approved leaves (manager_status = approved AND hr_status = approved)
      // PRIVACY SAFE: We do NOT fetch reason, medical notes, or comments.
      final leavesRes = await _db
          .from('leave_requests')
          .select(
            'id, employee_id, leave_type, day_portion, start_date, end_date, approved_start_date, approved_end_date, approved_days, days, manager_status, hr_status',
          )
          .eq('manager_status', 'approved')
          .eq('hr_status', 'approved')
          .isFilter('cancelled_at', null)
          .order('start_date', ascending: true);

      _approvedLeaves = List<Map<String, dynamic>>.from(leavesRes)
          .map((row) => LeaveRequest(row).effectiveRow)
          .toList();

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Column(
        children: [
          const Text('Could not load team leave.'),
          TextButton(onPressed: _loadData, child: const Text('Retry')),
        ],
      );
    }
    return TeamLeaveCalendar(
      leaves: _approvedLeaves,
      profiles: _profiles,
      onRefresh: _loadData,
    );
  }
}
