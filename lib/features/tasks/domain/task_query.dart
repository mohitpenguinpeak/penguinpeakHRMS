/// Filters apply to already-authorized records; database RLS remains authoritative.
class TaskQuery {
  const TaskQuery({
    this.search = '',
    this.status = 'all',
    this.priority = 'all',
    this.project,
    this.assignee,
    this.creator,
    this.due = 'all',
    this.from,
    this.to,
    this.sort = 'newest',
  });
  final String search, status, priority, due, sort;
  final String? project, assignee, creator;
  final DateTime? from, to;

  List<Map<String, dynamic>> apply(
    List<Map<String, dynamic>> tasks, {
    required DateTime now,
    required String Function(dynamic) employeeName,
  }) {
    final today = _day(now);
    final result = tasks.where((task) {
      if (status != 'all' && task['status'] != status) return false;
      if (priority != 'all' && task['priority'] != priority) return false;
      if (project != null &&
          (task['project']?.toString().trim() ?? '') != project) {
        return false;
      }
      if (assignee != null &&
          (task['assignee_id']?.toString() ?? '') != assignee) {
        return false;
      }
      if (creator != null && (task['creator_id']?.toString() ?? '') != creator) {
        return false;
      }
      final query = search.trim().toLowerCase();
      if (query.isNotEmpty &&
          ![
            task['title'],
            task['description'],
            task['project'],
            task['id'],
            employeeName(task['assignee_id']),
            employeeName(task['creator_id']),
          ].join(' ').toLowerCase().contains(query)) {
        return false;
      }
      final parsed = DateTime.tryParse('${task['due_date']}')?.toLocal();
      final deadline = parsed == null ? null : _day(parsed);
      final closed = [
        'completed',
        'declined',
        'cancelled',
      ].contains(task['status']);
      if (due == 'overdue' &&
          (closed || deadline == null || !deadline.isBefore(today))) {
        return false;
      }
      if (due == 'today' && deadline != today) return false;
      if (due == 'week' &&
          (deadline == null ||
              deadline.isBefore(today) ||
              deadline.isAfter(today.add(const Duration(days: 7))))) {
        return false;
      }
      if (due == 'undated' && deadline != null) return false;
      if (from != null && (deadline == null || deadline.isBefore(_day(from!)))) {
        return false;
      }
      if (to != null && (deadline == null || deadline.isAfter(_day(to!)))) {
        return false;
      }
      return true;
    }).toList();
    const ranks = {'urgent': 0, 'high': 1, 'medium': 2, 'low': 3};
    int compareDates(dynamic a, dynamic b, {bool descending = false}) {
      final left = DateTime.tryParse('$a');
      final right = DateTime.tryParse('$b');
      if (left == null) return right == null ? 0 : 1;
      if (right == null) return -1;
      return descending ? right.compareTo(left) : left.compareTo(right);
    }

    result.sort((a, b) {
      final comparison = switch (sort) {
        'title' => '${a['title']}'.toLowerCase().compareTo(
          '${b['title']}'.toLowerCase(),
        ),
        'due' => compareDates(a['due_date'], b['due_date']),
        'priority' => (ranks[a['priority']] ?? 4).compareTo(
          ranks[b['priority']] ?? 4,
        ),
        'oldest' => compareDates(a['created_at'], b['created_at']),
        _ => compareDates(a['created_at'], b['created_at'], descending: true),
      };
      return comparison != 0
          ? comparison
          : '${a['id']}'.compareTo('${b['id']}');
    });
    return result;
  }

  static DateTime _day(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day);
}
