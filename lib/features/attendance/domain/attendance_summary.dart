List<Map<String, dynamic>> attendanceSessions(Map<String, dynamic> record) {
  final sessions = (record['work_sessions'] as List? ?? [])
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList();
  if (sessions.isNotEmpty) return sessions;
  return record['check_in'] == null
      ? []
      : [
          {
            'check_in': record['check_in'],
            'check_out': record['check_out'],
            'work_duration_minutes': record['work_duration_minutes'],
          },
        ];
}

int attendanceSessionMinutes(
  Map<String, dynamic> record,
  Map<String, dynamic> session,
  int index,
  DateTime now,
) {
  final start = DateTime.tryParse('${session['check_in']}');
  final end = session['check_out'] == null
      ? now
      : DateTime.tryParse('${session['check_out']}');
  if (start == null || end == null || end.isBefore(start)) return 0;
  if (!record.containsKey('attendance_breaks') &&
      session['check_out'] != null &&
      session['work_duration_minutes'] is num) {
    return (session['work_duration_minutes'] as num).toInt().clamp(0, 1440);
  }
  final breaks = (record['attendance_breaks'] as List? ?? []).whereType<Map>();
  var breakMinutes = 0;
  for (final row in breaks) {
    if (((row['session_index'] as num?)?.toInt() ?? 0) != index) continue;
    final breakStart = DateTime.tryParse('${row['break_start']}');
    final breakEnd = row['break_end'] == null
        ? now
        : DateTime.tryParse('${row['break_end']}');
    if (breakStart != null && breakEnd != null) {
      final from = breakStart.isBefore(start) ? start : breakStart;
      final to = breakEnd.isAfter(end) ? end : breakEnd;
      if (to.isAfter(from)) breakMinutes += to.difference(from).inMinutes;
    } else {
      breakMinutes += ((row['duration_minutes'] as num?)?.toInt() ?? 0).clamp(
        0,
        1440,
      );
    }
  }
  return (end.difference(start).inMinutes - breakMinutes).clamp(0, 1440);
}

int attendanceWorkMinutes(Map<String, dynamic>? record, DateTime now) {
  if (record == null) return 0;
  return attendanceSessions(record).asMap().entries.fold<int>(
    0,
    (sum, entry) =>
        sum + attendanceSessionMinutes(record, entry.value, entry.key, now),
  );
}

String attendanceClockLabel(DateTime time) =>
    '${(time.hour % 12 == 0 ? 12 : time.hour % 12).toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')} ${time.hour >= 12 ? 'PM' : 'AM'}';

int attendanceLateMinutes(DateTime now, Map<String, dynamic> settings) {
  final parts = '${settings['work_start_time'] ?? '09:00:00'}'.split(':');
  final hour = int.tryParse(parts.first) ?? 9;
  final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  final start = now.isUtc
      ? DateTime.utc(now.year, now.month, now.day, hour, minute)
      : DateTime(now.year, now.month, now.day, hour, minute);
  final grace = (settings['grace_period_minutes'] as num?)?.toInt() ?? 15;
  return (now.difference(start).inMinutes - grace).clamp(0, 1440);
}

/// Each approved half counts once, even if legacy requests overlap.
double attendanceExpectedDay(Iterable<String> portions) {
  final values = portions.toSet();
  if (values.contains('full_day')) return 0;
  return 1.0 -
      (values.contains('first_half') ? 0.5 : 0) -
      (values.contains('second_half') ? 0.5 : 0);
}

String formatAttendanceDays(num days) =>
    days == days.round() ? days.round().toString() : days.toStringAsFixed(1);
