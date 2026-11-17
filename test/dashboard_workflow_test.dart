import 'package:penguinpeak_hrms/shared/widgets/app_toast.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:penguinpeak_hrms/role_dashboard_screen.dart';

import 'support/qa_backend.dart';

Future<void> dashboardFixture(
  WidgetTester tester,
  QaBackend backend,
  Future<void> Function() check,
) async {
  await tester.runAsync(backend.initialize);
  tester.view.physicalSize = const Size(1100, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  try {
    await tester.pumpWidget(
      const MaterialApp(home: RoleDashboardScreen(role: 'hr')),
    );
    await tester.pumpAndSettle();
    await check();
  } finally {
    AppToast.dismiss();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.runAsync(backend.dispose);
  }
}

void main() {
  testWidgets(
    'dashboard post uses the supported column and prevents duplicate publication',
    (tester) async {
      final backend = QaBackend();
      final saved = Completer<http.Response>();
      Map<String, dynamic>? payload;
      var posts = 0;
      backend.intercept = (request) async {
        if (request.method == 'POST' &&
            request.url.path.endsWith('/company_wall_posts')) {
          posts++;
          payload = jsonDecode(request.body) as Map<String, dynamic>;
          return saved.future;
        }
        return backend.respond(request);
      };
      await dashboardFixture(tester, backend, () async {
        final composer = find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.hintText?.startsWith(
                    'Share a company update',
                  ) ==
                  true,
        );
        await tester.ensureVisible(composer);
        await tester.enterText(composer, 'First post');
        await tester.ensureVisible(find.text('Publish Post'));
        await tester.tap(find.text('Publish Post'));
        await tester.tap(find.text('Publish Post'));
        await tester.pump();
        expect(posts, 1);
        expect(payload?['post_type'], 'general');
        expect(payload?.containsKey('category'), isFalse);
        await tester.enterText(composer, 'Next draft');
        saved.complete(backend.json(null, status: 201));
        await tester.pumpAndSettle();
        expect(find.text('Next draft'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    },
  );
  testWidgets(
    'quick checkout rejects an active break and ignores repeated taps',
    (tester) async {
      final backend = QaBackend();
      final now = DateTime.now();
      final record = <String, dynamic>{
        'id': 'attendance',
        'employee_id': qaEmployeeId,
        'attendance_date': now.toIso8601String().split('T')[0],
        'check_in': now
            .subtract(const Duration(hours: 1))
            .toUtc()
            .toIso8601String(),
        'check_out': null,
        'status': 'Present',
        'attendance_breaks': [
          {
            'break_start': now
                .subtract(const Duration(minutes: 10))
                .toUtc()
                .toIso8601String(),
            'break_end': null,
            'session_index': 0,
          },
        ],
      };
      backend.tables['attendance_records'] = [record];
      await dashboardFixture(tester, backend, () async {
        final pending = Completer<http.Response>();
        var reads = 0;
        backend.intercept = (request) async {
          if (request.method == 'GET' &&
              request.url.path.endsWith('/attendance_records')) {
            reads++;
            return pending.future;
          }
          return backend.respond(request);
        };
        await tester.scrollUntilVisible(
          find.text('Check Out Now'),
          300,
          scrollable: find
              .descendant(
                of: find.byKey(const PageStorageKey('workspace-Overview')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Check Out Now'));
        await tester.tap(find.text('Check Out Now'));
        await tester.pump();
        expect(reads, 1);
        pending.complete(backend.json([record]));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          backend.requests.where(
            (r) =>
                r.method == 'PATCH' &&
                r.url.path.endsWith('/attendance_records'),
          ),
          isEmpty,
        );
        expect(find.textContaining('end your active break'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    },
  );
}
