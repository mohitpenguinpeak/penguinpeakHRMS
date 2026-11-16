import 'package:flutter/material.dart';

import '../domain/task_time_summary.dart';

class TaskWorkLogEntry extends StatelessWidget {
  const TaskWorkLogEntry({
    super.key,
    required this.log,
    this.onDelete,
    this.deleting = false,
  });
  final Map<String, dynamic> log;
  final VoidCallback? onDelete;
  final bool deleting;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final date = DateTime.tryParse('${log['created_at']}')?.toLocal();
    final stamp = date == null
        ? '${log['date'] ?? 'Date unavailable'}'
        : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    final note = log['note']?.toString().trim() ?? '';
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3, right: 12),
            child: Icon(Icons.schedule, size: 20, color: colors.primary),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(stamp, style: Theme.of(context).textTheme.labelLarge),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        formatTaskTime((log['logged_seconds'] as num).toInt()),
                        style: TextStyle(
                          color: colors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  note.isEmpty ? 'No work details added' : note,
                  style: TextStyle(
                    color: note.isEmpty
                        ? colors.onSurfaceVariant
                        : colors.onSurface,
                  ),
                ),
              ],
            ),
          ),
          if (onDelete != null || deleting)
            IconButton(
              tooltip: 'Delete time entry',
              onPressed: deleting ? null : onDelete,
              icon: deleting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.delete_outline, color: colors.error),
            ),
        ],
      ),
    );
  }
}
