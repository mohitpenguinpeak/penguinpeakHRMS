import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/performance_repository.dart';
import '../domain/performance_report.dart';

class PerformanceWorkspace extends StatefulWidget {
  const PerformanceWorkspace({super.key, this.employeeId, this.repository});
  final String? employeeId;
  final PerformanceRepository? repository;

  @override
  State<PerformanceWorkspace> createState() => _PerformanceWorkspaceState();
}

class _PerformanceWorkspaceState extends State<PerformanceWorkspace> {
  late final PerformanceRepository _repository =
      widget.repository ??
      SupabasePerformanceRepository(Supabase.instance.client);
  PerformancePeriod _period = PerformancePeriod.monthly;
  DateTime? _anchor;
  PerformanceReport? _report;
  PerformanceReport? _previous;
  String? _employee;
  String? _error;
  bool _loading = true;
  int _revision = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!_loading) _load();
    });
  }

  @override
  void didUpdateWidget(covariant PerformanceWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.employeeId != widget.employeeId) {
      _employee = null;
      _load();
    }
  }

  @override
  void dispose() {
    _revision++;
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final revision = ++_revision;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await _repository.load(
        _period,
        anchor: _anchor,
        employeeId: widget.employeeId,
      );
      final previous = await _repository.load(
        _period,
        anchor: report.start.subtract(const Duration(days: 1)),
        employeeId: widget.employeeId,
      );
      if (!mounted || revision != _revision) return;
      setState(() {
        _report = report;
        _previous = previous;
        if (!report.employees.any((e) => e.id == _employee)) {
          final preferred = widget.employeeId ?? _repository.currentUserId;
          _employee = report.employees.any((e) => e.id == preferred)
              ? preferred
              : report.employees.firstOrNull?.id;
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted || revision != _revision) return;
      setState(() {
        _loading = false;
        _error =
            error is PostgrestException &&
                (error.code == 'PGRST202' || error.code == '42883')
            ? 'Performance setup is pending. Apply the automated performance database migration.'
            : 'Could not load performance. Check your connection and access, then retry.';
      });
    }
  }

  Future<void> _chooseDate() async {
    final today = _report?.today ?? DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _anchor ?? today,
      firstDate: DateTime(1970),
      lastDate: today,
    );
    if (selected == null || !mounted) return;
    _anchor = selected;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final employee = report?.employees
        .where((e) => e.id == _employee)
        .firstOrNull;
    final previous = _previous?.employees
        .where((e) => e.id == _employee)
        .firstOrNull;
    final delta = employee?.score != null && previous?.score != null
        ? employee!.score! - previous!.score!
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Text(
              'Performance',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            IconButton(
              onPressed: _loading ? null : _load,
              tooltip: 'Refresh performance',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const Text('Automatic KPI scorecards • Same matrix for every period'),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final period in PerformancePeriod.values)
              ChoiceChip(
                label: Text(period.label),
                selected: _period == period,
                onSelected: _loading
                    ? null
                    : (_) {
                        _period = period;
                        _load();
                      },
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _loading ? null : _chooseDate,
              icon: const Icon(Icons.calendar_month),
              label: const Text('Choose date'),
            ),
            TextButton(
              onPressed: _loading
                  ? null
                  : () {
                      _anchor = null;
                      _load();
                    },
              child: const Text('Current period'),
            ),
            if (report != null)
              Text(
                '${performanceDate(report.start)} – ${performanceDate(report.end)}',
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null) ...[
          Text(_error!),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: _load, child: const Text('Retry')),
          ),
        ] else if (employee == null)
          const Text('No approved employees available in your access scope.')
        else ...[
          if (report!.employees.length > 1) ...[
            DropdownButtonFormField<String>(
              key: ValueKey(_employee),
              initialValue: _employee,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Employee',
                border: OutlineInputBorder(),
              ),
              items: report.employees
                  .map(
                    (e) => DropdownMenuItem(
                      value: e.id,
                      child: Text(
                        '${e.name} • ${e.department}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (id) => setState(() => _employee = id),
            ),
            const SizedBox(height: 12),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    employee.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    employee.score == null
                        ? 'No data'
                        : '${employee.score!.toStringAsFixed(1)} / 100',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  Text(employee.rating),
                  if (delta != null)
                    Text(
                      '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)} points vs previous period',
                    ),
                  Text(
                    report.provisional
                        ? 'Provisional • Period in progress'
                        : 'Historical • Recalculated from current records',
                  ),
                  Text(
                    'KPI coverage: ${employee.value('available_weight')?.toInt() ?? 0}% of matrix',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 680
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _metric(
                    width,
                    employee,
                    'Task completion',
                    'completion',
                    50,
                    '${_number(employee, 'completed_tasks')} / ${_number(employee, 'task_count')} eligible tasks',
                  ),
                  _metric(
                    width,
                    employee,
                    'On-time delivery',
                    'delivery',
                    20,
                    '${_number(employee, 'on_time_tasks')} / ${_number(employee, 'dated_tasks')} dated tasks',
                  ),
                  _metric(
                    width,
                    employee,
                    'Attendance',
                    'attendance',
                    20,
                    '${_number(employee, 'attended_days')} / ${_number(employee, 'expected_days')} expected days',
                  ),
                  _metric(
                    width,
                    employee,
                    'Punctuality',
                    'punctuality',
                    10,
                    '${_number(employee, 'on_time_days')} / ${_number(employee, 'punctual_days')} eligible attended days',
                  ),
                ],
              );
            },
          ),
          if ((employee.value('unknown_completion_dates') ?? 0) > 0)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Some completed tasks have no completion timestamp. They count toward completion, but are excluded from on-time delivery.',
              ),
            ),
          const SizedBox(height: 12),
          Text(
            'Company timezone: ${report.timezone}. Refreshes every minute while open.',
          ),
          const ExpansionTile(
            key: PageStorageKey<String>('performance-kpi-explanation'),
            title: Text('How the KPI matrix works'),
            tilePadding: EdgeInsets.zero,
            children: [
              Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  'Score = task completion × 50% + on-time delivery × 20% + attendance × 20% + punctuality × 10%. '
                  'Metrics without evidence are excluded and remaining weights are normalized; coverage shows how much of the matrix was measured. '
                  'Periods use calendar boundaries; weeks start Monday and quarters start January, April, July and October. '
                  'Tasks are grouped by due date; undated tasks count only when completed in the period. Declined and unaccepted tasks are excluded. '
                  'Attendance uses Monday–Friday, excludes holidays, approved leave and dates before joining. Half-day attendance earns half credit; approved half-day leave reduces the expected day by half. '
                  'Today is included only once a check-in exists. Punctuality excludes approved half-day leave. '
                  'Historical scores can change after corrections or task edits. These operational KPIs are inputs for a review, not a complete assessment of work quality.',
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  String _number(PerformanceEmployee e, String key) {
    final value = e.value(key) ?? 0;
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(1);
  }

  Widget _metric(
    double width,
    PerformanceEmployee employee,
    String title,
    String key,
    int weight,
    String evidence,
  ) {
    final value = employee.value(key);
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$title • $weight%',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                value == null ? 'No data' : '${value.toStringAsFixed(1)}%',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: (value ?? 0).clamp(0, 100) / 100),
              const SizedBox(height: 8),
              Text(evidence),
            ],
          ),
        ),
      ),
    );
  }
}
