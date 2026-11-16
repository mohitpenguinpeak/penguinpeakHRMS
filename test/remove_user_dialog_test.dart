import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penguinpeak_hrms/features/people/presentation/remove_user_dialog.dart';

void main() {
  for (final confirm in [false, true]) {
    testWidgets('user removal requires explicit confirmation: $confirm', (
      tester,
    ) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await confirmUserRemoval(context, 'Asha');
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('This cannot be undone.'), findsOneWidget);
      expect(result, isNull);
      await tester.tap(find.text(confirm ? 'Delete permanently' : 'Cancel'));
      await tester.pumpAndSettle();
      expect(result, confirm);
      expect(tester.takeException(), isNull);
    });
  }
}
