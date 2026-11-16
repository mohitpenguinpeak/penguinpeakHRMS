import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penguinpeak_hrms/features/tasks/presentation/header_task_timer.dart';
import 'package:penguinpeak_hrms/task_management_screen.dart';

void main() {
  testWidgets('header shows shared elapsed time and running state', (
    tester,
  ) async {
    final tracker = TaskTracker.instance;
    tracker.pauseTimer();
    tracker.activeSeconds.value = 0;
    addTearDown(() {
      tracker.pauseTimer();
      tracker.activeSeconds.value = 0;
      tracker.activeTask.value = null;
    });
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: HeaderTaskTimer())),
    );
    expect(find.text('Timer'), findsOneWidget);
    tracker.startTimer({'id': 'task', 'title': 'Example'});
    tracker.activeSeconds.value = 3661;
    await tester.pump();
    expect(find.text('01:01:01'), findsOneWidget);
    expect(find.byIcon(Icons.timer), findsOneWidget);
    tracker.pauseTimer();
    await tester.pump();
    expect(find.text('01:01:01'), findsOneWidget);
    expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
  });
}
