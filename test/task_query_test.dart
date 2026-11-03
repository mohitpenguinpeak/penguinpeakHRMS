import 'package:flutter_test/flutter_test.dart';
import 'package:penguinpeak_hrms/features/tasks/domain/task_query.dart';

void main() {
  final now = DateTime(2026, 11, 3, 12);
  final tasks = <Map<String, dynamic>>[
    {
      'id': '1',
      'title': 'Design mobile view',
      'project': 'Website',
      'assignee_id': 'a',
      'creator_id': 'b',
      'status': 'in_progress',
      'priority': 'high',
      'due_date': '2026-11-02',
      'created_at': '2026-10-01',
    },
    {
      'id': '2',
      'title': 'Audit schema',
      'project': 'HR',
      'assignee_id': 'b',
      'creator_id': 'a',
      'status': 'todo',
      'priority': 'urgent',
      'due_date': '2026-11-03',
      'created_at': '2026-10-02',
    },
    {
      'id': '3',
      'title': 'Old closed task',
      'project': 'Website',
      'assignee_id': 'a',
      'status': 'completed',
      'priority': 'low',
      'due_date': '2026-11-01',
    },
    {
      'id': '4',
      'title': 'Undated backlog',
      'status': 'todo',
      'priority': 'medium',
    },
  ];
  List<String> ids(TaskQuery query) => query
      .apply(tasks, now: now, employeeName: (id) => id == 'a' ? 'Asha' : 'Sam')
      .map((t) => '${t['id']}')
      .toList();
  test('combines project, assignee, creator, state and priority', () {
    expect(
      ids(
        const TaskQuery(
          project: 'Website',
          assignee: 'a',
          creator: 'b',
          status: 'in_progress',
          priority: 'high',
        ),
      ),
      ['1'],
    );
    expect(ids(const TaskQuery(project: 'Website', assignee: 'b')), isEmpty);
  });
  test('search includes people, project and task ID', () {
    expect(
      ids(const TaskQuery(search: '  ASHA ')),
      containsAll(['1', '2', '3']),
    );
    expect(ids(const TaskQuery(search: 'website')), containsAll(['1', '3']));
    expect(ids(const TaskQuery(search: '4')), ['4']);
  });
  test('due presets exclude closed overdue tasks and retain unassigned', () {
    expect(ids(const TaskQuery(due: 'overdue')), ['1']);
    expect(ids(const TaskQuery(due: 'today')), ['2']);
    expect(ids(const TaskQuery(due: 'week')), ['2']);
    expect(ids(const TaskQuery(due: 'undated', assignee: '', project: '')), [
      '4',
    ]);
  });
  test('custom due range is inclusive and excludes missing dates', () {
    expect(
      ids(TaskQuery(from: DateTime(2026, 11, 2), to: DateTime(2026, 11, 3))),
      ['2', '1'],
    );
  });
  test('sorts actual dates and priorities with missing values last', () {
    expect(ids(const TaskQuery(sort: 'due')), ['3', '1', '2', '4']);
    expect(ids(const TaskQuery(sort: 'priority')), ['2', '1', '4', '3']);
    expect(ids(const TaskQuery(sort: 'title')), ['2', '1', '3', '4']);
    expect(tasks.first['id'], '1');
  });
  test('reset query restores every authorized loaded record', () {
    expect(ids(const TaskQuery()), hasLength(4));
  });
}
