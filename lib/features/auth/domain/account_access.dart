/// Interprets the authenticated user's database profile, never signup metadata.
/// This is a client gate; database RLS/RPCs must independently enforce access.
class AccountAccess {
  const AccountAccess({required this.status, required this.role});

  static const supportedRoles = {
    'employee',
    'management',
    'admin',
    'hr',
    'super_admin',
  };

  factory AccountAccess.fromProfile(Map<String, dynamic>? profile) =>
      AccountAccess(
        status: profile?['approval_status']?.toString() ?? '',
        role: profile?['role']?.toString() ?? '',
      );

  final String status;
  final String role;

  bool get isApproved => status == 'approved' && supportedRoles.contains(role);
  bool get isRejected => status == 'rejected';
}
