import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penguinpeak_hrms/shared/widgets/app_toast.dart';

void main() {
  testWidgets('existing messages retain their actions in the floating toast', (
    tester,
  ) async {
    addTearDown(AppToast.dismiss);
    late BuildContext host;
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              host = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    AppToast.of(host).showSnackBar(
      SnackBar(
        content: const Text('New notification'),
        action: SnackBarAction(
          label: 'View',
          onPressed: () {
            opened = true;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(find.text('View'));
    expect(opened, isTrue);
    await tester.pump();
    expect(find.text('New notification'), findsNothing);
  });

  testWidgets('compact toast replaces old feedback, dismisses, and expires', (
    tester,
  ) async {
    addTearDown(AppToast.dismiss);
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late BuildContext host;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              host = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    AppToast.show(
      host,
      'Leave request submitted to your manager',
      kind: ToastKind.success,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('All set'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    AppToast.show(host, 'Please select a leave date');
    await tester.pump();
    expect(find.text('Leave request submitted to your manager'), findsNothing);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.byTooltip('Dismiss notification'));
    await tester.pump();
    expect(find.text('Please select a leave date'), findsNothing);
    AppToast.show(host, 'Saved');
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('Saved'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
