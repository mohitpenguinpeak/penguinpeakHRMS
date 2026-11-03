import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penguinpeak_hrms/features/dashboard/presentation/holiday_list.dart';

void main() {
  testWidgets('empty backend shows no invented holidays', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HolidayList(holidays: const [], onRetry: () {}),
        ),
      ),
    );
    expect(
      find.text('No upcoming company holidays configured.'),
      findsOneWidget,
    );
    expect(find.textContaining('Christmas'), findsNothing);
    expect(find.byType(ListTile), findsNothing);
  });
  testWidgets('load error takes precedence and supports retry', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HolidayList(
            holidays: const [
              {'name': 'Stale holiday'},
            ],
            error: 'Could not load company holidays.',
            onRetry: () => retries++,
          ),
        ),
      ),
    );
    expect(find.text('Could not load company holidays.'), findsOneWidget);
    expect(find.text('Stale holiday'), findsNothing);
    await tester.tap(find.text('Retry holidays'));
    expect(retries, 1);
  });
  testWidgets('saved records display their actual dates and names', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HolidayList(
            holidays: const [
              {
                'name': 'Company foundation day',
                'holiday_date': '2026-12-04',
                'type': 'Company',
              },
            ],
            onRetry: () {},
          ),
        ),
      ),
    );
    expect(find.text('Company foundation day'), findsOneWidget);
    expect(find.text('2026-12-04 • Company'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
