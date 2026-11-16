import 'package:flutter/material.dart';

import '../../../shared/widgets/adaptive_layout.dart';

/// Uses authoritative allocations/usage, never assumed company entitlements.
class LeaveBalanceSummary extends StatelessWidget {
  const LeaveBalanceSummary({
    super.key,
    required this.balances,
    required this.onOpenLeave,
  });
  final List<Map<String, dynamic>> balances;
  final VoidCallback onOpenLeave;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'My Leave Balances',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: onOpenLeave,
                child: const Text('Apply Leave →'),
              ),
            ],
          ),
          if (balances.isEmpty)
            const Text(
              'No leave balance configured. Ask HR to allocate your leave.',
            )
          else
            AdaptiveCards(
              minWidth: 180,
              children: balances.map((row) {
                final allocated = _number(row['allocated_days']);
                final used = _number(row['used_days']);
                return SizedBox(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${row['leave_type']}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          row['is_unlimited'] == true
                              ? 'Unlimited'
                              : '${_format(allocated - used)} days remaining',
                        ),
                        Text(
                          row['is_unlimited'] == true
                              ? '${_format(used)} used · No allocation limit'
                              : '${_format(used)} used / ${_format(allocated)} allocated',
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: row['is_unlimited'] == true
                              ? 1
                              : allocated > 0
                              ? ((allocated - used) / allocated)
                                    .clamp(0, 1)
                                    .toDouble()
                              : 0,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    ),
  );

  static num _number(dynamic n) => n is num ? n : num.tryParse('$n') ?? 0;
  static String _format(num n) =>
      n % 1 == 0 ? n.toInt().toString() : n.toString();
}
