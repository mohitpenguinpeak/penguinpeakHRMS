import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penguinpeak_hrms/app_theme.dart';
import 'package:penguinpeak_hrms/features/hr/data/hr_repository.dart';
import 'package:penguinpeak_hrms/features/hr/domain/hr_module.dart';
import 'package:penguinpeak_hrms/features/hr/presentation/hr_workspace.dart';

class MemoryHr extends HrRepository {
  MemoryHr(this.module);
  final HrModule module;
  @override
  String get userId => 'employee';
  String? failure;
  bool empty = false;
  String? lastAction;
  int createCalls = 0;
  Map<String, dynamic> get row => {
    'id': 'record',
    'module': module.id,
    'employee_id': userId,
    'revision': 1,
    'title': 'Saved ${module.label}',
    'description': 'A real record loaded through the repository',
    'status': module.states.first,
    'created_at': '2026-11-04',
    'company_wide': false,
    'data': {
      for (final f in module.fields)
        f.key: f.number
            ? '100'
            : f.date
            ? '2026-11-04'
            : 'Saved value',
    },
  };
  @override
  Future<List<Map<String, dynamic>>> records(String module) async {
    if (failure != null) throw Exception(failure);
    return empty ? [] : [row];
  }

  @override
  Future<List<Map<String, dynamic>>> employees() async => [
    {
      'id': userId,
      'full_name': 'Asha with a long employee name',
      'manager_id': 'manager',
    },
  ];
  @override
  Future<String> create(
    String module,
    String employee,
    String title,
    String description,
    Map<String, dynamic> data,
    bool companyWide,
  ) async {
    createCalls++;
    return 'created';
  }

  @override
  Future<void> update(
    Map<String, dynamic> row,
    String action,
    String note,
    Map<String, dynamic> patch,
  ) async {
    lastAction = action;
  }

  @override
  Future<List<Map<String, dynamic>>> history(String id) async => [
    {
      'action': 'created',
      'created_at': '2026-11-04',
      'actor_id': userId,
      'note': '',
    },
  ];
  @override
  Future<List<Map<String, dynamic>>> attachments(String id) async => [];
  @override
  Future<List<Map<String, dynamic>>> acknowledgements(String id) async => [];
  @override
  Future<void> acknowledge(String id) async {}
  @override
  Future<void> upload(String id, String name, Uint8List bytes) async {}
  @override
  Future<String> downloadUrl(String path) async => 'https://example.test/file';
}

void main() {
  Future<void> host(WidgetTester tester, Widget child, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemes.dark,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(16), child: child),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('empty payslips workspace offers creation directly', (
    tester,
  ) async {
    final module = HrModule.all.firstWhere((m) => m.id == 'payslip');
    final repo = MemoryHr(module)..empty = true;
    await host(
      tester,
      HrWorkspace(module: module, role: 'hr', repository: repo),
      1000,
    );
    expect(find.text('Generate a salary slip'), findsOneWidget);
    await tester.tap(find.text('Create salary slip'));
    await tester.pumpAndSettle();
    expect(find.text('Salary month (YYYY-MM)'), findsOneWidget);
    expect(find.text('Basic salary'), findsOneWidget);
  });

  for (final width in [320.0, 390.0, 1600.0]) {
    for (final module in HrModule.all) {
      testWidgets('${module.label} list, details and form fit $width', (
        tester,
      ) async {
        final repo = MemoryHr(module);
        await host(
          tester,
          HrWorkspace(module: module, role: 'hr', repository: repo),
          width,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('View details'));
        await tester.pumpAndSettle();
        expect(find.text('Record ID: record'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        final createLabel = module.id == 'payslip'
            ? 'Generate payslip'
            : 'New record';
        await tester.ensureVisible(find.text(createLabel));
        await tester.tap(find.text(createLabel));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(
          find.text(module.id == 'payslip' ? 'Download PDF' : 'Save'),
        );
        await tester.pumpAndSettle();
        expect(find.text('Enter a title'), findsOneWidget);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('employees cannot issue payslips and can retry load errors', (
    tester,
  ) async {
    final repo = MemoryHr(HrModule.all.firstWhere((m) => m.id == 'payslip'))
      ..failure = 'Unavailable';
    await host(
      tester,
      HrWorkspace(module: repo.module, role: 'employee', repository: repo),
      390,
    );
    expect(find.text('New record'), findsNothing);
    expect(find.text('Could not load this module.'), findsOneWidget);
    repo.failure = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('View details'), findsOneWidget);
  });
  testWidgets('notification opens a specific HR record once', (tester) async {
    final repo = MemoryHr(HrModule.all.first);
    var consumed = 0;
    await host(
      tester,
      HrWorkspace(
        module: repo.module,
        role: 'employee',
        repository: repo,
        initialRecordId: 'record',
        onTargetConsumed: () => consumed++,
      ),
      390,
    );
    expect(find.text('Record ID: record'), findsOneWidget);
    expect(consumed, 1);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Record ID: record'), findsNothing);
    expect(consumed, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('unavailable HR notification target shows a useful error', (
    tester,
  ) async {
    final repo = MemoryHr(HrModule.all.first);
    await host(
      tester,
      HrWorkspace(
        module: repo.module,
        role: 'employee',
        repository: repo,
        initialRecordId: 'missing',
      ),
      390,
    );
    expect(
      find.text('This record is no longer available to your account.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  test('only payslips remain registered', () {
    expect(HrModule.all.map((module) => module.id), ['payslip']);
  });
  test('payslip publication retains role restrictions', () {
    final payslip = HrModule.all.firstWhere((m) => m.id == 'payslip');
    expect(payslip.actions('draft', hr: false, owner: true), isEmpty);
    expect(payslip.actions('draft', hr: true, owner: false), ['published']);
  });
  test('validates salary amounts and joining dates', () {
    const amount = HrField('basic', 'Basic salary', number: true);
    for (final v in ['-1', 'NaN', 'Infinity', '1.001', '100000001']) {
      expect(validateHrField(amount, v), isNotNull);
    }
    expect(validateHrField(amount, '0'), isNull);
    expect(validateHrField(amount, '150.50'), isNull);
    const date = HrField('joining_date', 'Joining date', date: true);
    expect(validateHrField(date, '2026-02-30'), isNotNull);
    expect(validateHrField(date, '2026-11-04'), isNull);
  });
}
