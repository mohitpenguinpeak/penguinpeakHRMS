import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const qaEmployeeId = '10000000-0000-0000-0000-000000000001';

/// Isolated fake backend; no live credentials, messages or employee changes.
class QaBackend {
  final Map<String, List<Map<String, dynamic>>> tables = {};
  final requests = <http.Request>[];
  Future<http.Response> Function(http.Request)? intercept;
  Map<String, dynamic> get profile => {
    'id': qaEmployeeId,
    'full_name': 'Alexandra Long Employee Name',
    'approval_status': 'approved',
    'role': 'hr',
    'created_at': '2026-01-01',
    'department': 'People and Operations',
    'designation': 'HR Manager',
  };
  Future<void> initialize() async {
    tables['profiles'] = [profile];
    tables['company_attendance_settings'] = [
      {
        'timezone': 'UTC',
        'work_start_time': '09:00:00',
        'work_end_time': '17:00:00',
        'half_day_hours': 4,
        'grace_period_minutes': 15,
        'breaks_enabled': true,
      },
    ];
    await Supabase.initialize(
      url: 'https://qa.invalid',
      publishableKey: 'qa-anon-key',
      realtimeClientOptions: RealtimeClientOptions(
        transport: (uri, headers) => QaSocket(),
      ),
      httpClient: MockClient((request) async {
        requests.add(request);
        final response = intercept == null
            ? respond(request)
            : await intercept!(request);
        return http.Response(
          response.body,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
      authOptions: FlutterAuthClientOptions(
        pkceAsyncStorage: QaAuthStorage(),
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
      ),
    );
    await Supabase.instance.client.auth.signInWithPassword(
      email: 'qa@example.invalid',
      password: 'fixture-only',
    );
  }

  http.Response respond(http.Request request) {
    if (request.url.path.contains('/auth/v1/token')) {
      final payload = base64Url
          .encode(
            utf8.encode(
              jsonEncode({
                'sub': qaEmployeeId,
                'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
              }),
            ),
          )
          .replaceAll('=', '');
      return json({
        'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.fixture',
        'token_type': 'bearer',
        'expires_in': 3600,
        'refresh_token': 'fixture-refresh',
        'user': {
          'id': qaEmployeeId,
          'aud': 'authenticated',
          'email': 'qa@example.invalid',
          'app_metadata': {},
          'user_metadata': {},
          'created_at': '2026-01-01T00:00:00Z',
        },
      });
    }
    if (request.url.path.contains('/auth/')) return json({});
    final table = request.url.pathSegments.last;
    if (table == 'task_work_logs' && request.method == 'POST') {
      return json(null, status: 201);
    }
    var rows = tables[table] ?? [];
    for (final entry in request.url.queryParameters.entries) {
      if (entry.value.startsWith('eq.')) {
        rows = rows
            .where((r) => r[entry.key]?.toString() == entry.value.substring(3))
            .toList();
      }
    }
    if (request.headers['accept']?.contains('vnd.pgrst.object') ?? false) {
      return rows.isEmpty
          ? json({
              'code': 'PGRST116',
              'details': 'The result contains 0 rows',
              'message': 'No rows',
            }, status: 406)
          : json(rows.first);
    }
    return json(rows);
  }

  http.Response json(dynamic body, {int status = 200}) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
  Future<void> dispose() => Supabase.instance.dispose();
}

// Minimal in-memory Phoenix transport: no DNS, sockets or remote subscriptions.
class QaSocket implements WebSocketChannel {
  final _incoming = StreamController<dynamic>();
  @override
  Stream<dynamic> get stream => _incoming.stream;
  @override
  late final WebSocketSink sink = QaSink(_incoming);
  @override
  Future<void> get ready async {}
  @override
  String? get protocol => null;
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class QaSink implements WebSocketSink {
  QaSink(this.incoming);
  final StreamController<dynamic> incoming;
  @override
  void add(dynamic data) {
    final message = jsonDecode(data as String);
    final payload = message is List ? message[4] : message['payload'];
    final filters = (payload?['config']?['postgres_changes'] as List? ?? []);
    final response = {
      'status': 'ok',
      'response': {
        'postgres_changes': [
          for (var i = 0; i < filters.length; i++)
            {...filters[i] as Map, 'id': i + 1},
        ],
      },
    };
    if (message is List) {
      incoming.add(
        jsonEncode([message[0], message[1], message[2], 'phx_reply', response]),
      );
    } else {
      incoming.add(
        jsonEncode({
          'topic': message['topic'],
          'ref': message['ref'],
          'event': 'phx_reply',
          'payload': response,
        }),
      );
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) => incoming.close();
  @override
  Future<void> get done => Future<void>.value();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class QaAuthStorage extends GotrueAsyncStorage {
  final values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    values.remove(key);
  }
}
