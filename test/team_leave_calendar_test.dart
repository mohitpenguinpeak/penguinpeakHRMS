import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penguinpeak_hrms/features/leave/presentation/team_leave_calendar.dart';

void main() {
  for (final width in [320.0, 1600.0]) {
    testWidgets('calendar selection and list fit $width without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final leave = <String, dynamic>{
        'employee_id': 'a',
        'leave_type': 'Casual',
        'start_date': '2026-11-12',
        'end_date': '2026-11-16',
        'approved_start_date': '2026-11-13',
        'approved_end_date': '2026-11-14',
        'manager_status': 'approved',
        'hr_status': 'approved',
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: TeamLeaveCalendar(
                  leaves: [leave],
                  profiles: const [
                    {
                      'id': 'a',
                      'full_name': 'A long employee name for testing layout',
                      'department': 'Engineering',
                    },
                  ],
                  initialDate: DateTime(2026, 11, 13),
                  onRefresh: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const ValueKey('leave-day-12')));
      await tester.tap(find.byKey(const ValueKey('leave-day-12')));
      await tester.pumpAndSettle();
      expect(find.text('12 November 2026 · 0 approved leaves'), findsOneWidget);
      await tester.ensureVisible(find.text('List'));
      await tester.tap(find.text('List'));
      await tester.pumpAndSettle();
      expect(find.text('November · 1 approved leaves'), findsOneWidget);
      expect(find.text('13 November 2026 – 14 November 2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
