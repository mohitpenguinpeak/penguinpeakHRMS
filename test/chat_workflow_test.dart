import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:penguinpeak_hrms/chat_screen.dart';

import 'support/qa_backend.dart';

Future<void> chatFixture(
  WidgetTester tester,
  QaBackend backend,
  Future<void> Function() check,
) async {
  await tester.runAsync(backend.initialize);
  backend.tables['conversation_participants'] = [
    {'user_id': qaEmployeeId, 'conversation_id': 'a'},
    {'user_id': qaEmployeeId, 'conversation_id': 'b'},
  ];
  backend.tables['conversations'] = [
    for (final id in ['a', 'b'])
      {
        'id': id,
        'is_group': true,
        'title': 'Conversation $id',
        'conversation_participants': [],
        'messages': [],
        'created_at': '2026-11-16',
      },
  ];
  tester.view.physicalSize = const Size(1100, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  try {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: ChatScreen(role: 'hr')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await check();
  } finally {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.runAsync(backend.dispose);
  }
}

void main() {
  testWidgets('late history response cannot replace the active conversation', (
    tester,
  ) async {
    final backend = QaBackend();
    final oldHistory = Completer<http.Response>();
    backend.intercept = (request) async {
      if (request.url.path.endsWith('/messages')) {
        if (request.url.queryParameters['conversation_id'] == 'eq.a') {
          return oldHistory.future;
        }
        return backend.json([
          {
            'id': 'new',
            'message': 'Current conversation message',
            'sender_id': qaEmployeeId,
            'created_at': '2026-11-16T09:00:00Z',
          },
        ]);
      }
      return backend.respond(request);
    };
    await chatFixture(tester, backend, () async {
      await tester.tap(find.text('Conversation a').first);
      await tester.pump();
      await tester.tap(find.text('Conversation b').first);
      await tester.pumpAndSettle();
      expect(find.text('Current conversation message'), findsOneWidget);
      oldHistory.complete(
        backend.json([
          {
            'id': 'old',
            'message': 'Old conversation message',
            'sender_id': qaEmployeeId,
            'created_at': '2026-11-16T08:00:00Z',
          },
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Current conversation message'), findsOneWidget);
      expect(find.text('Old conversation message'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
  testWidgets(
    'rapid sends submit once and do not clear a different conversation draft',
    (tester) async {
      final backend = QaBackend();
      final sent = Completer<http.Response>();
      var sends = 0;
      backend.intercept = (request) async {
        if (request.url.path.endsWith('/messages') &&
            request.method == 'POST') {
          sends++;
          return sent.future;
        }
        return backend.respond(request);
      };
      await chatFixture(tester, backend, () async {
        await tester.tap(find.text('Conversation a').first);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'First message');
        await tester.tap(find.byIcon(Icons.send));
        await tester.tap(find.byIcon(Icons.send));
        await tester.pump();
        expect(sends, 1);
        await tester.tap(find.text('Conversation b').first);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'New private draft');
        sent.complete(backend.json(null, status: 201));
        await tester.pumpAndSettle();
        expect(find.text('New private draft'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    },
  );
}
