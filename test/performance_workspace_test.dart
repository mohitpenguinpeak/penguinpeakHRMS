import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penguinpeak_hrms/features/performance/data/performance_repository.dart';
import 'package:penguinpeak_hrms/features/performance/domain/performance_report.dart';
import 'package:penguinpeak_hrms/features/performance/presentation/performance_workspace.dart';

class FakePerformanceRepository implements PerformanceRepository {
  final List<(PerformancePeriod, DateTime?, String?)> calls = [];
  bool fail = false;
  bool empty = false;
  @override
  String get currentUserId => 'self';
  @override
  Future<PerformanceReport> load(
    PerformancePeriod period, {
    DateTime? anchor,
    String? employeeId,
  }) async {
    calls.add((period, anchor, employeeId));
    if (fail) throw Exception('offline');
    return PerformanceReport.fromJson({
      'start': '2026-11-01',
      'end': '2026-11-30',
      'today': '2026-11-16',
      'timezone': 'Asia/Kolkata',
      'provisional': true,
      'employees': empty
          ? []
          : [
              for (final id
                  in employeeId == null ? ['self', 'report'] : [employeeId])
                {
                  'id': id,
                  'full_name': id == 'self' ? 'Alex Employee' : 'Jamie Report',
                  'department': 'Engineering',
                  'score': id == 'self' ? 82.5 : null,
                  'available_weight': id == 'self' ? 100 : 0,
                  'completion': 80,
                  'delivery': 75,
                  'attendance': 100,
                  'punctuality': 75,
                  'task_count': 10,
                  'completed_tasks': 8,
                  'dated_tasks': 8,
                  'on_time_tasks': 6,
                  'expected_days': 5,
                  'attended_days': 5,
                  'punctual_days': 4,
                  'on_time_days': 3,
                },
            ],
    });
  }
}

Widget app(FakePerformanceRepository repository, {String? employeeId}) =>
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PerformanceWorkspace(
            repository: repository,
            employeeId: employeeId,
          ),
        ),
      ),
    );

void main() {
  testWidgets('KPI explanation does not read a saved scroll offset as a bool', (
    tester,
  ) async {
    final bucket = PageStorageBucket();
    final scroll = ScrollController();
    final visible = ValueNotifier(false);
    addTearDown(scroll.dispose);
    addTearDown(visible.dispose);
    final repository = FakePerformanceRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PageStorage(
            bucket: bucket,
            child: ValueListenableBuilder<bool>(
              valueListenable: visible,
              builder: (context, show, _) => SingleChildScrollView(
                key: const PageStorageKey('performance-profile-scroll'),
                controller: scroll,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (show)
                      PerformanceWorkspace(
                        repository: repository,
                        employeeId: 'self',
                      ),
                    const SizedBox(height: 2000),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
    final scrollContext = tester.element(find.byType(SingleChildScrollView));
    expect(bucket.readState(scrollContext), isA<double>());
    visible.value = true;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('How the KPI matrix works'));
    await tester.tap(find.text('How the KPI matrix works'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ExpansionTile>(find.byType(ExpansionTile)).key,
      isA<PageStorageKey<String>>(),
    );
    expect(bucket.readState(scrollContext), isA<double>());
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('ratings preserve no evidence and score boundaries', () {
    expect(PerformanceEmployee({'id': 'x'}).rating, 'No data');
    for (final (score, label) in [
      (90, 'Excellent'),
      (75, 'On track'),
      (60, 'Developing'),
      (59.9, 'Needs attention'),
    ]) {
      expect(PerformanceEmployee({'id': 'x', 'score': score}).rating, label);
    }
  });

  testWidgets(
    'all five periods use the repository and preserve employee scope',
    (tester) async {
      final repository = FakePerformanceRepository();
      await tester.pumpWidget(app(repository, employeeId: 'self'));
      await tester.pumpAndSettle();
      expect(find.text('82.5 / 100'), findsOneWidget);
      expect(find.text('KPI coverage: 100% of matrix'), findsOneWidget);
      expect(
        repository.calls.first.$2,
        isNull,
      ); // Server owns the current date/timezone.
      for (final period in PerformancePeriod.values) {
        await tester.tap(find.text(period.label));
        await tester.pumpAndSettle();
        expect(repository.calls.last.$1, period);
        expect(repository.calls.last.$3, 'self');
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('mobile scorecard and expanded matrix fit without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(FakePerformanceRepository(), employeeId: 'self'),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('How the KPI matrix works'), 300);
    await tester.tap(find.text('How the KPI matrix works'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Monday–Friday'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'connection errors can be retried and empty scopes are explicit',
    (tester) async {
      final repository = FakePerformanceRepository()..fail = true;
      await tester.pumpWidget(app(repository));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not load performance'), findsOneWidget);
      repository
        ..fail = false
        ..empty = true;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(
        find.text('No approved employees available in your access scope.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'automatically refreshes while open and cancels its timer on disposal',
    (tester) async {
      final repository = FakePerformanceRepository();
      await tester.pumpWidget(app(repository));
      await tester.pumpAndSettle();
      expect(repository.calls.length, 2);
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      expect(repository.calls.length, 4);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 2));
      expect(repository.calls.length, 4);
    },
  );
}
