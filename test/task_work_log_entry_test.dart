import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penguinpeak_hrms/features/tasks/presentation/task_work_log_entry.dart';

void main() {
  final log = <String, dynamic>{
    'logged_seconds': 25,
    'created_at': '2026-11-13T10:00:00Z',
    'note': '',
  };
  testWidgets('entry shows duration and note placeholder with delete action', (
    tester,
  ) async {
    var deleted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskWorkLogEntry(log: log, onDelete: () => deleted = true),
        ),
      ),
    );
    expect(find.text('00:00:25'), findsOneWidget);
    expect(find.text('No work details added'), findsOneWidget);
    expect(find.textContaining('2026-11-13T'), findsNothing);
    await tester.tap(find.byTooltip('Delete time entry'));
    expect(deleted, isTrue);
  });
  testWidgets('entry without delete permission shows only work details', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskWorkLogEntry(log: {...log, 'note': 'Updated task'}),
        ),
      ),
    );
    expect(find.text('Updated task'), findsOneWidget);
    expect(find.byTooltip('Delete time entry'), findsNothing);
  });
}
