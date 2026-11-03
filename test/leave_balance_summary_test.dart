import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penguinpeak_hrms/features/leave/presentation/leave_balance_summary.dart';

void main() {
  testWidgets(
    'dashboard shows actual allocated and used days, including fractions',
    (tester) async {
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LeaveBalanceSummary(
              balances: const [
                {
                  'leave_type': 'Annual',
                  'allocated_days': 12,
                  'used_days': 2.5,
                },
              ],
              onOpenLeave: () => opened = true,
            ),
          ),
        ),
      );
      expect(find.text('9.5 days remaining'), findsOneWidget);
      expect(find.text('2.5 used / 12 allocated'), findsOneWidget);
      expect(find.text('18 Days'), findsNothing);
      await tester.tap(find.text('Apply Leave →'));
      expect(opened, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('unconfigured balance never invents an entitlement', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LeaveBalanceSummary(balances: const [], onOpenLeave: () {}),
        ),
      ),
    );
    expect(find.textContaining('No leave balance configured'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
