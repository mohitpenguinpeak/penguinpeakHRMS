import 'package:flutter/material.dart';

import '../domain/leave_request.dart';

class TeamLeaveCalendar extends StatefulWidget {
  const TeamLeaveCalendar({
    super.key,
    required this.leaves,
    required this.profiles,
    required this.onRefresh,
    this.initialDate,
  });
  final List<Map<String, dynamic>> leaves;
  final List<Map<String, dynamic>> profiles;
  final VoidCallback onRefresh;
  final DateTime? initialDate;
  @override
  State<TeamLeaveCalendar> createState() => _TeamLeaveCalendarState();
}

class _TeamLeaveCalendarState extends State<TeamLeaveCalendar> {
  late DateTime _selected;
  late DateTime _month;
  bool _calendar = true;
  static const _months = [
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
  @override
  void initState() {
    super.initState();
    final now = widget.initialDate ?? DateTime.now();
    _selected = DateTime(now.year, now.month, now.day);
    _month = DateTime(now.year, now.month);
  }

  String _date(DateTime date) =>
      '${date.day} ${_months[date.month - 1]} ${date.year}';
  void _move(int delta) => setState(() {
    _month = DateTime(_month.year, _month.month + delta);
    _selected = _month;
  });
  List<Map<String, dynamic>> _on(DateTime day) =>
      widget.leaves.where((leave) => LeaveRequest(leave).covers(day)).toList();
  Map<String, dynamic>? _profile(dynamic id) => widget.profiles
      .where((p) => p['id']?.toString() == id?.toString())
      .firstOrNull;

  Widget _leaveCard(Map<String, dynamic> row) {
    final profile = _profile(row['employee_id']);
    final leave = LeaveRequest(row);
    final now = DateTime.now();
    final start = DateTime.tryParse(leave.approvedStart);
    final end = DateTime.tryParse(leave.approvedEnd);
    final state = leave.covers(now)
        ? 'On leave today'
        : start != null && start.isAfter(now)
        ? 'Upcoming'
        : 'Past leave';
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: const Icon(Icons.event_available),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${profile?['full_name'] ?? 'Employee'}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${profile?['department'] ?? 'General'} · ${row['leave_type'] ?? 'Leave'} · ${leave.durationLabel}',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    start == null || end == null
                        ? 'Dates unavailable'
                        : '${_date(start)} – ${_date(end)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final monthEnd = DateTime(_month.year, _month.month + 1, 0);
    final monthLeaves = widget.leaves.where((row) {
      final leave = LeaveRequest(row);
      final start = DateTime.tryParse(leave.approvedStart);
      final end = DateTime.tryParse(leave.approvedEnd);
      return leave.isFinallyApproved &&
          start != null &&
          end != null &&
          !start.isAfter(monthEnd) &&
          !end.isBefore(_month);
    }).toList();
    final selectedLeaves = _on(_selected);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Team Leave Calendar',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Chip(
              avatar: Icon(Icons.verified_user_outlined, size: 16),
              label: Text('Approved leave only'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Explore team availability. Reasons and medical notes remain private.',
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        IconButton(
                          tooltip: 'Previous month',
                          onPressed: () => _move(-1),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Text(
                          '${_months[_month.month - 1]} ${_month.year}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        IconButton(
                          tooltip: 'Next month',
                          onPressed: () => _move(1),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () => setState(() {
                            final now = DateTime.now();
                            _selected = DateTime(now.year, now.month, now.day);
                            _month = DateTime(now.year, now.month);
                          }),
                          child: const Text('Today'),
                        ),
                        ChoiceChip(
                          label: const Text('Calendar'),
                          selected: _calendar,
                          onSelected: (_) => setState(() {
                            _calendar = true;
                          }),
                        ),
                        ChoiceChip(
                          label: const Text('List'),
                          selected: !_calendar,
                          onSelected: (_) => setState(() {
                            _calendar = false;
                          }),
                        ),
                        IconButton(
                          tooltip: 'Refresh leave',
                          onPressed: widget.onRefresh,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                  ],
                ),
                if (_calendar) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      for (final day in [
                        'Mon',
                        'Tue',
                        'Wed',
                        'Thu',
                        'Fri',
                        'Sat',
                        'Sun',
                      ])
                        Expanded(
                          child: Center(
                            child: Text(
                              day,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LayoutBuilder(
                    builder: (context, box) {
                      final offset = _month.weekday - 1;
                      final cells = ((offset + monthEnd.day) / 7).ceil() * 7;
                      final compact = box.maxWidth < 650;
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          mainAxisExtent: compact ? 68 : 100,
                          crossAxisSpacing: 4,
                          mainAxisSpacing: 4,
                        ),
                        itemCount: cells,
                        itemBuilder: (context, index) {
                          final number = index - offset + 1;
                          if (number < 1 || number > monthEnd.day) {
                            return const SizedBox.shrink();
                          }
                          final day = DateTime(
                            _month.year,
                            _month.month,
                            number,
                          );
                          final leaves = _on(day);
                          final selected = day == _selected;
                          final now = DateTime.now();
                          final today = DateUtils.isSameDay(day, now);
                          return Material(
                            color: selected
                                ? colors.primaryContainer
                                : colors.surfaceContainerHighest.withValues(
                                    alpha: 0.3,
                                  ),
                            borderRadius: BorderRadius.circular(8),
                            child: InkWell(
                              key: ValueKey('leave-day-$number'),
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => setState(() {
                                _selected = day;
                              }),
                              child: Padding(
                                padding: EdgeInsets.all(compact ? 4 : 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '$number',
                                      style: TextStyle(
                                        fontWeight: today || selected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: selected
                                            ? colors.onPrimaryContainer
                                            : today
                                            ? colors.primary
                                            : colors.onSurface,
                                      ),
                                    ),
                                    if (leaves.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        compact
                                            ? '${leaves.length} off'
                                            : '${leaves.length} on leave',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: selected
                                              ? colors.onPrimaryContainer
                                              : colors.primary,
                                        ),
                                      ),
                                      if (!compact)
                                        Text(
                                          '${_profile(leaves.first['employee_id'])?['full_name'] ?? 'Employee'}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          _calendar
              ? '${_date(_selected)} · ${selectedLeaves.length} approved leaves'
              : '${_months[_month.month - 1]} · ${monthLeaves.length} approved leaves',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        for (final leave in _calendar ? selectedLeaves : monthLeaves)
          _leaveCard(leave),
        if ((_calendar ? selectedLeaves : monthLeaves).isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('No approved leave for this period.'),
          ),
      ],
    );
  }
}
