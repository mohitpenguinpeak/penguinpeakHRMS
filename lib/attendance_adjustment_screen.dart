import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/theme/design_system.dart';
import 'shared/widgets/adaptive_layout.dart';

class AttendanceAdjustmentScreen extends StatefulWidget {
  final String role;
  const AttendanceAdjustmentScreen({
    super.key,
    required this.role,
    this.initialRequestId,
    this.onTargetConsumed,
  });
  final String? initialRequestId;
  final VoidCallback? onTargetConsumed;

  @override
  State<AttendanceAdjustmentScreen> createState() =>
      _AttendanceAdjustmentScreenState();
}

class _AttendanceAdjustmentScreenState extends State<AttendanceAdjustmentScreen>
    with SingleTickerProviderStateMixin {
  final SupabaseClient _db = Supabase.instance.client;
  late TabController _tabController;
  bool _loading = true;
  bool _targetConsumed = false;
  String? _error;
  bool _refreshInProgress = false;
  Timer? _syncTimer;
  List<Map<String, dynamic>> _requests = [];
  List<Map<String, dynamic>> _profiles = [];

  // Filter & Search states
  String _searchFilter = '';
  String _statusFilter = 'All';
  String _typeFilter = 'All';

  String? get _uid => _db.auth.currentUser?.id;
  bool get _canReview =>
      ['admin', 'super_admin', 'hr', 'management'].contains(widget.role);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _canReview ? 2 : 1, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadData();
    _syncTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && !_loading) _loadData(showLoading: false);
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _tabController.dispose();
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
      final profilesRes = await _db
          .from('profiles')
          .select('id, full_name, department, role')
          .eq('approval_status', 'approved')
          .order('full_name');
      _profiles = List<Map<String, dynamic>>.from(profilesRes);

      final adjustmentRes = await _db
          .from('attendance_adjustment_requests')
          .select('*')
          .order('created_at', ascending: false)
          .limit(500);
      final regularisationRes = await _db
          .from('attendance_correction_requests')
          .select('*')
          .order('created_at', ascending: false)
          .limit(500);
      _requests =
          [
            ...List<Map<String, dynamic>>.from(adjustmentRes)
                .map((r) => {...r, 'request_kind': 'adjustment'}),
            ...List<Map<String, dynamic>>.from(regularisationRes).map(
              (r) => {
                ...r,
                'request_kind': 'regularisation',
                'adjustment_type': 'regularisation',
                'duration_minutes': null,
              },
            ),
          ]..sort(
            (a, b) => (b['created_at']?.toString() ?? '').compareTo(
              a['created_at']?.toString() ?? '',
            ),
          );

      if (!mounted) return;
      if (!_targetConsumed && widget.initialRequestId != null) {
        _targetConsumed = true;
        widget.onTargetConsumed?.call();
        final target = _requests
            .where((r) => r['id'] == widget.initialRequestId)
            .firstOrNull;
        if (_canReview && target != null) {
          _tabController.index = target['employee_id'] == _uid ? 0 : 1;
        }
      }
      if (widget.initialRequestId != null) {
        _requests.sort(
          (a, b) => a['id'] == widget.initialRequestId
              ? -1
              : b['id'] == widget.initialRequestId
              ? 1
              : (b['created_at']?.toString() ?? '').compareTo(
                  a['created_at']?.toString() ?? '',
                ),
        );
      }
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

  String _employeeName(dynamic id) {
    final key = id?.toString();
    for (final p in _profiles) {
      if (p['id']?.toString() == key) {
        return (p['full_name'] ?? 'Employee').toString();
      }
    }
    return 'Employee';
  }

  String _regularisationSummary(Map<String, dynamic> request) {
    final sessions = List<Map<String, dynamic>>.from(
      (request['requested_sessions'] as List? ?? []).map(
        (s) => Map<String, dynamic>.from(s as Map),
      ),
    );
    if (sessions.isEmpty) {
      return '${request['requested_check_in'] ?? '—'} → ${request['requested_check_out'] ?? '—'}';
    }
    return sessions
        .asMap()
        .entries
        .map(
          (e) =>
              '#${e.key + 1} ${_formatPunchTime(e.value['check_in'])} → ${_formatPunchTime(e.value['check_out'])}',
        )
        .join('  •  ');
  }

  String _formatPunchTime(dynamic value) {
    if (value == null) return '—';
    final date = DateTime.tryParse(value.toString())?.toLocal();
    if (date == null) return value.toString();
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _applyRegularisation(Map<String, dynamic> request) async {
    final sessions = List<Map<String, dynamic>>.from(
      (request['requested_sessions'] as List? ?? []).map(
        (s) => Map<String, dynamic>.from(s as Map),
      ),
    );
    if (sessions.isEmpty) return;
    final existing = await _db
        .from('attendance_records')
        .select('id, attendance_breaks(*)')
        .eq('employee_id', request['employee_id'].toString())
        .eq('attendance_date', request['request_date'].toString())
        .maybeSingle();
    final breaks = List<Map<String, dynamic>>.from(
      (existing?['attendance_breaks'] as List? ?? []).map(
        (b) => Map<String, dynamic>.from(b as Map),
      ),
    );
    var totalMinutes = 0;
    for (var i = 0; i < sessions.length; i++) {
      final session = sessions[i];
      final start = session['check_in'];
      final end = session['check_out'];
      final grossMinutes = start == null || end == null
          ? 0
          : DateTime.parse(end.toString())
                .difference(DateTime.parse(start.toString()))
                .inMinutes
                .clamp(0, 1440);
      final breakMinutes = breaks
          .where((b) => ((b['session_index'] as num?)?.toInt() ?? 0) == i)
          .fold<int>(
            0,
            (sum, b) => sum + ((b['duration_minutes'] as num?)?.toInt() ?? 0),
          );
      final minutes = (grossMinutes - breakMinutes).clamp(0, 1440).toInt();
      session['work_duration_minutes'] = minutes;
      totalMinutes += minutes;
    }
    final employeeId = request['employee_id'].toString();
    final date = request['request_date'].toString();
    final firstIn = sessions.firstWhere(
      (s) => s['check_in'] != null,
      orElse: () => sessions.first,
    )['check_in'];
    final lastOut = sessions.lastWhere(
      (s) => s['check_out'] != null,
      orElse: () => sessions.last,
    )['check_out'];
    final status = totalMinutes < 4 * 60 ? 'Half Day' : 'Present';
    await _db.from('attendance_records').upsert({
      'employee_id': employeeId,
      'attendance_date': date,
      'check_in': firstIn,
      'check_out': lastOut,
      'work_sessions': sessions,
      'work_duration_minutes': totalMinutes,
      'status': status,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'employee_id,attendance_date');
  }

  Future<void> _requestAdjustment() async {
    String adjustmentType = 'late_arrival';
    final durationController = TextEditingController(text: '15');
    final reasonController = TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Request Attendance Adjustment'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: adjustmentType,
                    decoration: const InputDecoration(
                      labelText: 'Adjustment Type',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'late_arrival',
                        child: Text('Late Arrival'),
                      ),
                      DropdownMenuItem(
                        value: 'early_departure',
                        child: Text('Early Departure'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => adjustmentType = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: durationController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Duration in Minutes (Max 60 mins)',
                      helperText: 'Enforced maximum 60 minutes',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Reason for Adjustment *',
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
              onPressed: () async {
                final mins = int.tryParse(durationController.text.trim()) ?? 0;
                if (mins <= 0 || mins > 60) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Duration must be between 1 and 60 minutes.',
                      ),
                    ),
                  );
                  return;
                }
                if (reasonController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Reason is required.')),
                  );
                  return;
                }
                try {
                  await _db.from('attendance_adjustment_requests').insert({
                    'employee_id': _uid,
                    'adjustment_type': adjustmentType,
                    'duration_minutes': mins,
                    'reason': reasonController.text.trim(),
                    'status': 'pending',
                  });
                  if (!mounted) return;
                  Navigator.pop(dialogContext);
                  _loadData(showLoading: false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Adjustment request submitted successfully.',
                      ),
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              },
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reviewRequest(Map<String, dynamic> req, String status) async {
    final commentController = TextEditingController();
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          '${status == 'approved' ? 'Approve' : 'Reject'} Attendance Adjustment',
        ),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: commentController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Reviewer Comment (Optional)',
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
              try {
                final reviewData = {
                  'status': status,
                  if (req['request_kind'] == 'regularisation')
                    'reviewer_id': _uid,
                  if (req['request_kind'] != 'regularisation')
                    'reviewed_by': _uid,
                  'review_comment': commentController.text.trim(),
                  'updated_at': DateTime.now().toUtc().toIso8601String(),
                };
                if (req['request_kind'] == 'regularisation' &&
                    status == 'approved') {
                  await _applyRegularisation(req);
                }
                await _db
                    .from(
                      req['request_kind'] == 'regularisation'
                          ? 'attendance_correction_requests'
                          : 'attendance_adjustment_requests',
                    )
                    .update(reviewData)
                    .eq('id', req['id']);
                if (!mounted) return;
                Navigator.pop(dialogContext);
                _loadData(showLoading: false);
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('Request $status')));
              } catch (e) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            child: Text(status == 'approved' ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isReviewQueue = _canReview && _tabController.index == 1;
    final currentItems = _requests.where((r) {
      if (isReviewQueue) return true;
      return r['employee_id']?.toString() == _uid;
    }).toList();

    final pendingCount = currentItems
        .where((r) => r['status'] == 'pending')
        .length;
    final approvedCount = currentItems
        .where((r) => r['status'] == 'approved')
        .length;
    final rejectedCount = currentItems
        .where((r) => r['status'] == 'rejected')
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WorkspaceHeading(
          title: 'Attendance Adjustments',
          action: FilledButton.icon(
            onPressed: _requestAdjustment,
            icon: const Icon(Icons.edit_calendar),
            label: const Text('Request Adjustment'),
          ),
        ),
        const SizedBox(height: 16),
        // KPI Summary Cards Header
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 800;
            return GridView.count(
              crossAxisCount: isWide ? 4 : 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: isWide ? 1.8 : 1.5,
              children: [
                MetricCard(
                  title: 'Pending Review',
                  value: '$pendingCount',
                  icon: Icons.pending_actions,
                  accentColor: Colors.orange,
                ),
                MetricCard(
                  title: 'Approved',
                  value: '$approvedCount',
                  icon: Icons.check_circle_outline,
                  accentColor: Colors.green,
                ),
                MetricCard(
                  title: 'Rejected',
                  value: '$rejectedCount',
                  icon: Icons.cancel_outlined,
                  accentColor: Colors.red,
                ),
                MetricCard(
                  title: 'Total Requests',
                  value: '${currentItems.length}',
                  icon: Icons.list_alt,
                  accentColor: const Color(0xFF6366F1),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        if (_canReview)
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'My Requests'),
              Tab(text: 'Review Queue'),
            ],
          ),
        const SizedBox(height: 16),
        // Filters & Search Bar Card
        GlassCard(
          padding: const EdgeInsets.all(12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 700;
              if (isWide) {
                return Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Search by employee or reason...',
                          prefixIcon: Icon(Icons.search, size: 18),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() => _searchFilter = v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: _statusFilter,
                        decoration: const InputDecoration(
                          labelText: 'Status',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'All',
                            child: Text('All Statuses'),
                          ),
                          DropdownMenuItem(
                            value: 'pending',
                            child: Text('Pending'),
                          ),
                          DropdownMenuItem(
                            value: 'approved',
                            child: Text('Approved'),
                          ),
                          DropdownMenuItem(
                            value: 'rejected',
                            child: Text('Rejected'),
                          ),
                        ],
                        onChanged: (v) =>
                            setState(() => _statusFilter = v ?? 'All'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: _typeFilter,
                        decoration: const InputDecoration(
                          labelText: 'Request Type',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'All',
                            child: Text('All Types'),
                          ),
                          DropdownMenuItem(
                            value: 'regularisation',
                            child: Text('Regularisation'),
                          ),
                          DropdownMenuItem(
                            value: 'late_arrival',
                            child: Text('Late Arrival'),
                          ),
                          DropdownMenuItem(
                            value: 'early_departure',
                            child: Text('Early Departure'),
                          ),
                        ],
                        onChanged: (v) =>
                            setState(() => _typeFilter = v ?? 'All'),
                      ),
                    ),
                  ],
                );
              } else {
                return Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search by employee or reason...',
                        prefixIcon: Icon(Icons.search, size: 18),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _searchFilter = v),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _statusFilter,
                            decoration: const InputDecoration(
                              labelText: 'Status',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'All',
                                child: Text('All Statuses'),
                              ),
                              DropdownMenuItem(
                                value: 'pending',
                                child: Text('Pending'),
                              ),
                              DropdownMenuItem(
                                value: 'approved',
                                child: Text('Approved'),
                              ),
                              DropdownMenuItem(
                                value: 'rejected',
                                child: Text('Rejected'),
                              ),
                            ],
                            onChanged: (v) =>
                                setState(() => _statusFilter = v ?? 'All'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _typeFilter,
                            decoration: const InputDecoration(
                              labelText: 'Request Type',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'All',
                                child: Text('All Types'),
                              ),
                              DropdownMenuItem(
                                value: 'regularisation',
                                child: Text('Regularisation'),
                              ),
                              DropdownMenuItem(
                                value: 'late_arrival',
                                child: Text('Late Arrival'),
                              ),
                              DropdownMenuItem(
                                value: 'early_departure',
                                child: Text('Early Departure'),
                              ),
                            ],
                            onChanged: (v) =>
                                setState(() => _typeFilter = v ?? 'All'),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              }
            },
          ),
        ),
        const SizedBox(height: 16),
        _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(child: Text('Error: $_error'))
            : _buildList(currentItems, isReviewQueue),
      ],
    );
  }

  Widget _buildList(List<Map<String, dynamic>> items, bool isReviewQueue) {
    final filtered = items.where((r) {
      final name = _employeeName(r['employee_id']).toLowerCase();
      final reason = (r['reason'] ?? '').toString().toLowerCase();
      final status = (r['status'] ?? 'pending').toString().toLowerCase();
      final kind = (r['request_kind'] ?? '').toString().toLowerCase();

      final matchesQuery =
          _searchFilter.isEmpty ||
          name.contains(_searchFilter.toLowerCase()) ||
          reason.contains(_searchFilter.toLowerCase());

      final matchesStatus =
          _statusFilter == 'All' || status == _statusFilter.toLowerCase();

      final matchesType =
          _typeFilter == 'All' ||
          kind == _typeFilter.toLowerCase() ||
          (r['adjustment_type'] ?? '').toString().toLowerCase() ==
              _typeFilter.toLowerCase();

      return matchesQuery && matchesStatus && matchesType;
    }).toList();

    if (filtered.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.edit_calendar,
        title: 'No adjustment requests found',
        message: 'No attendance requests match the selected filters or search query.',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossCount = constraints.maxWidth >= 900 ? 2 : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: crossCount == 2 ? 2.2 : 1.8,
          ),
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final r = filtered[index];
            final isRegularisation = r['request_kind'] == 'regularisation';
            final type = isRegularisation
                ? 'Attendance Regularisation'
                : r['adjustment_type'] == 'late_arrival'
                ? 'Late Arrival'
                : 'Early Departure';
            final dateStr =
                r['request_date'] ??
                r['created_at']?.toString().split('T')[0] ??
                '-';
            final status = (r['status'] ?? 'pending').toString();
            final empName = _employeeName(r['employee_id']);

            Color statusColor = Colors.orange;
            if (status == 'approved') statusColor = Colors.green;
            if (status == 'rejected') statusColor = Colors.red;

            return GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: statusColor.withValues(alpha: 0.15),
                        child: Icon(
                          isRegularisation
                              ? Icons.edit_calendar
                              : r['adjustment_type'] == 'late_arrival'
                              ? Icons.login
                              : Icons.logout,
                          color: statusColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              empName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '$type • $dateStr',
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
                      StatusBadge(
                        label: status.toUpperCase(),
                        color: statusColor,
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  Text(
                    isRegularisation
                        ? 'Punches: ${_regularisationSummary(r)}'
                        : 'Duration: ${r['duration_minutes']} mins',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Reason: ${r['reason'] ?? 'No reason provided'}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (r['review_comment'] != null &&
                      r['review_comment'].toString().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Reviewer Comment: ${r['review_comment']}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: Colors.grey,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const Spacer(),
                  if (isReviewQueue &&
                      status == 'pending' &&
                      (!isRegularisation ||
                          [
                            'hr',
                            'admin',
                            'super_admin',
                          ].contains(widget.role))) ...[
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.green,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            onPressed: () => _reviewRequest(r, 'approved'),
                            icon: const Icon(Icons.check, size: 16),
                            label: const Text(
                              'Approve',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            onPressed: () => _reviewRequest(r, 'rejected'),
                            icon: const Icon(Icons.close, size: 16),
                            label: const Text(
                              'Reject',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}
