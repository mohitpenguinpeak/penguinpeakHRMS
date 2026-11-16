import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A second view of authorized task records, using the existing workflow states.
class TaskKanbanBoard extends StatelessWidget {
  const TaskKanbanBoard({
    super.key,
    required this.tasks,
    required this.onOpen,
    required this.employeeName,
  });

  final List<Map<String, dynamic>> tasks;
  final ValueChanged<Map<String, dynamic>> onOpen;
  final String Function(dynamic) employeeName;

  static const columns = <String, String>{
    'pending_acceptance': 'Awaiting acceptance',
    'todo': 'To do',
    'in_progress': 'In progress',
    'pending': 'Pending',
    'on_hold': 'On Hold',
    'in_review': 'In Review',
    'completed': 'Completed',
    'declined': 'Declined',
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final groups = <String, List<Map<String, dynamic>>>{
      for (final key in columns.keys) key: [],
    };
    for (final task in tasks) {
      final rawStatus = task['status']?.toString() ?? 'todo';
      final status = rawStatus == 'blocked' ? 'on_hold' : rawStatus;
      (groups[status] ??= []).add(task);
    }
    groups.removeWhere(
      (status, tasks) =>
          tasks.isEmpty &&
          !['todo', 'in_progress', 'completed'].contains(status),
    );
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth < 600
            ? math.max(220.0, box.maxWidth - 12)
            : math.max(
                260.0,
                (box.maxWidth - 12 * (groups.length - 1)) / groups.length,
              );
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final group in groups.entries)
                Container(
                  width: width,
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.onSurface.withValues(alpha: 0.035),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.circle, size: 8, color: colors.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              columns[group.key] ?? group.key,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            '${group.value.length}',
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (group.value.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            'No tasks',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        ),
                      for (final task in group.value)
                        Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => onOpen(task),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (task['priority'] ?? 'medium')
                                        .toString()
                                        .toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 10,
                                      letterSpacing: 1,
                                      color: colors.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    task['title']?.toString() ??
                                        'Untitled task',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (task['project']?.toString().isNotEmpty ==
                                      true) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      task['project'].toString(),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                  const Divider(height: 24),
                                  Text(
                                    employeeName(task['assignee_id']),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Due: ${task['due_date']?.toString().split('T').first ?? 'Not set'}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
