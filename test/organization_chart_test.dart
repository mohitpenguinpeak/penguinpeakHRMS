import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penguinpeak_hrms/app_theme.dart';
import 'package:penguinpeak_hrms/features/organization/domain/organization_tree.dart';
import 'package:penguinpeak_hrms/features/organization/presentation/organization_chart.dart';

Map<String, dynamic> person(
  String id,
  String name, {
  String? manager,
  String? department,
  String status = 'approved',
}) => {
  'id': id,
  'full_name': name,
  'manager_id': manager,
  'department': department,
  'approval_status': status,
};
void main() {
  final profiles = [
    person('a', 'Asha'),
    person('b', 'Biren'),
    person('c', 'Chirag', manager: 'a', department: 'Engineering'),
    person('d', 'Deepa', manager: 'c'),
  ];
  test(
    'independent roots are separate and reports have the correct parent',
    () {
      final tree = OrganizationTree(profiles);
      expect(tree.roots, ['a', 'b']);
      expect(tree.children['a'], ['c']);
      expect(tree.children['c'], ['d']);
    },
  );
  test('unavailable manager does not hide an employee or invent a parent', () {
    final tree = OrganizationTree([
      person('a', 'Asha', manager: 'hidden'),
      person('b', 'Pending', status: 'pending'),
    ]);
    expect(tree.roots, ['a']);
    expect(tree.note('a'), 'Manager not in this directory');
    expect(tree.people.length, 1);
  });
  test('cycles and self-management retain every approved employee safely', () {
    final tree = OrganizationTree([
      person('a', 'Asha', manager: 'b'),
      person('b', 'Biren', manager: 'a'),
      person('c', 'Chirag', manager: 'a'),
      person('d', 'Deepa', manager: 'd'),
    ]);
    expect(tree.cycles, {'a', 'b', 'd'});
    expect(tree.roots.toSet(), {'a', 'b', 'd'});
    expect(tree.children['a'], ['c']);
    expect(tree.children.values.expand((v) => v).length + tree.roots.length, 4);
  });
  test('search and department retain ancestor context', () {
    final tree = OrganizationTree(profiles);
    expect(tree.visible('Deepa', null), {'a', 'c', 'd'});
    expect(tree.visible('', 'Engineering'), {'a', 'c'});
    expect(tree.visible('missing', null), isEmpty);
  });
  Future<void> host(
    WidgetTester tester,
    double width, {
    List<Map<String, dynamic>>? data,
    ValueChanged<Map<String, dynamic>>? open,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemes.dark,
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 1000),
            textScaler: const TextScaler.linear(1.5),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: OrganizationChart(
                  profiles: data ?? profiles,
                  onOpenProfile: open ?? (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'phone outline opens a saved profile and search reveals descendants',
    (tester) async {
      Map<String, dynamic>? opened;
      await host(tester, 320, open: (profile) => opened = profile);
      expect(find.byType(InteractiveViewer), findsNothing);
      await tester.ensureVisible(find.text('Biren'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Biren'));
      expect(opened?['id'], 'b');
      await tester.ensureVisible(find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Deepa');
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(ListTile), matching: find.text('Deepa')), findsOneWidget);
      expect(find.text('Asha'), findsOneWidget);
      expect(find.text('Biren'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [768.0, 1600.0]) {
    testWidgets('desktop forest uses separate root positions at $width', (
      tester,
    ) async {
      await host(tester, width);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      final a = tester.getRect(find.byKey(const ValueKey('org-card:a')));
      final b = tester.getRect(find.byKey(const ValueKey('org-card:b')));
      final child = tester.getRect(find.byKey(const ValueKey('org-card:c')));
      expect(a.top, closeTo(b.top, 0.01));
      expect(a.left, isNot(b.left));
      expect(child.top, greaterThan(a.bottom));
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fit to view'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('empty directory is honest', (tester) async {
    await host(tester, 320, data: []);
    expect(
      find.text('No approved employees in this directory.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
