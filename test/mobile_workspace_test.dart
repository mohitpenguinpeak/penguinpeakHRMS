import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penguinpeak_hrms/app_theme.dart';
import 'package:penguinpeak_hrms/login_screen.dart';
import 'package:penguinpeak_hrms/signup_screen.dart';
import 'package:penguinpeak_hrms/role_dashboard_screen.dart';
import 'package:penguinpeak_hrms/features/leave/presentation/leave_balance_summary.dart';
import 'package:penguinpeak_hrms/features/tasks/presentation/task_calendar_view.dart';
import 'package:penguinpeak_hrms/features/tasks/presentation/task_analytics_view.dart';
import 'package:penguinpeak_hrms/shared/widgets/adaptive_layout.dart';

void main() {
  final now = DateTime.now();
  final tasks = <Map<String, dynamic>>[
    {
      'title': 'Review mobile onboarding',
      'due_date': DateTime(now.year, now.month, now.day).toIso8601String(),
      'status': 'in_progress',
      'priority': 'high',
      'assignee_id': 'a',
    },
    {
      'title': 'Completed work',
      'status': 'completed',
      'priority': 'medium',
      'completed_at': now.toIso8601String(),
    },
    {'title': 'Undated work', 'status': 'todo', 'priority': 'low'},
    {'title': 'Legacy completed work', 'status': 'completed'},
  ];
  Future<void> host(
    WidgetTester tester,
    Widget child,
    double width, {
    bool reduced = false,
  }) async {
    tester.view.resetPhysicalSize();
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemes.dark,
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 900),
            disableAnimations: reduced,
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Padding(padding: const EdgeInsets.all(16), child: child),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 390.0, 768.0, 1600.0]) {
    testWidgets('calendar fits $width and opens saved task', (tester) async {
      Map<String, dynamic>? opened;
      await host(
        tester,
        TaskCalendarView(tasks: tasks, onOpen: (task) => opened = task),
        width,
      );
      expect(tester.takeException(), isNull);
      final title = find.text('Review mobile onboarding');
      await tester.ensureVisible(title);
      await tester.tap(title);
      expect(opened, same(tasks.first));
      await tester.ensureVisible(find.byTooltip('Next month'));
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(find.text('No tasks due on this day.'), findsOneWidget);
      expect(find.text('Undated work'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('analytics fits $width using actual task values', (
      tester,
    ) async {
      await host(
        tester,
        TaskAnalyticsView(
          tasks: tasks,
          employeeName: (_) => 'Long employee name in a small mobile workspace',
        ),
        width,
      );
      expect(
        find.text('4 filtered tasks · snapshot of saved records'),
        findsOneWidget,
      );
      expect(find.text('completed · 2'), findsOneWidget);
      expect(
        find.text(
          '1 completed tasks have no saved completion date and are excluded.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('cards fill desktop and stack on phones', (tester) async {
    Widget cards() => AdaptiveCards(
      children: [
        for (var i = 0; i < 6; i++)
          SizedBox(key: ValueKey(i), height: 100, child: Text('Request $i')),
      ],
    );
    await host(tester, cards(), 1600);
    final first = tester.getRect(find.byKey(const ValueKey(0)));
    final second = tester.getRect(find.byKey(const ValueKey(1)));
    expect(first.top, second.top);
    expect(first.width, greaterThan(450));
    await host(tester, cards(), 320);
    expect(
      tester.getRect(find.byKey(const ValueKey(1))).top,
      greaterThan(tester.getRect(find.byKey(const ValueKey(0))).bottom),
    );
    expect(tester.getSize(find.byKey(const ValueKey(0))).width, 288);
    expect(tester.takeException(), isNull);
  });
  for (final width in [320.0, 390.0, 1600.0]) {
    testWidgets('dashboard actions adapt at $width', (tester) async {
      await host(
        tester,
        const SizedBox(
          width: 700,
          child: AdaptiveRow(
            children: [
              Text("Today's Attendance & Time Tracker"),
              Spacer(),
              Text('Not Checked In'),
            ],
          ),
        ),
        width,
      );
      expect(tester.takeException(), isNull);
      final heading = tester.getRect(
        find.text("Today's Attendance & Time Tracker"),
      );
      final status = tester.getRect(find.text('Not Checked In'));
      if (width < 600) {
        expect(status.top, greaterThan(heading.bottom));
      } else {
        expect(status.top, heading.top);
      }
    });
    testWidgets('authentication fits $width', (tester) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(theme: AppThemes.dark, home: const LoginScreen()),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(theme: AppThemes.dark, home: const SignupScreen()),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // The form remains scrollable when the keyboard reduces available height.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('entry animation respects reduced motion', (tester) async {
    await host(
      tester,
      const WorkspaceReveal(child: Text('Ready')),
      320,
      reduced: true,
    );
    expect(tester.widget<Opacity>(find.byType(Opacity).last).opacity, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('profile and leave cards fit a small phone', (tester) async {
    await host(
      tester,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkspaceHeading(
            title: 'Attendance adjustments',
            action: FilledButton(
              onPressed: () {},
              child: const Text('Request adjustment'),
            ),
          ),
          LeaveBalanceSummary(
            balances: const [
              {'leave_type': 'Annual', 'allocated_days': 12, 'used_days': 3},
            ],
            onOpenLeave: () {},
          ),
          const KekaEmployeeDetailWidget(
            profile: {
              'id': 'a',
              'full_name': 'Asha',
              'profile_details': {
                'bio': 'Working on a mobile friendly HR platform',
              },
            },
            managerName: 'Reporting Manager',
          ),
        ],
      ),
      320,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('9 days remaining'), findsOneWidget);
  });
}
