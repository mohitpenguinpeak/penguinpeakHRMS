import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/theme/design_system.dart';
import 'features/leave/domain/leave_request.dart';
import 'features/tasks/domain/task_query.dart';
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

  final ValueNotifier<List<Map<String, dynamic>>> timelogs =
      ValueNotifier<List<Map<String, dynamic>>>([]);

  void startTimer(Map<String, dynamic> task) {
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

  void stopAndLogTimer(String note) {
    pauseTimer();
    final secs = activeSeconds.value;
    if (secs > 0 && activeTask.value != null) {
      final hours = secs ~/ 3600;
      final mins = (secs % 3600) ~/ 60;
      addTimelog({
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'task_id': activeTask.value!['id'],
        'task_title': activeTask.value!['title'] ?? 'Task',
        'logged_seconds': secs,
        'logged_hours_fmt':
            '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}',
        'note': note,
        'date': DateTime.now().toIso8601String().split('T')[0],
        'created_at': DateTime.now().toIso8601String(),
      });
      activeSeconds.value = 0;
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
    this.onTargetConsumed,
  });
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

  String? get _uid => _db.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadData();
  }

  @override
  void dispose() {
    _taskSearchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tasksRes = await _db
          .from('tasks')
          .select('*, task_comments(*)')
          .order('created_at', ascending: false);
      _tasks = List<Map<String, dynamic>>.from(tasksRes);

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
            ScaffoldMessenger.of(context).showSnackBar(
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
        return Colors.redAccent;
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
        return 'Blocked';
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Booking accepted! Task is now In Progress.'),
          backgroundColor: Colors.green,
        ),
      );
      _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Booking request declined.'),
          backgroundColor: Colors.orange,
        ),
      );
      _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error declining booking: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _upsertTask({Map<String, dynamic>? existing}) async {
    final isEdit = existing != null;
    final titleController = TextEditingController(
      text: existing?['title'] ?? '',
    );
    final projectController = TextEditingController(
      text: existing?['project']?.toString() ?? '',
    );
    final rawDesc = _cleanDescription(existing?['description']);
    final descController = TextEditingController(
      text: rawDesc == 'No description provided.' ? '' : rawDesc,
    );
    String assigneeId = existing?['assignee_id']?.toString() ?? _uid ?? '';
    String initialStatus =
        existing?['status'] ??
        (assigneeId != _uid ? 'pending_acceptance' : 'todo');
    String priority = existing?['priority'] ?? 'medium';
    final hoursController = TextEditingController(
      text: _extractBookingHours(existing?['description']),
    );
    DateTime? dueDate = isEdit
        ? DateTime.tryParse('${existing['due_date']}')
        : DateTime.now().add(const Duration(days: 3));

    final route = DialogRoute<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final nextAvail = assigneeId.isNotEmpty
              ? _findNextAvailableDate(assigneeId)
              : DateTime.now();
          final isAvailToday = nextAvail.difference(DateTime.now()).inDays <= 0;

          return AlertDialog(
            title: Text(
              isEdit ? 'Edit Resource Task' : 'Book Resource / Assign Task',
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
                      decoration: const InputDecoration(
                        labelText: 'Task Title / Deliverable *',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: projectController,
                      decoration: const InputDecoration(labelText: 'Project'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descController,
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
                            value: initialStatus,
                            decoration: const InputDecoration(
                              labelText: 'Status',
                            ),
                            items: const [
                              DropdownMenuItem(
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
                                value: 'blocked',
                                child: Text('Blocked'),
                              ),
                              DropdownMenuItem(
                                value: 'declined',
                                child: Text('Declined'),
                              ),
                              DropdownMenuItem(
                                value: 'completed',
                                child: Text('Completed'),
                              ),
                            ],
                            onChanged: (v) {
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
                            !_profiles.any(
                              (p) => p['id'].toString() == assigneeId,
                            ))
                          DropdownMenuItem(
                            value: assigneeId,
                            child: const Text('Current assignee (unavailable)'),
                          ),
                        ..._profiles.map(
                          (p) => DropdownMenuItem(
                            value: p['id'].toString(),
                            child: Text(
                              '${p['full_name']} (${p['department'] ?? 'General'})',
                            ),
                          ),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() {
                            assigneeId = v;
                            if (!isEdit && assigneeId != _uid) {
                              initialStatus = 'pending_acceptance';
                            }
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: hoursController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Estimated Booking Hours',
                      ),
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
                          onPressed: () async {
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
                            onPressed: () =>
                                setDialogState(() => dueDate = null),
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Task title is required')),
                    );
                    return;
                  }
                  try {
                    if (assigneeId.isEmpty)
                      throw const FormatException('Select an assignee.');
                    final hours = hoursController.text.trim();
                    final userDesc = descController.text.trim();
                    final estimate = double.tryParse(hours);
                    if (hours.isNotEmpty &&
                        (estimate == null ||
                            !estimate.isFinite ||
                            estimate < 0)) {
                      throw const FormatException(
                        'Estimated hours must be a non-negative number.',
                      );
                    }
                    final fullDesc = hours.isEmpty
                        ? userDesc
                        : '[Booking: $hours hrs] $userDesc';

                    final data = {
                      'title': titleController.text.trim(),
                      'description': fullDesc,
                      'status': initialStatus,
                      'priority': priority,
                      'assignee_id': assigneeId,
                      if (!isEdit) 'creator_id': _uid,
                      'project': projectController.text.trim(),
                      'completed_at': initialStatus == 'completed'
                          ? (existing?['completed_at'] ??
                                DateTime.now().toUtc().toIso8601String())
                          : null,
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isEdit
                              ? 'Booking updated'
                              : assigneeId != _uid
                              ? 'Resource booked! Sent acceptance request to ${_employeeName(assigneeId)}.'
                              : 'Task created successfully',
                        ),
                      ),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error saving booking: $e')),
                    );
                  }
                },
                child: Text(isEdit ? 'Save Booking' : 'Book & Send Request'),
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
                    TaskOverviewPanel(task: task, employeeName: _employeeName),
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
                        if (TaskTracker.instance.activeTask.value?['id'] ==
                            task['id'])
                          const Chip(
                            label: Text('Active Task'),
                            backgroundColor: Colors.amber,
                          )
                        else if (!isPending &&
                            task['status'] != 'completed' &&
                            task['status'] != 'declined')
                          OutlinedButton.icon(
                            onPressed: () {
                              TaskTracker.instance.activeTask.value = task;
                              if (task['status'] == 'todo') {
                                _db
                                    .from('tasks')
                                    .update({'status': 'in_progress'})
                                    .eq('id', task['id'])
                                    .then((_) => _loadData());
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Set as Active Task for break continuity',
                                  ),
                                ),
                              );
                              setDialogState(() {});
                            },
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Set Active'),
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
                              ScaffoldMessenger.of(context).showSnackBar(
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
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
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
                          value: 'blocked',
                          child: Text('Blocked'),
                        ),
                        DropdownMenuItem(
                          value: 'declined',
                          child: Text('Declined'),
                        ),
                        DropdownMenuItem(
                          value: 'completed',
                          child: Text('Completed'),
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

  double _getEmployeeAllocatedHours(String empId, DateTime dateOnly) {
    double totalMins = 0;
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
        final estStr = _extractBookingHours(task['description']);
        final estNum = double.tryParse(estStr);
        final taskHours = (estNum != null && estNum > 0) ? estNum : 2.0;
        totalMins += (taskHours * 60);
      }
    }
    return totalMins / 60.0;
  }

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
  ) {
    final dateStr = '${dateOnly.day}/${dateOnly.month}/${dateOnly.year}';
    final tasks = _getEmployeeAssignedTasksForDate(empId, dateOnly);
    final freeHours = (8.0 - allocatedHours).clamp(0.0, 8.0);
    final progress = (allocatedHours / 8.0).clamp(0.0, 1.0);

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
              Text(
                'Date: $dateStr',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Daily Capacity (8h Limit)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  Text(
                    '${allocatedHours.toStringAsFixed(1)}h / 8.0h (${(progress * 100).toStringAsFixed(0)}%)',
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
                freeHours > 0
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
                'Assigned Tasks (${tasks.length})',
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
                    'No tasks assigned to this resource for this date.',
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
            onPressed: () {
              Navigator.pop(context);
              _upsertTask();
            },
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Assign Task'),
          ),
        ],
      ),
    );
  }

  Widget _buildResourceAvailabilityMatrix() {
    final now = DateTime.now();
    final dates = List.generate(14, (i) => now.add(Duration(days: i)));

    int totalResources = _profiles.length;
    int availableResources = 0;
    int busyResources = 0;
    int overutilizedResources = 0;

    for (final p in _profiles) {
      final empId = p['id']?.toString() ?? '';
      final todayHours = _getEmployeeAllocatedHours(
        empId,
        DateTime(now.year, now.month, now.day),
      );
      if (todayHours > 8.0) {
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
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 800;
            return GridView.count(
              crossAxisCount: isWide ? 4 : 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: isWide ? 2.0 : 1.5,
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
            );
          },
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Displaying ${_formatDateShort(dates.first)} to ${_formatDateShort(dates.last)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Wrap(
                      spacing: 12,
                      children: [
                        _legendItem('Available (Free Hours)', Colors.green),
                        _legendItem('Booked', Colors.orange),
                        _legendItem('Overloaded (>8h)', Colors.purple),
                        _legendItem('Vacation / Leave', Colors.grey),
                      ],
                    ),
                  ],
                ),
                const Divider(height: 24),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
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
                                _shortWeekday(d.weekday),
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
                    rows: _profiles.map((p) {
                      final empId = p['id']?.toString() ?? '';
                      final name = p['full_name']?.toString() ?? 'Employee';

                      double total14DaysAllocated = 0;
                      for (final d in dates) {
                        total14DaysAllocated += _getEmployeeAllocatedHours(
                          empId,
                          DateTime(d.year, d.month, d.day),
                        );
                      }
                      final totalCapacityMins = dates.length * 8;

                      return DataRow(
                        cells: [
                          DataCell(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
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
                            final dateOnly = DateTime(d.year, d.month, d.day);
                            final onLeave = _isEmployeeOnLeave(empId, dateOnly);
                            final allocatedHours = _getEmployeeAllocatedHours(
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

                            if (onLeave) {
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
                                : (allocatedHours / 8.0).clamp(0.0, 1.0);

                            return DataCell(
                              Tooltip(
                                message: tooltipMsg,
                                child: InkWell(
                                  onTap: () => _showResourceDetailDialog(
                                    empId,
                                    name,
                                    dateOnly,
                                    allocatedHours,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
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

  Widget _buildTimelogTabView() {
    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: TaskTracker.instance.timelogs,
      builder: (context, logs, child) {
        int totalSeconds = logs.fold<int>(
          0,
          (sum, log) => sum + ((log['logged_seconds'] as num?)?.toInt() ?? 0),
        );
        final totalHours = totalSeconds ~/ 3600;
        final totalMins = (totalSeconds % 3600) ~/ 60;
        final loggedHoursStr =
            '${totalHours.toString().padLeft(2, '0')}:${totalMins.toString().padLeft(2, '0')}';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Summary KPI Cards Header (OrangeScrum Style)
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 800;
                return GridView.count(
                  crossAxisCount: isWide ? 4 : 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: isWide ? 2.0 : 1.5,
                  children: [
                    MetricCard(
                      title: 'Estimated Hours',
                      value: '82:00',
                      icon: Icons.timer_outlined,
                      accentColor: Colors.amber,
                    ),
                    MetricCard(
                      title: 'Logged Hours',
                      value: loggedHoursStr,
                      icon: Icons.check_circle_outline,
                      accentColor: Colors.green,
                    ),
                    MetricCard(
                      title: 'Billable Hours',
                      value: '0:00',
                      icon: Icons.attach_money,
                      accentColor: Colors.blue,
                    ),
                    MetricCard(
                      title: 'Non-Billable Hours',
                      value: loggedHoursStr,
                      icon: Icons.work_outline,
                      accentColor: Colors.purple,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            // Live Digital Timer Card
            GlassCard(
              padding: const EdgeInsets.all(20),
              child: ValueListenableBuilder<int>(
                valueListenable: TaskTracker.instance.activeSeconds,
                builder: (context, secs, child) {
                  final h = (secs ~/ 3600).toString().padLeft(2, '0');
                  final m = ((secs % 3600) ~/ 60).toString().padLeft(2, '0');
                  final s = (secs % 60).toString().padLeft(2, '0');
                  final clockStr = '$h:$m:$s';
                  final activeTask = TaskTracker.instance.activeTask.value;
                  final isRunning = TaskTracker.instance.isTimerRunning.value;

                  return Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Live Task Timer',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                activeTask != null
                                    ? 'Tracking: ${activeTask['title']}'
                                    : 'No active task selected for timing',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                          StatusBadge(
                            label: isRunning ? 'TIMING ACTIVE ⏱️' : 'PAUSED',
                            color: isRunning ? Colors.green : Colors.grey,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        clockStr,
                        style: const TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          color: Color(0xFF6366F1),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          if (isRunning) ...[
                            OutlinedButton.icon(
                              onPressed: () {
                                TaskTracker.instance.pauseTimer();
                                setState(() {});
                              },
                              icon: const Icon(Icons.pause),
                              label: const Text('Pause Timer'),
                            ),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.orange,
                              ),
                              onPressed: () {
                                TaskTracker.instance.stopAndLogTimer(
                                  'Live task timer logged.',
                                );
                                setState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('⏱️ Time logged!'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              },
                              icon: const Icon(Icons.stop),
                              label: const Text('Stop & Save Log'),
                            ),
                          ] else
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.green,
                              ),
                              onPressed: () {
                                if (_tasks.isNotEmpty) {
                                  TaskTracker.instance.startTimer(
                                    activeTask ?? _tasks.first,
                                  );
                                  setState(() {});
                                }
                              },
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Start Timer'),
                            ),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                            ),
                            onPressed: () => _showManualTimeEntryDialog(),
                            icon: const Icon(Icons.add_task),
                            label: const Text('Log Time Entry'),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            // Timelog Entries Table (OrangeScrum Style)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Task Timelogs',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '${logs.length} timelog entries',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (logs.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            'No timelogs recorded yet. Click "Log Time Entry" or "Start Timer" on a task.',
                          ),
                        ),
                      )
                    else
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(
                              label: Text(
                                'DATE',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'TASK TITLE',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'LOGGED HOURS',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'NOTE',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'ACTIONS',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                          rows: logs.map((log) {
                            return DataRow(
                              cells: [
                                DataCell(
                                  Text(
                                    log['date']?.toString() ?? '-',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    log['task_title']?.toString() ?? '-',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  StatusBadge(
                                    label:
                                        log['logged_hours_fmt']?.toString() ??
                                        '00:00',
                                    color: Colors.green,
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    log['note']?.toString() ?? '—',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                DataCell(
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 18,
                                      color: Colors.red,
                                    ),
                                    onPressed: () {
                                      TaskTracker
                                          .instance
                                          .timelogs
                                          .value = TaskTracker
                                          .instance
                                          .timelogs
                                          .value
                                          .where((l) => l['id'] != log['id'])
                                          .toList();
                                    },
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
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

  void _showManualTimeEntryDialog([Map<String, dynamic>? initialTask]) {
    Map<String, dynamic>? selectedTask =
        initialTask ?? (_tasks.isNotEmpty ? _tasks.first : null);
    final hoursController = TextEditingController(text: '1');
    final minsController = TextEditingController(text: '0');
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Log Time Entry for Task'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<Map<String, dynamic>>(
                    value: selectedTask,
                    decoration: const InputDecoration(
                      labelText: 'Select Task *',
                    ),
                    items: _tasks
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(t['title'] ?? 'Task'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setDialogState(() => selectedTask = v),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: hoursController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Hours'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: minsController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Minutes',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Work Note / Description',
                    ),
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
              onPressed: () {
                if (selectedTask == null) return;
                final h = int.tryParse(hoursController.text.trim()) ?? 0;
                final m = int.tryParse(minsController.text.trim()) ?? 0;
                final totalSecs = (h * 3600) + (m * 60);

                if (totalSecs <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter valid hours or minutes.'),
                    ),
                  );
                  return;
                }

                TaskTracker.instance.addTimelog({
                  'id': DateTime.now().millisecondsSinceEpoch.toString(),
                  'task_id': selectedTask!['id'],
                  'task_title': selectedTask!['title'] ?? 'Task',
                  'logged_seconds': totalSecs,
                  'logged_hours_fmt':
                      '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}',
                  'note': noteController.text.trim(),
                  'date': DateTime.now().toIso8601String().split('T')[0],
                  'created_at': DateTime.now().toIso8601String(),
                });

                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ Time logged successfully!'),
                    backgroundColor: Colors.green,
                  ),
                );
                setState(() {});
              },
              child: const Text('Save Timelog'),
            ),
          ],
        ),
      ),
    );
  }
}
