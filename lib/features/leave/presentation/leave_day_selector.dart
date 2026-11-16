import 'package:flutter/material.dart';

class LeaveDaySelector extends StatelessWidget {
  const LeaveDaySelector({
    super.key,
    required this.halfDay,
    required this.half,
    required this.onModeChanged,
    required this.onHalfChanged,
  });
  final bool halfDay;
  final String? half;
  final ValueChanged<bool> onModeChanged;
  final ValueChanged<String> onHalfChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            label: const Text('Full Day'),
            selected: !halfDay,
            onSelected: (_) => onModeChanged(false),
          ),
          ChoiceChip(
            label: const Text('Half Day'),
            selected: halfDay,
            onSelected: (_) => onModeChanged(true),
          ),
        ],
      ),
      if (halfDay) ...[
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey(half),
          initialValue: half,
          decoration: const InputDecoration(
            labelText: 'Which half? *',
            hintText: 'Select a half',
          ),
          items: const [
            DropdownMenuItem(value: 'first_half', child: Text('First Half')),
            DropdownMenuItem(value: 'second_half', child: Text('Second Half')),
          ],
          onChanged: (value) {
            if (value != null) onHalfChanged(value);
          },
        ),
      ],
    ],
  );
}
