import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// Sessions cached per gateway. Server is source of truth after pull;
/// local rows exist so the UI works offline and deploys keep history.
class CachedSessions extends Table {
  TextColumn get gatewayId => text()();
  TextColumn get id => text()();
  TextColumn get source => text().nullable()();
  TextColumn get userId => text().nullable()();
  TextColumn get model => text().nullable()();
  TextColumn get title => text().nullable()();
  TextColumn get startedAt => text().nullable()();
  TextColumn get endedAt => text().nullable()();
  TextColumn get endReason => text().nullable()();
  IntColumn get messageCount => integer().nullable()();
  IntColumn get toolCallCount => integer().nullable()();
  TextColumn get lastActive => text().nullable()();
  TextColumn get preview => text().nullable()();
  TextColumn get parentSessionId => text().nullable()();

  /// pending | synced | deleted_pending
  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {gatewayId, id};
}

class CachedMessages extends Table {
  TextColumn get gatewayId => text()();
  TextColumn get sessionId => text()();
  TextColumn get id => text()();
  TextColumn get role => text()();
  TextColumn get content => text().nullable()();
  TextColumn get toolCallId => text().nullable()();
  TextColumn get toolName => text().nullable()();
  TextColumn get timestamp => text().nullable()();
  IntColumn get tokenCount => integer().nullable()();
  TextColumn get finishReason => text().nullable()();
  TextColumn get reasoning => text().nullable()();

  /// Opaque JSON for tool_calls when present.
  TextColumn get toolCallsJson => text().nullable()();
  IntColumn get sortIndex => integer().withDefault(const Constant(0))();

  /// pending | synced
  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();

  @override
  Set<Column> get primaryKey => {gatewayId, sessionId, id};
}

/// Outbound ops to flush when the gateway is reachable.
class PendingOps extends Table {
  TextColumn get id => text()();
  TextColumn get gatewayId => text()();

  /// create_session | delete_session | patch_session | chat
  TextColumn get opType => text()();
  TextColumn get sessionId => text().nullable()();
  TextColumn get payloadJson => text()();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cron jobs cached per gateway (local-first; survive offline / connection blips).
///
/// Rows with [syncStatus] `deleted_pending` stay until a successful server pull
/// confirms the job is gone — never drop on network error alone.
class CachedJobs extends Table {
  TextColumn get gatewayId => text()();
  TextColumn get id => text()();
  TextColumn get name => text().nullable()();
  TextColumn get schedule => text().nullable()();
  TextColumn get prompt => text().nullable()();
  TextColumn get deliver => text().nullable()();
  BoolColumn get enabled => boolean().nullable()();
  TextColumn get state => text().nullable()();
  TextColumn get lastRunAt => text().nullable()();
  TextColumn get lastStatus => text().nullable()();
  TextColumn get nextRunAt => text().nullable()();

