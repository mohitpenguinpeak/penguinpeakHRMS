import 'package:flutter/material.dart';

/// Own storage identity prevents collisions with the workspace scroll offset.
class TaskFilterPanel extends StatelessWidget {
  const TaskFilterPanel({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(vertical: 12),
    child: ExpansionTile(
      key: const PageStorageKey('task-filter-panel'),
      title: const Text('Filters, sorting & grouping'),
      leading: const Icon(Icons.tune),
      childrenPadding: const EdgeInsets.all(16),
      children: [child],
    ),
  );
}
