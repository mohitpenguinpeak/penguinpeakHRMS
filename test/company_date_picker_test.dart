import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penguinpeak_hrms/features/dashboard/presentation/company_date_picker.dart';

void main() {
  testWidgets(
    'picker shows saved holidays and the Saturday schedule before selection',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompanyDatePicker(
              initialDate: DateTime(2026, 11, 16),
              entries: const [
                {
                  'holiday_date': '2026-12-02',
                  'type': 'National Holiday',
                  'name': 'Office closed',
                },
                {
                  'holiday_date': '2026-12-19',
                  'type': 'Working day',
                  'name': 'Special shift',
                },
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(find.text('02 · Office closed'), findsOneWidget);
      expect(
        find.byTooltip('Saturday, December 5, 2026 · Weekly off'),
        findsOneWidget,
      );
      expect(
        find.byTooltip('Saturday, December 12, 2026 · Working Saturday'),
        findsOneWidget,
      );
      expect(
        find.byTooltip(
          'Saturday, December 19, 2026 · Special shift · Working day',
        ),
        findsOneWidget,
      );
    },
  );
}
