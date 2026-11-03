import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penguinpeak_hrms/app_theme.dart';
import 'package:penguinpeak_hrms/features/tasks/presentation/task_kanban_board.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'board retains task access and unknown states in ${dark ? 'dark' : 'light'} theme',
      (tester) async {
        Map<String, dynamic>? opened;
        final task = <String, dynamic>{
          'title': 'Review onboarding',
          'status': 'in_progress',
          'assignee_id': 'employee',
          'priority': 'high',
        };
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppThemes.dark : AppThemes.light,
            home: Scaffold(
              body: SingleChildScrollView(
                child: TaskKanbanBoard(
                  tasks: [
                    task,
                    {'title': 'Legacy task', 'status': 'custom_review'},
                  ],
                  employeeName: (_) => 'Team member',
                  onOpen: (value) => opened = value,
                ),
              ),
            ),
          ),
        );
        final title = find.text('Review onboarding');
        await tester.ensureVisible(title);
        await tester.tap(title);
        expect(opened, same(task));
        await tester.ensureVisible(find.text('Legacy task'));
        expect(find.text('custom_review'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
