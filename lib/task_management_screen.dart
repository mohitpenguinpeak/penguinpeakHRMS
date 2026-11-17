import 'package:penguinpeak_hrms/shared/widgets/company_calendar.dart';
import 'shared/widgets/app_toast.dart';

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/theme/design_system.dart';
import 'features/leave/domain/leave_request.dart';
import 'features/tasks/domain/task_query.dart';
import 'features/tasks/domain/task_booking.dart';
import 'features/tasks/domain/task_time_summary.dart';
import 'features/tasks/presentation/task_work_log_entry.dart';
import 'features/tasks/presentation/manual_task_time_entry.dart';
import 'features/tasks/presentation/booking_duration_picker.dart';
import 'features/tasks/presentation/task_overview_panel.dart';
import 'features/tasks/presentation/task_filter_panel.dart';
import 'features/tasks/presentation/grouped_task_board.dart';
import 'features/tasks/presentation/task_calendar_view.dart';
import 'features/tasks/presentation/task_analytics_view.dart';
import 'shared/widgets/adaptive_layout.dart';

class TaskTracker {
  static final TaskTracker instance = TaskTracker._internal();
  TaskTracker._internal();

  final ValueNotifier<Map<String, dynamic>?> activeTask =
      ValueNotifier<Map<String, dynamic>?>(null);
  Map<String, dynamic>? preBreakTask;

  // Live Timer & Timelogs
  final ValueNotifier<int> activeSeconds = ValueNotifier<int>(0);
  final ValueNotifier<bool> isTimerRunning = ValueNotifier<bool>(false);
  Timer? _liveTimer;
  bool _savingLog = false;
  int _sessionGeneration = 0;

  final ValueNotifier<List<Map<String, dynamic>>> timelogs =
      ValueNotifier<List<Map<String, dynamic>>>([]);

  void startTimer(Map<String, dynamic> task) {
    if (_savingLog) return;
    if (activeTask.value?['id'] != task['id'] && activeSeconds.value > 0) {
      throw StateError('Save the current timer before starting another task.');
    }
    if (activeTask.value?['id'] != task['id']) {
      activeTask.value = task;
      activeSeconds.value = 0;
    }
    isTimerRunning.value = true;
    _liveTimer?.cancel();
    _liveTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      activeSeconds.value++;
    });
  }

  void pauseTimer() {
    isTimerRunning.value = false;
    _liveTimer?.cancel();
  }

  void resetForSignOut() {
    _sessionGeneration++;
    pauseTimer();
    _savingLog = false;
    activeSeconds.value = 0;
    activeTask.value = null;
    preBreakTask = null;
    timelogs.value = [];
  }

  Future<void> stopAndLogTimer(String note) async {
    if (_savingLog) return;
    final generation = _sessionGeneration;
    _savingLog = true;
    try {
      pauseTimer();
      final secs = activeSeconds.value;
      if (secs > 0 && activeTask.value != null) {
        final hours = secs ~/ 3600;
        final mins = (secs % 3600) ~/ 60;
        final log = <String, dynamic>{
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
          'task_id': activeTask.value!['id'],
          'task_title': activeTask.value!['title'] ?? 'Task',
          'logged_seconds': secs,
          'logged_hours_fmt':
              '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}',
          'note': note,
          'date': DateTime.now().toIso8601String().split('T')[0],
          'created_at': DateTime.now().toIso8601String(),
        };
        await Supabase.instance.client.from('task_work_logs').insert({
          ...log,
          'employee_id': Supabase.instance.client.auth.currentUser!.id,
        });
        if (generation != _sessionGeneration) return;
        addTimelog(log);
        activeSeconds.value = 0;
      }
    } finally {
      if (generation == _sessionGeneration) _savingLog = false;
    }
  }

  void addTimelog(Map<String, dynamic> log) {
    timelogs.value = [log, ...timelogs.value];
  }

  void saveTaskBeforeBreak(Map<String, dynamic>? task) {
    preBreakTask = task;
  }

  Map<String, dynamic>? getAndClearPreBreakTask() {
    final t = preBreakTask;
    preBreakTask = null;
    return t;
  }
}

class TaskManagementScreen extends StatefulWidget {
  final String role;
  const TaskManagementScreen({
    super.key,
    required this.role,
    this.initialTaskId,
    this.availabilityOnly = false,
    this.onTargetConsumed,
  });
  final bool availabilityOnly;
  final String? initialTaskId;
  final VoidCallback? onTargetConsumed;

  @override
  State<TaskManagementScreen> createState() => _TaskManagementScreenState();
}

