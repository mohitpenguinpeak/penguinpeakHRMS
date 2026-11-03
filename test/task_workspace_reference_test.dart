import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penguinpeak_hrms/app_theme.dart';
import 'package:penguinpeak_hrms/features/tasks/presentation/grouped_task_board.dart';
import 'package:penguinpeak_hrms/features/tasks/presentation/task_overview_panel.dart';

void main() {
  final tasks = <Map<String, dynamic>>[
    {
      'id': '1',
      'title': 'Review design',
      'project': 'Website',
      'assignee_id': 'a',
      'status': 'in_progress',
      'description': '[Booking: 2.5 hrs] Review design',
    },
    {
      'id': '2',
      'title': 'Audit release',
      'project': 'HR',
      'assignee_id': 'b',
      'status': 'todo',
    },
  ];
  Future<void> host(WidgetTester tester, Widget child, double width) async {
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
            textScaler: const TextScaler.linear(1.3),
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

  for (final width in [320.0, 768.0, 1600.0]) {
    testWidgets('grouped board opens real tasks at $width', (tester) async {
      Map<String, dynamic>? opened;
      await host(
        tester,
        GroupedTaskBoard(
          tasks: tasks,
          groupBy: 'project',
          employeeName: (_) => 'Team member',
          onOpen: (task) => opened = task,
        ),
        width,
      );
      final title = find.text('Review design');
      await tester.ensureVisible(title);
      await tester.tap(title);
      expect(opened, same(tasks.first));
      await tester.ensureVisible(find.text('Collapse all groups'));
      await tester.tap(find.text('Collapse all groups'));
      await tester.pumpAndSettle();
      expect(find.text('Expand all groups'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('detail inspector fits $width with larger text', (
      tester,
    ) async {
      await host(
        tester,
        TaskOverviewPanel(
          task: tasks.first,
          employeeName: (_) => 'Team member',
        ),
        width,
      );
      expect(find.text('Website'), findsOneWidget);
      expect(find.text('2.5 hrs'), findsOneWidget);
      expect(find.text('Not recorded'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
  test('missing estimates never invent logged or estimated time', () {
    expect(TaskOverviewPanel.estimate(tasks.last), 'Not set');
    expect(
      TaskOverviewPanel.estimate({'description': '[Booking: 0 hrs]'}),
      '0 hrs',
    );
  });
}
