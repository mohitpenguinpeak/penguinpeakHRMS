import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penguinpeak_hrms/role_dashboard_screen.dart';

void main() {
  testWidgets('Profile badge follows attendance and hides unavailable status', (tester) async {
    Future<void> show(bool? checkedIn) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: SingleChildScrollView(child: KekaEmployeeDetailWidget(
          profile: const {'id': 'employee', 'full_name': 'Asha'},
          managerName: 'Manager',
          isCheckedIn: checkedIn,
        )),
      )));
      await tester.pumpAndSettle();
    }
    await show(true);
    expect(find.text('IN'), findsOneWidget);
    expect(find.text('OUT'), findsNothing);
    await show(false);
    expect(find.text('IN'), findsNothing);
    expect(find.text('OUT'), findsOneWidget);
    await show(true);
    expect(find.text('IN'), findsOneWidget);
    await show(null);
    expect(find.text('IN'), findsNothing);
    expect(find.text('OUT'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Profile displays saved details and invokes edit', (tester) async {
    var edited = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: KekaEmployeeDetailWidget(
        profile: const {
          'id': 'abc',
          'full_name': 'Asha',
          'profile_details': {
            'bio': 'Building HR tools',
            'skills': 'Dart, SQL',
            'work_shift': 'Evening shift',
            'emergency_contact': 'Sam: 12345',
          },
        },
        managerName: 'Manager',
        onEdit: () => edited = true,
      ))),
    ));
    expect(find.text('Building HR tools'), findsOneWidget);
    expect(find.text('Dart'), findsOneWidget);
    expect(find.text('SQL'), findsOneWidget);
    expect(find.text('Evening shift'), findsOneWidget);
    expect(find.text('Sam: 12345'), findsOneWidget);
    expect(find.textContaining('@company.com'), findsNothing);
    await tester.tap(find.text('Edit Details'));
    expect(edited, isTrue);
    expect(tester.takeException(), isNull);
  });
}
