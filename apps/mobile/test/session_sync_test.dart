import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/core/db/app_database.dart';
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
}
