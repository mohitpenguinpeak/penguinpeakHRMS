import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// A duration, rather than a time of day: no AM/PM or seconds.
class BookingDurationPicker extends StatefulWidget {
  const BookingDurationPicker({
    super.key,
    required this.initialMinutes,
    required this.onChanged,
  });

  final int initialMinutes;
  final ValueChanged<int> onChanged;

  @override
  State<BookingDurationPicker> createState() => _BookingDurationPickerState();
}

class _BookingDurationPickerState extends State<BookingDurationPicker> {
  late int _hours;
  late int _minutes;
  late final FixedExtentScrollController _hourController;
  late final FixedExtentScrollController _minuteController;

  @override
  void initState() {
    super.initState();
    _hours = widget.initialMinutes ~/ 60;
    _minutes = widget.initialMinutes % 60;
    _hourController = FixedExtentScrollController(initialItem: _hours);
    _minuteController = FixedExtentScrollController(initialItem: _minutes);
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.headlineSmall
        ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    Widget wheel(
      String label,
      int count,
      FixedExtentScrollController controller,
      ValueChanged<int> onChanged,
    ) => Expanded(
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          Expanded(
            child: CupertinoPicker.builder(
              scrollController: controller,
              itemExtent: 36,
              childCount: count,
              onSelectedItemChanged: onChanged,
              itemBuilder: (context, index) => Center(
                child: Text(index.toString().padLeft(2, '0'), style: style),
              ),
            ),
          ),
        ],
      ),
    );

    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Estimated Booking Duration',
      ),
      child: SizedBox(
        height: 132,
        child: Row(
          children: [
            wheel(
              'Hours',
              widget.initialMinutes ~/ 60 > 99
                  ? widget.initialMinutes ~/ 60 + 1
                  : 100,
              _hourController,
              (value) {
                _hours = value;
                widget.onChanged(_hours * 60 + _minutes);
              },
            ),
            Text(':', style: style),
            wheel('Minutes', 60, _minuteController, (value) {
              _minutes = value;
              widget.onChanged(_hours * 60 + _minutes);
            }),
          ],
        ),
      ),
    );
  }
}
