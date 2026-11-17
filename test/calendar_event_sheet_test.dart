import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penguinpeak_hrms/features/dashboard/presentation/calendar_event_sheet.dart';

void main() {
  testWidgets('save a working Saturday from the selected date without typing', (
    tester,
  ) async {
    final day = DateTime(2026, 12, 5);
    late List<Object> saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => CalendarEventSheet(
                    date: day,
                    entries: const [],
                    onRemove: (_) async => false,
                    onSave: (date, name, type) async {
                      saved = [date, name, type];
                    },
                  ),
                ),
                child: const Text('Add event'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Add event'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Working day'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save event'));
    await tester.pumpAndSettle();
    expect(saved, [day, 'Working day', 'Working day']);
    expect(find.text('New calendar event'), findsNothing);
  });
}
