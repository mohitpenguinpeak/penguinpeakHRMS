import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
import 'package:penguinpeak_hrms/task_management_screen.dart';

import 'support/qa_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('an in-flight log cannot restore state after account cleanup', () async {
    final backend = QaBackend();
    await backend.initialize();
    final tracker = TaskTracker.instance;
    final saved = Completer<http.Response>();
    backend.intercept = (request) async {
      if (request.url.path.endsWith('/task_work_logs')) return saved.future;
      return backend.respond(request);
    };
    try {
      tracker.startTimer({'id': 'old-task'});
      tracker.activeSeconds.value = 60;
      final pending = tracker.stopAndLogTimer('old session');
      await Future<void>.delayed(Duration.zero);
      tracker.resetForSignOut();
      tracker.startTimer({'id': 'new-task'});
      tracker.activeSeconds.value = 42;
      saved.complete(backend.json(null, status: 201));
      await pending;
      expect(tracker.activeTask.value?['id'], 'new-task');
      expect(tracker.activeSeconds.value, 42);
      expect(tracker.timelogs.value, isEmpty);
    } finally {
      tracker.resetForSignOut();
      await backend.dispose();
    }
  });
  test(
    'sign-out clears account-specific timers, breaks and cached time logs',
    () {
      final tracker = TaskTracker.instance;
      tracker.startTimer({'id': 'private-task', 'title': 'Private task'});
      tracker.activeSeconds.value = 75;
      tracker.preBreakTask = {'id': 'private-task'};
      tracker.addTimelog({'id': 'private-log'});
      tracker.resetForSignOut();
      expect(tracker.isTimerRunning.value, isFalse);
      expect(tracker.activeSeconds.value, 0);
      expect(tracker.activeTask.value, isNull);
      expect(tracker.preBreakTask, isNull);
      expect(tracker.timelogs.value, isEmpty);
    },
  );
  test(
    'timer pauses, resumes, and protects unsaved time when switching tasks',
    () {
      final tracker = TaskTracker.instance;
      final task = <String, dynamic>{'id': 'a', 'title': 'First task'};
      addTearDown(() {
        tracker.pauseTimer();
        tracker.activeTask.value = null;
        tracker.activeSeconds.value = 0;
      });
      tracker.startTimer(task);
      expect(tracker.isTimerRunning.value, isTrue);
      tracker.activeSeconds.value = 75;
      tracker.pauseTimer();
      expect(tracker.isTimerRunning.value, isFalse);
      tracker.startTimer(task);
      expect(tracker.activeSeconds.value, 75);
      expect(() => tracker.startTimer({'id': 'b'}), throwsStateError);
      expect(tracker.activeTask.value?['id'], 'a');
      expect(tracker.activeSeconds.value, 75);
    },
  );
}
