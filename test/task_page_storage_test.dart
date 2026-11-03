import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penguinpeak_hrms/features/tasks/presentation/task_filter_panel.dart';
import 'package:penguinpeak_hrms/features/tasks/presentation/grouped_task_board.dart';

void main() {
  testWidgets(
    'task panels isolate expansion flags from saved workspace scroll offsets',
    (tester) async {
      final bucket = PageStorageBucket();
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final showPanels = ValueNotifier(false);
      addTearDown(showPanels.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PageStorage(
              bucket: bucket,
              child: ValueListenableBuilder<bool>(
                valueListenable: showPanels,
                builder: (context, visible, _) => ListView(
                  controller: scroll,
                  key: const PageStorageKey('workspace-Tasks'),
                  children: [
                    if (visible)
                      const TaskFilterPanel(child: Text('Filter controls')),
                    if (visible)
                      GroupedTaskBoard(
                        tasks: const [
                          {
                            'id': '1',
                            'title': 'Stored task',
                            'project': 'Website',
                            'status': 'todo',
                          },
                        ],
                        groupBy: 'project',
                        onOpen: (_) {},
                        employeeName: (_) => 'Employee',
                      ),
                    const SizedBox(height: 2200),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.drag(find.byType(ListView), const Offset(0, -180));
      await tester.pumpAndSettle();
      final listContext = tester.element(find.byType(ListView));
      final scrollOffset = bucket.readState(listContext);
      expect(scrollOffset, isA<double>());
      expect(scrollOffset as double, greaterThan(0));
      showPanels.value = true;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // The collapsed filter header may be outside the ListView's lazy cache.
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Filters, sorting & grouping'));
      await tester.tap(find.text('Filters, sorting & grouping'));
      await tester.pumpAndSettle();
      expect(find.text('Filter controls'), findsOneWidget);
      expect(
        bucket.readState(tester.element(find.byType(ListView))),
        isA<double>(),
      );
      await tester.ensureVisible(find.text('Website').first);
      await tester.tap(find.text('Website').first);
      await tester.pumpAndSettle();
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Collapse all groups'));
      await tester.pumpAndSettle();
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Expand all groups'));
      await tester.pumpAndSettle();
      expect(find.text('Stored task'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
