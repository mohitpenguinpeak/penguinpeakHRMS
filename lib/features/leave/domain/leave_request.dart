/// Calendar-day leave dates. Attendance durations and half-days are separate policy.
class LeaveRequest {
  const LeaveRequest(this.row);
  final Map<String, dynamic> row;

  String get durationLabel => switch (row['day_portion']) {
    'first_half' => 'Half Day · First Half',
    'second_half' => 'Half Day · Second Half',
    _ => 'Full Day',
  };
  bool get isCancelled => row['cancelled_at'] != null;
  bool get isRejected =>
      row['manager_status'] == 'rejected' || row['hr_status'] == 'rejected';
  bool get isFinallyApproved =>
      !isCancelled &&
      row['manager_status'] == 'approved' &&
      row['hr_status'] == 'approved';
  num get requestedDays => _number(row['days']);
  num get approvedDays => row['approved_days'] == null
      ? requestedDays
      : _number(row['approved_days']);
  bool get isPartial => isFinallyApproved && approvedDays < requestedDays;
  String get approvedStart =>
      (row['approved_start_date'] ?? row['start_date'] ?? '').toString();
  String get approvedEnd =>
      (row['approved_end_date'] ?? row['end_date'] ?? '').toString();

  String get status {
    if (isCancelled) return 'Cancelled';
    if (row['manager_status'] == 'rejected') return 'Rejected by manager';
    if (row['hr_status'] == 'rejected') return 'Rejected by HR';
    if (isFinallyApproved) return isPartial ? 'Partially approved' : 'Approved';
    if (row['manager_status'] == 'approved') return 'Pending with HR';
    return 'Pending with manager';
  }

  bool canCancelOn(DateTime today) {
    if (isCancelled || isRejected) return false;
    final start = DateTime.tryParse(approvedStart);
    return start != null &&
        start.isAfter(DateTime(today.year, today.month, today.day));
  }

  bool covers(DateTime day) {
    if (!isFinallyApproved) return false;
    final first = DateTime.tryParse(approvedStart);
    final last = DateTime.tryParse(approvedEnd);
    final date = DateTime(day.year, day.month, day.day);
    return first != null &&
        last != null &&
        !date.isBefore(first) &&
        !date.isAfter(last);
  }

  Map<String, dynamic> get effectiveRow => {
    ...row,
    'start_date': approvedStart,
    'end_date': approvedEnd,
    'days': approvedDays,
  };

  static num _number(dynamic value) =>
      value is num ? value : num.tryParse('$value') ?? 0;
}