class _TaskManagementScreenState extends State<TaskManagementScreen>
    with SingleTickerProviderStateMixin {
  final SupabaseClient _db = Supabase.instance.client;
  late TabController _tabController;

  bool _loading = true;
  bool _initialTaskOpened = false;
  String? _error;
  List<Map<String, dynamic>> _tasks = [];
  List<Map<String, dynamic>> _profiles = [];
  List<Map<String, dynamic>> _approvedLeaves = [];

  String _taskView = 'list';
  String _searchQuery = '';
  String _statusFilter = 'all';
  String _priorityFilter = 'all';
  String? _projectFilter, _assigneeFilter, _creatorFilter;
  String _dueFilter = 'all', _sort = 'newest', _groupBy = 'none';
  DateTimeRange? _dueRange;
  final _taskSearchController = TextEditingController();
  final ScrollController _matrixScrollController = ScrollController();
  int _matrixStartOffset = 0;
  int _matrixDayCount = 14;

  String? _availabilityKey;
  Future<List<Map<String, dynamic>>>? _availabilityRequest;

  Future<List<Map<String, dynamic>>> _loadAvailability(DateTime start, int days) async {
    final rows = await _db.rpc('resource_availability', params: {
      'p_start': start.toIso8601String().split('T').first,
      'p_days': days,
    });
    return List<Map<String, dynamic>>.from(rows as List);
  }

  String? get _uid => _db.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadData();
    _refreshTimeLogs();
  }

  @override
  void dispose() {
    _taskSearchController.dispose();
    _matrixScrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _availabilityKey = null;
      _error = null;
    });
    try {
      final tasksRes = await _db
          .from('tasks')
          .select('*, task_comments(*)')
          .order('created_at', ascending: false);
      _tasks = List<Map<String, dynamic>>.from(tasksRes)
          .map(
            (task) => task['status'] == 'blocked'
                ? {...task, 'status': 'on_hold'}
                : task,
          )
          .toList();

      final profilesRes = await _db
          .from('profiles')
          .select('id, full_name, department, role')
          .eq('approval_status', 'approved')
          .order('full_name');
      _profiles = List<Map<String, dynamic>>.from(profilesRes);

      // Load approved leave requests for availability matrix
      final leavesRes = await _db
          .from('leave_requests')
          .select(
            'employee_id, start_date, end_date, approved_start_date, approved_end_date, approved_days, days',
          )
          .eq('manager_status', 'approved')
          .eq('hr_status', 'approved')
          .isFilter('cancelled_at', null);
      _approvedLeaves = List<Map<String, dynamic>>.from(leavesRes)
          .map((row) => LeaveRequest(row).effectiveRow)
          .toList();

      if (!mounted) return;
      setState(() => _loading = false);
      if (!_initialTaskOpened && widget.initialTaskId != null) {
        _initialTaskOpened = true;
        widget.onTargetConsumed?.call();
        final task = _tasks
            .where((t) => t['id'] == widget.initialTaskId)
            .firstOrNull;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (task != null) {
            _viewTaskDetails(task);
          } else {
            AppToast.of(context).showSnackBar(
              const SnackBar(
                content: Text('This task is no longer available.'),
              ),
            );
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _employeeName(dynamic id) {
    final key = id?.toString();
    for (final p in _profiles) {
      if (p['id']?.toString() == key) {
        return (p['full_name'] ?? 'Employee').toString();
      }
    }
    return 'Unknown Employee';
  }

  String _cleanDescription(String? desc) {
    if (desc == null || desc.trim().isEmpty) return 'No description provided.';
    final cleaned = desc
        .replaceAll(RegExp(r'\[Booking:\s*[\d.]+\s*hrs\]\s*'), '')
        .trim();
    return cleaned.isEmpty ? 'No description provided.' : cleaned;
  }

  String _extractBookingHours(String? desc) {
    if (desc == null) return '';
    final match = RegExp(r'\[Booking:\s*([\d.]+)\s*hrs\]').firstMatch(desc);
    return match?.group(1) ?? '';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'in_progress':
        return Colors.blue;
      case 'pending_acceptance':
        return Colors.orange;
      case 'declined':
        return Colors.red;
      case 'blocked':
      case 'on_hold':
        return Colors.redAccent;
      case 'pending':
        return Colors.orange;
      case 'in_review':
        return Colors.purple;
      default:
        return Colors.amber;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'completed':
        return 'Completed';
      case 'in_progress':
        return 'In Progress';
      case 'pending_acceptance':
        return 'Pending Acceptance';
      case 'declined':
        return 'Declined';
      case 'blocked':
      case 'on_hold':
        return 'On Hold';
      case 'pending':
        return 'Pending';
      case 'in_review':
        return 'In Review';
      case 'todo':
        return 'To Do';
      default:
        return status;
    }
  }

  Color _priorityColor(String priority) {
    switch (priority) {
      case 'urgent':
        return Colors.purple;
      case 'high':
        return Colors.deepOrange;
      case 'medium':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  bool _isOverdue(Map<String, dynamic> task) {
    if (task['status'] == 'completed') return false;
    final dueStr = task['due_date']?.toString();
    if (dueStr == null) return false;
    final dueDate = DateTime.tryParse(dueStr);
    if (dueDate == null) return false;
    final now = DateTime.now();
    return dueDate.isBefore(DateTime(now.year, now.month, now.day));
  }

  // --- AVAILABILITY LOGIC ---

  bool _isEmployeeOnLeave(String empId, DateTime date) {
    final dStr = date.toIso8601String().split('T')[0];
    for (final l in _approvedLeaves) {
      if (l['employee_id']?.toString() == empId) {
        final start = l['start_date']?.toString().split('T')[0] ?? '';
        final end = l['end_date']?.toString().split('T')[0] ?? '';
        if (dStr.compareTo(start) >= 0 && dStr.compareTo(end) <= 0) {
          return true;
        }
      }
    }
    return false;
  }

  int _getEmployeeActiveTaskCount(String empId, DateTime date) {
    final dStr = date.toIso8601String().split('T')[0];
    int count = 0;
    for (final t in _tasks) {
      if (t['assignee_id']?.toString() == empId &&
          t['status'] != 'completed' &&
          t['status'] != 'declined') {
        final due = t['due_date']?.toString().split('T')[0] ?? '';
        final created = t['created_at']?.toString().split('T')[0] ?? dStr;
        if (dStr.compareTo(created) >= 0 && dStr.compareTo(due) <= 0) {
          count++;
        }
      }
    }
    return count;
  }

  DateTime _findNextAvailableDate(String empId) {
    DateTime checkDate = DateTime.now();
    for (int i = 0; i < 30; i++) {
      final dt = checkDate.add(Duration(days: i));
      final dateOnly = DateTime(dt.year, dt.month, dt.day);
      bool onLeave = _isEmployeeOnLeave(empId, dateOnly);
      if (!CompanyCalendar.of(context).works(dateOnly)) continue;
      int tasksCount = _getEmployeeActiveTaskCount(empId, dateOnly);
      if (!onLeave && tasksCount == 0) {
        return dateOnly;
      }
    }
    return DateTime.now();
  }

  List<Map<String, dynamic>> _filteredTasks(String viewType) {
    final scoped = _tasks
        .where(
          (task) => switch (viewType) {
            'my' => task['assignee_id']?.toString() == _uid,
            'assigned_by' => task['creator_id']?.toString() == _uid,
            _ => true,
          },
        )
        .toList();
    return TaskQuery(
      search: _searchQuery,
      status: _statusFilter,
      priority: _priorityFilter,
      project: _projectFilter,
      assignee: _assigneeFilter,
      creator: _creatorFilter,
      due: _dueFilter,
      from: _dueRange?.start,
      to: _dueRange?.end,
      sort: _sort,
    ).apply(scoped, now: DateTime.now(), employeeName: _employeeName);
  }

  void _resetFilters() => setState(() {
    _searchQuery = '';
    _taskSearchController.clear();
    _statusFilter = 'all';
    _priorityFilter = 'all';
    _projectFilter = null;
    _assigneeFilter = null;
    _creatorFilter = null;
    _dueFilter = 'all';
    _dueRange = null;
    _sort = 'newest';
    _groupBy = 'none';
  });

  Widget _filterSelect(
    String label,
    String? value,
    Map<String, String> choices,
    ValueChanged<String?> onChanged, {
    bool allowAll = true,
  }) {
    final options = {...choices};
    if (value != null) {
      options.putIfAbsent(value, () => value.isEmpty ? 'Unassigned' : value);
    }
    return DropdownButtonFormField<String>(
      key: ValueKey('$label:$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, isDense: true),
      items: [
        if (allowAll)
          const DropdownMenuItem<String>(value: null, child: Text('All')),
        for (final entry in options.entries)
          DropdownMenuItem(
            value: entry.key,
            child: Text(entry.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }

  Widget _activeFilterSummary() {
    Widget chip(String label, VoidCallback clear) => InputChip(
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      onDeleted: () => setState(clear),
    );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (_searchQuery.trim().isNotEmpty)
          chip('Search: $_searchQuery', () {
            _searchQuery = '';
            _taskSearchController.clear();
          }),
        if (_statusFilter != 'all')
          chip(
            'Status: ${_statusLabel(_statusFilter)}',
            () => _statusFilter = 'all',
          ),
        if (_priorityFilter != 'all')
          chip('Priority: $_priorityFilter', () => _priorityFilter = 'all'),
        if (_projectFilter != null)
          chip(
            'Project: ${_projectFilter!.isEmpty ? 'No project' : _projectFilter}',
            () => _projectFilter = null,
          ),
        if (_assigneeFilter != null)
          chip(
            'Assigned: ${_assigneeFilter!.isEmpty ? 'Unassigned' : _employeeName(_assigneeFilter)}',
            () => _assigneeFilter = null,
          ),
        if (_creatorFilter != null)
          chip(
            'Created by: ${_employeeName(_creatorFilter)}',
            () => _creatorFilter = null,
          ),
        if (_dueFilter != 'all')
          chip('Due: $_dueFilter', () => _dueFilter = 'all'),
        if (_dueRange != null)
          chip('Custom due date range', () => _dueRange = null),
      ],
    );
  }

  Widget _advancedFilters() {
    final projects = <String, String>{
      for (final task in _tasks)
        (task['project']?.toString().trim() ??
            ''): (task['project']?.toString().trim().isNotEmpty == true
            ? task['project'].toString().trim()
            : 'No project'),
    };
    final assignees = <String, String>{
      '': 'Unassigned',
      for (final task in _tasks)
        if (task['assignee_id'] != null)
          task['assignee_id'].toString(): _employeeName(task['assignee_id']),
    };
    final creators = <String, String>{
      for (final task in _tasks)
        if (task['creator_id'] != null)
          task['creator_id'].toString(): _employeeName(task['creator_id']),
    };
    return TaskFilterPanel(
      child: AdaptiveCards(
        minWidth: 240,
        maxColumns: 4,
        children: [
          _filterSelect(
            'Project',
            _projectFilter,
            projects,
            (value) => setState(() => _projectFilter = value),
          ),
          _filterSelect(
            'Assigned to',
            _assigneeFilter,
            assignees,
            (value) => setState(() => _assigneeFilter = value),
          ),
          _filterSelect(
            'Created by',
            _creatorFilter,
            creators,
            (value) => setState(() => _creatorFilter = value),
          ),
          _filterSelect(
            'Due date',
            _dueFilter,
            const {
              'all': 'All dates',
              'overdue': 'Overdue active tasks',
              'today': 'Due today',
              'week': 'Due within 7 days',
              'undated': 'No due date',
            },
            (value) => setState(() {
              _dueFilter = value!;
              _dueRange = null;
            }),
            allowAll: false,
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final range = await showDateRangePicker(
                context: context,
                initialDateRange: _dueRange,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (range != null && mounted)
                setState(() {
                  _dueRange = range;
                  _dueFilter = 'all';
                });
            },
            icon: const Icon(Icons.date_range),
            label: Text(
              _dueRange == null
                  ? 'Custom due date range'
                  : '${_dueRange!.start.toIso8601String().split('T').first} – ${_dueRange!.end.toIso8601String().split('T').first}',
            ),
          ),
          _filterSelect(
            'Sort by',
            _sort,
            const {
              'newest': 'Newest first',
              'oldest': 'Oldest first',
              'due': 'Due date',
              'priority': 'Priority',
              'title': 'Title',
            },
            (value) => setState(() => _sort = value!),
            allowAll: false,
          ),
          _filterSelect(
            'Group board by',
            _groupBy,
            const {
              'none': 'No grouping',
              'project': 'Project',
              'assignee': 'Assignee',
              'priority': 'Priority',
            },
            (value) => setState(() => _groupBy = value!),
            allowAll: false,
          ),
          TextButton.icon(
            onPressed: _resetFilters,
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reset all filters'),
          ),
        ],
      ),
    );
  }

  Future<void> _acceptBooking(Map<String, dynamic> task) async {
    try {
      await _db
          .from('tasks')
          .update({
            'status': 'in_progress',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', task['id']);

      await _db.from('task_comments').insert({
        'task_id': task['id'],
        'author_id': _uid,
        'comment': 'Accepted the resource booking request.',
      });

      if (!mounted) return;
      AppToast.of(context).showSnackBar(
        const SnackBar(
          content: Text('Booking accepted! Task is now In Progress.'),
          backgroundColor: Colors.green,
        ),
      );
      _loadData();
    } catch (e) {
      if (!mounted) return;
      AppToast.of(context).showSnackBar(
        SnackBar(
          content: Text('Error accepting booking: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _declineBooking(Map<String, dynamic> task) async {
    final reasonController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Decline Booking Request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'State why you cannot accept this booking from ${_employeeName(task['creator_id'])}:',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason for declining *',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Decline Request'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final reason = reasonController.text.trim();
      await _db
          .from('tasks')
          .update({
            'status': 'declined',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', task['id']);

      await _db.from('task_comments').insert({
        'task_id': task['id'],
        'author_id': _uid,
        'comment':
            'Declined booking request. Reason: ${reason.isEmpty ? "Unavailable" : reason}',
      });

      if (!mounted) return;
      AppToast.of(context).showSnackBar(
        const SnackBar(
          content: Text('Booking request declined.'),
          backgroundColor: Colors.orange,
        ),
      );
      _loadData();
    } catch (e) {
      if (!mounted) return;
      AppToast.of(context).showSnackBar(
        SnackBar(
          content: Text('Error declining booking: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _upsertTask({
    Map<String, dynamic>? existing,
    Map<String,dynamic>? parent,
    String? initialAssigneeId,
    DateTime? initialDueDate,
  }) async {
    final isEdit = existing != null;
    final canEditDetails =
        !isEdit || existing['creator_id']?.toString() == _uid;
    if (isEdit &&
        !canEditDetails &&
        existing['assignee_id']?.toString() != _uid) {
      AppToast.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only the creator or assignee can edit this task.'),
        ),
      );
      return;
    }
    var assignees = _profiles;
    if (parent != null) {
      if (_uid == null || parent['assignee_id'] != _uid) return;
      try {
        assignees = await _loadAvailability(DateTime.now(), 1);
      } catch (error) {
        if (mounted) AppToast.of(context).showSnackBar(SnackBar(content: Text('Could not load assignees: $error')));
        return;
      }
      if (!mounted) return;
    }
    final titleController = TextEditingController(
      text: existing?['title'] ?? '',
    );
    final projectController = TextEditingController(
      text: (existing?['project'] ?? parent?['project'])?.toString() ?? '',
    );
    final rawDesc = _cleanDescription(existing?['description']);
    final descController = TextEditingController(
      text: rawDesc == 'No description provided.' ? '' : rawDesc,
    );
    String assigneeId =
        existing?['assignee_id']?.toString() ?? initialAssigneeId ?? _uid ?? '';
    String initialStatus = switch (existing?['status']) {
      'blocked' => 'on_hold',
      'declined' => 'pending',
      final String status => status,
      _ => 'todo',
    };
    String priority = existing?['priority'] ?? 'medium';
    final initialBookingMinutes =
        (taskBookingHours(existing?['description']?.toString()) * 60).round();
    final hoursController = TextEditingController(
      text: (initialBookingMinutes / 60).toString(),
    );
    DateTime? dueDate = isEdit
        ? DateTime.tryParse('${existing['due_date']}')
        : initialDueDate ?? DateTime.now().add(const Duration(days: 3));

    final route = DialogRoute<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final requiresAcceptance =
              !isEdit &&
              requiresBookingAcceptance(
                tasks: _tasks,
                assigneeId: assigneeId,
                day: dueDate ?? DateTime.now(),
                bookingHours: taskBookingHours(
                  '[Booking: ${hoursController.text} hrs]',
                ),
              );
          if (!isEdit) {
            if (requiresAcceptance) {
              initialStatus = 'pending_acceptance';
            } else if (initialStatus == 'pending_acceptance') {
              initialStatus = 'todo';
            }
          }
          final nextAvail = assigneeId.isNotEmpty
              ? _findNextAvailableDate(assigneeId)
              : DateTime.now();
          final isAvailToday = nextAvail.difference(DateTime.now()).inDays <= 0;

          return AlertDialog(
            title: Text(
              parent != null ? 'Create subtask' : isEdit ? 'Edit Resource Task' : 'Book Resource / Assign Task',
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (assigneeId.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: isAvailToday
                              ? Colors.green.withOpacity(0.15)
                              : Colors.orange.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isAvailToday ? Colors.green : Colors.orange,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isAvailToday
                                  ? Icons.check_circle_outline
                                  : Icons.event_busy,
                              color: isAvailToday
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                isAvailToday
                                    ? '🟢 ${_employeeName(assigneeId)} is AVAILABLE today for immediate work.'
                                    : '🔴 ${_employeeName(assigneeId)} is currently booked/busy. Next available: ${nextAvail.toIso8601String().split('T')[0]}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isAvailToday
                                      ? Colors.green
                                      : Colors.orange,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    TextField(
                      controller: titleController,
                      readOnly: !canEditDetails,
                      decoration: const InputDecoration(
                        labelText: 'Task Title / Deliverable *',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: projectController,
                      readOnly: !canEditDetails,
                      decoration: const InputDecoration(labelText: 'Project'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descController,
                      readOnly: !canEditDetails,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            key: ValueKey(initialStatus),
                            initialValue: initialStatus,
                            decoration: const InputDecoration(
                              labelText: 'Status',
                            ),
                            items: [
                              if (requiresAcceptance ||
                                  (isEdit &&
                                      initialStatus == 'pending_acceptance'))
                                const DropdownMenuItem(
                                  value: 'pending_acceptance',
                                  child: Text('Pending Acceptance'),
                                ),
                              DropdownMenuItem(
                                value: 'todo',
                                child: Text('To Do'),
                              ),
                              DropdownMenuItem(
                                value: 'in_progress',
                                child: Text('In Progress'),
                              ),
                              DropdownMenuItem(
                                value: 'on_hold',
                                child: Text('On Hold'),
                              ),
                              DropdownMenuItem(
                                value: 'pending',
                                child: Text('Pending'),
                              ),
                              DropdownMenuItem(
                                value: 'completed',
                                child: Text('Completed'),
                              ),
                              DropdownMenuItem(
                                value: 'in_review',
                                child: Text('In Review'),
                              ),
                            ],
                            onChanged: requiresAcceptance
                                ? null
                                : (v) {
                                    if (v != null) {
                                      setDialogState(() => initialStatus = v);
                                    }
                                  },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            value: priority,
                            decoration: const InputDecoration(
                              labelText: 'Priority / Urgency',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'low',
                                child: Text('Low'),
                              ),
                              DropdownMenuItem(
                                value: 'medium',
                                child: Text('Medium'),
                              ),
                              DropdownMenuItem(
                                value: 'high',
                                child: Text('High'),
                              ),
                              DropdownMenuItem(
                                value: 'urgent',
                                child: Text('🚨 Urgent (Escalation)'),
                              ),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setDialogState(() => priority = v);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: assigneeId.isEmpty ? null : assigneeId,
                      decoration: const InputDecoration(
                        labelText: 'Book Resource (Assign To)',
                      ),
                      items: [
                        if (assigneeId.isNotEmpty &&
                            !assignees.any(
                              (p) => p['id'].toString() == assigneeId,
                            ))
                          DropdownMenuItem(
                            value: assigneeId,
                            child: const Text('Current assignee (unavailable)'),
                          ),
                        ...assignees.map(
                          (p) => DropdownMenuItem(
                            value: p['id'].toString(),
                            child: Text(
                              p['department'] == null ? '${p['full_name']}' : '${p['full_name']} (${p['department']})',
                            ),
                          ),
                        ),
                      ],
                      onChanged: !canEditDetails
                          ? null
                          : (v) {
                              if (v != null) {
                                setDialogState(() {
                                  assigneeId = v;
                                });
                              }
                            },
                    ),
                    const SizedBox(height: 12),
                    if (!canEditDetails)
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Estimated Booking Duration',
                        ),
                        child: Text(
                          '${(initialBookingMinutes ~/ 60).toString().padLeft(2, '0')}:${(initialBookingMinutes % 60).toString().padLeft(2, '0')}',
                        ),
                      )
                    else
                      BookingDurationPicker(
                        initialMinutes: initialBookingMinutes,
                        onChanged: (minutes) => setDialogState(() {
                          hoursController.text = (minutes / 60).toString();
                        }),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            dueDate == null
                                ? 'No due date'
                                : 'Due: ${dueDate!.toLocal().toString().split(' ')[0]}',
                          ),
                        ),
                        OutlinedButton(
                          onPressed: !canEditDetails
                              ? null
                              : () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: dueDate ?? DateTime.now(),
                                    firstDate: DateTime.now().subtract(
                                      const Duration(days: 365),
                                    ),
                                    lastDate: DateTime.now().add(
                                      const Duration(days: 730),
                                    ),
                                  );
                                  if (picked != null) {
                                    setDialogState(() => dueDate = picked);
                                  }
                                },
                          child: const Text('Select Due Date'),
                        ),
                        if (dueDate != null)
                          IconButton(
                            tooltip: 'Clear due date',
                            onPressed: !canEditDetails
                                ? null
                                : () => setDialogState(() => dueDate = null),
                            icon: const Icon(Icons.close),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  if (titleController.text.trim().isEmpty) {
                    AppToast.of(context).showSnackBar(
                      const SnackBar(content: Text('Task title is required')),
                    );
                    return;
                  }
                  try {
                    if (assigneeId.isEmpty)
                      throw const FormatException('Select an assignee.');
                    // Refresh leave at save time rather than trusting the matrix cache.
                    final bookingDate =
                        dueDate ??
                        DateTime.tryParse('${existing?['created_at']}') ??
                        DateTime.now();
                    num bookedHours = 0;
                    if (canEditDetails) {
                      final roster = await _loadAvailability(bookingDate, 1);
                      final employee = roster.where((row) => row['id'] == assigneeId).firstOrNull;
                      if (employee == null) throw const FormatException('Choose an active assignee.');
                      final date = bookingDate.toIso8601String().split('T').first;
                      final day = employee['days'][date];
                      bookedHours = day['hours'] as num;
                      if (day['leave'] == true) {
                        throw FormatException("${employee['full_name']} is on approved leave on $date. Choose another date or assignee.");
                      }
                    }
                    final hours = hoursController.text.trim();
                    final userDesc = descController.text.trim();
                    final estimate = double.tryParse(hours);
                    if (hours.isNotEmpty &&
                        (estimate == null ||
                            !estimate.isFinite ||
                            estimate <= 0)) {
                      throw const FormatException(
                        'Select a booking duration of at least one minute.',
                      );
                    }
                    final fullDesc = hours.isEmpty
                        ? userDesc
                        : '[Booking: $hours hrs] $userDesc';

                    if (!isEdit) {
                      final needsAcceptance = bookedHours + taskBookingHours(fullDesc) > 8;
                      if (needsAcceptance) {
                        initialStatus = 'pending_acceptance';
                      } else if (initialStatus == 'pending_acceptance') {
                        initialStatus = 'todo';
                      }
                    }

                    final data = {
                      if (canEditDetails) 'title': titleController.text.trim(),
                      if (canEditDetails) 'description': fullDesc,
                      'status': initialStatus,
                      'priority': priority,
                      if (canEditDetails) 'assignee_id': assigneeId,
                      if (!isEdit) 'creator_id': _uid,
                      if (parent != null) 'parent_task_id': parent['id'],
                      if (canEditDetails)
                        'project': projectController.text.trim(),
                      'completed_at': initialStatus == 'completed'
                          ? (existing?['completed_at'] ??
                                DateTime.now().toUtc().toIso8601String())
                          : null,
                      if (canEditDetails)
                        'due_date': dueDate?.toIso8601String(),
                    };

                    if (isEdit) {
                      await _db
                          .from('tasks')
                          .update(data)
                          .eq('id', existing['id']);
                    } else {
                      await _db.from('tasks').insert(data);
                    }

                    if (!mounted) return;
                    Navigator.pop(dialogContext);
                    _loadData();
                    AppToast.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isEdit
                              ? 'Booking updated'
                              : initialStatus == 'pending_acceptance'
                              ? 'Resource booked! Sent acceptance request to ${_employeeName(assigneeId)}.'
                              : 'Task created successfully',
                        ),
                      ),
                    );
                  } catch (e) {
                    AppToast.of(context).showSnackBar(
                      SnackBar(content: Text('Error saving booking: $e')),
                    );
                  }
                },
                child: Text(
                  isEdit
                      ? 'Save Booking'
                      : requiresAcceptance
                      ? 'Book & Send Request'
                      : 'Assign Task',
                ),
              ),
            ],
          );
        },
      ),
    );
    await Navigator.of(context, rootNavigator: true).push(route);
    await route.completed;
    titleController.dispose();
    descController.dispose();
    projectController.dispose();
    hoursController.dispose();
  }

  Future<bool> _deleteTask(Map<String, dynamic> task) async {
    if (_uid == null || task['creator_id']?.toString() != _uid) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text(
          'Delete "${task['title']}" and its comments? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;
    try {
      final deleted = await _db
          .from('tasks')
          .delete()
          .eq('id', task['id'])
          .eq('creator_id', _uid!)
          .select('id');
      if (deleted.isEmpty) {
        throw StateError('Task was not deleted. Check your permissions.');
      }
      final tracker = TaskTracker.instance;
      if (tracker.activeTask.value?['id'] == task['id']) {
        tracker.pauseTimer();
        tracker.activeTask.value = null;
        tracker.activeSeconds.value = 0;
      }
      if (tracker.preBreakTask?['id'] == task['id']) {
        tracker.preBreakTask = null;
      }
      if (!mounted) return true;
      await _loadData();
      if (!mounted) return true;
      AppToast.of(context)
          .showSnackBar(const SnackBar(content: Text('Task deleted')));
      return true;
    } catch (e) {
      if (mounted) {
        AppToast.of(context)
            .showSnackBar(SnackBar(content: Text('Could not delete task: $e')));
      }
      return false;
    }
  }

  Future<void> _viewTaskDetails(Map<String, dynamic> task) async {
    final commentController = TextEditingController();
    final route = DialogRoute<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isAssignee = task['assignee_id']?.toString() == _uid;
          final isPending = task['status'] == 'pending_acceptance';

          return AlertDialog(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task['title'] ?? 'Task Details'),
                Chip(
                  label: Text(_statusLabel(task['status'] ?? 'todo')),
                  backgroundColor: _statusColor(task['status'] ?? 'todo')
                      .withOpacity(0.2),
                ),
              ],
            ),
            content: SizedBox(
              width: 1100,
              height: MediaQuery.sizeOf(context).height * 0.7,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (task['parent_task_id'] != null) Text(
                      'Subtask of ${_tasks.where((t) => t['id'] == task['parent_task_id']).firstOrNull?['title'] ?? 'assigned task'}',
                    ),
                    for (final child in _tasks.where((t) => t['parent_task_id'] == task['id']))
                      ListTile(leading: const Icon(Icons.subdirectory_arrow_right), title: Text(child['title'] ?? 'Subtask'),
                        subtitle: Text(_employeeName(child['assignee_id'])),
                        onTap: () { Navigator.pop(dialogContext); _viewTaskDetails(child); }),
                    if (isAssignee) TextButton.icon(
                      onPressed: () { Navigator.pop(dialogContext); _upsertTask(parent: task); },
                      icon: const Icon(Icons.add), label: const Text('Create subtask')),
                    TaskOverviewPanel(task: task, employeeName: _employeeName),
                    const SizedBox(height: 16),
                    _TaskTimerPanel(
                      task: task,
                      onManualEntry:
                          isAssignee &&
                              ![
                                'pending_acceptance',
                                'declined',
                              ].contains(task['status'])
                          ? () => _showManualTimeEntryDialog(task)
                          : null,
                      canTrack:
                          isAssignee &&
                          !isPending &&
                          task['status'] != 'completed' &&
                          task['status'] != 'declined',
                    ),
                    const SizedBox(height: 16),
                    if (isAssignee && isPending)
                      Card(
                        color: Colors.orange.withOpacity(0.15),
                        margin: const EdgeInsets.only(bottom: 16),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '🚨 Booking Request from ${_employeeName(task['creator_id'])}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Are you available to work on this task? Accept to confirm or Decline if unavailable.',
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.green,
                                    ),
                                    onPressed: () {
                                      Navigator.pop(dialogContext);
                                      _acceptBooking(task);
                                    },
                                    icon: const Icon(Icons.check),
                                    label: const Text('Accept Booking'),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red,
                                    ),
                                    onPressed: () {
                                      Navigator.pop(dialogContext);
                                      _declineBooking(task);
                                    },
                                    icon: const Icon(Icons.close),
                                    label: const Text('Decline'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    Text(
                      'Description:',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(_cleanDescription(task['description'])),
                    const SizedBox(height: 16),
                    const Divider(height: 24),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        const Text(
                          'Comments & Updates',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...((task['task_comments'] as List?) ?? []).map(
                      (c) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 12,
                                runSpacing: 4,
                                children: [
                                  Text(
                                    _employeeName(c['author_id']),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    c['created_at']?.toString().split('T')[0] ??
                                        '',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(c['comment'] ?? c['comment_text'] ?? ''),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: commentController,
                            decoration: const InputDecoration(
                              labelText: 'Add progress update...',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.send),
                          onPressed: () async {
                            if (commentController.text.trim().isEmpty) return;
                            try {
                              await _db.from('task_comments').insert({
                                'task_id': task['id'],
                                'author_id': _uid,
                                'comment': commentController.text.trim(),
                              });
                              commentController.clear();
                              final res = await _db
                                  .from('tasks')
                                  .select('*, task_comments(*)')
                                  .eq('id', task['id'])
                                  .single();
                              setDialogState(() {
                                task.clear();
                                task.addAll(res);
                              });
                              _loadData();
                            } catch (e) {
                              AppToast.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error adding comment: $e'),
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              if (_uid != null && task['creator_id']?.toString() == _uid)
                TextButton.icon(
                  onPressed: () async {
                    if (await _deleteTask(task) && dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                    }
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete task'),
                ),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _upsertTask(existing: task);
                },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit task'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
              if (isAssignee && task['status'] == 'in_progress')
                FilledButton(
                  onPressed: () async {
                    try {
                      await _db
                          .from('tasks')
                          .update({
                            'status': 'completed',
                            'completed_at': DateTime.now()
                                .toUtc()
                                .toIso8601String(),
                            'updated_at': DateTime.now()
                                .toUtc()
                                .toIso8601String(),
                          })
                          .eq('id', task['id']);
                      if (!dialogContext.mounted || !mounted) return;
                      Navigator.pop(dialogContext);
                      await _loadData();
                    } catch (_) {
                      if (dialogContext.mounted)
                        AppToast.of(dialogContext).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Could not complete this task. Please retry.',
                            ),
                          ),
                        );
                    }
                  },
                  child: const Text('Mark Completed'),
                ),
            ],
          );
        },
      ),
    );
    await Navigator.of(context, rootNavigator: true).push(route);
    await route.completed;
    commentController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.availabilityOnly) return _buildResourceAvailabilityMatrix();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Tasks & workload',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            FilledButton.icon(
              onPressed: () => _upsertTask(),
              icon: const Icon(Icons.add),
              label: const Text('Create task'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Plan work, track progress and coordinate team availability.',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 16),
        if (_tabController.index != 3) ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 650;
              final searchWidth = narrow
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 24) / 2;
              final filterWidth = narrow
                  ? (constraints.maxWidth - 12) / 2
                  : (constraints.maxWidth - 24) / 4;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: searchWidth,
                    child: TextField(
                      controller: _taskSearchController,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search tasks, projects or people...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                  ),
                  SizedBox(
                    width: filterWidth,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      key: ValueKey('status:$_statusFilter'),
                      initialValue: _statusFilter,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'all',
                          child: Text('All Statuses'),
                        ),
                        DropdownMenuItem(
                          value: 'pending_acceptance',
                          child: Text('Pending Acceptance'),
                        ),
                        DropdownMenuItem(value: 'todo', child: Text('To Do')),
                        DropdownMenuItem(
                          value: 'in_progress',
                          child: Text('In Progress'),
                        ),
                        DropdownMenuItem(
                          value: 'on_hold',
                          child: Text('On Hold'),
                        ),
                        DropdownMenuItem(
                          value: 'pending',
                          child: Text('Pending'),
                        ),
                        DropdownMenuItem(
                          value: 'completed',
                          child: Text('Completed'),
                        ),
                        DropdownMenuItem(
                          value: 'in_review',
                          child: Text('In Review'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _statusFilter = v);
                      },
                    ),
                  ),
                  SizedBox(
                    width: filterWidth,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      key: ValueKey('priority:$_priorityFilter'),
                      initialValue: _priorityFilter,
                      decoration: const InputDecoration(
                        labelText: 'Priority',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'all',
                          child: Text('All Priorities'),
                        ),
                        DropdownMenuItem(value: 'low', child: Text('Low')),
                        DropdownMenuItem(
                          value: 'medium',
                          child: Text('Medium'),
                        ),
                        DropdownMenuItem(value: 'high', child: Text('High')),
                        DropdownMenuItem(
                          value: 'urgent',
                          child: Text('🚨 Urgent'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _priorityFilter = v);
                      },
                    ),
                  ),
                ],
              );
            },
          ),
          _advancedFilters(),
          _activeFilterSummary(),
        ],
        const SizedBox(height: 16),
        TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          controller: _tabController,
          tabs: const [
            Tab(text: 'My Tasks & Bookings'),
            Tab(text: 'Assigned by Me'),
            Tab(text: 'All-Hands Board'),
            Tab(text: 'Resource Availability Matrix'),
            Tab(text: '⏱️ Timelog & Live Timer'),
          ],
        ),
        const SizedBox(height: 16),
        if (_tabController.index < 3) ...[
          Text(
            '${_filteredTasks(_tabController.index == 0
                ? 'my'
                : _tabController.index == 1
                ? 'assigned_by'
                : 'all_hands').length} matching tasks · filters apply to every task view',
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'list',
                  icon: Icon(Icons.view_list_outlined),
                  label: Text('List'),
                ),
                ButtonSegment(
                  value: 'board',
                  icon: Icon(Icons.view_kanban_outlined),
                  label: Text('Board'),
                ),
                ButtonSegment(
                  value: 'calendar',
                  icon: Icon(Icons.calendar_month_outlined),
                  label: Text('Calendar'),
                ),
                ButtonSegment(
                  value: 'analytics',
                  icon: Icon(Icons.insights_outlined),
                  label: Text('Graphs'),
                ),
              ],
              selected: {_taskView},
              onSelectionChanged: (value) =>
                  setState(() => _taskView = value.first),
            ),
          ),
          const SizedBox(height: 16),
        ],
        _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(child: Text('Error: $_error'))
            : _tabController.index == 4
            ? _buildTimelogTabView()
            : _tabController.index == 3
            ? _buildResourceAvailabilityMatrix()
            : _buildTaskView(
                _filteredTasks(
                  _tabController.index == 0
                      ? 'my'
                      : _tabController.index == 1
                      ? 'assigned_by'
                      : 'all_hands',
                ),
              ),
      ],
    );
  }

  Widget _buildTaskView(List<Map<String, dynamic>> tasks) => WorkspaceReveal(
    key: ValueKey('$_taskView:${_tabController.index}'),
    child: switch (_taskView) {
      'board' => GroupedTaskBoard(
        groupBy: _groupBy,
        tasks: tasks,
        onOpen: _viewTaskDetails,
        employeeName: _employeeName,
      ),
      'calendar' => TaskCalendarView(tasks: tasks, onOpen: _viewTaskDetails),
      'analytics' => TaskAnalyticsView(
        tasks: tasks,
        employeeName: _employeeName,
      ),
      _ => _buildTaskList(tasks),
    },
  );

  List<Map<String, dynamic>> _getEmployeeAssignedTasksForDate(
    String empId,
    DateTime dateOnly,
  ) {
    final list = <Map<String, dynamic>>[];
    for (final task in _tasks) {
      if (task['assignee_id']?.toString() != empId) continue;
      final status = (task['status'] ?? 'todo').toString();
      if (status == 'completed' || status == 'declined') continue;

      final dueDateStr = task['due_date']?.toString();
      DateTime? taskDate;
      if (dueDateStr != null && dueDateStr.isNotEmpty) {
        taskDate = DateTime.tryParse(dueDateStr.split('T')[0]);
      } else {
        final createdStr = task['created_at']?.toString();
        if (createdStr != null && createdStr.isNotEmpty) {
          taskDate = DateTime.tryParse(createdStr.split('T')[0]);
        }
      }

      if (taskDate != null &&
          taskDate.year == dateOnly.year &&
          taskDate.month == dateOnly.month &&
          taskDate.day == dateOnly.day) {
        list.add(task);
      }
    }
    return list;
  }

  void _showResourceDetailDialog(
    String empId,
    String empName,
    DateTime dateOnly,
    double allocatedHours,
    bool onLeave,
  ) {
    final dateStr = '${dateOnly.day}/${dateOnly.month}/${dateOnly.year}';
    final tasks = _getEmployeeAssignedTasksForDate(empId, dateOnly);
    final calendar = CompanyCalendar.of(context);
    final capacity = calendar.works(dateOnly) ? 8.0 : 0.0;
    final freeHours = (capacity - allocatedHours).clamp(0.0, 8.0);
    final progress = capacity == 0 ? 0.0 : (allocatedHours / capacity).clamp(0.0, 1.0);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Resource Availability • $empName'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CalendarDayDetails(calendar: calendar, day: dateOnly, onRemoved: () => Navigator.pop(context)),
              Text(
                'Date: $dateStr',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Daily capacity',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  Text(
                    '${allocatedHours.toStringAsFixed(1)}h / ${capacity.toStringAsFixed(1)}h (${(progress * 100).toStringAsFixed(0)}%)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: allocatedHours > 8.0
                          ? Colors.purple
                          : allocatedHours == 8.0
                          ? Colors.orange
                          : Colors.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 10,
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                  color: allocatedHours > 8.0
                      ? Colors.purple
                      : allocatedHours == 8.0
                      ? Colors.orange
                      : Colors.green,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                capacity == 0 ? 'Non-working day · no capacity available' : freeHours > 0
                    ? '🟢 ${freeHours.toStringAsFixed(1)} Hours Free Available for new tasks'
                    : allocatedHours > 8.0
                    ? '⚠️ Overloaded by ${(allocatedHours - 8.0).toStringAsFixed(1)} Hours'
                    : '🔴 Fully Booked (0h Free)',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Divider(height: 24),
              Text(
                'Visible tasks (${tasks.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              if (tasks.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No task details are visible to you for this date.',
                  ),
                )
              else
                ...tasks.map((t) {
                  final estStr = _extractBookingHours(t['description']);
                  final estNum = double.tryParse(estStr);
                  final taskHours = (estNum != null && estNum > 0)
                      ? estNum
                      : 2.0;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t['title'] ?? 'Task',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                'Status: ${t['status'] ?? 'todo'} • Priority: ${t['priority'] ?? 'medium'}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        StatusBadge(
                          label: '${taskHours.toStringAsFixed(1)}h',
                          color: const Color(0xFF6366F1),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: capacity == 0 || onLeave
                ? null
                : () {
                    Navigator.pop(context);
                    _upsertTask(
                      initialAssigneeId: empId,
                      initialDueDate: dateOnly,
                    );
                  },
            icon: const Icon(Icons.add, size: 16),
            label: Text(
              capacity == 0 ? 'Non-working day' : onLeave
                  ? 'On leave — assignment unavailable'
                  : 'Assign Task',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResourceAvailabilityMatrix() {
    final now = DateTime.now();
    final startDate = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(Duration(days: _matrixStartOffset));
    final dates = List.generate(
      _matrixDayCount,
      (i) => startDate.add(Duration(days: i)),
    );

    final key = '${dates.first.toIso8601String()}/$_matrixDayCount';
    if (_availabilityKey != key) {
      _availabilityKey = key;
      _availabilityRequest = _loadAvailability(dates.first, dates.length);
    }
    return FutureBuilder<List<Map<String,dynamic>>>(
      future: _availabilityRequest,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) {
          final error = snapshot.error;
          final message = switch (error) {
            PostgrestException(code: 'PGRST202') =>
              'Resource availability setup is pending. Ask your workspace administrator to install the availability database function.',
            PostgrestException(code: '42501') =>
              'Access was denied. Ask HR to check your account approval and availability permissions.',
            _ => 'Could not load resource availability. Please retry.',
          };
          return Column(children: [
            Text(message, textAlign: TextAlign.center),
            TextButton(onPressed: () => setState(() => _availabilityKey = null), child: const Text('Retry')),
          ]);
        }
        return _resourceGrid(snapshot.requireData, dates, now);
      },
    );
  }

  Widget _resourceGrid(List<Map<String,dynamic>> resources, List<DateTime> dates, DateTime now) {
    final byId = {for (final resource in resources) resource['id']: resource['days']};
    dynamic dayData(String id, DateTime day) => byId[id]?[day.toIso8601String().split('T').first];
    double hours(String id, DateTime day) => (dayData(id,day)?['hours'] as num?)?.toDouble() ?? 0;
    int totalResources = resources.length;
    int availableResources = 0;
    int busyResources = 0;
    int overutilizedResources = 0;

    for (final p in resources) {
      final empId = p['id']?.toString() ?? '';
      final todayHours = hours(
        empId,
        DateTime(now.year, now.month, now.day),
      );
      if (!CompanyCalendar.of(context).works(now) || dayData(empId,now)?['leave'] == true) {
        continue;
      } else if (todayHours > 8.0) {
        overutilizedResources++;
        busyResources++;
      } else if (todayHours >= 6.0) {
        busyResources++;
      } else {
        availableResources++;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top Summary KPI Cards Header (OrangeScrum Style)
        AdaptiveCards(
          minWidth: 160,
          maxColumns: 4,
              children: [
                MetricCard(
                  title: 'Total Resources',
                  value: '$totalResources',
                  icon: Icons.groups_outlined,
                  accentColor: const Color(0xFF6366F1),
                ),
                MetricCard(
                  title: 'Available Resources',
                  value: '$availableResources',
                  icon: Icons.check_circle_outline,
                  accentColor: Colors.green,
                ),
                MetricCard(
                  title: 'Busy Resources',
                  value: '$busyResources',
                  icon: Icons.work_history_outlined,
                  accentColor: Colors.orange,
                ),
                MetricCard(
                  title: 'Over-Utilized Resources',
                  value: '$overutilizedResources',
                  icon: Icons.warning_amber_outlined,
                  accentColor: Colors.purple,
                ),
              ],
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          tooltip: 'Previous Period',
                          onPressed: () => setState(
                            () => _matrixStartOffset -= _matrixDayCount,
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              setState(() => _matrixStartOffset = 0),
                          child: const Text('Today'),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          tooltip: 'Next Period',
                          onPressed: () => setState(
                            () => _matrixStartOffset += _matrixDayCount,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Displaying ${_formatDateShort(dates.first)} to ${_formatDateShort(dates.last)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SegmentedButton<int>(
                          segments: const [
                            ButtonSegment(value: 7, label: Text('7D')),
                            ButtonSegment(value: 14, label: Text('14D')),
                            ButtonSegment(value: 30, label: Text('30D')),
                          ],
                          selected: {_matrixDayCount},
                          onSelectionChanged: (val) =>
                              setState(() => _matrixDayCount = val.first),
                        ),
                        const SizedBox(width: 12),
                        Wrap(
                          spacing: 10,
                          children: [
                            _legendItem('Free', Colors.green),
                            _legendItem('Booked', Colors.orange),
                            _legendItem('Overloaded', Colors.purple),
                            _legendItem('Leave', Colors.grey),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                const Divider(height: 24),
                LayoutBuilder(
                  builder: (context, constraints) => ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      dragDevices: {
                        PointerDeviceKind.touch,
                        PointerDeviceKind.mouse,
                        PointerDeviceKind.trackpad,
                      },
                    ),
                    child: Scrollbar(
                      controller: _matrixScrollController,
                      thumbVisibility: true,
                      trackVisibility: true,
                      scrollbarOrientation: ScrollbarOrientation.bottom,
                      child: SingleChildScrollView(
                        controller: _matrixScrollController,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.only(bottom: 16),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: constraints.maxWidth,
                          ),
                          child: DataTable(
                            columnSpacing: 20,
                            headingRowHeight: 44,
                            dataRowMinHeight: 48,
                            columns: [
                              const DataColumn(
                                label: Text(
                                  'Resource Name',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              ...dates.map(
                                (d) => DataColumn(
                                  label: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        '${d.day}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                      Text(
                                        CompanyCalendar.of(context).entry(d) == null ? _shortWeekday(d.weekday) : '${_shortWeekday(d.weekday)} •',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            rows: resources.map((p) {
                              final empId = p['id']?.toString() ?? '';
                              final name =
                                  p['full_name']?.toString() ?? 'Employee';

                              double total14DaysAllocated = 0;
                              for (final d in dates) {
                                total14DaysAllocated +=
                                    hours(
                                      empId,
                                      DateTime(d.year, d.month, d.day),
                                    );
                              }
                              final totalCapacityMins = dates.where(CompanyCalendar.of(context).works).length * 8;

                              return DataRow(
                                cells: [
                                  DataCell(
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        Text(
                                          '${total14DaysAllocated.toStringAsFixed(0)}h / ${totalCapacityMins}h',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  ...dates.map((d) {
                                    final dateOnly = DateTime(
                                      d.year,
                                      d.month,
                                      d.day,
                                    );
                                    final onLeave = dayData(empId,dateOnly)?['leave'] == true;
                                    final allocatedHours =
                                        hours(
                                          empId,
                                          dateOnly,
                                        );
                                    final freeH = (8.0 - allocatedHours).clamp(
                                      0.0,
                                      8.0,
                                    );

                                    Color cellColor = Colors.green;
                                    String label = '8h Free';
                                    String tooltipMsg =
                                        'Total: 8h\nBooked: 0h\nAvailable: 8h';

                                    if (!CompanyCalendar.of(context).works(dateOnly)) {
                                      cellColor = Colors.grey;
                                      label = 'Off';
                                      tooltipMsg = CompanyCalendar.of(context).label(dateOnly) ?? 'Weekly off';
                                    } else if (onLeave) {
                                      cellColor = Colors.grey;
                                      label = 'Leave';
                                      tooltipMsg = 'Status: Vacation / Leave';
                                    } else if (allocatedHours > 8.0) {
                                      cellColor = Colors.purple;
                                      label =
                                          '${allocatedHours.toStringAsFixed(1).replaceAll('.0', '')}h Over';
                                      tooltipMsg =
                                          'Overloaded!\nTotal: 8h\nBooked: ${allocatedHours.toStringAsFixed(1)}h\nOverloaded: ${(allocatedHours - 8.0).toStringAsFixed(1)}h';
                                    } else if (allocatedHours == 8.0) {
                                      cellColor = Colors.orange;
                                      label = '8h Full';
                                      tooltipMsg = 'Fully Booked\nTotal: 8h\nBooked: 8h\nAvailable: 0h';
                                    } else if (allocatedHours > 0) {
                                      cellColor = Colors.amber.shade800;
                                      label =
                                          '${allocatedHours.toStringAsFixed(1).replaceAll('.0', '')}h (${freeH.toStringAsFixed(1).replaceAll('.0', '')}h Free)';
                                      tooltipMsg =
                                          'Booked: ${allocatedHours.toStringAsFixed(1)}h\nAvailable: ${freeH.toStringAsFixed(1)}h';
                                    }

                                    final progress = onLeave
                                        ? 0.0
                                        : (allocatedHours / 8.0).clamp(
                                            0.0,
                                            1.0,
                                          );

                                    return DataCell(
                                      Tooltip(
                                        message: tooltipMsg,
                                        child: InkWell(
                                          onTap: () =>
                                              _showResourceDetailDialog(
                                                empId,
                                                name,
                                                dateOnly,
                                                allocatedHours,
                                                onLeave,
                                              ),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          child: _buildResourceCellWidget(
                                            context,
                                            label,
                                            cellColor,
                                            progress,
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResourceCellWidget(
    BuildContext context,
    String label,
    Color color,
    double progress,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: 82,
      height: 38,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF16181F) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
      ),
      child: Stack(
        children: [
          if (progress > 0)
            FractionallySizedBox(
              widthFactor: progress.clamp(0.0, 1.0),
              heightFactor: 1.0,
              child: Container(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isDark ? 0.35 : 0.25),
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateShort(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  String _shortWeekday(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday - 1];
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildTaskList(List<Map<String, dynamic>> tasks) {
    if (tasks.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No tasks match these filters.'),
        ),
      );
    }
    return AdaptiveCards(
      minWidth: 420,
      maxColumns: 2,
      children: [
        for (final task in tasks)
          Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _viewTaskDetails(task),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${task['title'] ?? ''}',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (_isOverdue(task))
                          const Chip(label: Text('Overdue')),
                        Chip(
                          label: Text('${task['priority'] ?? 'medium'}'),
                          backgroundColor: _priorityColor(
                            task['priority'] ?? 'medium',
                          ).withValues(alpha: 0.15),
                        ),
                        Chip(
                          label: Text(_statusLabel(task['status'] ?? 'todo')),
                          backgroundColor: _statusColor(
                            task['status'] ?? 'todo',
                          ).withValues(alpha: 0.15),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _cleanDescription(task['description']),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    Text('Assigned to: ${_employeeName(task['assignee_id'])}'),
                    Text('Assigned by: ${_employeeName(task['creator_id'])}'),
                    Text('Estimate: ${TaskOverviewPanel.estimate(task)}'),
                    Text(
                      'Due: ${task['due_date']?.toString().split('T')[0] ?? 'Not set'}',
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (task['assignee_id']?.toString() == _uid &&
                            task['status'] == 'pending_acceptance') ...[
                          FilledButton.icon(
                            onPressed: () => _acceptBooking(task),
                            icon: const Icon(Icons.check),
                            label: const Text('Accept'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _declineBooking(task),
                            icon: const Icon(Icons.close),
                            label: const Text('Decline'),
                          ),
                        ],
                        OutlinedButton.icon(
                          onPressed: () => _upsertTask(existing: task),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Edit'),
                        ),
                        if (_uid != null &&
                            task['creator_id']?.toString() == _uid)
                          TextButton.icon(
                            onPressed: () => _deleteTask(task),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Delete'),
                          ),
                        TextButton.icon(
                          onPressed: () => _viewTaskDetails(task),
                          icon: const Icon(Icons.chat_bubble_outline),
                          label: const Text('Details & comments'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  String? _timeLogError;
  bool _loadingTimeLogs = false;

  Future<void> _refreshTimeLogs() async {
    if (_loadingTimeLogs || _uid == null) return;
    setState(() {
      _loadingTimeLogs = true;
      _timeLogError = null;
    });
    try {
      final saved = await _db
          .from('task_work_logs')
          .select()
          .eq('employee_id', _uid!)
          .order('created_at', ascending: false);
      if (!mounted) return;
      final merged = <String, Map<String, dynamic>>{
        for (final log in TaskTracker.instance.timelogs.value)
          '${log['id']}': log,
        for (final log in saved) '${log['id']}': log,
      };
      TaskTracker.instance.timelogs.value = merged.values.toList();
    } catch (_) {
      if (mounted) {
        setState(() {
          _timeLogError = 'Could not refresh saved time logs. Please retry.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingTimeLogs = false;
        });
      }
    }
  }

  Widget _buildTimelogTabView() {
    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: TaskTracker.instance.timelogs,
      builder: (context, logs, child) {
        final summaries = summarizeTaskTime(logs);
        final total = summaries.fold<int>(
          0,
          (sum, row) => sum + (row['seconds'] as int),
        );
        final estimated = _tasks
            .where((task) => task['assignee_id']?.toString() == _uid)
            .fold<double>(
              0,
              (sum, task) =>
                  sum + taskBookingHours(task['description']?.toString()),
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, box) => GridView.count(
                crossAxisCount: box.maxWidth >= 800
                    ? 3
                    : box.maxWidth >= 450
                    ? 2
                    : 1,
                mainAxisExtent: 116,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  MetricCard(
                    title: 'Total logged time',
                    value: formatTaskTime(total),
                    icon: Icons.timer_outlined,
                    accentColor: const Color(0xFF6366F1),
                  ),
                  MetricCard(
                    title: 'Tasks with logged time',
                    value: '${summaries.length}',
                    icon: Icons.task_alt,
                    accentColor: Colors.green,
                  ),
                  MetricCard(
                    title: 'Estimated task time',
                    value: formatTaskTime((estimated * 3600).round()),
                    icon: Icons.schedule,
                    accentColor: Colors.orange,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Time by task',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Combined time across all sessions. Use the header timer to track work.',
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Add time entry',
                          onPressed: _showManualTimeEntryDialog,
                          icon: const Icon(Icons.add),
                        ),
                        IconButton(
                          tooltip: 'Refresh saved logs',
                          onPressed: _loadingTimeLogs ? null : _refreshTimeLogs,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    if (_loadingTimeLogs) const LinearProgressIndicator(),
                    if (_timeLogError != null)
                      Text(
                        _timeLogError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    const SizedBox(height: 16),
                    if (summaries.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(Icons.av_timer, size: 40),
                            SizedBox(height: 12),
                            Text('No time logged yet'),
                            SizedBox(height: 4),
                            Text(
                              'Start the header timer on an assigned task to begin.',
                            ),
                          ],
                        ),
                      )
                    else
                      LayoutBuilder(
                        builder: (context, box) => SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minWidth: box.maxWidth),
                            child: DataTable(
                              showCheckboxColumn: false,
                              headingRowColor: WidgetStatePropertyAll(
                                Theme.of(context).colorScheme.primary
                                    .withValues(alpha: 0.06),
                              ),
                              dataRowMinHeight: 64,
                              dataRowMaxHeight: 72,
                              columns: const [
                                DataColumn(label: Text('Task')),
                                DataColumn(label: Text('Status')),
                                DataColumn(
                                  label: Text('Total logged'),
                                  numeric: true,
                                ),
                                DataColumn(label: Text('Last logged')),
                                DataColumn(label: Text('Timer')),
                              ],
                              rows: summaries.map((row) {
                                final date = DateTime.tryParse(
                                  row['last_logged'] as String,
                                )?.toLocal();
                                final dateText = date == null
                                    ? '—'
                                    : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}  ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                                final task = _tasks
                                    .where(
                                      (task) =>
                                          task['id']?.toString() ==
                                          row['task_id']?.toString(),
                                    )
                                    .firstOrNull;
                                final status = task?['status']?.toString();
                                final canTrack =
                                    task != null &&
                                    task['assignee_id']?.toString() == _uid &&
                                    ![
                                      'completed',
                                      'declined',
                                      'pending_acceptance',
                                    ].contains(status);
                                return DataRow(
                                  onSelectChanged: task == null
                                      ? null
                                      : (_) => _viewTaskDetails(task),
                                  cells: [
                                    DataCell(
                                      Text(
                                        '${row['task_title']}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      StatusBadge(
                                        label: status == null
                                            ? 'Unavailable'
                                            : _statusLabel(status),
                                        color: status == null
                                            ? Colors.grey
                                            : _statusColor(status),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        formatTaskTime(row['seconds'] as int),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                    ),
                                    DataCell(Text(dateText)),
                                    DataCell(
                                      ListenableBuilder(
                                        listenable: Listenable.merge([
                                          TaskTracker.instance.activeTask,
                                          TaskTracker.instance.activeSeconds,
                                          TaskTracker.instance.isTimerRunning,
                                        ]),
                                        builder: (context, _) {
                                          final tracker = TaskTracker.instance;
                                          final selected =
                                              tracker.activeTask.value?['id']
                                                  ?.toString() ==
                                              row['task_id']?.toString();
                                          final running =
                                              selected &&
                                              tracker.isTimerRunning.value;
                                          final hasTime =
                                              selected &&
                                              tracker.activeSeconds.value > 0;
                                          return TextButton.icon(
                                            onPressed: !canTrack
                                                ? null
                                                : () {
                                                    try {
                                                      if (running) {
                                                        tracker.pauseTimer();
                                                      } else {
                                                        tracker.startTimer(
                                                          task,
                                                        );
                                                        _viewTaskDetails(task);
                                                      }
                                                    } catch (e) {
                                                      AppToast.of(
                                                        context,
                                                      ).showSnackBar(
                                                        SnackBar(
                                                          content: Text('$e'),
                                                        ),
                                                      );
                                                    }
                                                  },
                                            icon: Icon(
                                              running
                                                  ? Icons.pause
                                                  : Icons.play_arrow,
                                            ),
                                            label: Text(
                                              running
                                                  ? 'Pause'
                                                  : hasTime
                                                  ? 'Resume'
                                                  : 'Start Timer',
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showManualTimeEntryDialog([
    Map<String, dynamic>? initialTask,
  ]) async {
    final eligible = _tasks
        .where(
          (task) =>
              task['assignee_id']?.toString() == _uid &&
              !['pending_acceptance', 'declined'].contains(task['status']),
        )
        .toList();
    final log = await showManualTaskTimeEntry(
      context,
      eligible,
      taskId: initialTask?['id']?.toString(),
    );
    if (log == null) return;
    TaskTracker.instance.addTimelog(log);
    if (mounted)
      AppToast.of(context)
          .showSnackBar(const SnackBar(content: Text('Time entry saved')));
  }
}

class _TaskTimerPanel extends StatefulWidget {
  const _TaskTimerPanel({
    required this.task,
    required this.canTrack,
    this.onManualEntry,
  });
  final Future<void> Function()? onManualEntry;
  final Map<String, dynamic> task;
  final bool canTrack;

  @override
  State<_TaskTimerPanel> createState() => _TaskTimerPanelState();
}

class _TaskTimerPanelState extends State<_TaskTimerPanel> {
  final _note = TextEditingController();
  late Future<List<Map<String, dynamic>>> _logs;
  bool _saving = false;
  final Set<String> _deleting = {};

  Future<List<Map<String, dynamic>>> _loadLogs() async => await Supabase
      .instance
      .client
      .from('task_work_logs')
      .select()
      .eq('task_id', widget.task['id'])
      .order('created_at', ascending: false);

  @override
  void initState() {
    super.initState();
    _logs = _loadLogs();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _refreshLogs() {
    final logs = _loadLogs();
    setState(() {
      _logs = logs;
    });
  }

  Future<void> _deleteLog(Map<String, dynamic> log) async {
    final db = Supabase.instance.client;
    final uid = db.auth.currentUser?.id;
    final id = log['id'].toString();
    if (uid == null || log['employee_id'] != uid || _deleting.contains(id))
      return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete time entry?'),
        content: Text(
          'Remove ${formatTaskTime((log['logged_seconds'] as num).toInt())} from this task’s logged time? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _deleting.add(id);
    });
    try {
      final removed = await db
          .from('task_work_logs')
          .delete()
          .eq('id', id)
          .eq('employee_id', uid)
          .select('id');
      if (removed.isEmpty) {
        throw StateError('Entry was not deleted. Check your permissions.');
      }
      final tracker = TaskTracker.instance;
      tracker.timelogs.value = tracker.timelogs.value
          .where((row) => row['id'].toString() != id)
          .toList();
      if (!mounted) return;
      _refreshLogs();
      AppToast.of(context)
          .showSnackBar(const SnackBar(content: Text('Time entry deleted')));
    } catch (e) {
      if (mounted) {
        AppToast.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not delete entry: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _deleting.remove(id);
        });
      }
    }
  }

  String _clock(int seconds) =>
      '${(seconds ~/ 3600).toString().padLeft(2, '0')}:${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';

  Future<void> _save() async {
    final tracker = TaskTracker.instance;
    if (_saving || tracker.activeTask.value?['id'] != widget.task['id']) return;
    setState(() => _saving = true);
    try {
      await tracker.stopAndLogTimer(_note.text.trim());
      if (!mounted) return;
      _note.clear();
      _refreshLogs();
    } catch (e) {
      if (mounted) {
        AppToast.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not save time log: $e. Your elapsed time is retained.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tracker = TaskTracker.instance;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Task timer & work logs',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (widget.onManualEntry != null)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add Time Entry'),
                    onPressed: () async {
                      await widget.onManualEntry!();
                      if (mounted) _refreshLogs();
                    },
                  ),
              ],
            ),
            if (widget.canTrack)
              ListenableBuilder(
                listenable: Listenable.merge([
                  tracker.activeTask,
                  tracker.activeSeconds,
                  tracker.isTimerRunning,
                ]),
                builder: (context, _) {
                  final selected =
                      tracker.activeTask.value?['id'] == widget.task['id'];
                  final running = selected && tracker.isTimerRunning.value;
                  final seconds = selected ? tracker.activeSeconds.value : 0;
                  final otherUnsaved =
                      !selected && tracker.activeSeconds.value > 0;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      Text(
                        _clock(seconds),
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      if (otherUnsaved)
                        const Text(
                          'Save the timer on the other task before starting this one.',
                        ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _note,
                        enabled: !_saving,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Work details (optional)',
                          hintText: 'What did you work on?',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: _saving || otherUnsaved
                                ? null
                                : () {
                                    if (running) {
                                      tracker.pauseTimer();
                                    } else {
                                      tracker.startTimer(widget.task);
                                    }
                                  },
                            icon: Icon(
                              running ? Icons.pause : Icons.play_arrow,
                            ),
                            label: Text(
                              running
                                  ? 'Pause Timer'
                                  : seconds > 0
                                  ? 'Resume Timer'
                                  : 'Start Timer',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _saving || seconds == 0 ? null : _save,
                            icon: const Icon(Icons.save_outlined),
                            label: Text(
                              _saving ? 'Saving…' : 'Stop & Save Log',
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            const Divider(height: 24),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _logs,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return TextButton(
                    onPressed: _refreshLogs,
                    child: const Text('Could not load time logs. Retry'),
                  );
                }
                if (!snapshot.hasData) return const LinearProgressIndicator();
                final logs = snapshot.data!;
                final total = logs.fold<int>(
                  0,
                  (sum, row) => sum + (row['logged_seconds'] as num).toInt(),
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Logged time',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Chip(
                          avatar: const Icon(Icons.timer_outlined, size: 18),
                          label: Text(_clock(total)),
                        ),
                        Text(
                          '${logs.length} ${logs.length == 1 ? 'entry' : 'entries'}',
                        ),
                      ],
                    ),
                    if (logs.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('No time logged for this task yet.'),
                      ),
                    for (final log in logs)
                      TaskWorkLogEntry(
                        log: log,
                        deleting: _deleting.contains(log['id'].toString()),
                        onDelete:
                            log['employee_id'] ==
                                Supabase.instance.client.auth.currentUser?.id
                            ? () => _deleteLog(log)
                            : null,
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
