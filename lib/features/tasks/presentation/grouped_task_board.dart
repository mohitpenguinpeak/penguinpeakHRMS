import 'package:flutter/material.dart';

import 'task_kanban_board.dart';

class GroupedTaskBoard extends StatefulWidget {
  const GroupedTaskBoard({
    super.key,
    required this.tasks,
    required this.groupBy,
    required this.onOpen,
    required this.employeeName,
  });
  final List<Map<String, dynamic>> tasks;
  final String groupBy;
  final ValueChanged<Map<String, dynamic>> onOpen;
  final String Function(dynamic) employeeName;
  @override
  State<GroupedTaskBoard> createState() => _GroupedTaskBoardState();
}

class _GroupedTaskBoardState extends State<GroupedTaskBoard> {
  bool _expanded = true;
  int _expansionRevision = 0;
  @override
  Widget build(BuildContext context) {
    if (widget.groupBy == 'none') {
      return TaskKanbanBoard(
        tasks: widget.tasks,
        onOpen: widget.onOpen,
        employeeName: widget.employeeName,
      );
    }
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final task in widget.tasks) {
      final value = switch (widget.groupBy) {
        'assignee' => task['assignee_id']?.toString() ?? '',
        'priority' => task['priority']?.toString() ?? 'medium',
        _ => task['project']?.toString().trim() ?? '',
      };
      (groups[value] ??= []).add(task);
    }
    if (groups.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('No tasks match these filters.'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => setState(() {
              _expanded = !_expanded;
              _expansionRevision++;
            }),
            icon: Icon(_expanded ? Icons.unfold_less : Icons.unfold_more),
            label: Text(
              _expanded ? 'Collapse all groups' : 'Expand all groups',
            ),
          ),
        ),
        for (final entry in groups.entries)
          Card(
            child: ExpansionTile(
              key: PageStorageKey(
                'task-board-group:${widget.groupBy}:${entry.key}:$_expansionRevision',
              ),
              initiallyExpanded: _expanded,
              title: Text(
                widget.groupBy == 'assignee'
                    ? entry.key.isEmpty
                          ? 'Unassigned'
                          : widget.employeeName(entry.key)
                    : entry.key.isEmpty
                    ? 'No project'
                    : entry.key,
              ),
              subtitle: Text(
                '${entry.value.length} tasks · ${entry.value.where((t) => t['status'] == 'completed').length} completed',
              ),
              childrenPadding: const EdgeInsets.all(12),
              children: [
                TaskKanbanBoard(
                  tasks: entry.value,
                  onOpen: widget.onOpen,
                  employeeName: widget.employeeName,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
