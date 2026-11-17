import 'package:flutter_test/flutter_test.dart';
import 'package:penguinpeak_hrms/features/attendance/domain/attendance_summary.dart';

void main() {
  test('monthly day equivalents preserve half-day leave and avoid duplicate credit', () {
    expect(attendanceExpectedDay([]), 1);
    expect(attendanceExpectedDay(['first_half']), 0.5);
    expect(attendanceExpectedDay(['first_half', 'first_half']), 0.5);
    expect(attendanceExpectedDay(['first_half', 'second_half']), 0);
    expect(attendanceExpectedDay(['full_day']), 0);
    expect(formatAttendanceDays(1.0), '1');
    expect(formatAttendanceDays(1.5), '1.5');
  });
  DateTime time(String clock) => DateTime.parse('2026-11-16T${clock}:00Z');
  test('separate sessions exclude checked-out gaps and closed breaks', () {
    final record = <String, dynamic>{
      'work_sessions': [
        {
          'check_in': time('09:00').toIso8601String(),
          'check_out': time('10:00').toIso8601String(),
        },
        {
          'check_in': time('13:00').toIso8601String(),
          'check_out': time('15:00').toIso8601String(),
        },
      ],
      'attendance_breaks': [
        {
          'session_index': 1,
          'break_start': time('14:00').toIso8601String(),
          'break_end': time('14:15').toIso8601String(),
          'duration_minutes': 15,
        },
      ],
    };
    expect(attendanceWorkMinutes(record, time('16:00')), 165);
  });
  test('ongoing breaks stop the live net work counter', () {
    final record = <String, dynamic>{
      'check_in': time('09:00').toIso8601String(),
      'check_out': null,
      'attendance_breaks': [
        {'break_start': time('10:00').toIso8601String(), 'break_end': null},
      ],
    };
    expect(attendanceWorkMinutes(record, time('10:30')), 60);
    expect(attendanceWorkMinutes(record, time('11:00')), 60);
  });
  test(
    'legacy rows preserve saved net time and invalid times cannot go negative',
    () {
      final record = <String, dynamic>{
        'check_in': time('09:00').toIso8601String(),
        'check_out': time('11:00').toIso8601String(),
        'work_duration_minutes': 90,
      };
      expect(attendanceWorkMinutes(record, time('12:00')), 90);
      expect(attendanceSessions(record).length, 1);
      expect(attendanceWorkMinutes({'check_in': 'invalid'}, time('12:00')), 0);
      expect(attendanceWorkMinutes(null, time('12:00')), 0);
    },
  );
  test('clock labels use twelve-hour time including noon and midnight', () {
    expect(attendanceClockLabel(time('00:05')), '12:05 AM');
    expect(attendanceClockLabel(time('12:05')), '12:05 PM');
    expect(attendanceClockLabel(time('15:30')), '03:30 PM');
  });
  test(
    'quick check-in uses configured start and subtracts the grace period',
    () {
      final settings = <String, dynamic>{
        'work_start_time': '09:00:00',
        'grace_period_minutes': 15,
      };
      expect(attendanceLateMinutes(time('09:10'), settings), 0);
      expect(attendanceLateMinutes(time('09:20'), settings), 5);
    },
  );
}
