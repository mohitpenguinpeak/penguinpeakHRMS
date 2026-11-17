import '../../../shared/widgets/app_toast.dart';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../task_management_screen.dart';

String _clock(int seconds) =>
    '${(seconds ~/ 3600).toString().padLeft(2, '0')}:${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';

class HeaderTaskTimer extends StatefulWidget {
  const HeaderTaskTimer({super.key, this.compact = false});
  final bool compact;

  @override
  State<HeaderTaskTimer> createState() => _HeaderTaskTimerState();
}

class _HeaderTaskTimerState extends State<HeaderTaskTimer> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tracker = TaskTracker.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([
        tracker.activeSeconds,
        tracker.isTimerRunning,
      ]),
      builder: (context, _) {
        void openLogger() => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          constraints: const BoxConstraints(maxWidth: 440),
          builder: (_) => _TimeLoggerSheet(note: _note),
        );
        if (widget.compact) {
          return IconButton(
            tooltip: 'Task timer: ${_clock(tracker.activeSeconds.value)}',
            onPressed: openLogger,
            icon: Icon(
              tracker.isTimerRunning.value ? Icons.timer : Icons.timer_outlined,
            ),
          );
        }
        return TextButton.icon(
          onPressed: openLogger,
          icon: Icon(
            tracker.isTimerRunning.value ? Icons.timer : Icons.timer_outlined,
          ),
          label: Text(
            tracker.activeSeconds.value > 0
                ? _clock(tracker.activeSeconds.value)
                : 'Timer',
          ),
        );
      },
    );
  }
}

class _TimeLoggerSheet extends StatefulWidget {
  const _TimeLoggerSheet({required this.note});
  final TextEditingController note;

  @override
  State<_TimeLoggerSheet> createState() => _TimeLoggerSheetState();
}

class _TimeLoggerSheetState extends State<_TimeLoggerSheet> {
  late Future<List<Map<String, dynamic>>> _tasks;
  String? _selectedId;
  String? _error;
  bool _saving = false;

  Future<List<Map<String, dynamic>>> _loadTasks() async {
    final db = Supabase.instance.client;
    final uid = db.auth.currentUser?.id;
    if (uid == null) return [];
    final rows = await db
        .from('tasks')
        .select()
        .eq('assignee_id', uid)
        .order('title');
    return rows
        .where(
          (task) => ![
            'completed',
            'declined',
            'pending_acceptance',
          ].contains(task['status']),
        )
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _tasks = _loadTasks();
    _selectedId = TaskTracker.instance.activeTask.value?['id']?.toString();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await TaskTracker.instance.stopAndLogTimer(widget.note.text.trim());
      if (!mounted) return;
      widget.note.clear();
      AppToast.of(context)
          .showSnackBar(const SnackBar(content: Text('Time log saved')));
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = 'Could not save: $e. Elapsed time is retained.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tracker = TaskTracker.instance;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _tasks,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Could not load your tasks.'),
                    TextButton(
                      onPressed: () {
                        final tasks = _loadTasks();
                        setState(() {
                          _tasks = tasks;
                        });
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                );
              }
              if (!snapshot.hasData) return const LinearProgressIndicator();
              final tasks = snapshot.data!;
              return ListenableBuilder(
                listenable: Listenable.merge([
                  tracker.activeTask,
                  tracker.activeSeconds,
                  tracker.isTimerRunning,
                ]),
                builder: (context, _) {
                  final hasTime = tracker.activeSeconds.value > 0;
                  final running = tracker.isTimerRunning.value;
                  final selectedId = hasTime
                      ? (tracker.activeTask.value?['id'])?.toString()
                      : _selectedId;
                  final selected = tasks
                      .where((task) => task['id'].toString() == selectedId)
                      .firstOrNull;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Time logger',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Minimize timer',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.keyboard_arrow_down),
                          ),
                        ],
                      ),
                      Text(
                        _clock(tracker.activeSeconds.value),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        key: ValueKey(selected?['id']),
                        initialValue: selected?['id']?.toString(),
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Task'),
                        items: tasks
                            .map(
                              (task) => DropdownMenuItem(
                                value: task['id'].toString(),
                                child: Text(
                                  '${task['title']}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: hasTime || running || _saving
                            ? null
                            : (id) => setState(() => _selectedId = id),
                      ),
                      if (hasTime && selected == null)
                        Text(
                          'Active task: ${tracker.activeTask.value?['title'] ?? ''}',
                        ),
                      if (selected != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Project: ${selected['project'] ?? 'No project'}',
                          ),
                        ),
                      if (tasks.isEmpty && !hasTime)
                        const Text('No accepted, open tasks assigned to you.'),
                      if (hasTime)
                        const Text('Save this session before changing tasks.'),
                      const SizedBox(height: 12),
                      TextField(
                        controller: widget.note,
                        enabled: !_saving,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Work details (optional)',
                          hintText: 'What are you working on?',
                        ),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: _saving || (!running && selected == null)
                                ? null
                                : () {
                                    setState(() => _error = null);
                                    try {
                                      if (running) {
                                        tracker.pauseTimer();
                                      } else {
                                        tracker.startTimer(selected!);
                                      }
                                    } catch (e) {
                                      setState(() => _error = '$e');
                                    }
                                  },
                            icon: Icon(
                              running ? Icons.pause : Icons.play_arrow,
                            ),
                            label: Text(
                              running
                                  ? 'Pause Timer'
                                  : hasTime
                                  ? 'Resume Timer'
                                  : 'Start Timer',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _saving || !hasTime ? null : _save,
                            icon: const Icon(Icons.save_outlined),
                            label: Text(
                              _saving ? 'Saving…' : 'Stop & Save Log',
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
