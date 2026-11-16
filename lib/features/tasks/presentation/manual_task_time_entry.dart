import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'booking_duration_picker.dart';

Future<Map<String, dynamic>?> showManualTaskTimeEntry(
  BuildContext context,
  List<Map<String, dynamic>> tasks, {
  String? taskId,
}) async {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => _ManualTimeDialog(tasks: tasks, taskId: taskId),
  );
}

class _ManualTimeDialog extends StatefulWidget {
  const _ManualTimeDialog({required this.tasks, this.taskId});
  final List<Map<String, dynamic>> tasks;
  final String? taskId;
  @override
  State<_ManualTimeDialog> createState() => _ManualTimeDialogState();
}

class _ManualTimeDialogState extends State<_ManualTimeDialog> {
  final _note = TextEditingController();
  String? _taskId;
  int _minutes = 60;
  DateTime _date = DateTime.now();
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _taskId = widget.taskId ?? widget.tasks.firstOrNull?['id']?.toString();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final task = widget.tasks
        .where((t) => t['id'].toString() == _taskId)
        .firstOrNull;
    if (task == null || _minutes <= 0) {
      setState(() {
        _error = 'Select a task and at least one minute.';
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final now = DateTime.now();
      final log = <String, dynamic>{
        'id': now.microsecondsSinceEpoch.toString(),
        'task_id': task['id'],
        'task_title': task['title'] ?? 'Task',
        'employee_id': Supabase.instance.client.auth.currentUser!.id,
        'logged_seconds': _minutes * 60,
        'logged_hours_fmt':
            '${(_minutes ~/ 60).toString().padLeft(2, '0')}:${(_minutes % 60).toString().padLeft(2, '0')}',
        'date': DateTime(
          _date.year,
          _date.month,
          _date.day,
        ).toIso8601String().split('T').first,
        'note': _note.text.trim(),
        'created_at': now.toUtc().toIso8601String(),
      };
      await Supabase.instance.client.from('task_work_logs').insert(log);
      if (mounted) Navigator.pop(context, log);
    } catch (e) {
      if (mounted)
        setState(() {
          _error = 'Could not save entry: $e';
        });
    } finally {
      if (mounted)
        setState(() {
          _saving = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('Add time entry'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _taskId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Task'),
                items: widget.tasks
                    .map(
                      (t) => DropdownMenuItem(
                        value: t['id'].toString(),
                        child: Text(
                          '${t['title']}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _saving || widget.taskId != null
                    ? null
                    : (id) => setState(() {
                        _taskId = id;
                      }),
              ),
              const SizedBox(height: 16),
              IgnorePointer(
                ignoring: _saving,
                child: BookingDurationPicker(
                  initialMinutes: 60,
                  onChanged: (minutes) {
                    _minutes = minutes;
                  },
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Work date'),
                subtitle: Text('${_date.day}/${_date.month}/${_date.year}'),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: _saving
                    ? null
                    : () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _date,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                        );
                        if (date != null && mounted)
                          setState(() {
                            _date = date;
                          });
                      },
              ),
              TextField(
                controller: _note,
                enabled: !_saving,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Work details (optional)',
                ),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving || widget.tasks.isEmpty ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save entry'),
        ),
      ],
    ),
  );
}
