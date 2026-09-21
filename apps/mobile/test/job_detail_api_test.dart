import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/core/models/hermes_models.dart';
import 'package:hermes_mobile/core/network/dashboard_client.dart';

class _JobAdapter implements HttpClientAdapter {
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    if (options.path.endsWith('/runs')) {
      return _json({
        'runs': [
          {
            'id': 'cron_job-1_20260816_090000',
            'source': 'cron',
            'title': 'Daily result',
            'model': 'gpt-5.6-terra',
            'started_at': 1786899600,
            'last_active': 1786899660,
            'message_count': 3,
          },
        ],
      });
    }
    return _json({
      'id': 'job-1',
      'name': 'Daily job',
      'prompt': 'Do the work',
      'last_error': 'Useful failure detail',
      'schedule': {'kind': 'cron', 'expr': '0 9 * * *'},
    });
  }

  ResponseBody _json(Object body) => ResponseBody.fromString(
    jsonEncode(body),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

void main() {
  late _JobAdapter adapter;
  late DashboardClient client;

  setUp(() {
    adapter = _JobAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://gateway.test'))
      ..httpClientAdapter = adapter;
    client = DashboardClient(
      profile: const ConnectionProfile(
        id: 'gw',
        baseUrl: 'https://gateway.test',
      ),
      dio: dio,
    );
  });

  test('fetches full cron job detail by encoded id', () async {
    final job = await client.getCronJob('job/1');
    expect(job.name, 'Daily job');
    expect(job.lastError, 'Useful failure detail');
    expect(job.schedule, '0 9 * * *');
    expect(adapter.lastRequest?.path, '/api/cron/jobs/job%2F1');
  });

  test('fetches bounded run history as ordinary Hermes sessions', () async {
    final runs = await client.listCronJobRuns('job-1', limit: 20);
    expect(runs, hasLength(1));
    expect(runs.single.id, 'cron_job-1_20260816_090000');
    expect(runs.single.source, 'cron');
    expect(runs.single.model, 'gpt-5.6-terra');
    expect(adapter.lastRequest?.queryParameters['limit'], 20);
  });
}
