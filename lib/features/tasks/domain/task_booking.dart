/// Booking hours use the same two-hour fallback as the availability matrix.
double taskBookingHours(String? description) {
  final match = RegExp(r'\[Booking:\s*([\d.]+)\s*hrs\]')
      .firstMatch(description ?? '');
  final hours = double.tryParse(match?.group(1) ?? '');
  return hours != null && hours.isFinite && hours > 0 ? hours : 2;
}

bool requiresBookingAcceptance({
  required Iterable<Map<String, dynamic>> tasks,
  required String assigneeId,
  required DateTime day,
  required double bookingHours,
}) {
  final date = day.toIso8601String().split('T').first;
  var allocated = 0.0;
  for (final task in tasks) {
    if (task['assignee_id']?.toString() != assigneeId ||
        task['status'] == 'completed' ||
        task['status'] == 'declined') {
      continue;
    }
    final taskDate = (task['due_date'] ?? task['created_at'])
        ?.toString()
        .split('T')
        .first;
    if (taskDate == date) {
      allocated += taskBookingHours(task['description']?.toString());
    }
  }
  return allocated + bookingHours > 8;
}
