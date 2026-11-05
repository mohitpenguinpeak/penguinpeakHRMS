import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'task_management_screen.dart';
import 'shared/widgets/adaptive_layout.dart';

class AttendanceManagementScreen extends StatefulWidget {
  final String role;

  const AttendanceManagementScreen({super.key, required this.role});

  @override
  State<AttendanceManagementScreen> createState() =>
      _AttendanceManagementScreenState();
}

class _AttendanceManagementScreenState
    extends State<AttendanceManagementScreen> {
  final SupabaseClient _db = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  bool _actionInProgress = false;
  bool _refreshInProgress = false;
  Timer? _syncTimer;

  List<Map<String, dynamic>> _profiles = [];
  List<Map<String, dynamic>> _myAttendance = [];
  List<Map<String, dynamic>> _allAttendance = [];
  List<Map<String, dynamic>> _myBreaks = [];
  List<Map<String, dynamic>> _correctionRequests = [];
  Map<String, dynamic>? _companySettings;

  // Filters for HR/Admin view
  String _searchQuery = '';
  String _departmentFilter = 'All';
  String _statusFilter = 'All';

  // Selected tab in employee/HR view
  int _selectedTab = 0; // 0: My Attendance, 1: HR Overview (if privileged), 2: Correction Requests
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  bool _showDetailedTable = false;

  String? get _uid => _db.auth.currentUser?.id;
  bool get _isPrivileged =>
      ['hr', 'admin', 'super_admin', 'management'].contains(widget.role);
  bool get _isHrOrAdmin => ['hr', 'admin', 'super_admin'].contains(widget.role);
  static const _breakTypes = ['Meal', 'Rest', 'Personal', 'Prayer', 'Other'];

  @override
  void initState() {
    super.initState();
    _loadData();
    _syncTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && !_actionInProgress && !_loading) {
        _loadData(showLoading: false);
      }
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData({bool showLoading = true}) async {
    if (_refreshInProgress) return;
    _refreshInProgress = true;
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final uid = _uid;
      if (uid == null) throw Exception('Session expired. Please log in again.');

      // Load company settings
      final settingsRes = await _db
          .from('company_attendance_settings')
          .select('*')
          .maybeSingle();
      _companySettings =
          settingsRes ??
          {
            'work_start_time': '09:00:00',
            'work_end_time': '17:00:00',
            'grace_period_minutes': 15,
            'half_day_hours': 4.0,
            'breaks_enabled': true,
            'timezone': 'UTC',
          };

      // Load profiles
      final profilesRes = await _db
          .from('profiles')
          .select(
            'id, full_name, department, designation, role, approval_status',
          )
          .order('full_name');
      _profiles = List<Map<String, dynamic>>.from(profilesRes);

      // Load my attendance records
      final myAttRes = await _db
          .from('attendance_records')
          .select('*, attendance_breaks(*)')
          .eq('employee_id', uid)
          .order('attendance_date', ascending: false);
      _myAttendance = List<Map<String, dynamic>>.from(myAttRes);

      // Load active breaks for today's record if any
      _myBreaks = [];
      final todayStr = _formatDate(DateTime.now());
      final todayRec = _myAttendance.firstWhere(
        (r) => r['attendance_date']?.toString() == todayStr,
        orElse: () => {},
      );
      if (todayRec.isNotEmpty && todayRec['attendance_breaks'] != null) {
        _myBreaks = List<Map<String, dynamic>>.from(
          todayRec['attendance_breaks'],
        );
      }

      // Load all attendance if privileged
      if (_isPrivileged) {
        final allAttRes = await _db
            .from('attendance_records')
            .select('*, attendance_breaks(*)')
            .order('attendance_date', ascending: false)
            .limit(500);
        _allAttendance = List<Map<String, dynamic>>.from(allAttRes);
      }

      // Load correction requests
      final corrRes = await _db
          .from('attendance_correction_requests')
          .select('*')
          .order('created_at', ascending: false);
      _correctionRequests = List<Map<String, dynamic>>.from(corrRes);

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    } finally {
      _refreshInProgress = false;
    }
  }

  String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String _formatTime(String? isoString) {
    if (isoString == null) return '-';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '-';
    }
  }

  String _formatDuration(int minutes) {
    if (minutes <= 0) return '0m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    return '${h}h ${m}m';
  }

  String _employeeName(String? empId) {
    if (empId == null) return 'Unknown';
    for (var p in _profiles) {
      if (p['id']?.toString() == empId) {
        return p['full_name']?.toString() ?? 'Employee';
      }
    }
    return 'Employee';
  }

  String _employeeDepartment(String? empId) {
    if (empId == null) return '-';
    for (var p in _profiles) {
      if (p['id']?.toString() == empId) {
        return p['department']?.toString() ?? '-';
      }
    }
    return '-';
  }

  // --- ACTIONS ---

  Future<void> _checkIn() async {
    if (_actionInProgress) return;
    setState(() => _actionInProgress = true);
    try {
      final uid = _uid;
      if (uid == null) throw Exception('Session expired');

      final todayStr = _formatDate(DateTime.now());
      // Check if already checked in today
      final existing = _myAttendance.firstWhere(
        (r) => r['attendance_date']?.toString() == todayStr,
        orElse: () => {},
      );

      if (existing.isNotEmpty && existing['check_out'] == null) {
        throw Exception(
          'You are already checked in. Check out before starting another session.',
        );
      }

      final nowIso = DateTime.now().toUtc().toIso8601String();

      // Calculate late status
      int lateMinutes = (existing['late_minutes'] as num?)?.toInt() ?? 0;
      String status = existing['status']?.toString() ?? 'Present';
      if (_companySettings != null) {
        final startParts = (_companySettings!['work_start_time'] ?? '09:00:00')
            .toString()
            .split(':');
        final grace =
            int.tryParse(
              _companySettings!['grace_period_minutes'].toString(),
            ) ??
            15;
        final nowLocal = DateTime.now();
        final scheduledStart = DateTime(
          nowLocal.year,
          nowLocal.month,
          nowLocal.day,
          int.parse(startParts[0]),
          int.parse(startParts[1]),
        );
        final diffMins = nowLocal.difference(scheduledStart).inMinutes;
        if (existing.isEmpty && diffMins > grace) {
          lateMinutes = diffMins - grace;
          status = 'Late';
        }
      }

      if (existing.isNotEmpty) {
        final sessions = List<Map<String, dynamic>>.from(
          (existing['work_sessions'] as List? ?? []).map(
            (s) => Map<String, dynamic>.from(s as Map),
          ),
        );
        if (sessions.isEmpty && existing['check_in'] != null) {
          final legacy = {
            'check_in': existing['check_in'],
            'check_out': existing['check_out'],
            'work_duration_minutes': existing['work_duration_minutes'] ?? 0,
          };
          legacy['work_duration_minutes'] = _durationForSession(
            existing,
            legacy,
            0,
          );
          sessions.add(legacy);
        } else {
          for (var i = 0; i < sessions.length; i++) {
            sessions[i]['work_duration_minutes'] = _durationForSession(
              existing,
              sessions[i],
              i,
            );
          }
        }
        sessions.add({
          'check_in': nowIso,
          'check_out': null,
          'work_duration_minutes': 0,
        });
        await _db
            .from('attendance_records')
            .update({
              'work_sessions': sessions,
              'check_out': null,
              'status': status,
              'late_minutes': lateMinutes,
              'updated_at': nowIso,
            })
            .eq('id', existing['id']);
      } else {
        await _db.from('attendance_records').insert({
          'employee_id': uid,
          'attendance_date': todayStr,
          'check_in': nowIso,
          'status': status,
          'late_minutes': lateMinutes,
          'work_sessions': [
            {'check_in': nowIso, 'check_out': null, 'work_duration_minutes': 0},
          ],
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Successfully checked in!'),
          backgroundColor: Colors.green,
        ),
      );
      await _loadData(showLoading: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Check-in failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  Future<void> _checkOut() async {
    if (_actionInProgress) return;
    setState(() => _actionInProgress = true);
    try {
      final uid = _uid;
      if (uid == null) throw Exception('Session expired');

      final todayStr = _formatDate(DateTime.now());
      final existing = _myAttendance.firstWhere(
        (r) => r['attendance_date']?.toString() == todayStr,
        orElse: () => {},
      );

      if (existing.isEmpty || existing['check_in'] == null) {
        throw Exception('No active check-in found for today.');
      }
      if (existing['check_out'] != null) {
        throw Exception('You have already checked out today.');
      }

      // Check if any break is still active
      for (var b in _myBreaks) {
        if (b['break_end'] == null) {
          throw Exception('Please end your active break before checking out.');
        }
      }

      final sessions = List<Map<String, dynamic>>.from(
        (existing['work_sessions'] as List? ?? []).map(
          (s) => Map<String, dynamic>.from(s as Map),
        ),
      );
      if (sessions.isEmpty) {
        sessions.add({
          'check_in': existing['check_in'],
          'check_out': null,
          'work_duration_minutes': 0,
        });
      }
      final sessionIndex = sessions.lastIndexWhere(
        (s) => s['check_out'] == null,
      );
      if (sessionIndex < 0) throw Exception('No open work session found.');
      final checkInTime = DateTime.parse(
        sessions[sessionIndex]['check_in'].toString(),
      );
      final now = DateTime.now();
      if (now.isBefore(checkInTime)) {
        throw Exception('Check-out time cannot be earlier than check-in time.');
      }

      final grossMinutes = now.difference(checkInTime).inMinutes;
      int breakMinutes = 0;
      for (var b in _myBreaks.where(
        (b) => ((b['session_index'] as num?)?.toInt() ?? 0) == sessionIndex,
      )) {
        breakMinutes += ((b['duration_minutes'] as num?)?.toInt() ?? 0);
      }
      final netMinutes = (grossMinutes - breakMinutes).clamp(0, 1440).toInt();
      sessions[sessionIndex] = {
        ...sessions[sessionIndex],
        'check_out': now.toUtc().toIso8601String(),
        'work_duration_minutes': netMinutes,
      };
      for (var i = 0; i < sessions.length; i++) {
        sessions[i]['work_duration_minutes'] = _durationForSession(
          existing,
          sessions[i],
          i,
        );
      }
      final totalWorkMinutes = sessions.fold<int>(
        0,
        (sum, session) =>
            sum + ((session['work_duration_minutes'] as num?)?.toInt() ?? 0),
      );
      final totalBreakMinutes = _myBreaks.fold<int>(
        0,
        (sum, b) => sum + ((b['duration_minutes'] as num?)?.toInt() ?? 0),
      );

      // Check half day threshold
      String status = existing['status'] ?? 'Present';
      final halfDayHours =
          double.tryParse(
            _companySettings?['half_day_hours']?.toString() ?? '4.0',
          ) ??
          4.0;
      if (totalWorkMinutes < (halfDayHours * 60) && status != 'Late') {
        status = 'Half Day';
      }

      final nowIso = now.toUtc().toIso8601String();

      await _db
          .from('attendance_records')
          .update({
            'check_out': nowIso,
            'work_sessions': sessions,
            'work_duration_minutes': totalWorkMinutes,
            'break_duration_minutes': totalBreakMinutes,
            'status': status,
            'updated_at': nowIso,
          })
          .eq('id', existing['id']);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Successfully checked out!'),
          backgroundColor: Colors.green,
        ),
      );
      await _loadData(showLoading: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Check-out failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  Future<void> _startBreak() async {
    if (_actionInProgress) return;
    setState(() => _actionInProgress = true);
    try {
      final todayStr = _formatDate(DateTime.now());
      final existing = _myAttendance.firstWhere(
        (r) => r['attendance_date']?.toString() == todayStr,
        orElse: () => {},
      );

      if (existing.isEmpty ||
          existing['check_in'] == null ||
          existing['check_out'] != null) {
        throw Exception(
          'You must be checked in (and not checked out) to start a break.',
        );
      }

      for (var b in _myBreaks) {
        if (b['break_end'] == null) {
          throw Exception('You already have an active break.');
        }
      }

      final breakType = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Choose break type'),
          children: [
            for (final type in _breakTypes)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, type),
                child: Text(type),
              ),
          ],
        ),
      );
      if (breakType == null) return;

      // Save active task before starting break for Smart Break Continuity
      TaskTracker.instance.saveTaskBeforeBreak(
        TaskTracker.instance.activeTask.value,
      );

      final nowIso = DateTime.now().toUtc().toIso8601String();
      final sessions = List<Map<String, dynamic>>.from(
        (existing['work_sessions'] as List? ?? []).map(
          (s) => Map<String, dynamic>.from(s as Map),
        ),
      );
      final sessionIndex = sessions.lastIndexWhere(
        (s) => s['check_out'] == null,
      );
      await _db.from('attendance_breaks').insert({
        'attendance_id': existing['id'],
        'break_start': nowIso,
        'break_type': breakType,
        'session_index': sessionIndex < 0 ? 0 : sessionIndex,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Break started. Active task preserved.'),
          backgroundColor: Colors.orange,
        ),
      );
      await _loadData(showLoading: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start break: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  Future<void> _endBreak() async {
    if (_actionInProgress) return;
    setState(() => _actionInProgress = true);
    try {
      final activeBreak = _myBreaks.firstWhere(
        (b) => b['break_end'] == null,
        orElse: () => {},
      );

      if (activeBreak.isEmpty) {
        throw Exception('No active break found.');
      }

      final breakStart = DateTime.parse(activeBreak['break_start']);
      final now = DateTime.now();
      final durationMins = now.difference(breakStart).inMinutes;
      final nowIso = now.toUtc().toIso8601String();

      await _db
          .from('attendance_breaks')
          .update({
            'break_end': nowIso,
            'duration_minutes': durationMins < 0 ? 0 : durationMins,
          })
          .eq('id', activeBreak['id']);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Break ended.'),
          backgroundColor: Colors.green,
        ),
      );
      await _loadData(showLoading: false);

      // Check Smart Break Continuity prompt
      final preBreakTask = TaskTracker.instance.getAndClearPreBreakTask();
      if (preBreakTask != null && mounted) {
        await showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Smart Break Continuity'),
            content: Text(
              'You were working on:\n\n"${preBreakTask['title']}"\n\nWould you like to continue?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Not Now'),
              ),
              OutlinedButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                },
                child: const Text('Choose Another Task'),
              ),
              FilledButton(
                onPressed: () async {
                  TaskTracker.instance.activeTask.value = preBreakTask;
                  await _db
                      .from('tasks')
                      .update({'status': 'in_progress'})
                      .eq('id', preBreakTask['id']);
                  Navigator.pop(dialogContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Resumed task!')),
                  );
                },
                child: const Text('Continue Task'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to end break: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  Future<void> _submitCorrectionRequest() async {
    DateTime selectedDate = DateTime.now();
    final reasonController = TextEditingController();
    List<Map<String, dynamic>> entries = [];

    List<Map<String, dynamic>> entriesForDate(DateTime date) {
      final dateString = _formatDate(date);
      final record = _myAttendance.firstWhere(
        (r) => r['attendance_date']?.toString() == dateString,
        orElse: () => {},
      );
      final stored = List<Map<String, dynamic>>.from(
        (record['work_sessions'] as List? ?? []).map(
          (s) => Map<String, dynamic>.from(s as Map),
        ),
      );
      if (stored.isEmpty && record['check_in'] != null) {
        stored.add({
          'check_in': record['check_in'],
          'check_out': record['check_out'],
        });
      }
      return stored
          .map(
            (session) => <String, dynamic>{
              'in': _timeOf(session['check_in']),
              'out': _timeOf(session['check_out']),
              'isNew': false,
            },
          )
          .toList();
    }

    entries = entriesForDate(selectedDate);
    if (entries.isEmpty)
      entries = [
        {'in': null, 'out': null, 'isNew': true},
      ];

    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Request Attendance Correction'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Attendance changes only after HR approval.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Date'),
                    subtitle: Text(_formatDate(selectedDate)),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 90),
                        ),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null)
                        setDialogState(() {
                          selectedDate = picked;
                          entries = entriesForDate(picked);
                          if (entries.isEmpty)
                            entries = [
                              {'in': null, 'out': null, 'isNew': true},
                            ];
                        });
                    },
                  ),
                  const Divider(),
                  for (var i = 0; i < entries.length; i++) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Punch ${i + 1}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove punch',
                          onPressed: entries.length == 1
                              ? null
                              : () => setDialogState(() => entries.removeAt(i)),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.login),
                            label: Text(
                              entries[i]['in']?.format(context) ?? 'Punch In',
                            ),
                            onPressed: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime:
                                    entries[i]['in'] ??
                                    const TimeOfDay(hour: 9, minute: 0),
                              );
                              if (picked != null)
                                setDialogState(() => entries[i]['in'] = picked);
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.logout),
                            label: Text(
                              entries[i]['out']?.format(context) ?? 'Punch Out',
                            ),
                            onPressed: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime:
                                    entries[i]['out'] ??
                                    const TimeOfDay(hour: 17, minute: 0),
                              );
                              if (picked != null)
                                setDialogState(
                                  () => entries[i]['out'] = picked,
                                );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setDialogState(
                        () => entries.add({
                          'in': null,
                          'out': null,
                          'isNew': true,
                        }),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Add punch pair'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: reasonController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Reason for correction',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final hasIncompleteNewEntry = entries.any(
                  (entry) =>
                      entry['isNew'] == true &&
                      (entry['in'] == null || entry['out'] == null),
                );
                final hasInvalidOrder = entries.any((entry) {
                  final punchIn = entry['in'] as TimeOfDay?;
                  final punchOut = entry['out'] as TimeOfDay?;
                  if (punchIn == null || punchOut == null) return false;
                  return punchOut.hour * 60 + punchOut.minute <
                      punchIn.hour * 60 + punchIn.minute;
                });
                if (reasonController.text.trim().isEmpty ||
                    hasIncompleteNewEntry ||
                    hasInvalidOrder) {
                  final message = reasonController.text.trim().isEmpty
                      ? 'Please provide a reason for the correction.'
                      : hasIncompleteNewEntry
                      ? 'New punch pairs need both an in and out time.'
                      : 'Punch out must be later than punch in.';
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(message)));
                  return;
                }
                if (!entries.any(
                  (entry) => entry['in'] != null || entry['out'] != null,
                )) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Add at least one punch time.'),
                    ),
                  );
                  return;
                }
                final dateStr = _formatDate(selectedDate);
                DateTime toIso(TimeOfDay time) => DateTime(
                  selectedDate.year,
                  selectedDate.month,
                  selectedDate.day,
                  time.hour,
                  time.minute,
                ).toUtc();
                final requestedSessions = entries
                    .map(
                      (entry) => {
                        'check_in': entry['in'] == null
                            ? null
                            : toIso(entry['in'] as TimeOfDay).toIso8601String(),
                        'check_out': entry['out'] == null
                            ? null
                            : toIso(entry['out'] as TimeOfDay)
                                  .toIso8601String(),
                      },
                    )
                    .toList();
                final firstCheckIn = requestedSessions.firstWhere(
                  (session) => session['check_in'] != null,
                  orElse: () => requestedSessions.first,
                )['check_in'];
                final lastCheckOut = requestedSessions.lastWhere(
                  (session) => session['check_out'] != null,
                  orElse: () => requestedSessions.last,
                )['check_out'];
                try {
                  final uid = _uid;
                  if (uid == null)
                    throw Exception('Session expired. Please log in again.');
                  await _db.from('attendance_correction_requests').insert({
                    'employee_id': uid,
                    'request_date': dateStr,
                    'requested_check_in': firstCheckIn,
                    'requested_check_out': lastCheckOut,
                    'requested_sessions': requestedSessions,
                    'reason': reasonController.text.trim(),
                    'status': 'pending',
                  });
                  if (!mounted) return;
                  Navigator.pop(dialogContext, true);
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(
                      content: Text('Correction request submitted.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  await _loadData(showLoading: false);
                } catch (e) {
                  if (dialogContext.mounted)
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text('Failed to submit request: $e')),
                    );
                }
              },
              child: const Text('Submit Request'),
            ),
          ],
        ),
      ),
    );
    reasonController.dispose();
  }

  String _requestedSessionLabel(Map<String, dynamic> request) {
    final sessions = List<Map<String, dynamic>>.from(
      (request['requested_sessions'] as List? ?? []).map(
        (s) => Map<String, dynamic>.from(s as Map),
      ),
    );
    if (sessions.isEmpty)
      return '${_formatTime(request['requested_check_in'])} – ${_formatTime(request['requested_check_out'])}';
    return sessions
        .asMap()
        .entries
        .map(
          (e) =>
              '#${e.key + 1} ${_formatTime(e.value['check_in'])}–${_formatTime(e.value['check_out'])}',
        )
        .join(', ');
  }

  TimeOfDay? _timeOf(dynamic value) {
    if (value == null) return null;
    final parsed = DateTime.tryParse(value.toString())?.toLocal();
    return parsed == null
        ? null
        : TimeOfDay(hour: parsed.hour, minute: parsed.minute);
  }

  Future<void> _reviewCorrection(
    Map<String, dynamic> request,
    bool approve,
  ) async {
    final commentController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          approve ? 'Approve Correction Request' : 'Reject Correction Request',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Employee: ${_employeeName(request['employee_id']?.toString())}',
            ),
            Text('Date: ${request['request_date']}'),
            const SizedBox(height: 12),
            TextField(
              controller: commentController,
              decoration: const InputDecoration(
                labelText: 'Review comment (optional)',
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
            style: FilledButton.styleFrom(
              backgroundColor: approve ? Colors.green : Colors.red,
            ),
            onPressed: () => Navigator.pop(c, true),
            child: Text(approve ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );

    if (result != true) return;

    try {
      final uid = _uid;
      if (uid == null) return;

      if (approve) {
        final empId = request['employee_id'];
        final dateStr = request['request_date'];
        final reqCheckIn = request['requested_check_in'];
        final reqCheckOut = request['requested_check_out'];
        final requestedSessions = List<Map<String, dynamic>>.from(
          (request['requested_sessions'] as List? ?? []).map(
            (s) => Map<String, dynamic>.from(s as Map),
          ),
        );

        final existingRes = await _db
            .from('attendance_records')
            .select('id, work_sessions, attendance_breaks(*)')
            .eq('employee_id', empId)
            .eq('attendance_date', dateStr)
            .maybeSingle();
        final breaks = List<Map<String, dynamic>>.from(
          (existingRes?['attendance_breaks'] as List? ?? []).map(
            (b) => Map<String, dynamic>.from(b as Map),
          ),
        );

        int workMins = 0;
        if (requestedSessions.isNotEmpty) {
          for (var i = 0; i < requestedSessions.length; i++) {
            final session = requestedSessions[i];
            final checkIn = session['check_in'];
            final checkOut = session['check_out'];
            final grossMinutes = checkIn == null || checkOut == null
                ? 0
                : DateTime.parse(checkOut.toString())
                      .difference(DateTime.parse(checkIn.toString()))
                      .inMinutes
                      .clamp(0, 1440);
            final breakMinutes = breaks
                .where((b) => ((b['session_index'] as num?)?.toInt() ?? 0) == i)
                .fold<int>(
                  0,
                  (sum, b) =>
                      sum + ((b['duration_minutes'] as num?)?.toInt() ?? 0),
                );
            final duration = (grossMinutes - breakMinutes)
                .clamp(0, 1440)
                .toInt();
            session['work_duration_minutes'] = duration;
            workMins += duration;
          }
        } else if (reqCheckIn != null && reqCheckOut != null) {
          final ci = DateTime.parse(reqCheckIn);
          final co = DateTime.parse(reqCheckOut);
          final breakMinutes = breaks
              .where((b) => ((b['session_index'] as num?)?.toInt() ?? 0) == 0)
              .fold<int>(
                0,
                (sum, b) =>
                    sum + ((b['duration_minutes'] as num?)?.toInt() ?? 0),
              );
          workMins = (co.difference(ci).inMinutes - breakMinutes)
              .clamp(0, 1440)
              .toInt();
        }
        final halfDayHours =
            double.tryParse(
              _companySettings?['half_day_hours']?.toString() ?? '4',
            ) ??
            4;
        final attendanceStatus = workMins < halfDayHours * 60
            ? 'Half Day'
            : 'Present';

        if (existingRes != null) {
          await _db
              .from('attendance_records')
              .update({
                if (requestedSessions.isNotEmpty)
                  'check_in': requestedSessions.firstWhere(
                    (session) => session['check_in'] != null,
                    orElse: () => requestedSessions.first,
                  )['check_in'],
                if (requestedSessions.isNotEmpty)
                  'check_out': requestedSessions.lastWhere(
                    (session) => session['check_out'] != null,
                    orElse: () => requestedSessions.last,
                  )['check_out'],
                if (requestedSessions.isEmpty && reqCheckIn != null)
                  'check_in': reqCheckIn,
                if (requestedSessions.isEmpty && reqCheckOut != null)
                  'check_out': reqCheckOut,
                if (requestedSessions.isNotEmpty)
                  'work_sessions': requestedSessions,
                'work_duration_minutes': workMins,
                'status': attendanceStatus,
                'updated_at': DateTime.now().toUtc().toIso8601String(),
              })
              .eq('id', existingRes['id']);
        } else {
          await _db.from('attendance_records').insert({
            'employee_id': empId,
            'attendance_date': dateStr,
            if (reqCheckIn != null) 'check_in': reqCheckIn,
            if (reqCheckOut != null) 'check_out': reqCheckOut,
            if (requestedSessions.isNotEmpty)
              'work_sessions': requestedSessions,
            'work_duration_minutes': workMins,
            'status': attendanceStatus,
          });
        }
      }

      await _db
          .from('attendance_correction_requests')
          .update({
            'status': approve ? 'approved' : 'rejected',
            'reviewer_id': uid,
            'review_comment': commentController.text.trim(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', request['id']);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approve
                ? 'Correction approved and applied.'
                : 'Correction request rejected.',
          ),
          backgroundColor: approve ? Colors.green : Colors.orange,
        ),
      );
      _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error processing correction: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // --- UI BUILDERS ---

  @override
  Widget build(BuildContext context) {
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
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Error loading attendance: $_error',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            const Text(
              'Attendance Management',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            if (_isPrivileged)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ToggleButtons(
                  isSelected: [
                    _selectedTab == 0,
                    _selectedTab == 1,
                    _selectedTab == 2,
                  ],
                  onPressed: (index) => setState(() => _selectedTab = index),
                  borderRadius: BorderRadius.circular(8),
                  constraints: const BoxConstraints(
                    minHeight: 36,
                    minWidth: 100,
                  ),
                  children: const [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('My Attendance'),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('HR Overview'),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('Corrections'),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),

        if (_selectedTab == 0) _buildMyAttendanceView(),
        if (_selectedTab == 1 && _isPrivileged) _buildHrOverviewView(),
        if (_selectedTab == 2 || (!_isPrivileged && _selectedTab == 1))
          _buildCorrectionsView(),
      ],
    );
  }

  Widget _buildMyAttendanceView() {
    final todayStr = _formatDate(DateTime.now());
    final todayRecord = _myAttendance.firstWhere(
      (r) => r['attendance_date']?.toString() == todayStr,
      orElse: () => {},
    );

    final checkedIn =
        todayRecord.isNotEmpty &&
        todayRecord['check_in'] != null &&
        todayRecord['check_out'] == null;
    final checkedOut =
        todayRecord.isNotEmpty && todayRecord['check_out'] != null;
    final activeBreak = _myBreaks.any((b) => b['break_end'] == null);

    int presentDays = 0;
    int lateDays = 0;
    int totalWorkMins = 0;
    for (var r in _myAttendance) {
      final st = r['status']?.toString();
      if (st == 'Present' || st == 'Late' || st == 'Half Day') presentDays++;
      if (st == 'Late') lateDays++;
      totalWorkMins += _recordWorkMinutes(r);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Text(
                      'Today: $todayStr',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Chip(
                      label: Text(
                        todayRecord['status']?.toString() ?? 'Not Checked In',
                      ),
                      backgroundColor: (todayRecord['status'] == 'Late')
                          ? Colors.orange.withOpacity(0.2)
                          : Colors.green.withOpacity(0.2),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Work Policy Base: Start ${_companySettings?['work_start_time'] ?? '09:00'} (Grace: ${_companySettings?['grace_period_minutes'] ?? 15}m) | End ${_companySettings?['work_end_time'] ?? '17:00'}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 18),
                _buildShiftProgress(todayRecord, checkedIn, activeBreak),
                const Divider(height: 24),
                Wrap(
                  spacing: 24,
                  runSpacing: 16,
                  children: [
                    _infoColumn(
                      'Check In',
                      _formatTime(todayRecord['check_in']),
                    ),
                    _infoColumn(
                      'Check Out',
                      _formatTime(todayRecord['check_out']),
                    ),
                    _infoColumn(
                      'Net Work',
                      _formatDuration(_recordWorkMinutes(todayRecord)),
                    ),
                    _infoColumn(
                      'Break Time',
                      _formatDuration(
                        _myBreaks.fold(
                          0,
                          (sum, b) =>
                              sum +
                              ((b['duration_minutes'] as num?)?.toInt() ?? 0),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: (_actionInProgress || checkedIn)
                          ? null
                          : _checkIn,
                      icon: const Icon(Icons.login),
                      label: const Text('Check In'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: (_actionInProgress || !checkedIn || checkedOut)
                          ? null
                          : _checkOut,
                      icon: const Icon(Icons.logout),
                      label: const Text('Check Out'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _submitCorrectionRequest,
                      icon: const Icon(Icons.edit_calendar),
                      label: const Text('Request Correction'),
                    ),
                  ],
                ),
                if (_myBreaks.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final b in _myBreaks)
                        Chip(
                          avatar: const Icon(Icons.coffee, size: 16),
                          label: Text(
                            '${b['break_type'] ?? 'Break'} • ${_formatDuration((b['duration_minutes'] as num?)?.toInt() ?? 0)}',
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        AdaptiveCards(
          minWidth: 230,
          maxColumns: 4,
          children: [
            _statCard(
              'Days Present',
              '$presentDays',
              Icons.event_available,
              Colors.green,
            ),
            _statCard('Late Arrivals', '$lateDays', Icons.timer, Colors.orange),
            _statCard(
              'Total Hours',
              _formatDuration(totalWorkMins),
              Icons.access_time,
              Colors.blue,
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Text(
          'Monthly Attendance',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _buildMonthlyAttendance(),
      ],
    );
  }

  Widget _buildMonthlyAttendance() {
    final targetDate = DateTime(_selectedYear, _selectedMonth, 1);
    final monthName = _monthLabel(
      '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}',
    );

    final daysInMonth = DateTime(targetDate.year, targetDate.month + 1, 0).day;

    int expectedWorkingDays = 0;
    int completedDays = 0;
    int lateDaysCount = 0;
    int absentDaysCount = 0;
    int totalMonthWorkMins = 0;

    final attendanceByDate = <String, Map<String, dynamic>>{};
    for (final r in _myAttendance) {
      final dateStr = r['attendance_date']?.toString();
      if (dateStr != null) {
        attendanceByDate[dateStr] = r;
      }
    }

    for (int d = 1; d <= daysInMonth; d++) {
      final curr = DateTime(targetDate.year, targetDate.month, d);
      final isWeekend =
          curr.weekday == DateTime.saturday || curr.weekday == DateTime.sunday;
      if (!isWeekend) {
        expectedWorkingDays++;
        final dateStr =
            '${curr.year}-${curr.month.toString().padLeft(2, '0')}-${curr.day.toString().padLeft(2, '0')}';
        final rec = attendanceByDate[dateStr];
        if (rec != null) {
          final st = rec['status']?.toString();
          if (st == 'Present' || st == 'Half Day') {
            completedDays++;
          } else if (st == 'Late') {
            completedDays++;
            lateDaysCount++;
          } else if (st == 'Absent') {
            absentDaysCount++;
          }
          totalMonthWorkMins += _recordWorkMinutes(rec);
        }
      }
    }

    final percentage = expectedWorkingDays > 0
        ? (completedDays / expectedWorkingDays).clamp(0.0, 1.0)
        : 0.0;
    final remainingDays = (expectedWorkingDays - completedDays).clamp(
      0,
      expectedWorkingDays,
    );
    final expectedMonthlyHoursMins = expectedWorkingDays * 8 * 60;
    final hoursProgress = expectedMonthlyHoursMins > 0
        ? (totalMonthWorkMins / expectedMonthlyHoursMins).clamp(0.0, 1.0)
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () {
                        setState(() {
                          if (_selectedMonth == 1) {
                            _selectedMonth = 12;
                            _selectedYear--;
                          } else {
                            _selectedMonth--;
                          }
                        });
                      },
                    ),
                    Text(
                      monthName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () {
                        setState(() {
                          if (_selectedMonth == 12) {
                            _selectedMonth = 1;
                            _selectedYear++;
                          } else {
                            _selectedMonth++;
                          }
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Monthly Attendance Progress',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '$completedDays / $expectedWorkingDays working days (${(percentage * 100).toStringAsFixed(0)}%)',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: percentage,
                    minHeight: 12,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    color: const Color(0xFF6366F1),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$completedDays completed',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      '$remainingDays working days remaining',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                const Divider(height: 32),
                Wrap(
                  spacing: 24,
                  runSpacing: 12,
                  children: [
                    _metricBadge(
                      'Present',
                      '$completedDays',
                      Icons.check_circle,
                      Colors.green,
                    ),
                    _metricBadge(
                      'Late',
                      '$lateDaysCount',
                      Icons.timer,
                      Colors.orange,
                    ),
                    _metricBadge(
                      'Remaining',
                      '$remainingDays',
                      Icons.schedule,
                      Colors.blue,
                    ),
                    _metricBadge(
                      'Absent',
                      '$absentDaysCount',
                      Icons.cancel,
                      Colors.red,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Working Hours',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      '${_formatDuration(totalMonthWorkMins)} / ${_formatDuration(expectedMonthlyHoursMins)} expected (${(hoursProgress * 100).toStringAsFixed(0)}%)',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: hoursProgress,
                    minHeight: 8,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    color: Colors.teal,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Daily Attendance Grid',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 16),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 1.1,
                  ),
                  itemCount: daysInMonth,
                  itemBuilder: (context, idx) {
                    final d = idx + 1;
                    final curr = DateTime(targetDate.year, targetDate.month, d);
                    final isWeekend =
                        curr.weekday == DateTime.saturday ||
                        curr.weekday == DateTime.sunday;
                    final dateStr =
                        '${curr.year}-${curr.month.toString().padLeft(2, '0')}-${curr.day.toString().padLeft(2, '0')}';
                    final rec = attendanceByDate[dateStr];
                    final st = rec?['status']?.toString();

                    Color cellColor = isWeekend
                        ? Colors.grey.withValues(alpha: 0.1)
                        : Colors.grey.withValues(alpha: 0.2);
                    String statusText = isWeekend ? 'Weekly Off' : 'No Entry';
                    IconData cellIcon = isWeekend
                        ? Icons.weekend
                        : Icons.remove;

                    if (st == 'Present') {
                      cellColor = Colors.green.withValues(alpha: 0.2);
                      statusText = 'Present';
                      cellIcon = Icons.check;
                    } else if (st == 'Late') {
                      cellColor = Colors.orange.withValues(alpha: 0.2);
                      statusText = 'Late';
                      cellIcon = Icons.timer;
                    } else if (st == 'Half Day') {
                      cellColor = Colors.purple.withValues(alpha: 0.2);
                      statusText = 'Half Day';
                      cellIcon = Icons.star_half;
                    } else if (st == 'Absent') {
                      cellColor = Colors.red.withValues(alpha: 0.2);
                      statusText = 'Absent';
                      cellIcon = Icons.close;
                    }

                    return InkWell(
                      onTap: () {
                        if (rec != null) {
                          _showDayDetailDialog(curr, rec);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'No attendance record for $dateStr ($statusText)',
                              ),
                            ),
                          );
                        }
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        decoration: BoxDecoration(
                          color: cellColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$d',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Icon(
                              cellIcon,
                              size: 14,
                              color:
                                  cellColor ==
                                      Colors.green.withValues(alpha: 0.2)
                                  ? Colors.green
                                  : Colors.grey,
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
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton.icon(
            onPressed: () =>
                setState(() => _showDetailedTable = !_showDetailedTable),
            icon: Icon(
              _showDetailedTable ? Icons.expand_less : Icons.expand_more,
            ),
            label: Text(
              _showDetailedTable
                  ? 'Hide detailed attendance logs'
                  : 'View detailed attendance logs',
            ),
          ),
        ),
        if (_showDetailedTable) ...[
          const SizedBox(height: 12),
          _buildDetailedDataTable(),
        ],
      ],
    );
  }

  Widget _metricBadge(String label, String count, IconData icon, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              count,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ],
    );
  }

  void _showDayDetailDialog(DateTime date, Map<String, dynamic> record) {
    final dateStr = _formatDate(date);
    final status = record['status']?.toString() ?? 'Present';
    final inTime = _formatTime(record['check_in']);
    final outTime = _formatTime(record['check_out']);
    final workMins = _recordWorkMinutes(record);
    final autoBreakMins = workMins >= 360 ? 30 : 0;
    final netWork = (workMins - autoBreakMins).clamp(0, 1440);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Attendance Details • $dateStr'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _keyVal('Status', status),
              _keyVal('Check In', inTime),
              _keyVal('Check Out', outTime),
              _keyVal('Net Work', _formatDuration(netWork)),
              _keyVal('Break Time', _formatDuration(autoBreakMins)),
              _keyVal(
                'Shift',
                '${_companySettings?['work_start_time'] ?? '09:00'} – ${_companySettings?['work_end_time'] ?? '17:00'}',
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _submitCorrectionRequest();
            },
            icon: const Icon(Icons.edit_calendar, size: 16),
            label: const Text('Request Correction'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _keyVal(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(
            v,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedDataTable() {
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(
            Theme.of(context).colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.5),
          ),
          columns: const [
            DataColumn(
              label: Text(
                'Date',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                'Status',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                'In-Time',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                'Out-Time',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                'Net Work',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                'Break Time',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
          rows: _myAttendance.map((record) {
            final dateStr = record['attendance_date']?.toString() ?? '-';
            final status = record['status']?.toString() ?? 'Present';
            final inTime = _formatTime(record['check_in']);
            final outTime = _formatTime(record['check_out']);
            final workMins = _recordWorkMinutes(record);
            final autoBreakMins = workMins >= 360 ? 30 : 0;
            final netWork = (workMins - autoBreakMins).clamp(0, 1440);

            Color statusColor = Colors.green;
            if (status == 'Late') statusColor = Colors.orange;
            if (status == 'Half Day') statusColor = Colors.purple;
            if (status == 'Absent') statusColor = Colors.red;

            return DataRow(
              cells: [
                DataCell(
                  Text(
                    dateStr,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                DataCell(Text(inTime)),
                DataCell(Text(outTime)),
                DataCell(
                  Text(
                    _formatDuration(netWork),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataCell(Text(_formatDuration(autoBreakMins))),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  String _monthLabel(String key) {
    final date = DateTime.tryParse('$key-01');
    if (date == null) return key;
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  int _durationForSession(
    Map<String, dynamic> record,
    Map<String, dynamic> session,
    int index,
  ) {
    final startValue = session['check_in'];
    final endValue = session['check_out'];
    if (startValue == null || endValue == null) {
      return (session['work_duration_minutes'] as num?)?.toInt() ?? 0;
    }
    final start = DateTime.tryParse(startValue.toString());
    final end = DateTime.tryParse(endValue.toString());
    if (start == null || end == null || !end.isAfter(start)) return 0;
    final breakMinutes = _breakMinutesAtIndex(record, index);
    return (end.difference(start).inMinutes - breakMinutes)
        .clamp(0, 1440)
        .toInt();
  }

  int _recordWorkMinutes(Map<String, dynamic> record) =>
      _sessionsForRecord(record).asMap().entries.fold(
        0,
        (sum, entry) =>
            sum + _durationForSession(record, entry.value, entry.key),
      );

  int _breakMinutesAtIndex(Map<String, dynamic> record, int index) =>
      List<Map<String, dynamic>>.from(
            (record['attendance_breaks'] as List? ?? []).map(
              (b) => Map<String, dynamic>.from(b as Map),
            ),
          )
          .where((b) => (b['session_index'] as num?)?.toInt() == index)
          .fold(
            0,
            (sum, b) => sum + ((b['duration_minutes'] as num?)?.toInt() ?? 0),
          );

  List<Map<String, dynamic>> _sessionsForRecord(Map<String, dynamic> record) {
    final sessions = List<Map<String, dynamic>>.from(
      (record['work_sessions'] as List? ?? []).map(
        (s) => Map<String, dynamic>.from(s as Map),
      ),
    );
    if (sessions.isNotEmpty) return sessions;
    if (record['check_in'] != null)
      return [
        {
          'check_in': record['check_in'],
          'check_out': record['check_out'],
          'work_duration_minutes': record['work_duration_minutes'] ?? 0,
        },
      ];
    return [
      {'check_in': null, 'check_out': null, 'work_duration_minutes': 0},
    ];
  }

  Widget _buildShiftProgress(
    Map<String, dynamic> record,
    bool checkedIn,
    bool activeBreak,
  ) {
    final targetMinutes =
        ((double.tryParse(
                      _companySettings?['daily_work_hours']?.toString() ?? '8',
                    ) ??
                    8) *
                60)
            .round();
    final sessions = List<Map<String, dynamic>>.from(
      (record['work_sessions'] as List? ?? []).map(
        (s) => Map<String, dynamic>.from(s as Map),
      ),
    );
    var worked = _recordWorkMinutes(record);
    if (checkedIn && sessions.isNotEmpty) {
      final open = sessions.lastWhere(
        (s) => s['check_out'] == null,
        orElse: () => {},
      );
      if (open.isNotEmpty) {
        final index = sessions.indexOf(open);
        final elapsed = DateTime.now()
            .difference(DateTime.parse(open['check_in'].toString()).toLocal())
            .inMinutes;
        final breaks = _myBreaks.where(
          (b) => ((b['session_index'] as num?)?.toInt() ?? 0) == index,
        );
        final breakMinutes = breaks.fold<int>(0, (sum, b) {
          final saved = (b['duration_minutes'] as num?)?.toInt() ?? 0;
          if (b['break_end'] == null) {
            final start = DateTime.tryParse(b['break_start']?.toString() ?? '')
                ?.toLocal();
            return sum +
                (start == null
                    ? 0
                    : DateTime.now().difference(start).inMinutes);
          }
          return sum + saved;
        });
        worked += (elapsed - breakMinutes).clamp(0, 1440).toInt();
      }
    }
    final progress = targetMinutes <= 0
        ? 0.0
        : (worked / targetMinutes).clamp(0.0, 1.0);
    final state = activeBreak
        ? 'On break'
        : checkedIn
        ? 'Working'
        : record['check_out'] != null
        ? 'Shift ended • Check in again to start another session'
        : 'Not started';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            Text(state, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(
              '${_formatDuration(worked)} / ${_formatDuration(targetMinutes)}',
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(value: progress, minHeight: 10),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text('Check in'),
            Text('Target hours'),
            Text('Check out'),
          ],
        ),
      ],
    );
  }

  Widget _infoColumn(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withOpacity(0.2),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHrOverviewView() {
    final todayStr = _formatDate(DateTime.now());
    int presentToday = _allAttendance
        .where(
          (r) =>
              r['attendance_date']?.toString() == todayStr &&
              r['check_in'] != null,
        )
        .length;
    int checkedInNow = _allAttendance
        .where(
          (r) =>
              r['attendance_date']?.toString() == todayStr &&
              r['check_in'] != null &&
              r['check_out'] == null,
        )
        .length;
    int lateToday = _allAttendance
        .where(
          (r) =>
              r['attendance_date']?.toString() == todayStr &&
              r['status'] == 'Late',
        )
        .length;
    int missingCheckout = _allAttendance
        .where(
          (r) =>
              r['attendance_date']?.toString() != todayStr &&
              r['check_in'] != null &&
              r['check_out'] == null,
        )
        .length;

    final filtered = _allAttendance.where((r) {
      final empId = r['employee_id']?.toString();
      final name = _employeeName(empId).toLowerCase();
      final dept = _employeeDepartment(empId);
      final status = r['status']?.toString() ?? '';

      if (_searchQuery.isNotEmpty && !name.contains(_searchQuery.toLowerCase()))
        return false;
      if (_departmentFilter != 'All' && dept != _departmentFilter) return false;
      if (_statusFilter != 'All' && status != _statusFilter) return false;
      return true;
    }).toList();

    final departments = <String>['All'];
    for (var p in _profiles) {
      final d = p['department']?.toString();
      if (d != null && d.isNotEmpty && !departments.contains(d)) {
        departments.add(d);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdaptiveCards(
          minWidth: 230,
          maxColumns: 4,
          children: [
            _statCard(
              'Present Today',
              '$presentToday',
              Icons.people,
              Colors.green,
            ),
            _statCard(
              'Checked In Now',
              '$checkedInNow',
              Icons.login,
              Colors.blue,
            ),
            _statCard('Late Today', '$lateToday', Icons.timer, Colors.orange),
            _statCard(
              'Missing Checkout',
              '$missingCheckout',
              Icons.warning,
              Colors.red,
            ),
          ],
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 16,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: (MediaQuery.sizeOf(context).width - 96)
                      .clamp(0, 260)
                      .toDouble(),
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Search employee',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ),
                DropdownButton<String>(
                  value: _departmentFilter,
                  items: departments
                      .map(
                        (d) =>
                            DropdownMenuItem(value: d, child: Text('Dept: $d')),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _departmentFilter = v ?? 'All'),
                ),
                DropdownButton<String>(
                  value: _statusFilter,
                  items: const [
                    DropdownMenuItem(value: 'All', child: Text('Status: All')),
                    DropdownMenuItem(value: 'Present', child: Text('Present')),
                    DropdownMenuItem(value: 'Late', child: Text('Late')),
                    DropdownMenuItem(
                      value: 'Half Day',
                      child: Text('Half Day'),
                    ),
                  ],
                  onChanged: (v) => setState(() => _statusFilter = v ?? 'All'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Employee')),
                DataColumn(label: Text('Department')),
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Check In')),
                DataColumn(label: Text('Check Out')),
                DataColumn(label: Text('Net Work')),
                DataColumn(label: Text('Late Time')),
              ],
              rows: filtered.map((r) {
                final empId = r['employee_id']?.toString();
                final lateMins = (r['late_minutes'] as num?)?.toInt() ?? 0;
                return DataRow(
                  cells: [
                    DataCell(Text(_employeeName(empId))),
                    DataCell(Text(_employeeDepartment(empId))),
                    DataCell(Text(r['attendance_date']?.toString() ?? '-')),
                    DataCell(Text(r['status']?.toString() ?? '-')),
                    DataCell(Text(_formatTime(r['check_in']))),
                    DataCell(Text(_formatTime(r['check_out']))),
                    DataCell(Text(_formatDuration(_recordWorkMinutes(r)))),
                    DataCell(
                      Text(lateMins == 0 ? '-' : _formatDuration(lateMins)),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCorrectionsView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Attendance Correction Requests',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Employee')),
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('Requested Punch Entries')),
                DataColumn(label: Text('Reason')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Actions')),
              ],
              rows: _correctionRequests.map((req) {
                final empId = req['employee_id']?.toString();
                final status = req['status']?.toString() ?? 'pending';
                return DataRow(
                  cells: [
                    DataCell(Text(_employeeName(empId))),
                    DataCell(Text(req['request_date']?.toString() ?? '-')),
                    DataCell(Text(_requestedSessionLabel(req))),
                    DataCell(Text(req['reason']?.toString() ?? '-')),
                    DataCell(
                      Chip(
                        label: Text(status),
                        backgroundColor: status == 'approved'
                            ? Colors.green.withOpacity(0.2)
                            : status == 'rejected'
                            ? Colors.red.withOpacity(0.2)
                            : Colors.orange.withOpacity(0.2),
                      ),
                    ),
                    DataCell(
                      status == 'pending' && _isHrOrAdmin
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.check,
                                    color: Colors.green,
                                  ),
                                  onPressed: () => _reviewCorrection(req, true),
                                  tooltip: 'Approve',
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.red,
                                  ),
                                  onPressed: () =>
                                      _reviewCorrection(req, false),
                                  tooltip: 'Reject',
                                ),
                              ],
                            )
                          : Text(req['review_comment']?.toString() ?? '-'),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}
