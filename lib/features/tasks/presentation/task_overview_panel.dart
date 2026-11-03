import 'package:flutter/material.dart';

import '../../../shared/widgets/adaptive_layout.dart';

class TaskOverviewPanel extends StatelessWidget {
  const TaskOverviewPanel({
    super.key,
    required this.task,
    required this.employeeName,
  });
  final Map<String, dynamic> task;
  final String Function(dynamic) employeeName;
  static String estimate(Map<String, dynamic> task) {
    final match = RegExp(r'\[Booking:\s*([\d.]+)\s*hrs\]')
        .firstMatch('${task['description'] ?? ''}');
    final hours = double.tryParse(match?.group(1) ?? '');
    return hours != null && hours >= 0 ? '${match!.group(1)} hrs' : 'Not set';
  }

  @override
  Widget build(BuildContext context) {
    String date(dynamic value) =>
        DateTime.tryParse('$value')?.toLocal().toString().split('.').first ??
        'Not recorded';
    Widget field(String label, String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        SelectableText(
          value,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ],
    );
    final panels = <Widget>[
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Task details',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              AdaptiveCards(
                minWidth: 200,
                maxColumns: 3,
                children: [
                  field(
                    'Project',
                    task['project']?.toString().trim().isNotEmpty == true
                        ? '${task['project']}'
                        : 'No project',
                  ),
                  field(
                    'Assigned to',
                    task['assignee_id'] == null
                        ? 'Unassigned'
                        : employeeName(task['assignee_id']),
                  ),
                  field(
                    'Created by',
                    task['creator_id'] == null
                        ? 'Not recorded'
                        : employeeName(task['creator_id']),
                  ),
                  field(
                    'Due date',
                    task['due_date'] == null
                        ? 'Not set'
                        : date(task['due_date']),
                  ),
                  field(
                    'Status',
                    '${task['status'] ?? 'todo'}'.replaceAll('_', ' '),
                  ),
                  field('Priority', '${task['priority'] ?? 'medium'}'),
                  field('Estimated hours', estimate(task)),
                ],
              ),
            ],
          ),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Timeline', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              AdaptiveCards(
                minWidth: 200,
                maxColumns: 3,
                children: [
                  field('Created', date(task['created_at'])),
                  field('Last updated', date(task['updated_at'])),
                  field('Completed', date(task['completed_at'])),
                ],
              ),
            ],
          ),
        ),
      ),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth >= 900) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: panels.first),
              const SizedBox(width: 12),
              Expanded(child: panels.last),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: panels,
        );
      },
    );
  }
}