  /// synced | deleted_pending
  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {gatewayId, id};
}

/// Installed skills cached per gateway (survive offline / failed pulls).
class CachedSkills extends Table {
  TextColumn get gatewayId => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get category => text().nullable()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  TextColumn get provenance => text().nullable()();
  IntColumn get usage => integer().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {gatewayId, name};
}

@DriftDatabase(
  tables: [
    CachedSessions,
    CachedMessages,
    PendingOps,
    CachedJobs,
    CachedSkills,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(cachedJobs);
      }
      if (from < 3) {
        await m.createTable(cachedSkills);
      }
    },
  );

  // ── Sessions ───────────────────────────────────────────────────────

  Future<List<CachedSession>> sessionsForGateway(String gatewayId) {
    return (select(cachedSessions)
          ..where(
            (r) =>
                r.gatewayId.equals(gatewayId) &
                r.syncStatus.isNotValue('deleted_pending'),
          )
          ..orderBy([
            (r) => OrderingTerm(
              expression: r.lastActive,
              mode: OrderingMode.desc,
              nulls: NullsOrder.last,
            ),
            (r) => OrderingTerm.desc(r.updatedAt),
          ]))
        .get();
  }

  Future<void> upsertSession(CachedSessionsCompanion row) {
    return into(cachedSessions).insertOnConflictUpdate(row);
  }

  Future<void> replaceSessions(
    String gatewayId,
    List<CachedSessionsCompanion> rows,
  ) {
    return transaction(() async {
      // Keep local-only pending creates not yet on server.
      final pending =
          await (select(cachedSessions)..where(
                (r) =>
                    r.gatewayId.equals(gatewayId) &
                    r.syncStatus.equals('pending'),
              ))
              .get();
      await (delete(cachedSessions)..where(
            (r) =>
                r.gatewayId.equals(gatewayId) &
                r.syncStatus.isNotValue('pending'),
          ))
          .go();
      await batch((b) => b.insertAllOnConflictUpdate(cachedSessions, rows));
      // Re-apply pending if not overwritten by server id collision.
      for (final p in pending) {
        final exists = rows.any((r) => r.id.value == p.id);
        if (!exists) {
          await into(cachedSessions).insertOnConflictUpdate(
            CachedSessionsCompanion.insert(
              gatewayId: p.gatewayId,
              id: p.id,
              source: Value(p.source),
              userId: Value(p.userId),
              model: Value(p.model),
              title: Value(p.title),
              startedAt: Value(p.startedAt),
              endedAt: Value(p.endedAt),
              endReason: Value(p.endReason),
              messageCount: Value(p.messageCount),
              toolCallCount: Value(p.toolCallCount),
              lastActive: Value(p.lastActive),
              preview: Value(p.preview),
              parentSessionId: Value(p.parentSessionId),
              syncStatus: const Value('pending'),
              updatedAt: p.updatedAt,
            ),
          );
        }
      }
    });
  }

  Future<void> markSessionDeleted(String gatewayId, String sessionId) {
    return (update(
          cachedSessions,
        )..where((r) => r.gatewayId.equals(gatewayId) & r.id.equals(sessionId)))
        .write(
          CachedSessionsCompanion(
            syncStatus: const Value('deleted_pending'),
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
  }

  Future<void> removeSession(String gatewayId, String sessionId) {
    return transaction(() async {
      await (delete(cachedSessions)..where(
            (r) => r.gatewayId.equals(gatewayId) & r.id.equals(sessionId),
          ))
          .go();
      await (delete(cachedMessages)..where(
            (r) =>
                r.gatewayId.equals(gatewayId) & r.sessionId.equals(sessionId),
          ))
          .go();
    });
  }

  // ── Messages ───────────────────────────────────────────────────────

  Future<List<CachedMessage>> messagesForSession(
    String gatewayId,
    String sessionId,
  ) {
    return (select(cachedMessages)
          ..where(
            (r) =>
                r.gatewayId.equals(gatewayId) & r.sessionId.equals(sessionId),
          )
          ..orderBy([
            (r) => OrderingTerm.asc(r.sortIndex),
            (r) => OrderingTerm.asc(r.timestamp),
          ]))
        .get();
  }

  Future<void> replaceMessages(
    String gatewayId,
    String sessionId,
    List<CachedMessagesCompanion> rows,
  ) {
    return transaction(() async {
      final pending =
          await (select(cachedMessages)..where(
                (r) =>
                    r.gatewayId.equals(gatewayId) &
                    r.sessionId.equals(sessionId) &
                    r.syncStatus.equals('pending'),
              ))
              .get();
      await (delete(cachedMessages)..where(
            (r) =>
                r.gatewayId.equals(gatewayId) &
                r.sessionId.equals(sessionId) &
                r.syncStatus.isNotValue('pending'),
          ))
          .go();
      await batch((b) => b.insertAllOnConflictUpdate(cachedMessages, rows));
      for (final p in pending) {
        final exists = rows.any((r) => r.id.value == p.id);
        if (!exists) {
          await into(cachedMessages).insertOnConflictUpdate(
            CachedMessagesCompanion.insert(
              gatewayId: p.gatewayId,
              sessionId: p.sessionId,
              id: p.id,
              role: p.role,
              content: Value(p.content),
              toolCallId: Value(p.toolCallId),
              toolName: Value(p.toolName),
              timestamp: Value(p.timestamp),
              tokenCount: Value(p.tokenCount),
              finishReason: Value(p.finishReason),
              reasoning: Value(p.reasoning),
              toolCallsJson: Value(p.toolCallsJson),
              sortIndex: Value(p.sortIndex),
              syncStatus: const Value('pending'),
            ),
          );
        }
      }
    });
  }

  Future<void> upsertMessage(CachedMessagesCompanion row) {
    return into(cachedMessages).insertOnConflictUpdate(row);
  }

  // ── Outbox ─────────────────────────────────────────────────────────

  Future<List<PendingOp>> pendingOpsForGateway(String gatewayId) {
    return (select(pendingOps)
          ..where((r) => r.gatewayId.equals(gatewayId))
          ..orderBy([(r) => OrderingTerm.asc(r.createdAt)]))
        .get();
  }

  Future<void> enqueueOp(PendingOpsCompanion row) {
    return into(pendingOps).insertOnConflictUpdate(row);
  }

  Future<void> removeOp(String id) {
    return (delete(pendingOps)..where((r) => r.id.equals(id))).go();
  }

  Future<void> bumpOpFailure(String id, String error) {
    return transaction(() async {
      final row = await (select(
        pendingOps,
      )..where((r) => r.id.equals(id))).getSingleOrNull();
      if (row == null) return;
      await (update(pendingOps)..where((r) => r.id.equals(id))).write(
        PendingOpsCompanion(
          attemptCount: Value(row.attemptCount + 1),
          lastError: Value(error),
          nextAttemptAt: Value(
            DateTime.now().toUtc().add(
              Duration(seconds: (row.attemptCount + 1).clamp(1, 8) * 5),
            ),
          ),
        ),
      );
    });
  }

  // ── Jobs (cron) ────────────────────────────────────────────────────

  Future<List<CachedJob>> jobsForGateway(
    String gatewayId, {
    bool includeDeletedPending = false,
  }) {
    return (select(cachedJobs)
          ..where((r) {
            final gw = r.gatewayId.equals(gatewayId);
            if (includeDeletedPending) return gw;
            return gw & r.syncStatus.isNotValue('deleted_pending');
          })
          ..orderBy([
            (r) => OrderingTerm(
              expression: r.nextRunAt,
              mode: OrderingMode.asc,
              nulls: NullsOrder.last,
            ),
            (r) => OrderingTerm.desc(r.updatedAt),
          ]))
        .get();
  }

  Future<void> upsertJob(CachedJobsCompanion row) {
    return into(cachedJobs).insertOnConflictUpdate(row);
  }

  /// Apply a successful server list without wiping local tombstones on blips.
  ///
  /// - Upserts every remote job as `synced` (unless local is `deleted_pending`)
  /// - Removes local `synced` rows missing from [remote] (server confirmed gone)
  /// - Removes `deleted_pending` only when remote no longer includes them
  Future<void> mergeJobsFromServer(
    String gatewayId,
    List<CachedJobsCompanion> remote,
  ) {
    return transaction(() async {
      final local = await (select(
        cachedJobs,
      )..where((r) => r.gatewayId.equals(gatewayId))).get();
      final remoteIds = {for (final r in remote) r.id.value};

      for (final row in remote) {
        final existing = local.where((l) => l.id == row.id.value).firstOrNull;
        if (existing?.syncStatus == 'deleted_pending') {
          // Tombstone wins until server no longer lists the id.
          continue;
        }
        await into(cachedJobs).insertOnConflictUpdate(row);
      }

      for (final l in local) {
        if (remoteIds.contains(l.id)) continue;
        if (l.syncStatus == 'deleted_pending') {
          // Server confirmed deletion.
          await (delete(cachedJobs)..where(
                (r) => r.gatewayId.equals(gatewayId) & r.id.equals(l.id),
              ))
              .go();
          continue;
        }
        // Was synced, not on server anymore → gone for real.
        if (l.syncStatus == 'synced') {
          await (delete(cachedJobs)..where(
                (r) => r.gatewayId.equals(gatewayId) & r.id.equals(l.id),
              ))
              .go();
        }
      }
    });
  }

  Future<void> markJobDeleted(String gatewayId, String jobId) {
    return (update(
      cachedJobs,
    )..where((r) => r.gatewayId.equals(gatewayId) & r.id.equals(jobId))).write(
      CachedJobsCompanion(
        syncStatus: const Value('deleted_pending'),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> removeJob(String gatewayId, String jobId) {
    return (delete(
      cachedJobs,
    )..where((r) => r.gatewayId.equals(gatewayId) & r.id.equals(jobId))).go();
  }

  // ── Skills ─────────────────────────────────────────────────────────

  Future<List<CachedSkill>> skillsForGateway(String gatewayId) {
    return (select(cachedSkills)
          ..where((r) => r.gatewayId.equals(gatewayId))
          ..orderBy([
            (r) => OrderingTerm.asc(r.category),
            (r) => OrderingTerm.asc(r.name),
          ]))
        .get();
  }

  /// Replace the full skill catalog for [gatewayId] after a successful pull.
  Future<void> replaceSkills(
    String gatewayId,
    List<CachedSkillsCompanion> rows,
  ) {
    return transaction(() async {
      await (delete(
        cachedSkills,
      )..where((r) => r.gatewayId.equals(gatewayId))).go();
      if (rows.isNotEmpty) {
        await batch((b) => b.insertAllOnConflictUpdate(cachedSkills, rows));
      }
    });
  }

  Future<void> clearGatewayData(String gatewayId) {
    return transaction(() async {
      await (delete(
        cachedSessions,
      )..where((r) => r.gatewayId.equals(gatewayId))).go();
      await (delete(
        cachedMessages,
      )..where((r) => r.gatewayId.equals(gatewayId))).go();
      await (delete(
        cachedJobs,
      )..where((r) => r.gatewayId.equals(gatewayId))).go();
      await (delete(
        cachedSkills,
      )..where((r) => r.gatewayId.equals(gatewayId))).go();
      await (delete(
        pendingOps,
      )..where((r) => r.gatewayId.equals(gatewayId))).go();
    });
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'hermes_sessions.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
