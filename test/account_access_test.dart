import 'package:flutter_test/flutter_test.dart';
import 'package:penguinpeak_hrms/features/auth/domain/account_access.dart';

void main() {
  test('all existing approved roles can enter the application', () {
    for (final role in [
      'employee',
      'management',
      'hr',
      'admin',
      'super_admin',
    ]) {
      expect(
        AccountAccess.fromProfile({'approval_status': 'approved', 'role': role})
            .isApproved,
        isTrue,
        reason: role,
      );
    }
  });

  test(
    'pending and rejected accounts remain denied even with privileged roles',
    () {
      for (final status in ['pending', 'rejected', '', 'APPROVED']) {
        expect(
          AccountAccess.fromProfile({
            'approval_status': status,
            'role': 'super_admin',
          }).isApproved,
          isFalse,
          reason: status,
        );
      }
    },
  );

  test('missing profile and unknown or missing roles fail closed', () {
    for (final profile in <Map<String, dynamic>?>[
      null,
      {},
      {'approval_status': 'approved'},
      {'approval_status': 'approved', 'role': 'owner'},
      {'approval_status': 'approved', 'role': 'HR'},
    ]) {
      expect(AccountAccess.fromProfile(profile).isApproved, isFalse);
    }
  });

  test('rejected accounts retain their distinct account state', () {
    final access = AccountAccess.fromProfile({
      'approval_status': 'rejected',
      'role': 'employee',
    });
    expect(access.isRejected, isTrue);
    expect(access.isApproved, isFalse);
  });
}
