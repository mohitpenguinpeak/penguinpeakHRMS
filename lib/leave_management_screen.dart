import 'package:penguinpeak_hrms/shared/widgets/company_calendar.dart';
import 'package:flutter/material.dart';

import 'shared/widgets/adaptive_layout.dart';
import 'shared/widgets/app_toast.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/leave/domain/leave_request.dart';
import 'features/leave/presentation/leave_day_selector.dart';
import 'features/leave/presentation/employee_leave_balances.dart';
import 'features/leave/data/leave_repository.dart';

class LeaveManagementScreen extends StatefulWidget {
  final String role;

  const LeaveManagementScreen({super.key, required this.role});

  @override
  State<LeaveManagementScreen> createState() => _LeaveManagementScreenState();
}

class _LeaveManagementScreenState extends State<LeaveManagementScreen> {
  final SupabaseClient _db = Supabase.instance.client;
  final _leaveActions = LeaveRepository(Supabase.instance.client);
  bool _loading = true;
  String? _error;
  String? _myManagerId;
  List<Map<String, dynamic>> _profiles = [];
  List<Map<String, dynamic>> _requests = [];
  List<Map<String, dynamic>> _balances = [];

  String? get _uid => _db.auth.currentUser?.id;
  bool get _isHr => widget.role == 'hr';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = _uid;
      if (uid == null)
        throw Exception('Your session has expired. Please log in again.');

      final ownProfile = await _db
          .from('profiles')
          .select('id, manager_id')
          .eq('id', uid)
          .maybeSingle();
      _myManagerId = ownProfile?['manager_id']?.toString();

      final requestsResult = await _db
          .from('leave_requests')
          .select('*')
          .order('created_at', ascending: false);
      _requests = List<Map<String, dynamic>>.from(requestsResult);

      final balanceResult = await _db
          .from('leave_balances')
          .select('*')
          .order('leave_type');
      _balances = List<Map<String, dynamic>>.from(balanceResult);

      final profilesResult = await _db
          .from('profiles')
          .select('id, full_name, role, approval_status, manager_id')
          .eq('approval_status', 'approved')
          .order('full_name');
      _profiles = List<Map<String, dynamic>>.from(profilesResult);

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

  String _employeeName(dynamic id) {
    final key = id?.toString();
    for (final p in _profiles) {
      if (p['id']?.toString() == key) {
        final name = (p['full_name'] ?? '').toString().trim();
        return name.isEmpty ? 'Unnamed employee' : name;
      }
    }
    return 'Employee';
  }

  String _requestStatus(Map<String, dynamic> request) =>
      LeaveRequest(request).status;

  Color _statusColor(String status) {
    if (status == 'Cancelled') return Colors.grey;
    if (status == 'Approved' || status == 'Partially approved') {
      return Colors.green;
    }
    if (status.startsWith('Rejected')) return Colors.red;
    return Colors.orange;
  }

