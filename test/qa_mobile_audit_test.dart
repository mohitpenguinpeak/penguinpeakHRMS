import 'package:penguinpeak_hrms/attendance_management_screen.dart';
import 'package:penguinpeak_hrms/attendance_adjustment_screen.dart';
import 'package:penguinpeak_hrms/leave_management_screen.dart';
import 'package:penguinpeak_hrms/task_management_screen.dart';
import 'package:penguinpeak_hrms/company_wall_screen.dart';
import 'package:penguinpeak_hrms/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penguinpeak_hrms/app_theme.dart';
import 'package:penguinpeak_hrms/role_dashboard_screen.dart';
import 'package:penguinpeak_hrms/shared/widgets/adaptive_layout.dart';

import 'support/qa_backend.dart';

void main() {
  testWidgets('narrow content in a wide viewport stacks AdaptiveRow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 280,
              child: AdaptiveRow(
                children: [
                  const Text('Attendance and work session summary'),
                  const Spacer(),
                  FilledButton(
                    onPressed: () {},
                    child: const Text('Manage attendance'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0, 768.0, 1024.0]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('real dashboard fits $width at text scale $scale', (
        tester,
      ) async {
        final backend = QaBackend();
        await tester.runAsync(backend.initialize);
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppThemes.dark,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: const RoleDashboardScreen(role: 'hr'),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.textContaining('Could not load dashboard'),
            findsNothing,
            reason: tester
                .widgetList<SelectableText>(find.byType(SelectableText))
                .map((w) => w.data)
                .join(' | '),
          );
          final list = find.byKey(const PageStorageKey('workspace-Overview'));
          expect(list, findsOneWidget);
          // Exercise cards below the initial viewport, including the company wall.
          for (var i = 0; i < 6; i++) {
            await tester.drag(list, const Offset(0, -500));
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          await tester.runAsync(backend.dispose);
        }
      });
    }
  }
  for (final entry in <String, Widget>{
    'Attendance': const AttendanceManagementScreen(role: 'hr'),
    'Adjustments': const AttendanceAdjustmentScreen(role: 'hr'),
    'Leave': const LeaveManagementScreen(role: 'hr'),
    'Tasks': const TaskManagementScreen(role: 'hr'),
    'Company wall': const CompanyWallScreen(role: 'hr'),
    'Chat': const ChatScreen(role: 'hr'),
  }.entries) {
    testWidgets('${entry.key} loads on a 320px phone with larger text', (
      tester,
    ) async {
      final backend = QaBackend();
      await tester.runAsync(backend.initialize);
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppThemes.dark,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(1.5)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: entry.value,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (var i = 0; i < 4; i++) {
          await tester.drag(
            find.byType(SingleChildScrollView).first,
            const Offset(0, -400),
          );
          await tester.pumpAndSettle();
        }
        expect(find.textContaining('Error:'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await tester.runAsync(backend.dispose);
      }
    });
  }
  testWidgets(
    'active breaks can be ended and detailed attendance is reachable',
    (tester) async {
      final backend = QaBackend();
      await tester.runAsync(backend.initialize);
      final now = DateTime.now();
      backend.tables['attendance_records'] = [
        {
          'id': 'attendance',
          'employee_id': qaEmployeeId,
          'attendance_date': now.toIso8601String().split('T')[0],
          'check_in': now
              .subtract(const Duration(hours: 2))
              .toUtc()
              .toIso8601String(),
          'check_out': null,
          'status': 'Present',
          'work_duration_minutes': 60,
          'attendance_breaks': [
            {
              'id': 'break',
              'session_index': 0,
              'break_start': now
                  .subtract(const Duration(minutes: 10))
                  .toUtc()
                  .toIso8601String(),
              'break_end': null,
              'duration_minutes': 0,
            },
          ],
        },
      ];
      try {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: AttendanceManagementScreen(role: 'hr'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final endBreak = tester.widget<OutlinedButton>(
          find.ancestor(
            of: find.text('End Break'),
            matching: find.byType(OutlinedButton),
          ),
        );
        expect(endBreak.onPressed, isNotNull);
        final checkout = tester.widget<FilledButton>(
          find.ancestor(
            of: find.text('Check Out'),
            matching: find.byType(FilledButton),
          ),
        );
        expect(checkout.onPressed, isNull);
        await tester.ensureVisible(find.byTooltip('Detailed attendance table'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Detailed attendance table'));
        await tester.pumpAndSettle();
        expect(find.byType(DataTable), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await tester.runAsync(backend.dispose);
      }
    },
  );
}
