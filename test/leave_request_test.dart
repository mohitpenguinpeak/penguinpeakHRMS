import 'package:flutter_test/flutter_test.dart';
import 'package:penguinpeak_hrms/features/leave/domain/leave_request.dart';

void main() {
  final requested = <String, dynamic>{
    'start_date': '2099-01-10',
    'end_date': '2099-01-14',
    'days': 5,
    'manager_status': 'approved',
    'hr_status': 'approved',
    'approved_start_date': '2099-01-11',
    'approved_end_date': '2099-01-13',
    'approved_days': 3,
  };
  test('partial leave covers only the approved date range', () {
    final leave = LeaveRequest(requested);
    expect(leave.status, 'Partially approved');
    expect(leave.covers(DateTime(2099, 1, 10)), isFalse);
    expect(leave.covers(DateTime(2099, 1, 11)), isTrue);
    expect(leave.covers(DateTime(2099, 1, 13)), isTrue);
    expect(leave.covers(DateTime(2099, 1, 14)), isFalse);
    expect(leave.effectiveRow['days'], 3);
    expect(leave.effectiveRow['start_date'], '2099-01-11');
    expect(requested['start_date'], '2099-01-10');
  });
  test('cancelled approved leave is removed from availability', () {
    final leave = LeaveRequest({
      ...requested,
      'cancelled_at': '2098-12-01T12:00:00Z',
    });
    expect(leave.status, 'Cancelled');
    expect(leave.isFinallyApproved, isFalse);
    expect(leave.covers(DateTime(2099, 1, 12)), isFalse);
    expect(leave.canCancelOn(DateTime(2098, 12, 1)), isFalse);
  });
  test('pending and rejected requests are not counted as approved leave', () {
    for (final hrStatus in ['pending', 'rejected']) {
      expect(
        LeaveRequest({...requested, 'hr_status': hrStatus})
            .covers(DateTime(2099, 1, 12)),
        isFalse,
      );
    }
  });
  test('legacy full approval falls back to requested dates and quantity', () {
    final leave = LeaveRequest({
      'start_date': '2099-01-10',
      'end_date': '2099-01-14',
      'days': 5,
      'manager_status': 'approved',
      'hr_status': 'approved',
    });
    expect(leave.status, 'Approved');
    expect(leave.approvedDays, 5);
    expect(leave.covers(DateTime(2099, 1, 14)), isTrue);
  });
  test('cancellation is available only before effective start day', () {
    final leave = LeaveRequest(requested);
    expect(leave.canCancelOn(DateTime(2099, 1, 10)), isTrue);
    expect(leave.canCancelOn(DateTime(2099, 1, 11)), isFalse);
    expect(leave.canCancelOn(DateTime(2099, 1, 12)), isFalse);
  });
}
