import 'package:penguinpeak_hrms/shared/widgets/company_calendar.dart';
import 'package:flutter/material.dart';

class TaskCalendarView extends StatefulWidget {
  const TaskCalendarView({
    super.key,
    required this.tasks,
    required this.onOpen,
  });
  final List<Map<String, dynamic>> tasks;
  final ValueChanged<Map<String, dynamic>> onOpen;
  @override
  State<TaskCalendarView> createState() => _TaskCalendarViewState();
}

class _TaskCalendarViewState extends State<TaskCalendarView> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selected = DateUtils.dateOnly(DateTime.now());
  static const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  DateTime? _due(Map<String, dynamic> task) =>
      DateTime.tryParse('${task['due_date']}')?.toLocal();
  List<Map<String, dynamic>> _forDay(DateTime day) => widget.tasks
      .where((task) => DateUtils.isSameDay(_due(task), day))
      .toList();
  void _move(int offset) => setState(() {
    _month = DateTime(_month.year, _month.month + offset);
    _selected = _month;
  });
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final days = DateUtils.getDaysInMonth(_month.year, _month.month);
    final leading = _month.weekday - 1;
    final selected = _forDay(_selected);
    final undated = widget.tasks.where((task) => _due(task) == null).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous month',
                      onPressed: () => _move(-1),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        '${months[_month.month - 1]} ${_month.year}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next month',
                      onPressed: () => _move(1),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _selected = DateUtils.dateOnly(DateTime.now());
                    _month = DateTime(_selected.year, _selected.month);
                  }),
                  child: const Text('Today'),
                ),
                Row(
                  children: [
                    for (final day in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                      Expanded(child: Center(child: Text(day))),
                  ],
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, box) => GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisExtent: box.maxWidth < 500 ? 52 : 80,
                      crossAxisSpacing: 3,
                      mainAxisSpacing: 3,
                    ),
                    itemCount: ((leading + days + 6) ~/ 7) * 7,
                    itemBuilder: (context, index) {
                      final number = index - leading + 1;
                      if (number < 1 || number > days) {
                        return const SizedBox.shrink();
                      }
                      final date = DateTime(_month.year, _month.month, number);
                      final count = _forDay(date).length;
                      final active = DateUtils.isSameDay(_selected, date);
                      final today = DateUtils.isSameDay(DateTime.now(), date);
                      return Semantics(
                        label:
                            '${months[date.month - 1]} $number, $count tasks due',
                        selected: active,
                        child: Material(
                          color: active
                              ? colors.primaryContainer
                              : colors.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: today
                                  ? colors.primary
                                  : colors.outlineVariant,
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => setState(() => _selected = date),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '$number',
                                  style: TextStyle(
                                    decoration:
                                        CompanyCalendar.of(context)
                                                .label(date) ==
                                            null
                                        ? null
                                        : TextDecoration.underline,
                                    color: active
                                        ? colors.onPrimaryContainer
                                        : colors.onSurface,
                                  ),
                                ),
                                if (count > 0)
                                  Text(
                                    '$count',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: active
                                          ? colors.onPrimaryContainer
                                          : colors.primary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        CalendarDayDetails(
          calendar: CompanyCalendar.of(context),
          day: _selected,
        ),
        Text(
          'Due ${_selected.day} ${months[_selected.month - 1]} · ${selected.length} tasks',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (selected.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('No tasks due on this day.'),
          ),
        for (final task in selected) _tile(task),
        if (undated.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Without a due date'),
          for (final task in undated) _tile(task),
        ],
      ],
    );
  }

  Widget _tile(Map<String, dynamic> task) => Card(
    child: ListTile(
      title: Text('${task['title'] ?? 'Untitled task'}'),
      subtitle: Text(
        '${(task['status'] ?? 'todo').toString().replaceAll('_', ' ')} · ${task['priority'] ?? 'medium'}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => widget.onOpen(task),
    ),
  );
}
