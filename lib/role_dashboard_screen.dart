import 'features/dashboard/presentation/calendar_event_sheet.dart';
import 'package:penguinpeak_hrms/shared/widgets/company_calendar.dart';
import 'shared/widgets/alpine_landscape.dart';
import 'features/attendance/domain/attendance_summary.dart';
import 'shared/widgets/app_toast.dart';
import 'features/notifications/domain/notification_destination.dart';
import 'features/hr/domain/hr_module.dart';
import 'features/hr/presentation/hr_workspace.dart';
import 'features/performance/presentation/performance_workspace.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/leave/domain/leave_request.dart';
import 'features/people/presentation/remove_user_dialog.dart';

import 'app_theme.dart';
import 'core/theme/design_system.dart';
import 'features/organization/presentation/organization_chart.dart';
import 'shared/widgets/adaptive_layout.dart';
import 'features/dashboard/presentation/holiday_list.dart';
import 'features/leave/presentation/leave_balance_summary.dart';
import 'attendance_adjustment_screen.dart';
import 'attendance_management_screen.dart';
import 'chat_screen.dart';
import 'company_wall_screen.dart';
import 'leave_management_screen.dart';
import 'features/auth/presentation/session_gate.dart';
import 'features/auth/data/session_repository.dart';
import 'notification_bell.dart';
import 'task_management_screen.dart';
import 'features/tasks/presentation/header_task_timer.dart';
import 'team_leave_calendar_screen.dart';

const _profileDetailFields = <String, String>{
  'bio': 'Work Summary & Bio',
  'skills': 'Primary Skills (comma separated)',
  'location': 'Location',
  'contact_email': 'Contact Email',
  'emergency_contact': 'Emergency Contact',
  'date_of_birth': 'Date of Birth (YYYY-MM-DD)',
  'gender': 'Gender',
  'marital_status': 'Marital Status',
  'blood_group': 'Blood Group',
  'address': 'Permanent Address',
  'work_shift': 'Work Shift',
  'employment_type': 'Employment Type',
  'probation_period': 'Probation Period',
};

class RoleDashboardScreen extends StatefulWidget {
  final String role;

  const RoleDashboardScreen({super.key, required this.role});

  @override
  State<RoleDashboardScreen> createState() => _RoleDashboardScreenState();
}

class _RoleDashboardScreenState extends State<RoleDashboardScreen> {
  final _supabase = Supabase.instance.client;

  Map<String, dynamic>? _myProfile;
  List<Map<String, dynamic>> _profiles = [];
  Map<String, dynamic>? _myTodayAttendance;
  List<Map<String, dynamic>> _onLeaveToday = [];
  List<Map<String, dynamic>> _myLeaveBalances = [];
  List<Map<String, dynamic>> _announcements = [];
  List<Map<String, dynamic>> _holidays = [];

  String? _holidayLoadError;

  bool _loading = true;
  bool _clockBusy = false;
  bool _publishingPost = false;
  String? _error;
  int _selectedIndex = 0;
  String? _notificationRecordId;
  int _notificationOpenRevision = 0;
  void _openNotificationDestination(NotificationDestination destination) {
    final index = _menuItems.indexWhere(
      (item) => item.label == destination.label,
    );
    if (index < 0) return;
    setState(() {
      _selectedIndex = index;
      _notificationRecordId = destination.recordId;
      _notificationOpenRevision++;
    });
  }

  void _consumeNotificationTarget() {
    _notificationRecordId = null;
  }

  String _searchQuery = '';
  String _roleFilter = 'all';
  String _statusFilter = 'all';

  // Company Wall Composer Controller
  final TextEditingController _wallPostController = TextEditingController();
  String _composerCategory = 'post'; // 'post', 'announcement', 'praise'

  // Live Timer for Attendance Widget
  Timer? _timer;
  DateTime _now = DateTime.now();

  bool get _canViewAllEmployees =>
      ['admin', 'super_admin', 'hr'].contains(widget.role);

  String get _roleLabel {
    switch (widget.role) {
      case 'super_admin':
      case 'admin':
        return 'Administrator';
      case 'management':
        return 'Management';
      case 'hr':
        return 'Human Resources';
      default:
        return 'Employee';
    }
  }

  List<_DashboardItem> get _menuItems {
    final items = <_DashboardItem>[
      const _DashboardItem('Overview', Icons.dashboard_outlined),
    ];

    items.addAll([
      const _DashboardItem('Employees', Icons.people_outline),
      const _DashboardItem('Organization', Icons.account_tree_outlined),
      const _DashboardItem('Leave', Icons.event_note_outlined),
      const _DashboardItem('Attendance', Icons.access_time_outlined),
      const _DashboardItem(
        'Attendance Adjustments',
        Icons.edit_calendar_outlined,
      ),
      const _DashboardItem('Tasks', Icons.task_alt_outlined),
      const _DashboardItem('Resource Availability', Icons.people_alt_outlined),
      const _DashboardItem('Performance', Icons.insights_outlined),
      const _DashboardItem('Chat', Icons.chat_bubble_outline),
      const _DashboardItem('Company Wall', Icons.feed_outlined),
      const _DashboardItem('Team Calendar', Icons.calendar_month_outlined),
      for (final module in HrModule.all)
        _DashboardItem(module.label, module.icon),
      const _DashboardItem('My Profile', Icons.person_outline),
      const _DashboardItem('Settings', Icons.settings_outlined),
    ]);

    return items;
  }

  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    _loadData();
    _setupRealtime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  void _setupRealtime() {
    try {
      _realtimeChannel = _supabase
          .channel('public:workspace_all_changes')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            callback: (payload) {
              if (mounted) {
                if (payload.table == 'holidays') {
                  _refreshCalendar();
                } else {
                  _loadDataSilently();
                }
              }
            },
          )
          .subscribe();
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _readCalendar() async {
    final loadedHolidays = <Map<String,dynamic>>[];
    for (var offset = 0; ; offset += 500) {
      final rows = await _supabase.from('holidays')
          .select('id, name, holiday_date, type').order('holiday_date').order('id')
          .range(offset, offset + 499);
      loadedHolidays.addAll(rows);
      if (rows.length < 500) break;
    }
    return loadedHolidays;
  }

  Future<void> _refreshCalendar() async {
    try {
      final rows = await _readCalendar();
      if (mounted) setState(() { _holidays = rows; _holidayLoadError = null; });
    } catch (_) {
      if (mounted) setState(() => _holidayLoadError = 'Could not load company calendar. Please refresh.');
    }
  }

  Future<void> _loadDataSilently() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      final todayStr = DateTime.now().toIso8601String().split('T')[0];

      final myProfile = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      final result = await _supabase
          .from('profiles')
          .select()
          .order('created_at', ascending: false);

      final attRes = await _supabase
          .from('attendance_records')
          .select('*, attendance_breaks(*)')
          .eq('employee_id', user.id)
          .eq('attendance_date', todayStr)
          .maybeSingle();

      final leavesRes = await _supabase
          .from('leave_requests')
          .select('*')
          .eq('manager_status', 'approved')
          .eq('hr_status', 'approved')
          .isFilter('cancelled_at', null)
          .lte('start_date', todayStr)
          .gte('end_date', todayStr);

      final myBalancesRes = await _supabase
          .from('leave_balances')
          .select()
          .eq('employee_id', user.id);

      final wallRes = await _supabase
          .from('company_wall_posts')
          .select('*')
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: false)
          .limit(5);

