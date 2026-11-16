import 'package:flutter_test/flutter_test.dart';
import 'package:penguinpeak_hrms/features/notifications/domain/notification_destination.dart';

void main() {
  const id = '10000000-0000-0000-0000-000000000001';
  test('legacy leave notifications retain their destination', () {
    final target = NotificationDestination.fromMap({'leave_request_id': id});
    expect(target?.screen, 'leave');
    expect(target?.recordId, id);
  });
  test('all active modules route to a known workspace label', () {
    for (final screen in NotificationDestination.labels.keys) {
      final target = NotificationDestination.fromMap({
        'destination': screen,
        'target_id': id,
      });
      expect(target?.label, NotificationDestination.labels[screen]);
      expect(target?.recordId, id);
    }
  });
  test('retired modules and external links cannot become destinations', () {
    for (final screen in [
      'expense',
      'shift',
      'onboarding',
      'ticket',
      'document',
      'swap',
      'asset',
      'performance',
      'offboarding',
      'reports',
      'https://example.com',
    ]) {
      expect(NotificationDestination.fromMap({'screen': screen}), isNull);
    }
  });
  test(
    'invalid identifiers fall back to the module without opening a record',
    () {
      expect(
        NotificationDestination.fromMap({
          'destination': 'payslip',
          'target_id': '../../secret',
        })?.recordId,
        isNull,
      );
    },
  );
}
