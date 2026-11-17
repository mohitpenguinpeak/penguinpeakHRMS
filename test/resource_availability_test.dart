import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penguinpeak_hrms/task_management_screen.dart';

import 'support/qa_backend.dart';

void main() {
  testWidgets('employee sees a peer in the availability matrix on a phone', (
    tester,
  ) async {
    final backend = QaBackend();
    await tester.runAsync(backend.initialize);
    backend.tables['profiles'] = [
      {...backend.profile, 'role': 'employee'},
    ];
    backend.intercept = (request) async =>
        request.url.path.endsWith('/rpc/resource_availability')
        ? backend.json([
            {'id': 'peer', 'full_name': 'Peer Employee', 'days': {}},
          ])
        : backend.respond(request);
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    try {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TaskManagementScreen(
                role: 'employee',
                availabilityOnly: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Peer Employee'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.runAsync(backend.dispose);
    }
  });
}
