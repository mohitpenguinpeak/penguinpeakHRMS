import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/leave/domain/leave_request.dart';

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
            'id, employee_id, leave_type, start_date, end_date, approved_start_date, approved_end_date, approved_days, days, manager_status, hr_status',
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

  Map<String, dynamic>? _getProfile(dynamic employeeId) {
    final key = employeeId?.toString();
    for (final p in _profiles) {
      if (p['id']?.toString() == key) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            Text(
              'Team Leave Calendar',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            Chip(
              label: const Text('Privacy Protected (Approved Leaves Only)'),
              backgroundColor: Colors.green.withOpacity(0.2),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'View upcoming and current team leaves. Note: Medical notes and reasons are strictly private.',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 16),
        _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(child: Text('Error: $_error'))
            : _approvedLeaves.isEmpty
            ? const Center(child: Text('No approved upcoming leaves found.'))
            : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _approvedLeaves.length,
                itemBuilder: (context, index) {
                  final leave = _approvedLeaves[index];
                  final profile = _getProfile(leave['employee_id']);
                  final name = profile?['full_name'] ?? 'Employee';
                  final dept = profile?['department'] ?? 'General';
                  final startDate =
                      leave['start_date']?.toString().split('T')[0] ?? '';
                  final endDate =
                      leave['end_date']?.toString().split('T')[0] ?? '';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.green.withOpacity(0.2),
                        child: const Icon(
                          Icons.event_available,
                          color: Colors.green,
                        ),
                      ),
                      title: Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        'Department: $dept • Type: ${leave['leave_type']}',
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Chip(
                            label: Text(
                              'On Leave',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                            backgroundColor: Colors.green,
                            visualDensity: VisualDensity.compact,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$startDate to $endDate',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ],
    );
  }
}
