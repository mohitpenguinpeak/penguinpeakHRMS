import 'features/notifications/domain/notification_destination.dart';
import 'features/hr/domain/hr_module.dart';
import 'features/hr/presentation/hr_workspace.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/leave/domain/leave_request.dart';

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

  @override
  void initState() {
    super.initState();
    _loadData();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
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
          .select(
            'id, full_name, approval_status, role, created_at, '
            'department, designation, phone, joining_date, manager_id, profile_details',
          )
          .eq('id', user.id)
          .maybeSingle();

      if (myProfile == null) {
        throw Exception(
          'Your profile was not found. Contact your administrator.',
        );
      }

      final result = await _supabase
          .from('profiles')
          .select(
            'id, full_name, approval_status, role, created_at, '
            'department, designation, phone, joining_date, manager_id, profile_details',
          )
          .order('created_at', ascending: false);
      final profiles = List<Map<String, dynamic>>.from(result);

      final todayStr = DateTime.now().toIso8601String().split('T')[0];

      // Load today's attendance for current user
      final attRes = await _supabase
          .from('attendance_records')
          .select('*')
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
          .select('leave_type, allocated_days, used_days')
          .eq('employee_id', user.id);

      // Load announcements from company_wall_posts
      final wallRes = await _supabase
          .from('company_wall_posts')
          .select('*')
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: false)
          .limit(5);

      // Only real upcoming records, bounded for a 50-person internal app.
      List<Map<String, dynamic>> loadedHolidays = [];
      String? holidayError;
      try {
        final rows = await _supabase
            .from('holidays')
            .select('id, name, holiday_date, type')
            .gte('holiday_date', todayStr)
            .order('holiday_date')
            .limit(20);
        loadedHolidays = List<Map<String, dynamic>>.from(rows);
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

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Logout failed: $e')));
    }
  }

  Future<void> _reviewEmployee(String userId, String status) async {
    try {
      await _supabase.rpc(
        'review_employee',
        params: {'p_user_id': userId, 'p_approval_status': status},
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🎉 Account $status successfully!'),
          backgroundColor: status == 'approved' ? Colors.green : Colors.orange,
        ),
      );
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update account status: $e')),
      );
    }
  }

  Future<void> _handleClockInOut() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    final todayStr = DateTime.now().toIso8601String().split('T')[0];
    final nowTime = DateTime.now().toUtc().toIso8601String();

    try {
      final existing = await _supabase
          .from('attendance_records')
          .select('*')
          .eq('employee_id', user.id)
          .eq('attendance_date', todayStr)
          .maybeSingle();

      if (existing == null) {
        // Clock In
        final now = DateTime.now();
        final startTime = DateTime(now.year, now.month, now.day, 9, 0);
        int lateMins = 0;
        if (now.isAfter(startTime)) {
          lateMins = now.difference(startTime).inMinutes;
        }
        String status = lateMins > 15 ? 'Late' : 'Present';

        final newRec = await _supabase
            .from('attendance_records')
            .insert({
              'employee_id': user.id,
              'attendance_date': todayStr,
              'check_in': nowTime,
              'status': status,
              'late_minutes': lateMins,
            })
            .select()
            .single();
        setState(() => _myTodayAttendance = newRec);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🟢 Successfully checked in!'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (existing['check_out'] == null) {
        // Clock Out
        final updated = await _supabase
            .from('attendance_records')
            .update({'check_out': nowTime})
            .eq('id', existing['id'])
            .select()
            .single();
        setState(() => _myTodayAttendance = updated);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🔴 Successfully checked out!'),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Attendance already completed for today.'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Attendance action failed: $e')));
    }
  }

  Future<void> _submitWallPost() async {
    final text = _wallPostController.text.trim();
    final user = _supabase.auth.currentUser;
    if (user == null || text.isEmpty) return;

    try {
      await _supabase.from('company_wall_posts').insert({
        'author_id': user.id,
        'title': _composerCategory == 'announcement'
            ? '📢 Announcement'
            : _composerCategory == 'praise'
            ? '👏 Praise'
            : 'Company Update',
        'content': text,
        'category': _composerCategory,
        'is_pinned': _composerCategory == 'announcement',
      });

      _wallPostController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 Post published to Company Wall!'),
          backgroundColor: Colors.green,
        ),
      );
      _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error publishing post: $e')));
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
                      icon: const Icon(Icons.menu),
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
              NotificationBell(
                role: widget.role,
                onNavigate: _openNotificationDestination,
              ),
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
                    if (action == 'refresh') {
                      _loadData();
                    } else {
                      _logout();
                    }
                  },
                  itemBuilder: (_) => const [
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
          body: Row(
            children: [
              if (isDesktop)
                SizedBox(width: 245, child: _buildSidebar(isDrawer: false)),
              Expanded(child: _buildPage(colors)),
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

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(right: BorderSide(color: colors.outlineVariant)),
      ),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'WORKSPACE',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
                letterSpacing: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 10),
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
                        selectedTileColor: colors.primary.withValues(
                          alpha: 0.12,
                        ),
                        selectedColor: colors.primary,
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
            leading: CircleAvatar(
              backgroundColor: AppThemes.orange,
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : 'U',
                style: const TextStyle(color: Colors.black),
              ),
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
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Workspace / $page',
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: colors.onSurfaceVariant),
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
                if (page == 'Tasks')
                  TaskManagementScreen(
                    key: ValueKey('task-notice-$_notificationOpenRevision'),
                    role: widget.role,
                    initialTaskId: _notificationRecordId,
                    onTargetConsumed: _consumeNotificationTarget,
                  ),
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
        _buildWelcomeBanner(name, colors),

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
              _buildQuickAccessCard(),
              const SizedBox(height: 16),
              _buildAttendanceWidget(),
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

  Widget _buildWelcomeBanner(String name, ColorScheme colors) {
    final dept = _myProfile?['department']?.toString() ?? 'PenguinPeak';
    final desig = _myProfile?['designation']?.toString() ?? 'Team Member';
    final todayFormatted =
        '${_now.day}/${_now.month}/${_now.year} • ${DateTime.now().toLocal().toString().split(' ')[1].substring(0, 5)}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppThemes.orange.withOpacity(0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppThemes.orange.withOpacity(0.12),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppThemes.orange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppThemes.orange),
                      ),
                      child: Text(
                        _roleLabel.toUpperCase(),
                        style: const TextStyle(
                          color: AppThemes.orange,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '• $desig ($dept)',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Welcome back, $name! 👋',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Here is your workplace overview & daily activities for $todayFormatted',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          if (MediaQuery.sizeOf(context).width >= 650)
            CircleAvatar(
              radius: 34,
              backgroundColor: AppThemes.orange,
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : 'U',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ),
        ],
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
        final crossCount = constraints.maxWidth >= 900 ? 4 : 2;
        return GridView.count(
          crossAxisCount: crossCount,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.5,
          children: [
            _kpiTile(
              'Total Employees',
              '$totalEmployees Active',
              '+4% this mo',
              Icons.groups,
              const Color(0xFF6366F1),
            ),
            _kpiTile(
              'Approved Roster',
              '$approvedCount Verified',
              '100% secure',
              Icons.verified,
              const Color(0xFF10B981),
            ),
            _kpiTile(
              'Pending Approvals',
              '$pendingCount Action Req',
              pendingCount > 0 ? 'Review now' : 'All clear',
              Icons.pending_actions,
              const Color(0xFFF59E0B),
            ),
            _kpiTile(
              'On Leave Today',
              '${_onLeaveToday.length} Members',
              'Team roster',
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
    String subtitle,
    IconData icon,
    Color color,
  ) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              StatusBadge(label: subtitle, color: color),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
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
              'Quick Access Shortcuts',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 130,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                mainAxisExtent: MediaQuery.sizeOf(context).width < 600
                    ? 112
                    : null,
                childAspectRatio: 1.1,
              ),
              itemCount: items.length,
              itemBuilder: (context, idx) {
                final item = items[idx];
                return InkWell(
                  onTap: () => _navigateToModule(item['module'] as String),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          item['icon'] as IconData,
                          color: AppThemes.orange,
                          size: 22,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item['label'] as String,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              },
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
        inTime =
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} ${dt.hour >= 12 ? 'PM' : 'AM'}';
      }
    }

    final lateMins = ((todayRec?['late_minutes'] as num?)?.toInt() ?? 0);
    final lateStr = lateMins > 0
        ? ' • ⚠️ Late by ${lateMins ~/ 60}h ${lateMins % 60}m'
        : ' • 🟢 On Time';

    int totalMinutesWorked = 0;
    if (isCheckedIn) {
      final start =
          DateTime.tryParse(todayRec['check_in'].toString()) ?? DateTime.now();
      final end = isCheckedOut
          ? (DateTime.tryParse(todayRec['check_out'].toString()) ?? _now)
          : _now;
      totalMinutesWorked = end.difference(start).inMinutes.clamp(0, 1440);
    }

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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                          ? Colors.grey
                          : isCheckedIn
                          ? Colors.orange.shade800
                          : Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: isCheckedOut ? null : _handleClockInOut,
                    icon: Icon(
                      isCheckedIn ? Icons.logout : Icons.login,
                      size: 18,
                    ),
                    label: Text(
                      isCheckedOut
                          ? 'Shift Completed'
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

  Future<void> _manageHolidaysDialog() async {
    final nameController = TextEditingController();
    DateTime? selectedDate = DateTime.now().add(const Duration(days: 30));
    String holidayType = 'National Holiday';

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Manage Company Holidays'),
          content: SizedBox(
            width: 480,
            height: 450,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Add New Holiday',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppThemes.orange,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Holiday Name *',
                      hintText: 'e.g. Diwali, Independence Day',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          selectedDate == null
                              ? 'No date selected'
                              : 'Date: ${selectedDate!.toIso8601String().split('T')[0]}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (picked != null) {
                            setDialogState(() => selectedDate = picked);
                          }
                        },
                        child: const Text('Select Date'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: holidayType,
                    decoration: const InputDecoration(
                      labelText: 'Holiday Category / Type',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'National Holiday',
                        child: Text('National Holiday'),
                      ),
                      DropdownMenuItem(
                        value: 'Festive Holiday',
                        child: Text('Festive Holiday'),
                      ),
                      DropdownMenuItem(
                        value: 'Optional / Floating',
                        child: Text('Optional / Floating'),
                      ),
                      DropdownMenuItem(
                        value: 'Regional Holiday',
                        child: Text('Regional Holiday'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => holidayType = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppThemes.orange,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: () async {
                        final hName = nameController.text.trim();
                        if (hName.isEmpty || selectedDate == null) return;

                        final newHoliday = {
                          'name': hName,
                          'holiday_date': selectedDate!.toIso8601String().split(
                            'T',
                          )[0],
                          'type': holidayType,
                        };

                        try {
                          final inserted = await _supabase
                              .from('holidays')
                              .insert(newHoliday)
                              .select()
                              .single();

                          setState(() {
                            _holidays.add(inserted);
                          });
                          setDialogState(() {
                            nameController.clear();
                          });

                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '🎉 $hName published to all employees!',
                              ),
                              backgroundColor: Colors.green,
                            ),
                          );
                        } catch (e) {
                          setState(() {
                            _holidays.add(newHoliday);
                          });
                          setDialogState(() {
                            nameController.clear();
                          });

                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Added locally. Run Supabase SQL to sync across devices: $e',
                              ),
                              backgroundColor: Colors.orange.shade900,
                              duration: const Duration(seconds: 5),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add Holiday'),
                    ),
                  ),
                  const Divider(height: 28),
                  const Text(
                    'Configured Company Holidays',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  ..._holidays.map(
                    (h) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        h['name']?.toString() ?? 'Holiday',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        '${h['holiday_date'] ?? h['date'] ?? ''} • ${h['type'] ?? 'Company Holiday'}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                          size: 20,
                        ),
                        onPressed: () async {
                          try {
                            if (h['id'] != null) {
                              await _supabase
                                  .from('holidays')
                                  .delete()
                                  .eq('id', h['id']);
                            }
                          } catch (_) {}
                          setState(() {
                            _holidays.remove(h);
                          });
                          setDialogState(() {});
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        ),
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
                  'Upcoming Company Holidays',
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
                      'Manage Holidays',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            HolidayList(
              holidays: _holidays,
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
            Row(
              children: [
                const Icon(Icons.business, color: AppThemes.orange),
                const SizedBox(width: 8),
                const Text(
                  'PenguinPeak Technologies',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(
            v,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
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
                onPressed: _submitWallPost,
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

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Employee details updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      await _loadData();
      return true;
    } catch (e) {
      if (!mounted) return false;

      ScaffoldMessenger.of(context).showSnackBar(
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
      managerName: _managerName(profile['manager_id']?.toString()),
      onEdit: () => _editEmployee(profile),
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
              'Settings',
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

  const KekaEmployeeDetailWidget({
    super.key,
    required this.profile,
    required this.managerName,
    this.onEdit,
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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'IN',
                    style: TextStyle(
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
  Widget _buildPerformanceTab() =>
      const Center(child: Text('No performance reviews available.'));
}
