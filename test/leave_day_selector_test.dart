import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penguinpeak_hrms/features/leave/presentation/leave_day_selector.dart';
import 'package:penguinpeak_hrms/features/leave/domain/leave_request.dart';

void main() {
  testWidgets('half day asks which half and full day hides that choice', (
    tester,
  ) async {
    var halfDay = false;
    String? half;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => LeaveDaySelector(
              halfDay: halfDay,
              half: half,
              onModeChanged: (value) => update(() {
                halfDay = value;
              }),
              onHalfChanged: (value) => update(() {
                half = value;
              }),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Which half? *'), findsNothing);
    await tester.tap(find.text('Half Day'));
    await tester.pumpAndSettle();
    expect(find.text('Which half? *'), findsOneWidget);
    expect(half, isNull);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second Half').last);
    await tester.pumpAndSettle();
    expect(half, 'second_half');
    await tester.tap(find.text('Full Day'));
    await tester.pumpAndSettle();
    expect(find.text('Which half? *'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  test('approved half day retains fractional quantity and half label', () {
    const request = LeaveRequest({
      'day_portion': 'first_half',
      'days': 0.5,
      'approved_days': 0.5,
      'start_date': '2026-11-13',
      'end_date': '2026-11-13',
      'manager_status': 'approved',
      'hr_status': 'approved',
    });
    expect(request.approvedDays, 0.5);
    expect(request.durationLabel, 'Half Day · First Half');
    expect(request.covers(DateTime(2026, 11, 13)), isTrue);
    expect(request.covers(DateTime(2026, 11, 14)), isFalse);
  });
}
