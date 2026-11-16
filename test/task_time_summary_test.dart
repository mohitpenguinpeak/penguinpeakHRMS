import 'package:flutter_test/flutter_test.dart';
import 'package:penguinpeak_hrms/features/tasks/domain/task_time_summary.dart';

void main() {
  test('combines sessions by task ID and retains seconds', () {
    final rows = summarizeTaskTime([
      {
        'task_id': 'a',
        'task_title': 'Same title',
        'logged_seconds': 16,
        'created_at': '2026-11-13T10:00:00Z',
      },
      {
        'task_id': 'a',
        'task_title': 'Same title',
        'logged_seconds': 5,
        'created_at': '2026-11-13T11:00:00Z',
      },
      {
        'task_id': 'b',
        'task_title': 'Same title',
        'logged_seconds': 3600,
        'created_at': '2026-11-12T11:00:00Z',
      },
    ]);
    expect(rows, hasLength(2));
    expect(rows.first['seconds'], 21);
    expect(rows.first['sessions'], 2);
    expect(rows.first['last_logged'], '2026-11-13T11:00:00Z');
    expect(formatTaskTime(rows.first['seconds'] as int), '00:00:21');
    expect(formatTaskTime(3661), '01:01:01');
    expect(formatTaskTime(90000), '25:00:00');
    expect(summarizeTaskTime([]), isEmpty);
  });
}
