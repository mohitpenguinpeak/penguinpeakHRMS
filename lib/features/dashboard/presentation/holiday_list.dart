import 'package:flutter/material.dart';

/// Displays only saved backend holidays; failures never become example records.
class HolidayList extends StatelessWidget {
  const HolidayList({
    super.key,
    required this.holidays,
    this.error,
    required this.onRetry,
  });
  final List<Map<String, dynamic>> holidays;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(error!),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry holidays'),
          ),
        ],
      );
    }
    if (holidays.isEmpty)
      return const Text('No upcoming company holidays configured.');
    return Column(
      children: holidays
          .map(
            (holiday) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.beach_access),
              title: Text(
                holiday['name']?.toString() ?? 'Unnamed holiday',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              subtitle: Text(
                '${holiday['holiday_date'] ?? ''} • ${holiday['type'] ?? 'Company Holiday'}',
              ),
            ),
          )
          .toList(),
    );
  }
}
