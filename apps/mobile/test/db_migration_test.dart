import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/core/db/app_database.dart';

/// Upgrade coverage for [AppDatabase.migration].
///
/// Every other database test in this suite opens `NativeDatabase.memory()` on
/// an empty file, which only ever runs `onCreate` → `createAll()`. That path
/// is the one shipped installs never take, and it is why a broken `onUpgrade`
/// shipped: `Migrator.createTable` builds its DDL from the table class's
/// *current* columns (drift keeps no historical snapshot), so the `from < 4`
/// step creates `deleted_messages` **including** `fingerprint`, and a second
/// unconditional `addColumn(fingerprint)` then threw
/// `duplicate column name: fingerprint` on the first cache read for every
/// device upgrading from v3 or earlier — i.e. every shipped install.
///
/// The historical schemas below are hand-written `CREATE TABLE` snapshots
/// rather than `drift_dev schema dump` output: dumping requires a schema
/// history that was never recorded, and there is no way to reconstruct v1–v4
/// from the current sources (that reconstruction *is* the bug). If a future
/// schema change adds a proper `drift_schemas/` history, this can be replaced
/// with `SchemaVerifier.runMigrations`.
void main() {
  // ── Historical DDL ───────────────────────────────────────────────────
  //
  // Copied from `sqlite_master` at the version each one represents. They are
  // snapshots: do NOT regenerate them from the live table classes.

  const createCachedSessions =
      'CREATE TABLE "cached_sessions" ('
      '"gateway_id" TEXT NOT NULL, "id" TEXT NOT NULL, "source" TEXT NULL, '
      '"user_id" TEXT NULL, "model" TEXT NULL, "title" TEXT NULL, '
      '"started_at" TEXT NULL, "ended_at" TEXT NULL, "end_reason" TEXT NULL, '
      '"message_count" INTEGER NULL, "tool_call_count" INTEGER NULL, '
      '"last_active" TEXT NULL, "preview" TEXT NULL, '
      '"parent_session_id" TEXT NULL, '
      '"sync_status" TEXT NOT NULL DEFAULT \'synced\', '
      '"updated_at" INTEGER NOT NULL, '
      'PRIMARY KEY ("gateway_id", "id"))';

  // v1–v3: no `display_kind` column yet (added by the `from < 4` step).
  const createCachedMessagesV1 =
      'CREATE TABLE "cached_messages" ('
      '"gateway_id" TEXT NOT NULL, "session_id" TEXT NOT NULL, '
      '"id" TEXT NOT NULL, "role" TEXT NOT NULL, "content" TEXT NULL, '
      '"tool_call_id" TEXT NULL, "tool_name" TEXT NULL, '
      '"timestamp" TEXT NULL, "token_count" INTEGER NULL, '
      '"finish_reason" TEXT NULL, "reasoning" TEXT NULL, '
      '"tool_calls_json" TEXT NULL, '
      '"sort_index" INTEGER NOT NULL DEFAULT 0, '
      '"sync_status" TEXT NOT NULL DEFAULT \'synced\', '
      'PRIMARY KEY ("gateway_id", "session_id", "id"))';

  const createCachedMessagesV4 =
      'CREATE TABLE "cached_messages" ('
      '"gateway_id" TEXT NOT NULL, "session_id" TEXT NOT NULL, '
      '"id" TEXT NOT NULL, "role" TEXT NOT NULL, "content" TEXT NULL, '
      '"tool_call_id" TEXT NULL, "tool_name" TEXT NULL, '
      '"timestamp" TEXT NULL, "token_count" INTEGER NULL, '
      '"finish_reason" TEXT NULL, "reasoning" TEXT NULL, '
      '"tool_calls_json" TEXT NULL, '
      '"sort_index" INTEGER NOT NULL DEFAULT 0, '
      '"sync_status" TEXT NOT NULL DEFAULT \'synced\', '
      '"display_kind" TEXT NULL, '
      'PRIMARY KEY ("gateway_id", "session_id", "id"))';

  const createPendingOps =
      'CREATE TABLE "pending_ops" ('
      '"id" TEXT NOT NULL, "gateway_id" TEXT NOT NULL, '
      '"op_type" TEXT NOT NULL, "session_id" TEXT NULL, '
      '"payload_json" TEXT NOT NULL, '
      '"attempt_count" INTEGER NOT NULL DEFAULT 0, '
      '"last_error" TEXT NOT NULL DEFAULT \'\', '
      '"created_at" INTEGER NOT NULL, "next_attempt_at" INTEGER NULL, '
      'PRIMARY KEY ("id"))';

  const createCachedJobs =
      'CREATE TABLE "cached_jobs" ('
      '"gateway_id" TEXT NOT NULL, "id" TEXT NOT NULL, "name" TEXT NULL, '
      '"schedule" TEXT NULL, "prompt" TEXT NULL, "deliver" TEXT NULL, '
      '"enabled" INTEGER NULL CHECK ("enabled" IN (0, 1)), '
      '"state" TEXT NULL, "last_run_at" TEXT NULL, "last_status" TEXT NULL, '
      '"next_run_at" TEXT NULL, '
      '"sync_status" TEXT NOT NULL DEFAULT \'synced\', '
      '"updated_at" INTEGER NOT NULL, '
      'PRIMARY KEY ("gateway_id", "id"))';

  const createCachedSkills =
      'CREATE TABLE "cached_skills" ('
      '"gateway_id" TEXT NOT NULL, "name" TEXT NOT NULL, '
      '"description" TEXT NULL, "category" TEXT NULL, '
      '"enabled" INTEGER NOT NULL DEFAULT 1 CHECK ("enabled" IN (0, 1)), '
      '"provenance" TEXT NULL, "usage" INTEGER NULL, '
      '"updated_at" INTEGER NOT NULL, '
      'PRIMARY KEY ("gateway_id", "name"))';

  // v4 only: the tombstone table before `fingerprint` existed.
  const createDeletedMessagesV4 =
      'CREATE TABLE "deleted_messages" ('
      '"gateway_id" TEXT NOT NULL, "session_id" TEXT NOT NULL, '
      '"message_id" TEXT NOT NULL, "deleted_at" INTEGER NOT NULL, '
      'PRIMARY KEY ("gateway_id", "session_id", "message_id"))';

  List<String> schemaAt(int version) => <String>[
    createCachedSessions,
    version >= 4 ? createCachedMessagesV4 : createCachedMessagesV1,
    createPendingOps,
    if (version >= 2) createCachedJobs,
    if (version >= 3) createCachedSkills,
    if (version >= 4) createDeletedMessagesV4,
  ];

  /// Opens [AppDatabase] on an in-memory database that already holds the
  /// schema and `user_version` of [version], plus one cached message and (from
  /// v4) one tombstone written by that build. Nothing here runs the migration
  /// yet — drift does that lazily, on the first statement.
  AppDatabase openAtVersion(int version) {
    return AppDatabase.forTesting(
      // The callback's parameter is package:sqlite3's `Database`; left
      // untyped so the test needs no direct dependency on that package.
      NativeDatabase.memory(
        setup: (rawDb) {
          for (final statement in schemaAt(version)) {
            rawDb.execute(statement);
          }
          rawDb.execute(
            'INSERT INTO cached_messages '
            '(gateway_id, session_id, id, role, content, sort_index, '
            'sync_status) '
            "VALUES ('gw1', 's1', 'm1', 'user', 'legacy row', 0, 'synced')",
          );
          if (version >= 4) {
            // A tombstone written by the v4 build: no fingerprint column
            // existed, so this row is exactly the "pre-v5, null fingerprint"
            // case the v5 column has to keep readable.
            rawDb.execute(
              'INSERT INTO deleted_messages '
              '(gateway_id, session_id, message_id, deleted_at) '
              "VALUES ('gw1', 's1', 'old', 1700000000)",
            );
          }
          rawDb.execute('PRAGMA user_version = $version');
        },
      ),
    );
  }

  for (final from in [1, 2, 3, 4]) {
    group('upgrade from schema v$from', () {
      late AppDatabase db;

      setUp(() => db = openAtVersion(from));
      tearDown(() async => db.close());

      test('the migration completes on the first cache read', () async {
        // The original `if (from < 5)` guard threw
        // `duplicate column name: fingerprint` right here for from <= 3.
        final messages = await db.messagesForSession('gw1', 's1');
        expect(messages, hasLength(1));
        expect(messages.single.id, 'm1');
        expect(messages.single.content, 'legacy row');
        // Column added by the `from < 4` step; null for a pre-v4 row.
        expect(messages.single.displayKind, isNull);

        final version = await db
            .customSelect('PRAGMA user_version')
            .getSingle();
        expect(version.data.values.single, 5);
      });

      test(
        'deleted_messages ends up with exactly one fingerprint column',
        () async {
          final columns = await db
              .customSelect("PRAGMA table_info('deleted_messages')")
              .get();
          final names = columns.map((r) => r.data['name']).toList();
          expect(
            names.where((n) => n == 'fingerprint'),
            hasLength(1),
            reason: 'names: $names',
          );
        },
      );

      test('a tombstone with a fingerprint round-trips', () async {
        await db.tombstoneMessage(
          'gw1',
          's1',
          'm1',
          fingerprint: 'user:d41d8cd98f00b204',
        );
        final rows = await db.tombstonesForSession('gw1', 's1');
        final tombstone = rows.firstWhere((r) => r.messageId == 'm1');
        expect(tombstone.fingerprint, 'user:d41d8cd98f00b204');
        // The tombstone also dropped the cached row it hides.
        expect(await db.messagesForSession('gw1', 's1'), isEmpty);
      });

      test('a pre-v5 tombstone still reads with a null fingerprint', () async {
        if (from < 4) {
          // No tombstone table existed before v4, so write the equivalent
          // row — the read path is what is under test either way.
          await db.customStatement(
            'INSERT INTO deleted_messages '
            '(gateway_id, session_id, message_id, deleted_at) '
            "VALUES ('gw1', 's1', 'old', 1700000000)",
          );
        }
        final rows = await db.tombstonesForSession('gw1', 's1');
        final legacy = rows.firstWhere((r) => r.messageId == 'old');
        expect(legacy.fingerprint, isNull);
        expect(await db.tombstonedMessageIds('gw1', 's1'), contains('old'));
      });

      test('the tables added by later versions are usable', () async {
        expect(await db.jobsForGateway('gw1'), isEmpty);
        expect(await db.skillsForGateway('gw1'), isEmpty);
        expect(await db.sessionsForGateway('gw1'), isEmpty);
        expect(await db.pendingOpsForGateway('gw1'), isEmpty);
      });
    });
  }

  test('an already-current database is left alone', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    // Forces onCreate.
    await db.messagesForSession('gw1', 's1');
    await db.tombstoneMessage('gw1', 's1', 'm1', fingerprint: 'fp');
    expect(
      (await db.tombstonesForSession('gw1', 's1')).single.fingerprint,
      'fp',
    );
    await db.close();
  });
}
