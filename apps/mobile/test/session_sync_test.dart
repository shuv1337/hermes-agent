import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/core/db/app_database.dart';
import 'package:hermes_mobile/core/network/hermes_api.dart';
import 'package:hermes_mobile/core/sync/session_sync_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => Directory.systemTemp.path,
      );

  late AppDatabase db;
  late SessionSyncRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = SessionSyncRepository(gatewayId: 'gw1', db: db, api: null);
  });

  tearDown(() async {
    await db.close();
  });

  test('model switches are explicitly scoped to one session', () {
    expect(
      SessionSyncRepository.modelConfigValue('grok-4.5', provider: 'xai'),
      'grok-4.5 --provider xai --session',
    );
    expect(
      SessionSyncRepository.modelConfigValue('local-model'),
      'local-model --session',
    );
  });

  test('create session is stored locally when offline', () async {
    final session = await repo.createSession(title: 'Offline chat');
    expect(session.title, 'Offline chat');
    expect(session.id, startsWith('local_'));

    final list = await repo.loadSessionsLocal();
    expect(list.length, 1);
    expect(list.first.id, session.id);
  });

  test('send message offline queues and keeps local transcript', () async {
    final session = await repo.createSession(title: 'Chat');
    final result = await repo.sendMessage(
      sessionId: session.id,
      input: 'hello offline',
    );
    expect(result.queued, isTrue);
    expect(result.messages.any((m) => m.content == 'hello offline'), isTrue);

    final msgs = await repo.loadMessagesLocal(session.id);
    expect(msgs.length, 1);
    expect(msgs.first.role, 'user');
  });

  test('sessions are scoped by gateway id', () async {
    final other = SessionSyncRepository(gatewayId: 'gw2', db: db, api: null);
    await repo.createSession(title: 'A');
    await other.createSession(title: 'B');

    expect((await repo.loadSessionsLocal()).length, 1);
    expect((await other.loadSessionsLocal()).length, 1);
    expect((await repo.loadSessionsLocal()).first.title, 'A');
    expect((await other.loadSessionsLocal()).first.title, 'B');
  });

  // ── Startup redundant-fetch coalescing (single-flight) ─────────────────
  //
  // Reproduces the cold-launch shape from the bug report: several callers
  // (sessionsProvider.build(), GatewayRealtime connect, GatewayShell boot)
  // each kick their own `syncSessions()` within milliseconds of each other.
  // Only one `GET /api/sessions` should reach the network.
  group('syncSessions single-flight coalescing', () {
    late _CountingAdapter adapter;
    late SessionSyncRepository apiRepo;

    setUp(() {
      adapter = _CountingAdapter(
        '/api/sessions',
        '{"data": [{"id": "s1", "title": "Hello"}]}',
      );
      final dio = Dio(BaseOptions(baseUrl: 'https://gw.test'))
        ..httpClientAdapter = adapter;
      final api = HermesApi(baseUrl: 'https://gw.test', apiKey: 'k', dio: dio);
      apiRepo = SessionSyncRepository(gatewayId: 'gw-flight', db: db, api: api);
    });

    test('concurrent startup triggers collapse into one HTTP call', () async {
      final results = await Future.wait([
        apiRepo.syncSessions(),
        apiRepo.syncSessions(),
        apiRepo.syncSessions(),
      ]);

      expect(adapter.calls, 1);
      for (final list in results) {
        expect(list.map((s) => s.id), ['s1']);
      }
    });

    test('a back-to-back call right after completion reuses the cached '
        'result (TTL) instead of hitting the network again', () async {
      await apiRepo.syncSessions();
      expect(adapter.calls, 1);

      // Arrives moments later — well inside the single-flight TTL.
      final again = await apiRepo.syncSessions();
      expect(adapter.calls, 1);
      expect(again.map((s) => s.id), ['s1']);
    });

    test(
      'bypassTtl (explicit user pull-to-refresh) still hits the network',
      () async {
        await apiRepo.syncSessions();
        expect(adapter.calls, 1);

        await apiRepo.syncSessions(bypassTtl: true);
        expect(adapter.calls, 2);
      },
    );
  });
}

/// Minimal Dio [HttpClientAdapter] that counts requests to [path] and
/// returns a fixed JSON [body] for every call — enough to prove single-flight
/// coalescing without a real gateway.
class _CountingAdapter implements HttpClientAdapter {
  _CountingAdapter(this.path, this.body);

  final String path;
  final String body;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.contains(path) || options.uri.path.contains(path)) {
      calls++;
    }
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
