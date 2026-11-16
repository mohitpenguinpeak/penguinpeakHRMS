import 'dart:typed_data';

import 'package:penguinpeak_hrms/shared/widgets/app_toast.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:penguinpeak_hrms/features/hr/domain/hr_module.dart';
import 'package:penguinpeak_hrms/features/hr/presentation/hr_workspace.dart';

import 'hr_modules_test.dart' show MemoryHr;

class CapturingPicker extends FilePickerPlatform {
  Uint8List? savedBytes;
  bool cancel = false;
  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    savedBytes = bytes;
    return cancel ? null : Uri.file('/tmp/payslip.pdf');
  }
}

void main() {
  tearDown(AppToast.dismiss);
  testWidgets('new salary slip downloads without creating a Supabase record', (
    tester,
  ) async {
    final original = FilePickerPlatform.instance;
    final picker = CapturingPicker();
    FilePickerPlatform.instance = picker;
    addTearDown(() {
      FilePickerPlatform.instance = original;
    });
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final module = HrModule.all.firstWhere((m) => m.id == 'payslip');
    final repo = MemoryHr(module)..empty = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HrWorkspace(module: module, role: 'hr', repository: repo),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create salary slip'));
    await tester.pumpAndSettle();
    for (final field in {
      'Title': 'Salary November',
      'Salary month (YYYY-MM)': '2026-11',
      'Basic salary': '20000',
      'Allowances': '2000',
      'Deductions': '1000',
    }.entries) {
      final input = find.widgetWithText(TextFormField, field.key);
      await tester.ensureVisible(input);
      await tester.enterText(input, field.value);
    }
    await tester.ensureVisible(find.text('Download PDF'));
    await tester.tap(find.text('Download PDF'));
    for (var i = 0; i < 80 && picker.savedBytes == null; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(picker.savedBytes, isNotNull);
    expect(String.fromCharCodes(picker.savedBytes!.take(5)), '%PDF-');
    expect(repo.createCalls, 0);
    expect(find.text('Salary slip PDF saved successfully.'), findsOneWidget);
    AppToast.dismiss();
    await tester.pumpAndSettle();
  });

  for (final cancelled in [false, true]) {
    testWidgets('PDF download generates actual bytes; cancelled=$cancelled', (
      tester,
    ) async {
      final original = FilePickerPlatform.instance;
      final picker = CapturingPicker()..cancel = cancelled;
      FilePickerPlatform.instance = picker;
      addTearDown(() {
        FilePickerPlatform.instance = original;
      });
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final module = HrModule.all.firstWhere((m) => m.id == 'payslip');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HrWorkspace(
              module: module,
              role: 'hr',
              repository: MemoryHr(module),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('View details'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Download / Generate Payslip PDF'));
      await tester.tap(find.text('Download / Generate Payslip PDF'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download PDF'));
      for (var i = 0; i < 80 && picker.savedBytes == null; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump(const Duration(milliseconds: 300));
      expect(picker.savedBytes, isNotNull);
      expect(String.fromCharCodes(picker.savedBytes!.take(5)), '%PDF-');
      expect(
        find.text('Salary slip PDF saved successfully.'),
        cancelled ? findsNothing : findsOneWidget,
      );
      AppToast.dismiss();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