  Future<void> _applyLeave() async {
    final calendar = CompanyCalendar.of(context);
    if (!calendar.available) {
      _toast('Refresh the company calendar before requesting leave.');
      return;
    }
    final availableTypes = _balances
        .where((b) => b['employee_id']?.toString() == _uid)
        .map((b) => b['leave_type'].toString())
        .toSet()
        .toList();
    final types = availableTypes.isEmpty
        ? <String>['Annual', 'Sick', 'Casual']
        : availableTypes;
    String leaveType = types.first;
    DateTime? startDate;
    DateTime? endDate;
    bool halfDay = false;
    String? half;
    final reasonController = TextEditingController();
    bool submitting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Apply for leave'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: leaveType,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Leave type'),
                    items: types
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => leaveType = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  LeaveDaySelector(
                    halfDay: halfDay,
                    half: half,
                    onModeChanged: (value) => setDialogState(() {
                      halfDay = value;
                      if (halfDay) endDate = startDate;
                    }),
                    onHalfChanged: (value) => setDialogState(() {
                      half = value;
                    }),
                  ),
                  const SizedBox(height: 12),
                  _dateButton(
                    label: startDate == null
                        ? 'Select start date'
                        : 'From: ${_dateText(startDate!)}',
                    onPressed: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: startDate,
                        selectableDayPredicate: calendar.works,
                        firstDate: DateTime(now.year - 1),
                        lastDate: DateTime(now.year + 5),
                      );
                      if (picked != null)
                        setDialogState(() {
                          startDate = picked;
                          if (halfDay) endDate = picked;
                          if (endDate != null && endDate!.isBefore(picked))
                            endDate = picked;
                        });
                    },
                  ),
                  const SizedBox(height: 8),
                  if (!halfDay)
                    _dateButton(
                      label: endDate == null
                          ? 'Select end date'
                          : 'To: ${_dateText(endDate!)}',
                      onPressed: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: endDate ?? startDate,
                          selectableDayPredicate: calendar.works,
                          firstDate: startDate ?? DateTime(now.year - 1),
                          lastDate: DateTime(now.year + 5),
                        );
                        if (picked != null)
                          setDialogState(() => endDate = picked);
                      },
                    ),
                  if (startDate != null && endDate != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          halfDay
                              ? '0.5 day'
                              : '${calendar.count(startDate!, endDate!)} working day(s)',
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Reason',
                      hintText: 'Briefly explain your leave request',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_myManagerId == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'Your reporting manager has not been assigned. Ask HR to set “Reports to” first.',
                        style: TextStyle(color: Colors.orange),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      if (startDate == null || endDate == null) {
                        _toast('Please select both leave dates');
                        return;
                      }
                      if (halfDay && half == null) {
                        _toast('Please select First Half or Second Half');
                        return;
                      }
                      if (reasonController.text.trim().isEmpty) {
                        _toast('Please enter a reason');
                        return;
                      }
                      setDialogState(() => submitting = true);
                      try {
                        await _db.rpc(
                          'apply_for_leave_duration',
                          params: {
                            'p_leave_type': leaveType,
                            'p_start_date': _dateText(startDate!),
                            'p_end_date': _dateText(endDate!),
                            'p_day_portion': halfDay ? half : 'full_day',
                            'p_reason': reasonController.text.trim(),
                          },
                        );
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        await _load();
                        _toast('Leave request submitted to your manager');
                      } catch (e) {
                        setDialogState(() => submitting = false);
                        _toast('Could not submit leave: $e');
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Submit request'),
            ),
          ],
        ),
      ),
    );
    reasonController.dispose();
  }

  Widget _dateButton({
    required String label,
    required VoidCallback onPressed,
  }) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: const Icon(Icons.calendar_month_outlined),
    label: Text(label),
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(44),
      alignment: Alignment.centerLeft,
    ),
  );

  String _dateText(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _reviewManager(
    Map<String, dynamic> request,
    String decision,
  ) async {
    final comment = await _commentDialog(
      decision == 'approved' ? 'Approve leave' : 'Reject leave',
    );
    if (comment == null) return;
    try {
      await _db.rpc(
        'review_leave_by_manager',
        params: {
          'p_request_id': request['id'],
          'p_decision': decision,
          'p_comment': comment,
        },
      );
      await _load();
      _toast(
        decision == 'approved'
            ? 'Forwarded to HR for final approval'
            : 'Leave rejected by manager',
      );
    } catch (e) {
      _toast('Could not review leave: $e');
    }
  }

  Future<void> _reviewHr(Map<String, dynamic> request, String decision) async {
    final comment = await _commentDialog(
      decision == 'approved' ? 'Final HR approval' : 'Reject leave',
    );
    if (comment == null) return;
    try {
      await _db.rpc(
        'review_leave_by_hr',
        params: {
          'p_request_id': request['id'],
          'p_decision': decision,
          'p_comment': comment,
        },
      );
      await _load();
      _toast(
        decision == 'approved'
            ? 'Leave finally approved; balance deducted'
            : 'Leave rejected by HR',
      );
    } catch (e) {
      _toast('Could not review leave: $e');
    }
  }

  Future<void> _approveRange(Map<String, dynamic> request) async {
    final first = DateTime.parse(request['start_date'].toString());
    final last = DateTime.parse(request['end_date'].toString());
    final calendar = CompanyCalendar.of(context);
    final range = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      selectableDayPredicate: (day, _, _) => calendar.works(day),
      initialDateRange: calendar.works(first) && calendar.works(last) ? DateTimeRange(start: first, end: last) : null,
      helpText: 'Select dates to approve',
    );
    if (range == null || !mounted) return;
    final comment = await _commentDialog('Approve selected dates');
    if (comment == null) return;
    try {
      await _leaveActions.approveRange(
        id: request['id'].toString(),
        firstDay: _dateText(range.start),
        lastDay: _dateText(range.end),
        comment: comment,
      );
      if (!mounted) return;
      await _load();
      _toast('Selected dates approved; balance updated');
    } catch (error) {
      _toast('Could not approve dates: $error');
    }
  }

  Future<void> _cancelRequest(Map<String, dynamic> request) async {
    final reason = await _commentDialog('Cancel leave — enter a reason');
    if (reason == null) return;
    if (reason.isEmpty) {
      _toast('A cancellation reason is required');
      return;
    }
    try {
      await _leaveActions.cancel(request['id'].toString(), reason);
      if (!mounted) return;
      await _load();
      _toast('Leave cancelled; any deducted balance has been restored');
    } catch (error) {
      _toast('Could not cancel leave: $error');
    }
  }

  Future<void> _showHistory(Map<String, dynamic> request) async {
    final history = _leaveActions.history(request['id'].toString());
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave history'),
        content: SizedBox(
          width: 480,
          height: 340,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: history,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text('Could not load history. Close and retry.');
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final rows = snapshot.data!;
              if (rows.isEmpty) {
                return const Text(
                  'No history recorded before this feature was enabled.',
                );
              }
              return ListView(
                children: rows.map((entry) {
                  final details = entry['details'] as Map? ?? {};
                  final actor = _employeeName(entry['actor_id']);
                  return ListTile(
                    title: Text('${entry['action']} • $actor'),
                    subtitle: Text(
                      '${entry['created_at']}\n'
                      '${details['approved_start'] ?? details['requested_start']} → '
                      '${details['approved_end'] ?? details['requested_end']}'
                      '${details['approved_days'] == null ? '' : ' • ${details['approved_days']} approved days'}'
                      '${details['cancellation_reason'] == null ? '' : '\n${details['cancellation_reason']}'}',
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<String?> _commentDialog(String title) async {
    final controller = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Comment (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _manageBalance({
    String? initialEmployeeId,
    String? initialLeaveType,
  }) async {
    if (!_isHr) return;
    final eligible = _profiles
        .where((p) => ['employee', 'hr'].contains(p['role']))
        .toList();
    if (eligible.isEmpty) {
      _toast('No approved Employee or HR profiles found');
      return;
    }
    String employeeId =
        eligible.any((p) => p['id'].toString() == initialEmployeeId)
        ? initialEmployeeId!
        : eligible.first['id'].toString();
    String typeKey(String name) => name.trim().toLowerCase();
    final labels = <String, String>{};
    for (final name in [
      'Annual',
      'Sick',
      'Casual',
      'Unpaid Leaves',
      ..._balances.map((row) => row['leave_type']).whereType<String>(),
    ]) {
      if (name.trim().isNotEmpty) {
        labels.putIfAbsent(typeKey(name), () => name.trim());
      }
    }
    String leaveType =
        labels[typeKey(initialLeaveType ?? 'Annual')] ?? 'Annual';
    String storedType = initialLeaveType ?? leaveType;
    final daysController = TextEditingController();
    bool unlimited = false;
    void fillAllocation() {
      final matches = _balances.where(
        (row) =>
            row['employee_id']?.toString() == employeeId &&
            typeKey(row['leave_type'].toString()) == typeKey(leaveType),
      );
      final existing =
          matches.where((row) => row['leave_type'] == storedType).firstOrNull ??
          matches.firstOrNull;
      storedType = existing?['leave_type']?.toString() ?? leaveType;
      daysController.text = existing?['allocated_days']?.toString() ?? '';
      unlimited = existing?['is_unlimited'] == true;
    }

    fillAllocation();
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Manage leave balance'),
          scrollable: true,
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: employeeId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Employee / HR'),
                  items: eligible
                      .map(
                        (p) => DropdownMenuItem(
                          value: p['id'].toString(),
                          child: Text(
                            '${p['full_name'] ?? 'Unnamed'} (${p['role']})',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null)
                      setDialogState(() {
                        employeeId = v;
                        fillAllocation();
                      });
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: leaveType,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Leave type'),
                  items: [
                    for (final type in (labels.values.toList()..sort()))
                      DropdownMenuItem(value: type, child: Text(type)),
                  ],
                  onChanged: saving
                      ? null
                      : (type) {
                          if (type == null) return;
                          setDialogState(() {
                            leaveType = type;
                            fillAllocation();
                          });
                        },
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add leave type'),
                    onPressed: saving
                        ? null
                        : () async {
                            String draft = '';
                            final name = await showDialog<String>(
                              context: context,
                              builder: (prompt) => AlertDialog(
                                title: const Text('Add leave type'),
                                content: TextField(
                                  autofocus: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Type name',
                                  ),
                                  onChanged: (value) => draft = value.trim(),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(prompt),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () {
                                      if (draft.isNotEmpty)
                                        Navigator.pop(prompt, draft);
                                    },
                                    child: const Text('Select type'),
                                  ),
                                ],
                              ),
                            );
                            if (name == null || !context.mounted) return;
                            setDialogState(() {
                              leaveType = labels.putIfAbsent(
                                typeKey(name),
                                () => name,
                              );
                              fillAllocation();
                            });
                          },
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Unlimited allocation'),
                  subtitle: const Text(
                    'Track used days without a fixed day limit.',
                  ),
                  value: unlimited,
                  onChanged: saving
                      ? null
                      : (value) => setDialogState(() {
                          unlimited = value;
                        }),
                ),
                if (!unlimited)
                  TextField(
                    controller: daysController,
                    enabled: !saving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Total allocated days',
                      border: OutlineInputBorder(),
                    ),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'Used days are system-controlled and are deducted only after final HR approval.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final days = num.tryParse(daysController.text.trim());
                      if (leaveType.trim().isEmpty ||
                          (!unlimited &&
                              (days == null || !days.isFinite || days < 0))) {
                        _toast(
                          'Enter a leave type and valid non-negative day total',
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        await _db.rpc(
                          'set_employee_leave_allocation',
                          params: {
                            'p_employee_id': employeeId,
                            'p_leave_type': storedType,
                            'p_allocated_days': unlimited ? null : days,
                            'p_is_unlimited': unlimited,
                          },
                        );
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        await _load();
                        _toast('Leave balance saved');
                      } catch (e) {
                        setDialogState(() => saving = false);
                        _toast('Could not save balance: $e');
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save balance'),
            ),
          ],
        ),
      ),
    );
    daysController.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    final kind = message.startsWith('Could not')
        ? ToastKind.error
        : message.contains('saved') ||
              message.contains('submitted') ||
              message.contains('approved') ||
              message.contains('cancelled') ||
              message.contains('rejected')
        ? ToastKind.success
        : ToastKind.info;
    AppToast.show(context, message, kind: kind);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    if (_error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Could not load leave data',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SelectableText(_error!),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      );
    }

    final uid = _uid;
    final myRequests = _requests
        .where((r) => r['employee_id']?.toString() == uid)
        .toList();
    final managerQueue = _requests
        .where(
          (r) =>
              r['cancelled_at'] == null &&
              r['manager_id']?.toString() == uid &&
              r['manager_status'] == 'pending',
        )
        .toList();
    final hrQueue = _isHr
        ? _requests
              .where(
                (r) =>
                    r['cancelled_at'] == null &&
                    r['manager_status'] == 'approved' &&
                    r['hr_status'] == 'pending',
              )
              .toList()
        : <Map<String, dynamic>>[];
    final myBalances = _balances
        .where((b) => b['employee_id']?.toString() == uid)
        .toList();
    final visibleBalances = _isHr
        ? _balances
              .where(
                (b) => _profiles.any(
                  (p) =>
                      p['id']?.toString() == b['employee_id']?.toString() &&
                      ['employee', 'hr'].contains(p['role']),
                ),
              )
              .toList()
        : myBalances;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Leave management',
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Manager approval first, then final HR approval. Balance is deducted only after HR approves.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: _applyLeave,
              icon: const Icon(Icons.add),
              label: const Text('Apply for leave'),
            ),
            if (_isHr)
              OutlinedButton.icon(
                onPressed: _manageBalance,
                icon: const Icon(Icons.tune),
                label: const Text('Manage balances'),
              ),
          ],
        ),
        const SizedBox(height: 24),
        _sectionTitle('My leave balance'),
        if (myBalances.isEmpty)
          const _InfoCard(
            message: 'No leave balance configured yet. Ask HR to allocate your leave days.',
          )
        else
          _balanceCards(myBalances),
        const SizedBox(height: 24),
        if (managerQueue.isNotEmpty) ...[
          _sectionTitle('Manager approvals (${managerQueue.length})'),
          const Text('Requests from employees who report directly to you.'),
          const SizedBox(height: 8),
          AdaptiveCards(
            children: managerQueue
                .map((r) => _requestCard(r, managerActions: true))
                .toList(),
          ),
          const SizedBox(height: 20),
        ],
        if (_isHr) ...[
          _sectionTitle('Pending with HR (${hrQueue.length})'),
          const Text(
            'Only manager-approved requests appear here. HR approval is the final step.',
          ),
          const SizedBox(height: 8),
          if (hrQueue.isEmpty)
            const _InfoCard(
              message: 'No leave requests are waiting for HR approval.',
            ),
          AdaptiveCards(
            children: hrQueue
                .map((r) => _requestCard(r, hrActions: true))
                .toList(),
          ),
          const SizedBox(height: 20),
          _sectionTitle('Manage employee and HR balances'),
          if (visibleBalances.isEmpty)
            const _InfoCard(
              message: 'No balances configured for approved Employee or HR accounts yet.',
            )
          else
            _balanceCards(visibleBalances, showEmployee: true),
          const SizedBox(height: 20),
        ],
        _sectionTitle('My leave requests (${myRequests.length})'),
        if (myRequests.isEmpty)
          const _InfoCard(
            message: 'You have not submitted any leave requests yet.',
          )
        else
          AdaptiveCards(
            children: myRequests.map((r) => _requestCard(r)).toList(),
          ),
      ],
    );
  }

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.bold),
    ),
  );

  Widget _balanceCards(
    List<Map<String, dynamic>> balances, {
    bool showEmployee = false,
  }) => EmployeeLeaveBalances(
    balances: balances,
    employeeName: _employeeName,
    showEmployee: showEmployee,
    onManageEmployee: _isHr && showEmployee
        ? (id) => _manageBalance(initialEmployeeId: id)
        : null,
    onManageType: _isHr && showEmployee
        ? (id, type) =>
              _manageBalance(initialEmployeeId: id, initialLeaveType: type)
        : null,
  );

  Widget _requestCard(
    Map<String, dynamic> r, {
    bool managerActions = false,
    bool hrActions = false,
  }) {
    final status = _requestStatus(r);
    final color = _statusColor(status);
    final isOwn = r['employee_id']?.toString() == _uid;
    final employeeName = _employeeName(r['employee_id']);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                Text(
                  isOwn
                      ? r['leave_type'].toString()
                      : '$employeeName • ${r['leave_type']}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${r['start_date']} → ${r['end_date']}  •  ${r['days']} day(s)',
            ),
            const SizedBox(height: 4),
            Text(LeaveRequest(r).durationLabel),
            Text('Reason: ${r['reason']}'),
            if (r['approved_days'] != null)
              Text(
                'Approved: ${r['approved_start_date']} → ${r['approved_end_date']} • ${r['approved_days']} day(s)',
              ),
            if (r['cancelled_at'] != null)
              Text('Cancelled: ${r['cancellation_reason'] ?? ''}'),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () => _showHistory(r),
                  icon: const Icon(Icons.history),
                  label: const Text('History'),
                ),
                if ((isOwn || _isHr) &&
                    LeaveRequest(r).canCancelOn(DateTime.now()))
                  TextButton.icon(
                    onPressed: () => _cancelRequest(r),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Cancel leave'),
                  ),
              ],
            ),
            if ((r['manager_comment'] ?? '').toString().isNotEmpty)
              Text('Manager comment: ${r['manager_comment']}'),
            if ((r['hr_comment'] ?? '').toString().isNotEmpty)
              Text('HR comment: ${r['hr_comment']}'),
            if (managerActions || hrActions) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => managerActions
                        ? _reviewManager(r, 'approved')
                        : _reviewHr(r, 'approved'),
                    icon: const Icon(Icons.check, size: 18),
                    label: Text(
                      managerActions ? 'Approve & send to HR' : 'Final approve',
                    ),
                  ),
                  if (hrActions)
                    OutlinedButton.icon(
                      onPressed: () => _approveRange(r),
                      icon: const Icon(Icons.date_range),
                      label: const Text('Approve selected dates'),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => managerActions
                        ? _reviewManager(r, 'rejected')
                        : _reviewHr(r, 'rejected'),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Reject'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String message;
  const _InfoCard({required this.message});
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}
