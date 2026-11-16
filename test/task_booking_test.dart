import 'package:flutter_test/flutter_test.dart';

import 'package:penguinpeak_hrms/features/tasks/domain/task_booking.dart';

void main() {
  test('acceptance is required only above daily capacity', () {
    final day = DateTime(2026, 11, 13);
    Map<String, dynamic> booking(
      String hours, {
      String status = 'todo',
      String employee = 'a',
      String date = '2026-11-13',
    }) => {
      'assignee_id': employee,
      'status': status,
      'due_date': date,
      'description': '[Booking: $hours hrs]',
    };
    void check(List<Map<String, dynamic>> tasks, double hours, bool expected) {
      final actual = requiresBookingAcceptance(
        tasks: tasks,
        assigneeId: 'a',
        day: day,
        bookingHours: hours,
      );
      expect(actual, expected);
    }

    check([], 2, false);
    check([booking('6')], 2, false);
    check([booking('6')], 3, true);
    check([booking('8')], 2, true);
    check([], 9, true);
    check(
      [booking('8', status: 'completed'), booking('8', status: 'declined')],
      2,
      false,
    );
    check(
      [booking('8', employee: 'b'), booking('8', date: '2026-11-14')],
      2,
      false,
    );
    check([booking('7', status: 'pending_acceptance')], 2, true);
    check(
      [
        {
          'assignee_id': 'a',
          'created_at': '2026-11-13T12:00:00',
          'description': '',
        },
      ],
      7,
      true,
    );
    if (taskBookingHours('') != 2 ||
        taskBookingHours('[Booking: 0 hrs]') != 2) {
      throw StateError(
        'Missing or zero estimates must match the matrix fallback',
      );
    }
  });
}
