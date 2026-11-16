/// Only known destinations can be opened, including from untrusted push data.
class NotificationDestination {
  const NotificationDestination(this.screen, {this.recordId});
  final String screen;
  final String? recordId;
  static const labels = {
    'leave': 'Leave',
    'payslip': 'Payslips & Salary',
    'tasks': 'Tasks',
    'chat': 'Chat',
    'attendance_adjustments': 'Attendance Adjustments',
    'company_wall': 'Company Wall',
  };
  String get label => labels[screen]!;
  static NotificationDestination? fromMap(Map<String, dynamic> value) {
    final screen = (value['destination'] ?? value['screen'] ?? 'leave')
        .toString();
    if (!labels.containsKey(screen)) return null;
    final id =
        value['target_id'] ??
        (screen == 'leave' ? value['leave_request_id'] : null);
    final text = id?.toString();
    final valid =
        text != null &&
        RegExp(r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')
            .hasMatch(text);
    return NotificationDestination(screen, recordId: valid ? text : null);
  }
}
