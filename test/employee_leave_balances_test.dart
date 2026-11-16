import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penguinpeak_hrms/features/leave/presentation/employee_leave_balances.dart';

void main() {
  testWidgets(
    'unlimited leave shows usage without a negative remaining count',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmployeeLeaveBalances(
              balances: const [
                {
                  'employee_id': 'a',
                  'leave_type': 'Unpaid',
                  'allocated_days': 0,
                  'used_days': 20,
                  'is_unlimited': true,
                },
              ],
              employeeName: (_) => 'Asha',
            ),
          ),
        ),
      );
      expect(find.text('Unlimited'), findsOneWidget);
      expect(find.text('20 used · No allocation limit'), findsOneWidget);
      expect(find.text('-20 days left'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('employee and type actions pass the selected allocation', (
    tester,
  ) async {
    String? employee;
    String? type;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmployeeLeaveBalances(
            balances: const [
              {
                'employee_id': 'a',
                'leave_type': 'Annual',
                'allocated_days': 12,
                'used_days': 2,
              },
            ],
            employeeName: (_) => 'Asha',
            onManageEmployee: (id) {
              employee = id;
            },
            onManageType: (id, selectedType) {
              employee = id;
              type = selectedType;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Asha'));
    expect(employee, 'a');
    await tester.tap(find.byTooltip('Edit Annual allocation'));
    expect(type, 'Annual');
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 1600.0]) {
    testWidgets('groups types by employee without overflow at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: EmployeeLeaveBalances(
                employeeName: (_) => 'Same employee name',
                balances: const [
                  {
                    'employee_id': 'a',
                    'leave_type': 'Annual',
                    'allocated_days': 12,
                    'used_days': 2,
                  },
                  {
                    'employee_id': 'a',
                    'leave_type': 'Birthday',
                    'allocated_days': 0.5,
                    'used_days': 0,
                  },
                  {
                    'employee_id': 'b',
                    'leave_type': 'Sick',
                    'allocated_days': 12,
                    'used_days': 12,
                  },
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Card), findsNWidgets(2));
      final first = find.byKey(const ValueKey('employee-balance-a'));
      expect(
        find.descendant(of: first, matching: find.text('Annual')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: first, matching: find.text('Birthday')),
        findsOneWidget,
      );
      expect(find.text('0.5 days left'), findsOneWidget);
      expect(find.text('0 days left'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
