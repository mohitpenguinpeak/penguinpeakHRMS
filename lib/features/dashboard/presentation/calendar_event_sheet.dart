import 'package:flutter/material.dart';

import 'company_date_picker.dart';

class CalendarEventSheet extends StatefulWidget {
  const CalendarEventSheet({
    super.key,
    required this.date,
    required this.entries,
    required this.onSave,
    required this.onRemove,
  });
  final DateTime date;
  final List<Map<String, dynamic>> entries;
  final Future<void> Function(DateTime, String, String) onSave;
  final Future<bool> Function(Map<String, dynamic>) onRemove;

  @override
  State<CalendarEventSheet> createState() => _CalendarEventSheetState();
}

class _CalendarEventSheetState extends State<CalendarEventSheet> {
  late DateTime date = widget.date;
  late final entries = [...widget.entries];
  bool working = false;
  bool saving = false;
  String title = '';
  String category = 'National Holiday';
  String? error;

  Future<void> save() async {
    if (saving) return;
    final key = date.toIso8601String().split('T').first;
    if (entries.any((entry) => entry['holiday_date'] == key)) {
      setState(() => error = 'This date already has a calendar event.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    final type = working ? 'Working day' : category;
    try {
      await widget.onSave(
        date,
        title.trim().isEmpty
            ? (working ? 'Working day' : 'Holiday')
            : title.trim(),
        type,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted)
        setState(() {
          saving = false;
          error = 'Could not save event: $e';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = MaterialLocalizations.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'New calendar event',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: saving ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              enabled: !saving,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Event name (optional)',
                hintText: 'e.g. Diwali',
              ),
              onChanged: (value) => title = value,
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Holiday')),
                ButtonSegment(value: true, label: Text('Working day')),
              ],
              selected: {working},
              onSelectionChanged: saving
                  ? null
                  : (value) => setState(() => working = value.single),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(local.formatFullDate(date)),
              trailing: const Icon(Icons.chevron_right),
              onTap: saving
                  ? null
                  : () async {
                      final picked = await showDialog<DateTime>(
                        context: context,
                        builder: (_) => CompanyDatePicker(
                          initialDate: date,
                          entries: entries,
                        ),
                      );
                      if (picked != null && mounted)
                        setState(() {
                          date = picked;
                          error = null;
                        });
                    },
            ),
            if (!working)
              ExpansionTile(
                title: const Text('Holiday category'),
                tilePadding: EdgeInsets.zero,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    isExpanded: true,
                    items: [
                      for (final type in [
                        'National Holiday',
                        'Festive Holiday',
                        'Optional / Floating',
                        'Regional Holiday',
                      ])
                        DropdownMenuItem(value: type, child: Text(type)),
                    ],
                    onChanged: saving
                        ? null
                        : (type) => setState(() => category = type!),
                  ),
                ],
              ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: saving ? null : save,
              child: Text(saving ? 'Saving…' : 'Save event'),
            ),
            if (entries.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Saved events'),
                children: [
                  for (final entry in entries)
                    ListTile(
                      title: Text('${entry['name']}'),
                      subtitle: Text('${entry['holiday_date']}'),
                      trailing: IconButton(
                        tooltip: 'Remove event',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: saving
                            ? null
                            : () async {
                                if (await widget.onRemove(entry) && mounted)
                                  setState(() => entries.remove(entry));
                              },
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
