import 'package:flutter_test/flutter_test.dart';
import 'package:penguinpeak_hrms/task_management_screen.dart';

void main() {
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
