import 'package:flutter/material.dart';

class CompanyCalendar extends InheritedWidget {
  CompanyCalendar({
    super.key,
    required super.child,
    required this.entries,
    this.available = true,
    this.remove,
    this.add,
  });
  final Future<bool> Function(Map<String, dynamic>)? remove;
  final ValueChanged<DateTime>? add;
  final bool available;
  final List<Map<String, dynamic>> entries;
  late final Map<String, Map<String, dynamic>> dates = {
    for (final row in entries.where((r) => r['type'] == 'Working day'))
      '${row['holiday_date']}': row,
    for (final row in entries.where((r) => r['type'] != 'Working day'))
      '${row['holiday_date']}': row,
  };

  static CompanyCalendar of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CompanyCalendar>() ??
      CompanyCalendar(entries: const [], child: const SizedBox.shrink());
  Map<String, dynamic>? entry(DateTime day) =>
      dates[day.toIso8601String().split('T').first];
  bool _workingSaturday(DateTime day) =>
      day.weekday == DateTime.saturday &&
      ((day.day >= 8 && day.day <= 14) || (day.day >= 22 && day.day <= 28));

  bool works(DateTime day) {
    final row = entry(day);
    return row == null
        ? day.weekday <= DateTime.friday || _workingSaturday(day)
        : row['type'] == 'Working day';
  }

  String? label(DateTime day) {
    final row = entry(day);
    if (row == null && _workingSaturday(day)) return 'Working Saturday';
    return row == null
        ? (works(day) ? null : 'Weekly off')
        : "${row['name']} · ${row['type']}";
  }

  int count(DateTime from, DateTime to) {
    var days = 0;
    for (
      var date = from;
      !date.isAfter(to);
      date = DateTime(date.year, date.month, date.day + 1)
    ) {
      if (works(date)) days++;
    }
    return days;
  }

  @override
  bool updateShouldNotify(CompanyCalendar oldWidget) =>
      entries != oldWidget.entries ||
      available != oldWidget.available ||
      remove != oldWidget.remove ||
      add != oldWidget.add;
}

class CalendarDayDetails extends StatelessWidget {
  const CalendarDayDetails({
    super.key,
    required this.calendar,
    required this.day,
    this.onRemoved,
  });
  final CompanyCalendar calendar;
  final DateTime day;
  final VoidCallback? onRemoved;
  @override
  Widget build(BuildContext context) {
    final label = calendar.label(day);
    if (label == null && calendar.add == null) return const SizedBox.shrink();
    final entry = calendar.entry(day);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (label != null) Text(label),
        if (entry == null && calendar.add != null && onRemoved == null)
          TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add event'),
            onPressed: () => calendar.add!(day),
          ),

        if (entry != null && calendar.remove != null)
          IconButton(
            tooltip: 'Remove calendar override',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final removed = await calendar.remove!(entry);
              if (removed && context.mounted) onRemoved?.call();
            },
          ),
      ],
    );
  }
}
