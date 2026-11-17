import 'package:flutter/material.dart';

import '../../../shared/widgets/company_calendar.dart';

class CompanyDatePicker extends StatefulWidget {
  const CompanyDatePicker({
    super.key,
    required this.initialDate,
    required this.entries,
  });
  final DateTime initialDate;
  final List<Map<String, dynamic>> entries;

  @override
  State<CompanyDatePicker> createState() => _CompanyDatePickerState();
}

class _CompanyDatePickerState extends State<CompanyDatePicker> {
  late DateTime selected = widget.initialDate;
  late DateTime month = DateTime(selected.year, selected.month);
  late final calendar = CompanyCalendar(
    entries: widget.entries,
    child: const SizedBox.shrink(),
  );
  late final firstYear = selected.year < 2020 ? selected.year : 2020;
  late final lastYear =
      (selected.year > DateTime.now().year
          ? selected.year
          : DateTime.now().year) +
      10;

  @override
  Widget build(BuildContext context) {
    final local = MaterialLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final offset = DateUtils.firstDayOffset(month.year, month.month, local);
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
      title: const Text('Select date'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: PopupMenuButton<int>(
                    tooltip: 'Choose year',
                    initialValue: month.year,
                    itemBuilder: (_) => [
                      for (var year = firstYear; year <= lastYear; year++)
                        PopupMenuItem(value: year, child: Text('$year')),
                    ],
                    onSelected: (year) =>
                        setState(() => month = DateTime(year, month.month)),
                    child: Text(
                      local.formatMonthYear(month),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
                for (final direction in [-1, 1])
                  IconButton(
                    tooltip: direction < 0
                        ? local.previousMonthTooltip
                        : local.nextMonthTooltip,
                    onPressed:
                        (direction < 0 && month == DateTime(firstYear) ||
                            direction > 0 && month == DateTime(lastYear, 12))
                        ? null
                        : () => setState(
                            () => month = DateTime(
                              month.year,
                              month.month + direction,
                            ),
                          ),
                    icon: Icon(
                      direction < 0 ? Icons.chevron_left : Icons.chevron_right,
                    ),
                  ),
              ],
            ),
            Table(
              children: [
                TableRow(
                  children: [
                    for (var i = 0; i < 7; i++)
                      Center(
                        child: Text(
                          local.narrowWeekdays[(local.firstDayOfWeekIndex + i) %
                              7],
                        ),
                      ),
                  ],
                ),
                for (var week = 0; week < (offset + days + 6) ~/ 7; week++)
                  TableRow(
                    children: [
                      for (var col = 0; col < 7; col++)
                        if (week * 7 + col - offset + 1 < 1 ||
                            week * 7 + col - offset + 1 > days)
                          const SizedBox()
                        else
                          dayCell(
                            DateTime(
                              month.year,
                              month.month,
                              week * 7 + col - offset + 1,
                            ),
                            local,
                            colors,
                          ),
                    ],
                  ),
              ],
            ),
            const Divider(),
            const Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text('★ Holiday'),
                Text('− Weekly off'),
                Text('+ Working day'),
              ],
            ),
            for (final row in widget.entries.where(
              (r) =>
                  r['holiday_date'].toString().startsWith(
                    month.toIso8601String().substring(0, 7),
                  ) &&
                  r['type'] != 'Working day',
            ))
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "${row['holiday_date'].toString().substring(8)} · ${row['name']}",
                ),
              ),
            const SizedBox(height: 8),
            Text(
              "${local.formatFullDate(selected)} · ${calendar.label(selected) ?? 'Working day'}",
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(local.cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, selected),
          child: Text(local.okButtonLabel),
        ),
      ],
    );
  }

  Widget dayCell(
    DateTime date,
    MaterialLocalizations local,
    ColorScheme colors,
  ) {
    final saved = calendar.entry(date);
    final works = calendar.works(date);
    final marker = saved != null
        ? (works ? '+' : '★')
        : !works
        ? '−'
        : date.weekday == DateTime.saturday
        ? '+'
        : '';
    final active = DateUtils.isSameDay(date, selected);
    final label =
        "${local.formatFullDate(date)} · ${calendar.label(date) ?? 'Working day'}";
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: active,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: active ? colors.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () => setState(() => selected = date),
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('${date.day}'),
                  Text(
                    marker,
                    style: TextStyle(
                      height: 1,
                      fontSize: 13,
                      color: saved != null && !works
                          ? colors.error
                          : colors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
