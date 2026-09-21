import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/core/models/hermes_models.dart';
import 'package:hermes_mobile/core/network/dashboard_client.dart';

class _ProfileAdapter implements HttpClientAdapter {
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromString(
      jsonEncode({'ok': true}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('bot profile deletion uses the encoded server REST endpoint', () async {
    final adapter = _ProfileAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://gateway.test'))
      ..httpClientAdapter = adapter;
    final client = DashboardClient(
      profile: const ConnectionProfile(
        id: 'gw',
        baseUrl: 'https://gateway.test',
      ),
      dio: dio,
    );

    await client.deleteProfile('health/coach');

    expect(adapter.lastRequest?.method, 'DELETE');
    expect(adapter.lastRequest?.path, '/api/profiles/health%2Fcoach');
  });

  test('the default profile cannot be deleted', () async {
    final client = DashboardClient(
      profile: const ConnectionProfile(
        id: 'gw',
        baseUrl: 'https://gateway.test',
      ),
      dio: Dio(BaseOptions(baseUrl: 'https://gateway.test')),
    );

    await expectLater(client.deleteProfile('default'), throwsStateError);
  });
}
