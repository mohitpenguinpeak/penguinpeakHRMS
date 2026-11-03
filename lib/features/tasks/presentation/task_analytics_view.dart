import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/widgets/adaptive_layout.dart';

/// Snapshot analytics of the same authorized, filtered records as the task list.
/// Completion trend uses saved completed_at; it never invents status history.
class TaskAnalyticsView extends StatelessWidget {
  const TaskAnalyticsView({
    super.key,
    required this.tasks,
    required this.employeeName,
  });
  final List<Map<String, dynamic>> tasks;
  final String Function(dynamic) employeeName;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No tasks match these filters. Adjust filters to see analytics.',
          ),
        ),
      );
    }
    final statuses = <String, int>{};
    final priorities = <String, int>{};
    final projects = <String, int>{};
    final workload = <String, int>{};
    final deadlines = <String, int>{
      'Overdue': 0,
      'Due today': 0,
      'Next 7 days': 0,
      'Later': 0,
      'No due date': 0,
    };
    final today = DateUtils.dateOnly(DateTime.now());
    final completion = List<int>.filled(7, 0);
    var completedWithoutDate = 0;
    for (final task in tasks) {
      final status = '${task['status'] ?? 'todo'}';
      final priority = '${task['priority'] ?? 'medium'}';
      statuses.update(status, (n) => n + 1, ifAbsent: () => 1);
      priorities.update(priority, (n) => n + 1, ifAbsent: () => 1);
      final project = task['project']?.toString().trim() ?? '';
      projects.update(
        project.isEmpty ? 'No project' : project,
        (n) => n + 1,
        ifAbsent: () => 1,
      );
      if (status == 'completed') {
        final end = DateTime.tryParse('${task['completed_at']}')?.toLocal();
        if (end == null) {
          completedWithoutDate++;
        } else {
          final age = DateTime.utc(
            today.year,
            today.month,
            today.day,
          ).difference(DateTime.utc(end.year, end.month, end.day)).inDays;
          if (age >= 0 && age < 7) completion[6 - age]++;
        }
      }
      if (status == 'completed' ||
          status == 'declined' ||
          status == 'cancelled') {
        continue;
      }
      final owner = task['assignee_id']?.toString() ?? 'unassigned';
      workload.update(owner, (n) => n + 1, ifAbsent: () => 1);
      final due = DateTime.tryParse('${task['due_date']}')?.toLocal();
      final days = due == null
          ? null
          : DateTime.utc(due.year, due.month, due.day)
                .difference(DateTime.utc(today.year, today.month, today.day))
                .inDays;
      final bucket = days == null
          ? 'No due date'
          : days < 0
          ? 'Overdue'
          : days == 0
          ? 'Due today'
          : days <= 7
          ? 'Next 7 days'
          : 'Later';
      deadlines[bucket] = deadlines[bucket]! + 1;
    }
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${tasks.length} filtered tasks · snapshot of saved records',
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        AdaptiveCards(
          minWidth: 350,
          maxColumns: 2,
          children: [
            _panel(
              context,
              'Status distribution',
              Column(
                children: [
                  SizedBox(
                    height: 160,
                    child: Semantics(
                      label: statuses.entries
                          .map((e) => '${e.key}: ${e.value}')
                          .join(', '),
                      child: CustomPaint(
                        size: const Size(160, 160),
                        painter: _Donut(
                          statuses.values.toList(),
                          colors.primary,
                          colors.outlineVariant,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _bars(context, statuses, tinted: true),
                ],
              ),
            ),
            _panel(context, 'Priority breakdown', _bars(context, priorities)),
            _panel(context, 'Tasks by project', _bars(context, projects)),
            _panel(
              context,
              'Active workload by assignee',
              workload.isEmpty
                  ? const Text('No active tasks.')
                  : _bars(
                      context,
                      workload,
                      label: (id) =>
                          id == 'unassigned' ? 'Unassigned' : employeeName(id),
                    ),
            ),
            _panel(
              context,
              'Active deadline health',
              _bars(context, deadlines),
            ),
            _panel(
              context,
              'Completions · last 7 days',
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 130,
                    child: Semantics(
                      label:
                          'Completions oldest to newest: ${completion.join(', ')}',
                      child: CustomPaint(
                        painter: _Trend(
                          completion,
                          colors.primary,
                          colors.outlineVariant,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (var i = 0; i < 7; i++)
                    Text(
                      '${today.subtract(Duration(days: 6 - i)).day}/${today.subtract(Duration(days: 6 - i)).month}: ${completion[i]} completed',
                    ),
                  if (completedWithoutDate > 0)
                    Text(
                      '$completedWithoutDate completed tasks have no saved completion date and are excluded.',
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _panel(BuildContext context, String title, Widget child) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 20),
          child,
        ],
      ),
    ),
  );
  Widget _bars(
    BuildContext context,
    Map<String, int> values, {
    String Function(String)? label,
    bool tinted = false,
  }) {
    final maximum = values.values.fold(1, math.max);
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in values.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${label == null ? entry.key.replaceAll('_', ' ') : label(entry.key)} · ${entry.value}',
                ),
                const SizedBox(height: 6),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: entry.value / maximum),
                  duration: reduce
                      ? Duration.zero
                      : const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => LinearProgressIndicator(
                    value: value,
                    color: tinted
                        ? Color.lerp(
                            Theme.of(context).colorScheme.primary,
                            Theme.of(context).colorScheme.outlineVariant,
                            values.keys.toList().indexOf(entry.key) /
                                math.max(1, values.length) *
                                0.8,
                          )
                        : null,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Donut extends CustomPainter {
  _Donut(this.values, this.color, this.track);
  final List<int> values;
  final Color color;
  final Color track;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: math.min(size.width, size.height) / 2 - 12,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18;
    canvas.drawOval(rect, paint..color = track);
    var start = -math.pi / 2;
    final total = values.fold(0, (sum, n) => sum + n);
    if (total == 0) return;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * math.pi * 2;
      canvas.drawArc(
        rect,
        start,
        math.max(0, sweep - 0.025),
        false,
        paint
          ..color = Color.lerp(
            color,
            track,
            i / math.max(1, values.length) * 0.8,
          )!,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _Donut old) => true;
}

class _Trend extends CustomPainter {
  _Trend(this.values, this.color, this.track);
  final List<int> values;
  final Color color;
  final Color track;
  @override
  void paint(Canvas canvas, Size size) {
    final maximum = values.fold(1, math.max);
    final paint = Paint()
      ..color = track
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = 8 + (size.height - 16) * i / 4;
      canvas.drawLine(Offset(8, y), Offset(size.width - 8, y), paint);
    }
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final point = Offset(
        8 + (size.width - 16) * i / 6,
        size.height - 8 - (size.height - 16) * values[i] / maximum,
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawCircle(point, 4, Paint()..color = color);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant _Trend old) => true;
}
