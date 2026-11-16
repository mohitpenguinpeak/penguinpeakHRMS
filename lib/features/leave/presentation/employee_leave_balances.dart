import 'package:flutter/material.dart';

import '../../../shared/widgets/adaptive_layout.dart';

/// One employee per card; each allocation remains a distinct leave type.
class EmployeeLeaveBalances extends StatelessWidget {
  const EmployeeLeaveBalances({
    super.key,
    required this.balances,
    required this.employeeName,
    this.showEmployee = true,
    this.onManageEmployee,
    this.onManageType,
  });
  final List<Map<String, dynamic>> balances;
  final String Function(dynamic) employeeName;
  final bool showEmployee;
  final ValueChanged<String>? onManageEmployee;
  final void Function(String employeeId, String leaveType)? onManageType;
  static num _number(dynamic value) =>
      value is num ? value : num.tryParse('$value') ?? 0;
  static String _days(num value) =>
      value % 1 == 0 ? value.toInt().toString() : value.toString();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final balance in balances) {
      groups.putIfAbsent('${balance['employee_id']}', () => []).add(balance);
    }
    final employees = groups.keys.toList()
      ..sort(
        (a, b) =>
            employeeName(a)
                .toLowerCase()
                .compareTo(employeeName(b).toLowerCase()),
      );
    return AdaptiveCards(
      minWidth: 380,
      maxColumns: 2,
      children: [
        for (final id in employees)
          Card(
            key: ValueKey('employee-balance-$id'),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onManageEmployee == null
                  ? null
                  : () => onManageEmployee!(id),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: colors.primaryContainer,
                          child: Icon(
                            showEmployee
                                ? Icons.person_outline
                                : Icons.event_available,
                            color: colors.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                showEmployee
                                    ? employeeName(id)
                                    : 'Your leave balances',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              Text(
                                '${groups[id]!.length} leave ${groups[id]!.length == 1 ? 'type' : 'types'}',
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (onManageEmployee != null)
                          IconButton(
                            tooltip: 'Manage leave balance',
                            onPressed: () => onManageEmployee!(id),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (final row
                        in (List<Map<String, dynamic>>.from(groups[id]!)..sort(
                          (a, b) => '${a['leave_type']}'
                              .toLowerCase()
                              .compareTo('${b['leave_type']}'.toLowerCase()),
                        )))
                      Builder(
                        builder: (context) {
                          final allocated = _number(row['allocated_days']);
                          final used = _number(row['used_days']);
                          final remaining = allocated - used;
                          return Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Divider(
                                  height: 1,
                                  color: colors.outlineVariant,
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (onManageType != null)
                                      IconButton(
                                        tooltip:
                                            'Edit ${row['leave_type']} allocation',
                                        onPressed: () => onManageType!(
                                          id,
                                          '${row['leave_type']}',
                                        ),
                                        icon: const Icon(
                                          Icons.edit_outlined,
                                          size: 18,
                                        ),
                                      ),
                                    Expanded(
                                      child: Text(
                                        '${row['leave_type']}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      row['is_unlimited'] == true
                                          ? 'Unlimited'
                                          : '${_days(remaining)} days left',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: row['is_unlimited'] != true && remaining <= 0
                                            ? colors.error
                                            : colors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    minHeight: 5,
                                    value: row['is_unlimited'] == true
                                        ? 1
                                        : allocated > 0
                                        ? (remaining / allocated)
                                              .clamp(0, 1)
                                              .toDouble()
                                        : 0,
                                    backgroundColor:
                                        colors.surfaceContainerHighest,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  row['is_unlimited'] == true
                                      ? '${_days(used)} used · No allocation limit'
                                      : '${_days(used)} used / ${_days(allocated)} allocated',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