      if (!mounted) return;
      setState(() {
        if (myProfile != null)
          _myProfile = Map<String, dynamic>.from(myProfile);
        _profiles = List<Map<String, dynamic>>.from(result)
            .where((row) => row['removed_at'] == null)
            .toList();
        _myTodayAttendance = attRes;
        _onLeaveToday = List<Map<String, dynamic>>.from(leavesRes)
            .where((row) => LeaveRequest(row).covers(DateTime.now()))
            .map((row) => LeaveRequest(row).effectiveRow)
            .toList();
        _myLeaveBalances = List<Map<String, dynamic>>.from(myBalancesRes);
        _announcements = List<Map<String, dynamic>>.from(wallRes);
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    _realtimeChannel?.unsubscribe();
    _wallPostController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final user = _supabase.auth.currentUser;

      if (user == null) {
        throw Exception('Your session has expired. Please log in again.');
      }

      final myProfile = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (myProfile == null) {
        throw Exception(
          'Your profile was not found. Contact your administrator.',
        );
      }

      final result = await _supabase
          .from('profiles')
          .select()
          .order('created_at', ascending: false);
      final profiles = List<Map<String, dynamic>>.from(result)
          .where((row) => row['removed_at'] == null)
          .toList();

      final todayStr = DateTime.now().toIso8601String().split('T')[0];

      // Load today's attendance for current user
      final attRes = await _supabase
          .from('attendance_records')
          .select('*, attendance_breaks(*)')
          .eq('employee_id', user.id)
          .eq('attendance_date', todayStr)
          .maybeSingle();

      // Load employees on approved leave today
      final leavesRes = await _supabase
          .from('leave_requests')
          .select('*')
          .eq('manager_status', 'approved')
          .eq('hr_status', 'approved')
          .isFilter('cancelled_at', null)
          .lte('start_date', todayStr)
          .gte('end_date', todayStr);

      // Load authoritative allocations and usage for the current employee.
      final myBalancesRes = await _supabase
          .from('leave_balances')
          .select()
          .eq('employee_id', user.id);

      // Load announcements from company_wall_posts
      final wallRes = await _supabase
          .from('company_wall_posts')
          .select('*')
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: false)
          .limit(5);

      // All workspace calendars share these saved overrides.
      List<Map<String, dynamic>> loadedHolidays = [];
      String? holidayError;
      try {
        loadedHolidays = await _readCalendar();
      } catch (_) {
        holidayError = 'Could not load company holidays. Please retry.';
      }

      if (!mounted) return;

      setState(() {
        _myProfile = Map<String, dynamic>.from(myProfile);
        _profiles = profiles;
        _myTodayAttendance = attRes;
        _onLeaveToday = List<Map<String, dynamic>>.from(leavesRes)
            .where((row) => LeaveRequest(row).covers(DateTime.now()))
            .map((row) => LeaveRequest(row).effectiveRow)
            .toList();
        _myLeaveBalances = List<Map<String, dynamic>>.from(myBalancesRes);
        _announcements = List<Map<String, dynamic>>.from(wallRes);
        _holidays = loadedHolidays;
        _holidayLoadError = holidayError;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _logout() async {
    try {
      await SupabaseSessionRepository(_supabase).signOut();

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SessionGate()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;

      AppToast.of(context)
          .showSnackBar(SnackBar(content: Text('Logout failed: $e')));
    }
  }

  Future<void> _showPreviouslyRemovedUsers() async {
    if (widget.role != 'hr') return;
    try {
      final removed = await _supabase
          .from('profiles')
          .select('id, full_name')
          .not('removed_at', 'is', null);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Previously removed users'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'These accounts still have login records. Delete permanently to free their email addresses.',
                  ),
                  if (removed.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No previously removed users.'),
                    ),
                  for (final profile in removed)
                    ListTile(
                      title: Text('${profile['full_name'] ?? 'User'}'),
                      trailing: IconButton(
                        tooltip: 'Delete permanently',
                        icon: const Icon(Icons.delete_forever_outlined),
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          _removeUser(profile);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted)
        AppToast.show(
          context,
          'Could not load removed users: $e',
          kind: ToastKind.error,
        );
    }
  }

  final Set<String> _removingUsers = {};

  Future<void> _removeUser(Map<String, dynamic> profile) async {
    final id = profile['id']?.toString();
    if (widget.role != 'hr' ||
        id == null ||
        id == _supabase.auth.currentUser?.id ||
        _removingUsers.contains(id))
      return;
    if (!await confirmUserRemoval(
          context,
          '${profile['full_name'] ?? 'this user'}',
        ) ||
        !mounted)
      return;
    setState(() {
      _removingUsers.add(id);
    });
    try {
      final response = await _supabase.functions.invoke(
        'delete-user',
        body: {'user_id': id},
      );
      if (response.status != 200 ||
          response.data is! Map ||
          response.data['deleted'] != true) {
        throw StateError('Permanent deletion did not complete. Please retry.');
      }
      if (!mounted) return;
      setState(() {
        _profiles.removeWhere((row) => row['id']?.toString() == id);
      });
      AppToast.show(
        context,
        'User permanently deleted. Their email can be registered again.',
        kind: ToastKind.success,
      );
      await _loadData();
    } catch (e) {
      if (mounted)
        AppToast.show(
          context,
          'Could not remove user: $e',
          kind: ToastKind.error,
        );
    } finally {
      if (mounted)
        setState(() {
          _removingUsers.remove(id);
        });
    }
  }

  Future<void> _reviewEmployee(String userId, String status) async {
    try {
      await _supabase.rpc(
        'review_employee',
        params: {'p_user_id': userId, 'p_approval_status': status},
      );

      if (!mounted) return;
      AppToast.of(context).showSnackBar(
        SnackBar(
          content: Text('🎉 Account $status successfully!'),
          backgroundColor: status == 'approved' ? Colors.green : Colors.orange,
        ),
      );
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      AppToast.of(context).showSnackBar(
        SnackBar(content: Text('Could not update account status: $e')),
      );
    }
  }

  Future<void> _handleClockInOut() async {
    if (_clockBusy) return;
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    final todayStr = DateTime.now().toIso8601String().split('T')[0];
    final nowIso = DateTime.now().toUtc().toIso8601String();

    setState(() => _clockBusy = true);
    try {
      final existing = await _supabase
          .from('attendance_records')
          .select('*, attendance_breaks(*)')
          .eq('employee_id', user.id)
          .eq('attendance_date', todayStr)
          .maybeSingle();

      if (existing == null) {
        // First check in today
        final nowLocal = DateTime.now();
        final settings =
            await _supabase
                .from('company_attendance_settings')
                .select()
                .maybeSingle() ??
            <String, dynamic>{};
        final lateMinutes = attendanceLateMinutes(nowLocal, settings);
        final status = lateMinutes > 0 ? 'Late' : 'Present';

        final newRec = await _supabase
            .from('attendance_records')
            .insert({
              'employee_id': user.id,
              'attendance_date': todayStr,
              'check_in': nowIso,
              'status': status,
              'late_minutes': lateMinutes,
              'work_sessions': [
                {
                  'check_in': nowIso,
                  'check_out': null,
                  'work_duration_minutes': 0,
                },
              ],
            })
            .select()
            .single();
        if (!mounted) return;
        setState(() => _myTodayAttendance = newRec);
        AppToast.of(context).showSnackBar(
          const SnackBar(
            content: Text('🟢 Successfully checked in!'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (existing['check_out'] != null) {
        // Already checked out before, start a new session (Check In Again)
        final sessions = attendanceSessions(existing);
        sessions.add({
          'check_in': nowIso,
          'check_out': null,
          'work_duration_minutes': 0,
        });

        final updated = await _supabase
            .from('attendance_records')
            .update({
              'work_sessions': sessions,
              'check_out': null,
              'updated_at': nowIso,
            })
            .eq('id', existing['id'])
            .select()
            .single();
        if (!mounted) return;
        setState(() => _myTodayAttendance = updated);
        AppToast.of(context).showSnackBar(
          const SnackBar(
            content: Text('🟢 Successfully checked in again!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        // Currently checked in -> Check Out
        final breaks = (existing['attendance_breaks'] as List? ?? [])
            .whereType<Map>();
        if (breaks.any((row) => row['break_end'] == null)) {
          throw StateError('Please end your active break before checking out.');
        }
        final sessions = attendanceSessions(existing);
        final sessionIndex = sessions.lastIndexWhere(
          (session) => session['check_out'] == null,
        );
        if (sessionIndex < 0) throw StateError('No open work session found.');
        final now = DateTime.now();
        final start = DateTime.tryParse(
          '${sessions[sessionIndex]['check_in']}',
        );
        if (start == null || now.isBefore(start)) {
          throw StateError('Check-out cannot be earlier than check-in.');
        }
        sessions[sessionIndex]['check_out'] = nowIso;
        for (var i = 0; i < sessions.length; i++) {
          sessions[i]['work_duration_minutes'] = attendanceSessionMinutes(
            existing,
            sessions[i],
            i,
            now,
          );
        }
        final totalWorkMinutes = sessions.fold<int>(
          0,
          (sum, session) => sum + (session['work_duration_minutes'] as int),
        );
        final settings =
            await _supabase
                .from('company_attendance_settings')
                .select()
                .maybeSingle() ??
            <String, dynamic>{};
        final threshold =
            double.tryParse('${settings['half_day_hours'] ?? 4}') ?? 4;
        final status = existing['status'] == 'Late'
            ? 'Late'
            : totalWorkMinutes < threshold * 60
            ? 'Half Day'
            : 'Present';
        final updated = await _supabase
            .from('attendance_records')
            .update({
              'check_out': nowIso,
              'work_sessions': sessions,
              'work_duration_minutes': totalWorkMinutes,
              'status': status,
              'break_duration_minutes': breaks.fold<int>(
                0,
                (sum, row) =>
                    sum + ((row['duration_minutes'] as num?)?.toInt() ?? 0),
              ),
              'updated_at': nowIso,
            })
            .eq('id', existing['id'])
            .select()
            .single();
        if (!mounted) return;
        setState(() => _myTodayAttendance = updated);
        AppToast.of(context).showSnackBar(
          const SnackBar(
            content: Text('🔴 Successfully checked out!'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      await _loadDataSilently();
    } catch (e) {
      if (!mounted) return;
      AppToast.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Attendance action failed: $e')));
    } finally {
      if (mounted) setState(() => _clockBusy = false);
    }
  }

  Future<void> _submitWallPost() async {
    if (_publishingPost) return;
    final text = _wallPostController.text.trim();
    final user = _supabase.auth.currentUser;
    if (user == null || text.isEmpty) return;

    setState(() => _publishingPost = true);
    try {
      await _supabase.from('company_wall_posts').insert({
        'author_id': user.id,
        'title': _composerCategory == 'announcement'
            ? '📢 Announcement'
            : _composerCategory == 'praise'
            ? '👏 Praise'
            : 'Company Update',
        'content': text,
        'post_type': _composerCategory == 'post'
            ? 'general'
            : _composerCategory,
        'is_pinned': _composerCategory == 'announcement',
      });

      if (!mounted) return;
      if (_wallPostController.text.trim() == text) _wallPostController.clear();
      AppToast.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 Post published to Company Wall!'),
          backgroundColor: Colors.green,
        ),
      );
      _loadData();
    } catch (e) {
      if (!mounted) return;
      AppToast.of(context)
          .showSnackBar(SnackBar(content: Text('Error publishing post: $e')));
    } finally {
      if (mounted) setState(() => _publishingPost = false);
    }
  }

  void _navigateToModule(String moduleName) {
    final idx = _menuItems.indexWhere((item) => item.label == moduleName);
    if (idx != -1) {
      setState(() {
        _selectedIndex = idx;
        _notificationRecordId = null;
      });
    }
  }

  Widget _buildTopSearchBar(bool isDesktop) {
    return SizedBox(
      width: isDesktop ? 340 : double.infinity,
      height: 40,
      child: SearchAnchor(
        builder: (context, controller) {
          return SearchBar(
            controller: controller,
            hintText: 'Search employees or actions...',
            hintStyle: WidgetStateProperty.all(
              const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            elevation: WidgetStateProperty.all(1),
            padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(horizontal: 12),
            ),
            leading: const Icon(
              Icons.search,
              size: 18,
              color: AppThemes.orange,
            ),
            onChanged: (_) {
              if (!controller.isOpen) controller.openView();
            },
            onTap: () {
              if (!controller.isOpen) controller.openView();
            },
          );
        },
        suggestionsBuilder: (context, controller) {
          final query = controller.text.trim().toLowerCase();

          final matchedEmployees = _profiles.where((p) {
            final name = (p['full_name'] ?? '').toString().toLowerCase();
            final dept = (p['department'] ?? '').toString().toLowerCase();
            final desig = (p['designation'] ?? '').toString().toLowerCase();
            return name.contains(query) ||
                dept.contains(query) ||
                desig.contains(query);
          }).toList();

          final matchedModules = _menuItems.where((m) {
            return m.label.toLowerCase().contains(query);
          }).toList();

          final suggestions = <Widget>[];

          if (matchedModules.isNotEmpty) {
            suggestions.add(
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'HRMS MODULES & ACTIONS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppThemes.orange,
                  ),
                ),
              ),
            );
            for (final m in matchedModules) {
              suggestions.add(
                ListTile(
                  leading: Icon(m.icon, color: AppThemes.orange, size: 20),
                  title: Text(
                    m.label,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'Navigate to module',
                    style: TextStyle(fontSize: 11),
                  ),
                  onTap: () {
                    controller.closeView(m.label);
                    _navigateToModule(m.label);
                  },
                ),
              );
            }
            suggestions.add(const Divider());
          }

          if (matchedEmployees.isNotEmpty) {
            suggestions.add(
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'EMPLOYEE DIRECTORY MATCHES',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppThemes.orange,
                  ),
                ),
              ),
            );
            for (final p in matchedEmployees) {
              final empName = p['full_name'] ?? 'Employee';
              suggestions.add(
                ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      empName.isNotEmpty ? empName[0].toUpperCase() : 'U',
                    ),
                  ),
                  title: Text(
                    empName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${p['department'] ?? 'General'} • ${p['designation'] ?? 'Staff'}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  onTap: () {
                    controller.closeView(empName);
                    _showEmployeeProfile(p);
                  },
                ),
              );
            }
          }

          if (suggestions.isEmpty) {
            suggestions.add(
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text('No employees or modules match your search.'),
                ),
              ),
            );
          }

          return suggestions;
        },
      ),
    );
  }

  void _selectPage(
    int index,
    BuildContext tileContext, {
    required bool isDrawer,
  }) {
    setState(() {
      _selectedIndex = index;
      _notificationRecordId = null;
    });

    if (isDrawer) {
      Navigator.of(tileContext).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 850;
        final theme = Theme.of(context);
        final colors = theme.colorScheme;

        return Scaffold(
          drawer: isDesktop
              ? null
              : Drawer(child: SafeArea(child: _buildSidebar(isDrawer: true))),
          appBar: AppBar(
            bottom: isDesktop
                ? null
                : PreferredSize(
                    preferredSize: const Size.fromHeight(64),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: _buildTopSearchBar(false),
                    ),
                  ),
            leading: isDesktop
                ? null
                : Builder(
                    builder: (context) => IconButton(
                      tooltip: 'Open workspace menu',
                      icon: const Icon(Icons.menu_rounded),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                  ),
            title: Row(
              children: [
                const Flexible(
                  child: Text(
                    'PenguinPeak HRMS',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
                if (isDesktop) ...[
                  const SizedBox(width: 16),
                  _buildTopSearchBar(true),
                ],
              ],
            ),
            actions: [
              HeaderTaskTimer(compact: !isDesktop),
              NotificationBell(
                role: widget.role,
                onNavigate: _openNotificationDestination,
              ),
              if (isDesktop)
                IconButton(
                  tooltip: 'Switch theme',
                  onPressed: () {
                    appThemeMode.value = appThemeMode.value == ThemeMode.dark
                        ? ThemeMode.light
                        : ThemeMode.dark;
                  },
                  icon: Icon(
                    theme.brightness == Brightness.dark
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                  ),
                ),
              if (isDesktop)
                IconButton(
                  tooltip: 'Refresh data',
                  onPressed: _loadData,
                  icon: const Icon(Icons.refresh),
                ),
              if (isDesktop)
                IconButton(
                  tooltip: 'Logout',
                  onPressed: _logout,
                  icon: const Icon(Icons.logout),
                ),
              if (!isDesktop)
                PopupMenuButton<String>(
                  tooltip: 'Workspace actions',
                  onSelected: (action) {
                    if (action == 'theme') {
                      appThemeMode.value = appThemeMode.value == ThemeMode.dark
                          ? ThemeMode.light
                          : ThemeMode.dark;
                    } else if (action == 'refresh') {
                      _loadData();
                    } else {
                      _logout();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'theme', child: Text('Switch theme')),
                    PopupMenuItem(
                      value: 'refresh',
                      child: Text('Refresh data'),
                    ),
                    PopupMenuItem(value: 'logout', child: Text('Log out')),
                  ],
                ),
              const SizedBox(width: 8),
            ],
          ),
          bottomNavigationBar: constraints.maxWidth < 600
              ? SafeArea(
                  top: false,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      border: Border(top: BorderSide(color: colors.outlineVariant, width: .5)),
                    ),
                    child: Row(
                      children: [
                        for (final item in _menuItems.where((item) =>
                            const {'Overview', 'Attendance', 'Tasks', 'My Profile'}.contains(item.label)))
                          Expanded(child: _DockItem(
                            label: item.label,
                            icon: item.icon,
                            selected: item.label == _menuItems[_selectedIndex].label,
                            onTap: () => _navigateToModule(item.label),
                          )),
                      ],
                    ),
                  ),
                )
              : null,
          body: Row(
            children: [
              if (isDesktop)
                SizedBox(width: 245, child: _buildSidebar(isDrawer: false)),
              Expanded(
                child: TweenAnimationBuilder<double>(
                  key: ValueKey(_selectedIndex),
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  tween: Tween(begin: 0, end: 1),
                  builder: (context, progress, page) => Opacity(
                    opacity: progress,
                    child: Transform.translate(
                      offset: Offset(0, 8 * (1 - progress)),
                      child: page,
                    ),
                  ),
                  child: CompanyCalendar(entries: _holidays, available: _holidayLoadError == null, add: _canViewAllEmployees ? _manageHolidaysDialog : null, remove: _canViewAllEmployees ? _removeCalendarOverride : null, child: _buildPage(colors)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSidebar({required bool isDrawer}) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final name = _myProfile?['full_name']?.toString() ?? 'User';

    return Material(
      color: colors.surfaceContainerLow,
      shape: Border(right: BorderSide(color: colors.outlineVariant)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 16, 24),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppThemes.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Image.asset('assets/images/penguinpeak_logo.png'),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'PenguinPeak\nHRMS',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: _menuItems.length,
              itemBuilder: (context, index) {
                final item = _menuItems[index];
                final selected = _selectedIndex == index;
                final section = switch (item.label) {
                  'Overview' => 'HOME',
                  'Employees' => 'PEOPLE & ORGANIZATION',
                  'Leave' => 'TIME & ATTENDANCE',
                  'Tasks' => 'WORK MANAGEMENT',
                  'Chat' => 'COLLABORATION',
                  'Onboarding' => 'HR SERVICES',
                  'My Profile' => 'PERSONAL',
                  _ => null,
                };

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (section != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 18, 8, 6),
                        child: Text(
                          section,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                            letterSpacing: 1,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: ListTile(
                        selected: selected,
                        dense: true,
                        selectedTileColor: colors.secondaryContainer,
                        selectedColor: colors.onSecondaryContainer,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        leading: Icon(item.icon),
                        title: Text(item.label),
                        onTap: () =>
                            _selectPage(index, context, isDrawer: isDrawer),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const Divider(),
          ListTile(
            leading: Stack(
              alignment: Alignment.topLeft,
              children: [
                CircleAvatar(
                  backgroundColor: AppThemes.orange,
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'U',
                    style: const TextStyle(color: Colors.black),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color:
                        _myTodayAttendance?['check_in'] != null &&
                            _myTodayAttendance?['check_out'] == null
                        ? Colors.green
                        : Colors.grey,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _myTodayAttendance?['check_in'] != null &&
                            _myTodayAttendance?['check_out'] == null
                        ? 'IN'
                        : 'OUT',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(_roleLabel),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildPage(ColorScheme colors) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Could not load dashboard data',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SelectableText(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    final page = _menuItems[_selectedIndex].label;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final pagePadding = screenWidth < 600 ? 16.0 : 24.0;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        key: PageStorageKey('workspace-$page'),
        padding: EdgeInsets.all(pagePadding),
        children: [
          if (page != 'Overview') Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  page,
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -1),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(
                    Icons.badge_outlined,
                    size: 16,
                    color: colors.primary,
                  ),
                  label: Text(_roleLabel),
                ),
              ],
            ),
          ),
          WorkspaceReveal(
            key: ValueKey(page),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (page == 'Overview') _buildOverview(colors),
                if (page == 'Employees') _buildEmployees(),
                if (page == 'Organization') _buildOrganizationTree(),
                if (page == 'Leave') LeaveManagementScreen(role: widget.role),
                if (page == 'Attendance')
                  AttendanceManagementScreen(role: widget.role),
                if (page == 'Resource Availability')
                  TaskManagementScreen(role: widget.role, availabilityOnly: true),
                if (page == 'Tasks')
                  TaskManagementScreen(
                    key: ValueKey('task-notice-$_notificationOpenRevision'),
                    role: widget.role,
                    initialTaskId: _notificationRecordId,
                    onTargetConsumed: _consumeNotificationTarget,
                  ),
                if (page == 'Performance') const PerformanceWorkspace(),
                if (page == 'Chat')
                  ChatScreen(
                    key: ValueKey('chat-notice-$_notificationOpenRevision'),
                    role: widget.role,
                    initialConversationId: _notificationRecordId,
                    onTargetConsumed: _consumeNotificationTarget,
                  ),
                if (page == 'Company Wall')
                  CompanyWallScreen(
                    key: ValueKey('wall-notice-$_notificationOpenRevision'),
                    role: widget.role,
                    initialPostId: _notificationRecordId,
                    onTargetConsumed: _consumeNotificationTarget,
                  ),
                if (page == 'Team Calendar')
                  TeamLeaveCalendarScreen(role: widget.role),
                if (page == 'Attendance Adjustments')
                  AttendanceAdjustmentScreen(
                    key: ValueKey(
                      'attendance-notice-$_notificationOpenRevision',
                    ),
                    role: widget.role,
                    initialRequestId: _notificationRecordId,
                    onTargetConsumed: _consumeNotificationTarget,
                  ),
                for (final module in HrModule.all)
                  if (page == module.label)
                    HrWorkspace(
                      key: ValueKey('${module.id}:$_notificationOpenRevision'),
                      initialRecordId: _notificationRecordId,
                      onTargetConsumed: _consumeNotificationTarget,
                      module: module,
                      role: widget.role,
                    ),
                if (page == 'My Profile') _buildProfile(),
                if (page == 'Settings') _buildSettings(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- KEKA-INSPIRED REDESIGNED HOME DASHBOARD OVERVIEW ---

  Widget _buildOverview(ColorScheme colors) {
    final name = _myProfile?['full_name']?.toString() ?? 'Employee';
    final isDesktop = MediaQuery.sizeOf(context).width >= 1200;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Welcome Banner
        _buildWelcomeBanner(name),

        const SizedBox(height: 20),

        // Vibrant KPI Grid (SmartHR Style)
        _buildVibrantKpiGrid(),

        const SizedBox(height: 24),

        // Two-Column Layout (Desktop Side-by-Side, Mobile Stacked)
        if (isDesktop)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // LEFT COLUMN (Quick Access & Operations)
              Expanded(
                flex: 58,
                child: Column(
                  children: [
                    if (_canViewAllEmployees) _buildPendingApprovalsCard(),
                    if (_canViewAllEmployees) const SizedBox(height: 16),
                    _buildQuickAccessCard(),
                    const SizedBox(height: 16),
                    _buildAttendanceWidget(),
                    const SizedBox(height: 16),
                    _buildLeaveBalancesWidget(),
                    const SizedBox(height: 16),
                    _buildOnLeaveTodayWidget(),
                    const SizedBox(height: 16),
                    _buildHolidaysWidget(),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // RIGHT COLUMN (Org Context & Engagement)
              Expanded(
                flex: 42,
                child: Column(
                  children: [
                    _buildOrgContextCard(),
                    const SizedBox(height: 16),
                    _buildCompanyWallComposerCard(),
                    const SizedBox(height: 16),
                    _buildAnnouncementsWidget(),
                    const SizedBox(height: 16),
                    _buildCelebrationsWidget(),
                  ],
                ),
              ),
            ],
          )
        else
          Column(
            children: [
              if (_canViewAllEmployees) _buildPendingApprovalsCard(),
              if (_canViewAllEmployees) const SizedBox(height: 16),
              _buildAttendanceWidget(),
              const SizedBox(height: 16),
              _buildQuickAccessCard(),
              const SizedBox(height: 16),
              _buildOrgContextCard(),
              const SizedBox(height: 16),
              _buildLeaveBalancesWidget(),
              const SizedBox(height: 16),
              _buildCompanyWallComposerCard(),
              const SizedBox(height: 16),
              _buildOnLeaveTodayWidget(),
              const SizedBox(height: 16),
              _buildAnnouncementsWidget(),
              const SizedBox(height: 16),
              _buildHolidaysWidget(),
              const SizedBox(height: 16),
              _buildCelebrationsWidget(),
            ],
          ),
      ],
    );
  }

  Widget _buildWelcomeBanner(String name) {
    final material = MaterialLocalizations.of(context);
    final greeting = _now.hour < 12 ? 'Good morning' : _now.hour < 18 ? 'Good afternoon' : 'Good evening';
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: AlpineLandscape(
        child: LayoutBuilder(builder: (context, bounds) {
          final wide = bounds.maxWidth >= 620;
          return Padding(
            padding: EdgeInsets.fromLTRB(wide ? 36 : 20, wide ? 32 : 22,
                wide ? bounds.maxWidth * .32 : 20, wide ? 36 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(material.formatFullDate(_now),
                    style: const TextStyle(color: Color(0xffc9e7ea), fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 18),
                Text('$greeting, $name',
                    style: TextStyle(color: Colors.white, fontSize: wide ? 38 : 28,
                        height: 1.1, fontWeight: FontWeight.w700, letterSpacing: -1.2)),
                const SizedBox(height: 10),
                Text([_myProfile?['designation'] ?? _roleLabel, _myProfile?['department']]
                    .whereType<String>().where((part) => part.isNotEmpty).join('  ·  '),
                    style: const TextStyle(color: Color(0xffdeedf2), fontSize: 14)),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildVibrantKpiGrid() {
    final totalEmployees = _profiles.length;
    final approvedCount = _profiles
        .where((p) => p['approval_status'] == 'approved')
        .length;
    final pendingCount = _profiles
        .where((p) => p['approval_status'] == 'pending')
        .length;

    return LayoutBuilder(
      builder: (context, constraints) {
        return AdaptiveCards(
          minWidth: 135 * MediaQuery.textScalerOf(context).scale(1).clamp(1, 2),
          maxColumns: 4,
          children: [
            _kpiTile(
              'Total Employees',
              '$totalEmployees',
              Icons.groups,
              const Color(0xFF6366F1),
            ),
            _kpiTile(
              'Approved Roster',
              '$approvedCount',
              Icons.verified,
              const Color(0xFF10B981),
            ),
            _kpiTile(
              'Pending Approvals',
              '$pendingCount',
              Icons.pending_actions,
              const Color(0xFFF59E0B),
            ),
            _kpiTile(
              'On Leave Today',
              '${_onLeaveToday.length}',
              Icons.event_available,
              const Color(0xFFEC4899),
            ),
          ],
        );
      },
    );
  }

  Widget _kpiTile(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Color.lerp(color, Theme.of(context).colorScheme.onSurface, .22), size: 22),
          const SizedBox(height: 16),
          Text(
            value,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAccessCard() {
    final items = [
      {'label': 'Apply Leave', 'icon': Icons.event_note, 'module': 'Leave'},
      {
        'label': 'Clock In / Out',
        'icon': Icons.access_time,
        'module': 'Attendance',
      },
      {
        'label': 'Leave Balances',
        'icon': Icons.account_balance_wallet,
        'module': 'Leave',
      },
      {'label': 'My Tasks', 'icon': Icons.task_alt, 'module': 'Tasks'},
      {
        'label': 'Secure Chat',
        'icon': Icons.chat_bubble_outline,
        'module': 'Chat',
      },
      {
        'label': 'Company Wall',
        'icon': Icons.feed_outlined,
        'module': 'Company Wall',
      },
      {
        'label': 'Team Calendar',
        'icon': Icons.calendar_month,
        'module': 'Team Calendar',
      },
      {
        'label': 'My Profile',
        'icon': Icons.person_outline,
        'module': 'My Profile',
      },
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Quick access',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            AdaptiveCards(
              minWidth: 132 * MediaQuery.textScalerOf(context).scale(1).clamp(1, 2),
              maxColumns: 4,
              children: [
                for (final item in items)
                  Material(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _navigateToModule(item['module'] as String),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                        child: Row(children: [
                          Icon(item['icon'] as IconData, size: 19, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Expanded(child: Text(item['label'] as String,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                        ]),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceWidget() {
    final todayRec = _myTodayAttendance;

    final isCheckedIn = todayRec != null && todayRec['check_in'] != null;
    final isCheckedOut = todayRec != null && todayRec['check_out'] != null;

    String inTime = 'Not Checked In';
    if (isCheckedIn) {
      final dt = DateTime.tryParse(todayRec['check_in'].toString())?.toLocal();
      if (dt != null) {
        inTime = attendanceClockLabel(dt);
      }
    }

    final lateMins = ((todayRec?['late_minutes'] as num?)?.toInt() ?? 0);
    final lateStr = !isCheckedIn
        ? ''
        : lateMins > 0
        ? ' • ⚠️ Late by ${lateMins ~/ 60}h ${lateMins % 60}m'
        : ' • 🟢 On Time';

    final totalMinutesWorked = attendanceWorkMinutes(todayRec, _now);

    final workProgress = (totalMinutesWorked / 480.0).clamp(0.0, 1.0);
    final workHoursFormatted =
        '${totalMinutesWorked ~/ 60}h ${totalMinutesWorked % 60}m';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdaptiveRow(
              children: [
                const Text(
                  'Today\'s Attendance & Time Tracker',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isCheckedOut
                        ? Colors.grey.withOpacity(0.2)
                        : isCheckedIn
                        ? Colors.green.withOpacity(0.2)
                        : Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isCheckedOut
                        ? '⚪ Checked Out'
                        : isCheckedIn
                        ? '🟢 Checked In'
                        : '🟡 Not Checked In',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isCheckedOut
                          ? Colors.grey
                          : isCheckedIn
                          ? Colors.green
                          : Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'In-Time / Late Status',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$inTime$lateStr',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Logged Work / Target (8h)',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$workHoursFormatted / 8h 00m',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppThemes.orange,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    const Text(
                      'Daily Shift Progress',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    Text(
                      '${(workProgress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppThemes.orange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: workProgress,
                    backgroundColor: AppThemes.orange.withOpacity(0.2),
                    color: AppThemes.orange,
                    minHeight: 10,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            AdaptiveRow(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: isCheckedOut
                          ? Colors.green
                          : isCheckedIn
                          ? Colors.orange.shade800
                          : Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _clockBusy ? null : _handleClockInOut,
                    icon: Icon(
                      isCheckedIn ? Icons.logout : Icons.login,
                      size: 18,
                    ),
                    label: Text(
                      isCheckedOut
                          ? 'Check In Again'
                          : isCheckedIn
                          ? 'Check Out Now'
                          : 'Check In Now',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _navigateToModule('Attendance'),
                  icon: const Icon(Icons.access_time_outlined, size: 16),
                  label: const Text('Manage'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaveBalancesWidget() => LeaveBalanceSummary(
    balances: _myLeaveBalances,
    onOpenLeave: () => _navigateToModule('Leave'),
  );

  Widget _buildOnLeaveTodayWidget() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdaptiveRow(
              children: [
                const Text(
                  'On Leave Today',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text('${_onLeaveToday.length}'),
                  backgroundColor: AppThemes.orange.withOpacity(0.2),
                  visualDensity: VisualDensity.compact,
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => _navigateToModule('Team Calendar'),
                  child: const Text('View Calendar'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_onLeaveToday.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '🎉 Nobody is on leave today! Full team strength.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _onLeaveToday.length,
                itemBuilder: (context, idx) {
                  final l = _onLeaveToday[idx];
                  final prof = l['profiles'] as Map<String, dynamic>?;
                  final name = prof?['full_name']?.toString() ?? 'Employee';
                  final dept = prof?['department']?.toString() ?? 'General';

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'U',
                      ),
                    ),
                    title: Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Text(
                      '$dept • Approved Leave',
                      style: const TextStyle(fontSize: 11),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingApprovalsCard() {
    final pendingList = _profiles
        .where((p) => p['approval_status'] == 'pending')
        .toList();
    if (pendingList.isEmpty) return const SizedBox.shrink();

    return Card(
      color: Colors.orange.withOpacity(0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.orange, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdaptiveRow(
              children: [
                const Icon(Icons.pending_actions, color: Colors.orange),
                const SizedBox(width: 8),
                const Text(
                  '🚨 Pending HR Account Approvals',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
                const Spacer(),
                Chip(
                  label: Text('${pendingList.length} Pending'),
                  backgroundColor: Colors.orange,
                  labelStyle: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...pendingList.map(
              (p) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: AdaptiveRow(
                  children: [
                    CircleAvatar(
                      child: Text((p['full_name'] ?? 'U')[0].toUpperCase()),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p['full_name'] ?? 'New Employee',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            'Role: ${p['role'] ?? 'employee'} • Department: ${p['department'] ?? 'General'}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () =>
                          _reviewEmployee(p['id'].toString(), 'approved'),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Approve'),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () =>
                          _reviewEmployee(p['id'].toString(), 'rejected'),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Reject'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _removeCalendarOverride(Map<String,dynamic> entry) async {
    if (!_canViewAllEmployees || entry['id'] == null) return false;
    final confirmed = await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(
      title: const Text('Remove calendar override?'),
      content: Text("${entry['name']} · ${entry['holiday_date']}"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Remove')),
      ],
    ));
    if (confirmed != true || !mounted) return false;
    try {
      await _supabase.from('holidays').delete().eq('id', entry['id']).select('id').single();
      if (mounted) setState(() => _holidays = _holidays.where((r) => r['id'] != entry['id']).toList());
      return true;
    } catch (error) {
      if (mounted) AppToast.of(context).showSnackBar(SnackBar(content: Text('Could not remove calendar override: $error')));
      return false;
    }
  }

  Future<void> _manageHolidaysDialog([DateTime? day]) async {
    if (!_canViewAllEmployees) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (_) => CalendarEventSheet(
        date: day ?? DateUtils.dateOnly(DateTime.now()),
        entries: _holidays,
        onRemove: _removeCalendarOverride,
        onSave: (date, name, type) async {
          final inserted = await _supabase.from('holidays').insert({
            'name': name,
            'holiday_date': date.toIso8601String().split('T').first,
            'type': type,
          }).select().single();
          if (!mounted) return;
          setState(() {
            _holidays = [..._holidays.where((row) => row['id'] != inserted['id']), inserted]
              ..sort((a, b) => a['holiday_date'].toString().compareTo(b['holiday_date'].toString()));
          });
        },
      ),
    );
  }

  Widget _buildHolidaysWidget() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdaptiveRow(
              children: [
                const Text(
                  'Upcoming company calendar',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_canViewAllEmployees)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppThemes.orange,
                      side: const BorderSide(color: AppThemes.orange),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _manageHolidaysDialog,
                    icon: const Icon(Icons.edit_calendar, size: 14),
                    label: const Text(
                      'Manage calendar',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            HolidayList(
              holidays: _holidays.where((row) => row['holiday_date'].toString().compareTo(DateTime.now().toIso8601String().split('T').first) >= 0).take(20).toList(),
              error: _holidayLoadError,
              onRetry: _loadData,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrgContextCard() {
    final dept = _myProfile?['department']?.toString() ?? 'Engineering';
    final desig = _myProfile?['designation']?.toString() ?? 'Team Member';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Icon(Icons.business, color: AppThemes.orange),
                const SizedBox(width: 8),
                const Text(
                  'PenguinPeak Technologies',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Chip(
                  label: Text('Approved 🟢'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const Divider(height: 24),
            _infoRow('Department', dept),
            _infoRow('Designation', desig),
            _infoRow(
              'Reporting Manager',
              _managerName(_myProfile?['manager_id']?.toString()),
            ),
            _infoRow('Role Privileges', _roleLabel),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: LayoutBuilder(
        builder: (context, box) {
          final label = Text(
            k,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          );
          final value = Text(
            v,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          );
          if (box.maxWidth < 420) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [label, const SizedBox(height: 2), value],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: label),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  v,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCompanyWallComposerCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Share Update on Company Wall',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'post',
                    label: Text('Post'),
                    icon: Icon(Icons.edit_note, size: 16),
                  ),
                  ButtonSegment(
                    value: 'announcement',
                    label: Text('Announcement'),
                    icon: Icon(Icons.campaign, size: 16),
                  ),
                  ButtonSegment(
                    value: 'praise',
                    label: Text('Praise'),
                    icon: Icon(Icons.thumb_up, size: 16),
                  ),
                ],
                selected: {_composerCategory},
                onSelectionChanged: (set) =>
                    setState(() => _composerCategory = set.first),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _wallPostController,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText:
                    'Share a company update, shoutout, or announcement...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppThemes.orange,
                  foregroundColor: Colors.black,
                ),
                onPressed: _publishingPost ? null : _submitWallPost,
                icon: const Icon(Icons.send, size: 16),
                label: const Text('Publish Post'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnnouncementsWidget() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdaptiveRow(
              children: [
                const Text(
                  'Recent Announcements',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => _navigateToModule('Company Wall'),
                  child: const Text('View All →'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_announcements.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No company announcements published yet.'),
              )
            else
              ..._announcements.map(
                (a) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (a['is_pinned'] == true) ...[
                            const Icon(
                              Icons.push_pin,
                              size: 14,
                              color: AppThemes.orange,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              a['title'] ?? 'Company Update',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Text(
                            a['created_at']?.toString().split('T')[0] ?? '',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        a['content'] ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCelebrationsWidget() {
    final recentJoiners = _profiles.take(3).toList();

    return DefaultTabController(
      length: 3,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const TabBar(
                tabs: [
                  Tab(text: '🎂 Birthdays'),
                  Tab(text: '🏅 Anniversaries'),
                  Tab(text: '🌱 New Joiners'),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 180,
                child: TabBarView(
                  children: [
                    // Birthdays Tab
                    ListView.builder(
                      itemCount: _profiles.take(3).length,
                      itemBuilder: (context, idx) {
                        final p = _profiles[idx];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            child: Text(
                              (p['full_name'] ?? 'U')[0].toUpperCase(),
                            ),
                          ),
                          title: Text(
                            p['full_name'] ?? 'Employee',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: const Text(
                            'Birthday coming up this month! 🎂',
                            style: TextStyle(fontSize: 11),
                          ),
                        );
                      },
                    ),
                    // Anniversaries Tab
                    ListView.builder(
                      itemCount: _profiles.take(2).length,
                      itemBuilder: (context, idx) {
                        final p = _profiles[idx];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            child: Text(
                              (p['full_name'] ?? 'U')[0].toUpperCase(),
                            ),
                          ),
                          title: Text(
                            p['full_name'] ?? 'Employee',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: const Text(
                            'Celebrating Work Anniversary 🏅',
                            style: TextStyle(fontSize: 11),
                          ),
                        );
                      },
                    ),
                    // New Joiners Tab
                    ListView.builder(
                      itemCount: recentJoiners.length,
                      itemBuilder: (context, idx) {
                        final p = recentJoiners[idx];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            child: Text(
                              (p['full_name'] ?? 'U')[0].toUpperCase(),
                            ),
                          ),
                          title: Text(
                            p['full_name'] ?? 'Employee',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            'Joined: ${p['created_at']?.toString().split('T')[0] ?? 'Recently'}',
                            style: TextStyle(fontSize: 11),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- EXISTING EMPLOYEES & ORG TREE IMPLEMENTATION ---

  Future<bool> _saveEmployeeDetails({
    required String userId,
    required String fullName,
    required String department,
    required String designation,
    required String phone,
    required String? joiningDate,
    required String? managerId,
    required Map<String, dynamic> profileDetails,
  }) async {
    try {
      final updateData = <String, dynamic>{
        'full_name': fullName.trim(),
        'department': department.trim().isEmpty ? null : department.trim(),
        'designation': designation.trim().isEmpty ? null : designation.trim(),
        'phone': phone.trim().isEmpty ? null : phone.trim(),
        'joining_date': joiningDate,
        'manager_id': managerId,
        'profile_details': profileDetails,
      };

      await _supabase.from('profiles').update(updateData).eq('id', userId);

      if (!mounted) return false;

      AppToast.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Employee details updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      await _loadData();
      return true;
    } catch (e) {
      if (!mounted) return false;

      AppToast.of(context).showSnackBar(
        SnackBar(content: Text('Could not save employee details: $e')),
      );
      return false;
    }
  }

  Future<void> _editEmployee(Map<String, dynamic> profile) async {
    final rawName = profile['full_name']?.toString().trim() ?? '';
    final employeeName = rawName.isEmpty ? 'employee' : rawName;
    final fullNameController = TextEditingController(text: rawName);
    final departmentController = TextEditingController(
      text: profile['department']?.toString() ?? '',
    );
    final designationController = TextEditingController(
      text: profile['designation']?.toString() ?? '',
    );
    final phoneController = TextEditingController(
      text: profile['phone']?.toString() ?? '',
    );
    final details = Map<String, dynamic>.from(
      profile['profile_details'] as Map? ?? {},
    );
    final detailControllers = {
      for (final key in _profileDetailFields.keys)
        key: TextEditingController(text: details[key]?.toString() ?? ''),
    };
    String? managerId = profile['manager_id']?.toString();
    DateTime? joiningDate;
    final rawDate = profile['joining_date']?.toString();
    if (rawDate != null && rawDate.isNotEmpty) {
      joiningDate = DateTime.tryParse(rawDate);
    }
    String dateLabel() => joiningDate == null
        ? 'Not set'
        : '${joiningDate!.year.toString().padLeft(4, '0')}-'
              '${joiningDate!.month.toString().padLeft(2, '0')}-'
              '${joiningDate!.day.toString().padLeft(2, '0')}';

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text('Edit $employeeName'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: fullNameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: Icon(Icons.person_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: departmentController,
                      enabled: _canViewAllEmployees,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Department',
                        hintText: 'e.g. IT, Human Resources',
                        prefixIcon: Icon(Icons.business_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: designationController,
                      enabled: _canViewAllEmployees,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Designation',
                        hintText: 'e.g. Flutter Developer',
                        prefixIcon: Icon(Icons.work_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone number',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final entry in _profileDetailFields.entries) ...[
                      TextField(
                        controller: detailControllers[entry.key],
                        enabled:
                            _canViewAllEmployees ||
                            !const {
                              'work_shift',
                              'employment_type',
                              'probation_period',
                            }.contains(entry.key),
                        decoration: InputDecoration(labelText: entry.value),
                      ),
                      const SizedBox(height: 12),
                    ],
                    DropdownButtonFormField<String?>(
                      value:
                          _profiles.any((p) => p['id']?.toString() == managerId)
                          ? managerId
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Manager / Reports to',
                        prefixIcon: Icon(Icons.supervisor_account_outlined),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('None (No manager assigned)'),
                        ),
                        ..._profiles
                            .where(
                              (p) =>
                                  p['id']?.toString() !=
                                      profile['id']?.toString() &&
                                  p['approval_status'] == 'approved',
                            )
                            .map((p) {
                              final id = p['id'].toString();
                              final name = (p['full_name'] ?? 'Unnamed user')
                                  .toString();
                              final dept = (p['department'] ?? '').toString();
                              final desig = (p['designation'] ?? '').toString();
                              final sub = [
                                if (desig.isNotEmpty) desig,
                                if (dept.isNotEmpty) dept,
                              ].join(' • ');

                              return DropdownMenuItem<String?>(
                                value: id,
                                child: Text(
                                  sub.isEmpty ? name : '$name ($sub)',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }),
                      ],
                      onChanged: _canViewAllEmployees
                          ? (val) => setDialogState(() => managerId = val)
                          : null,
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_today_outlined),
                      title: const Text('Joining date'),
                      subtitle: Text(dateLabel()),
                      trailing: TextButton(
                        onPressed: !_canViewAllEmployees
                            ? null
                            : () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: joiningDate ?? DateTime.now(),
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2100),
                                );
                                if (picked != null) {
                                  setDialogState(() => joiningDate = picked);
                                }
                              },
                        child: const Text('Select'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final formattedDate = joiningDate == null
                      ? null
                      : '${joiningDate!.year.toString().padLeft(4, '0')}-'
                            '${joiningDate!.month.toString().padLeft(2, '0')}-'
                            '${joiningDate!.day.toString().padLeft(2, '0')}';

                  final ok = await _saveEmployeeDetails(
                    userId: profile['id'].toString(),
                    fullName: fullNameController.text,
                    department: departmentController.text,
                    designation: designationController.text,
                    phone: phoneController.text,
                    joiningDate: formattedDate,
                    managerId: managerId,
                    profileDetails: {
                      ...details,
                      for (final entry in detailControllers.entries)
                        entry.key: entry.value.text.trim(),
                    },
                  );

                  if (ok && mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                },
                child: const Text('Save details'),
              ),
            ],
          ),
        ),
      );
    } finally {
      for (final controller in detailControllers.values) {
        controller.dispose();
      }
      fullNameController.dispose();
      departmentController.dispose();
      designationController.dispose();
      phoneController.dispose();
    }
  }

  Widget _buildEmployees() {
    final filteredProfiles = _profiles.where((profile) {
      final name = (profile['full_name'] ?? '').toString();
      final department = (profile['department'] ?? '').toString();
      final designation = (profile['designation'] ?? '').toString();
      final role = (profile['role'] ?? 'employee').toString();
      final status = (profile['approval_status'] ?? 'unknown').toString();

      final matchesQuery =
          _searchQuery.isEmpty ||
          name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          department.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          designation.toLowerCase().contains(_searchQuery.toLowerCase());

      final matchesRole = _roleFilter == 'all' || role == _roleFilter;
      final matchesStatus = _statusFilter == 'all' || status == _statusFilter;

      return matchesQuery && matchesRole && matchesStatus;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Employees',
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  '${filteredProfiles.length} profiles found',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (widget.role == 'hr')
              TextButton.icon(
                onPressed: _showPreviouslyRemovedUsers,
                icon: const Icon(Icons.person_off_outlined),
                label: const Text('Previously removed'),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: (MediaQuery.sizeOf(context).width - 96)
                      .clamp(0, 260)
                      .toDouble(),
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search employees...',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                ),
                DropdownButton<String>(
                  value: _roleFilter,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Roles')),
                    DropdownMenuItem(
                      value: 'super_admin',
                      child: Text('Super Admin'),
                    ),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    DropdownMenuItem(
                      value: 'management',
                      child: Text('Management'),
                    ),
                    DropdownMenuItem(value: 'hr', child: Text('HR')),
                    DropdownMenuItem(
                      value: 'employee',
                      child: Text('Employee'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _roleFilter = val);
                  },
                ),
                DropdownButton<String>(
                  value: _statusFilter,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Statuses')),
                    DropdownMenuItem(
                      value: 'approved',
                      child: Text('Approved'),
                    ),
                    DropdownMenuItem(value: 'pending', child: Text('Pending')),
                    DropdownMenuItem(
                      value: 'rejected',
                      child: Text('Rejected'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _statusFilter = val);
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (filteredProfiles.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('No employees match the filters.')),
          )
        else
          AdaptiveCards(
            minWidth: 300,
            maxColumns: 4,
            children: filteredProfiles.map((profile) {
              final name = (profile['full_name'] ?? '').toString().trim();
              final displayName = name.isEmpty ? 'Unnamed user' : name;
              final role = (profile['role'] ?? 'employee').toString();
              final status = (profile['approval_status'] ?? 'unknown')
                  .toString();
              final department = (profile['department'] ?? 'Not assigned')
                  .toString();
              final designation = (profile['designation'] ?? 'Not assigned')
                  .toString();
              final phone = (profile['phone'] ?? 'Not set').toString();

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            child: Text(
                              displayName.isEmpty
                                  ? '?'
                                  : displayName[0].toUpperCase(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  designation,
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      Text(
                        'Department: $department',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Phone: $phone',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Role: $role • Status: $status',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_canViewAllEmployees && status == 'pending') ...[
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: () => _reviewEmployee(
                                  profile['id'].toString(),
                                  'approved',
                                ),
                                icon: const Icon(Icons.check, size: 16),
                                label: const Text('Approve'),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: () => _reviewEmployee(
                                  profile['id'].toString(),
                                  'rejected',
                                ),
                                icon: const Icon(Icons.close, size: 16),
                                label: const Text('Reject'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _showEmployeeProfile(profile),
                              child: const Text('View profile'),
                            ),
                          ),
                          if (_canViewAllEmployees) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _editEmployee(profile),
                              tooltip: 'Edit details',
                            ),
                          ],
                          if (widget.role == 'hr' &&
                              profile['id']?.toString() !=
                                  _supabase.auth.currentUser?.id)
                            IconButton(
                              tooltip: 'Delete user permanently',
                              onPressed:
                                  _removingUsers.contains(
                                    profile['id'].toString(),
                                  )
                                  ? null
                                  : () => _removeUser(profile),
                              icon: Icon(
                                Icons.person_remove_outlined,
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildOrganizationTree() => OrganizationChart(
    profiles: _profiles,
    onOpenProfile: _showEmployeeProfile,
  );

  String _managerName(String? managerId) {
    if (managerId == null || managerId.isEmpty) return 'None';
    for (final p in _profiles) {
      if (p['id']?.toString() == managerId) {
        return (p['full_name'] ?? 'Unnamed manager').toString();
      }
    }
    return 'Assigned Manager';
  }

  Future<void> _showEmployeeProfile(Map<String, dynamic> profile) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: SizedBox(
          width: 960,
          height: 700,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                title: Text(
                  '${profile['full_name'] ?? 'Employee'} Details',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                elevation: 0,
                backgroundColor: Colors.transparent,
              ),
              body: KekaEmployeeDetailWidget(
                profile: profile,
                isCheckedIn: (profile['id'] == _myProfile?['id'])
                    ? (_myTodayAttendance?['check_in'] != null &&
                          _myTodayAttendance?['check_out'] == null)
                    : null,
                managerName: _managerName(profile['manager_id']?.toString()),
                onEdit: () => _editEmployee(profile),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfile() {
    final profile = _myProfile!;
    return KekaEmployeeDetailWidget(
      profile: profile,
      isCheckedIn:
          _myTodayAttendance?['check_in'] != null &&
          _myTodayAttendance?['check_out'] == null,
      managerName: _managerName(profile['manager_id']?.toString()),
      onEdit: () => _editEmployee(profile),
    );
  }

  Future<void> _editCompanyPolicyDialog() async {
    Map<String, dynamic>? policy;
    try {
      policy = await _supabase.from('company_attendance_settings').select().maybeSingle();
    } catch (error) {
      if (mounted) AppToast.of(context).showSnackBar(SnackBar(content: Text('Could not load attendance policy: $error')));
      return;
    }
    if (!mounted) return;
    var startValue = (policy?['work_start_time'] ?? '09:00:00').toString();
    var endValue = (policy?['work_end_time'] ?? '17:00:00').toString();
    var graceValue = (policy?['grace_period_minutes'] ?? 15).toString();
    var halfDayValue = (policy?['half_day_hours'] ?? 4.0).toString();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Manage Attendance Policy & Working Hours'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: startValue,
                onChanged: (value) => startValue = value,
                decoration: const InputDecoration(
                  labelText: 'Work Start Time (HH:MM:SS)',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: endValue,
                onChanged: (value) => endValue = value,
                decoration: const InputDecoration(
                  labelText: 'Work End Time (HH:MM:SS)',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: graceValue,
                onChanged: (value) => graceValue = value,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Grace Period (Minutes)',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: halfDayValue,
                onChanged: (value) => halfDayValue = value,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Half Day Threshold Hours',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                final policyData = {
                  'work_start_time': startValue.trim(),
                  'work_end_time': endValue.trim(),
                  'grace_period_minutes':
                      int.tryParse(graceValue.trim()) ?? 15,
                  'half_day_hours':
                      double.tryParse(halfDayValue.trim()) ?? 4.0,
                  'updated_at': DateTime.now().toUtc().toIso8601String(),
                };

                final existing = await _supabase
                    .from('company_attendance_settings')
                    .select('id')
                    .maybeSingle();
                if (existing != null) {
                  await _supabase
                      .from('company_attendance_settings')
                      .update(policyData)
                      .eq('id', existing['id']);
                } else {
                  await _supabase
                      .from('company_attendance_settings')
                      .insert(policyData);
                }

                if (!context.mounted) return;
                Navigator.pop(context);
                AppToast.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ Attendance policy updated successfully!'),
                    backgroundColor: Colors.green,
                  ),
                );

              } catch (e) {
                if (!context.mounted) return;
                AppToast.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to update policy: $e')),
                );
              }
            },
            child: const Text('Save Policy'),
          ),
        ],
      ),
    );
  }

  Widget _buildSettings() {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeMode,
      builder: (context, mode, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Appearance',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Card(
              child: SwitchListTile(
                secondary: Icon(
                  mode == ThemeMode.dark
                      ? Icons.dark_mode_outlined
                      : Icons.light_mode_outlined,
                ),
                title: const Text('Dark mode'),
                subtitle: const Text('Change the appearance of the app'),
                value: mode == ThemeMode.dark,
                onChanged: (enabled) {
                  appThemeMode.value = enabled
                      ? ThemeMode.dark
                      : ThemeMode.light;
                },
              ),
            ),
            if (['hr', 'admin', 'super_admin'].contains(widget.role)) ...[
              const SizedBox(height: 24),
              Text('Company policies', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Card(child: ListTile(
                leading: const Icon(Icons.calendar_month),
                title: const Text('Company working calendar'),
                subtitle: const Text('Manage holidays and working-day overrides'),
                onTap: _manageHolidaysDialog,
              )),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.schedule_outlined),
                  title: const Text('Attendance policy'),
                  subtitle: const Text('Working hours, grace period and half-day threshold'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _editCompanyPolicyDialog,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _DashboardItem {
  final String label;
  final IconData icon;

  const _DashboardItem(this.label, this.icon);
}

class KekaEmployeeDetailWidget extends StatefulWidget {
  final Map<String, dynamic> profile;
  final String managerName;
  final VoidCallback? onEdit;
  // Null means attendance is unavailable; do not imply that the employee is in.
  final bool? isCheckedIn;

  const KekaEmployeeDetailWidget({
    super.key,
    required this.profile,
    required this.managerName,
    this.onEdit,
    this.isCheckedIn,
  });

  @override
  State<KekaEmployeeDetailWidget> createState() =>
      _KekaEmployeeDetailWidgetState();
}

class _KekaEmployeeDetailWidgetState extends State<KekaEmployeeDetailWidget>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final name = profile['full_name']?.toString() ?? 'Employee';
    final designation = profile['designation']?.toString() ?? 'Not provided';
    final department = profile['department']?.toString() ?? 'Not provided';
    final phone = profile['phone']?.toString() ?? 'Not provided';
    final joiningDate = profile['joining_date']?.toString() ?? 'Not provided';
    final id = profile['id']?.toString() ?? '';
    final empId = id.length > 4 ? id.substring(0, 4) : id;

    final leftSummaryCard = Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Stack(
              alignment: Alignment.topLeft,
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Theme.of(context).colorScheme.primary
                      .withOpacity(0.2),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'U',
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (widget.isCheckedIn != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: widget.isCheckedIn! ? Colors.green : Colors.grey,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      widget.isCheckedIn! ? 'IN' : 'OUT',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              designation,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'ID: $empId',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (widget.onEdit != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFF59E0B),
                    side: const BorderSide(color: Color(0xFFF59E0B)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: widget.onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text(
                    'Edit Details',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
            ],
            const Divider(height: 28),
            Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Reporting to',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        child: Text(
                          widget.managerName.isNotEmpty
                              ? widget.managerName[0]
                              : 'M',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.managerName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const Text(
                              'Lead Engineer / Manager',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 28),
                  const Text(
                    'Personal details',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _iconLabel(Icons.phone_outlined, phone),
                  _iconLabel(Icons.email_outlined, _detail('contact_email')),
                  _iconLabel(Icons.location_on_outlined, _detail('location')),
                  const Divider(height: 28),
                  const Text(
                    'Job details',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _keyVal('Job title', designation),
                  _keyVal('Department', department),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final rightTabbedCard = Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabs: const [
                Tab(text: 'About'),
                Tab(text: 'Profile'),
                Tab(text: 'Job'),
                Tab(text: 'Documents'),
                Tab(text: 'Assets'),
                Tab(text: 'Performance'),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 480,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildAboutTab(),
                  _buildPersonalProfileTab(name, phone, joiningDate),
                  _buildJobTab(designation, department, joiningDate),
                  _buildDocumentsTab(name),
                  _buildAssetsTab(),
                  _buildPerformanceTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth >= 850) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 310, child: leftSummaryCard),
              const SizedBox(width: 16),
              Expanded(child: rightTabbedCard),
            ],
          );
        } else {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              leftSummaryCard,
              const SizedBox(height: 16),
              rightTabbedCard,
            ],
          );
        }
      },
    );
  }

  Widget _iconLabel(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _keyVal(String key, String val) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(key, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          Text(
            val,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  String _detail(String key) {
    final details = widget.profile['profile_details'];
    final value = details is Map ? details[key]?.toString().trim() ?? '' : '';
    return value.isEmpty ? 'Not provided' : value;
  }

  Widget _buildAboutTab() {
    final skills = _detail('skills')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Work Summary & Bio',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(_detail('bio')),
          const Divider(height: 24),
          const Text('Primary Skills'),
          Wrap(
            spacing: 8,
            children: skills.map((s) => Chip(label: Text(s))).toList(),
          ),
          const Divider(height: 24),
          _keyVal('Work Shift', _detail('work_shift')),
          _keyVal('Emergency Contact', _detail('emergency_contact')),
        ],
      ),
    );
  }

  Widget _buildPersonalProfileTab(
    String name,
    String phone,
    String joiningDate,
  ) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _keyVal('Full Name', name),
        _keyVal('Phone', phone),
        for (final key in [
          'date_of_birth',
          'gender',
          'marital_status',
          'blood_group',
          'address',
        ])
          _keyVal(_profileDetailFields[key]!, _detail(key)),
      ],
    ),
  );

  Widget _buildJobTab(
    String designation,
    String department,
    String joiningDate,
  ) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _keyVal('Job Title', designation),
        _keyVal('Department', department),
        _keyVal('Employment Type', _detail('employment_type')),
        _keyVal('Probation Period', _detail('probation_period')),
        _keyVal('Date of Joining', joiningDate),
        _keyVal('Reporting Manager', widget.managerName),
      ],
    ),
  );

  Widget _buildDocumentsTab(String name) =>
      const Center(child: Text('No documents uploaded.'));
  Widget _buildAssetsTab() => const Center(child: Text('No assets assigned.'));
  Widget _buildPerformanceTab() => SingleChildScrollView(
    child: PerformanceWorkspace(employeeId: widget.profile['id']?.toString()),
  );
}

class _DockItem extends StatelessWidget {
  const _DockItem({required this.label, required this.icon, required this.selected, required this.onTap});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 3),
              decoration: BoxDecoration(color: selected ? colors.secondaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, size: 20, color: selected ? colors.onSecondaryContainer : colors.onSurfaceVariant),
            ),
            const SizedBox(height: 2),
            Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? colors.primary : colors.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}
