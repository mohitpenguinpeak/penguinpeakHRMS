/// Combine sessions by task without rounding away sub-minute entries.
List<Map<String, dynamic>> summarizeTaskTime(List<Map<String, dynamic>> logs) {
  final groups = <String, Map<String, dynamic>>{};
  for (final log in logs) {
    final key = log['task_id']?.toString() ?? '';
    final group = groups.putIfAbsent(
      key,
      () => {
        'task_id': key,
        'task_title': log['task_title'] ?? 'Task',
        'seconds': 0,
        'sessions': 0,
        'last_logged': '',
      },
    );
    group['seconds'] =
        (group['seconds'] as int) +
        ((log['logged_seconds'] as num?)?.toInt() ?? 0);
    group['sessions'] = (group['sessions'] as int) + 1;
    final date = (log['created_at'] ?? log['date'] ?? '').toString();
    if (date.compareTo(group['last_logged'] as String) > 0) {
      group['last_logged'] = date;
      group['task_title'] = log['task_title'] ?? group['task_title'];
    }
  }
  return groups.values.toList()..sort(
    (a, b) =>
        (b['last_logged'] as String).compareTo(a['last_logged'] as String),
  );
}

String formatTaskTime(int seconds) =>
    '${(seconds ~/ 3600).toString().padLeft(2, '0')}:${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
