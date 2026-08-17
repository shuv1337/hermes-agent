import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/core/db/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('rich job detail survives an offline cache read', () async {
    final detail = {
      'id': 'job-1',
      'name': 'Daily sync',
      'last_error': 'actionable server error',
      'future_field': {'version': 2},
    };
    await db.upsertJob(
      CachedJobsCompanion.insert(
        gatewayId: 'gw',
        id: 'job-1',
        name: const Value('Daily sync'),
        detailsJson: Value(jsonEncode(detail)),
        updatedAt: DateTime.utc(2026, 8, 16),
      ),
    );

    final row = (await db.jobsForGateway('gw')).single;
    expect(
      jsonDecode(row.detailsJson!)['last_error'],
      'actionable server error',
    );
    expect(jsonDecode(row.detailsJson!)['future_field'], {'version': 2});
  });

  test('failed refresh can retain prior bounded run history', () async {
    await db.replaceJobRuns('gw', 'job-1', [
      CachedJobRunsCompanion.insert(
        gatewayId: 'gw',
        jobId: 'job-1',
        sessionId: 'cron_job-1_first',
        sessionJson: jsonEncode({'id': 'cron_job-1_first', 'source': 'cron'}),
        lastActive: const Value('2026-08-16T09:00:00Z'),
        updatedAt: DateTime.utc(2026, 8, 16),
      ),
    ]);

    expect(
      (await db.jobRunsForJob('gw', 'job-1')).single.sessionId,
      'cron_job-1_first',
    );

    await db.replaceJobRuns('gw', 'job-1', [
      CachedJobRunsCompanion.insert(
        gatewayId: 'gw',
        jobId: 'job-1',
        sessionId: 'cron_job-1_second',
        sessionJson: jsonEncode({'id': 'cron_job-1_second', 'source': 'cron'}),
        lastActive: const Value('2026-08-17T09:00:00Z'),
        updatedAt: DateTime.utc(2026, 8, 17),
      ),
    ]);

    final rows = await db.jobRunsForJob('gw', 'job-1');
    expect(rows.map((row) => row.sessionId), ['cron_job-1_second']);
  });
}
