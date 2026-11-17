import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penguinpeak_hrms/shared/widgets/company_calendar.dart';

void main() {
  test('leave counts and calendar labels follow the same saved overrides', () {
    final calendar = CompanyCalendar(
      entries: const [
        {
          'holiday_date': '2026-12-02',
          'type': 'National Holiday',
          'name': 'Office closed',
        },
        {
          'holiday_date': '2026-12-05',
          'type': 'Working day',
          'name': 'Saturday shift',
        },
      ],
      child: const SizedBox(),
    );
    DateTime date(int day) => DateTime(2026, 12, day);
    expect(calendar.works(date(2)), isFalse);
    expect(calendar.label(date(2)), contains('Office closed'));
    expect(calendar.works(date(5)), isTrue);
    expect(calendar.label(date(5)), contains('Saturday shift'));
    expect(calendar.works(date(12)), isTrue);
    expect(calendar.label(date(26)), 'Working Saturday');
    expect(calendar.works(date(19)), isFalse);
    expect(calendar.works(DateTime(2027, 1, 30)), isFalse);
    expect(calendar.works(date(6)), isFalse);
    expect(calendar.count(date(1), date(7)), 5);
  });
}
