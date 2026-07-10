import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;

import 'package:hermes_mobile/core/models/hermes_models.dart';

/// Thin client for the Hermes API server (gateway-hosted).
///
/// Only the mobile-connector surface: health, models, sessions, chat, jobs.
/// Full agent setup stays on the host.
class HermesApi {
  HermesApi({required this.baseUrl, required this.apiKey, Dio? dio})
    : dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: _normalizeBase(baseUrl),
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 120),
              headers: {
                'Accept': 'application/json',
                'Authorization': 'Bearer $apiKey',
              },
            ),
          );

  final String baseUrl;
  final String apiKey;
  final Dio dio;

  static String _normalizeBase(String raw) {
    var value = raw.trim();
    if (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  // ── Health / capabilities ──────────────────────────────────────────

  Future<Map<String, dynamic>> health() async {
    final res = await dio.get<Map<String, dynamic>>('/health');
    return res.data ?? const {'status': 'ok'};
  }

  Future<Map<String, dynamic>> healthDetailed() async {
    final res = await dio.get<Map<String, dynamic>>('/health/detailed');
    return res.data ?? const {};
  }

  Future<HermesCapabilities> capabilities() async {
    final res = await dio.get<Map<String, dynamic>>('/v1/capabilities');
    return HermesCapabilities.fromJson(res.data ?? const {});
  }

  // ── Models ─────────────────────────────────────────────────────────

  Future<List<HermesModelInfo>> listModels() async {
    final res = await dio.get<Map<String, dynamic>>('/v1/models');
    final data = res.data?['data'];
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((m) => HermesModelInfo.fromJson(m.cast<String, dynamic>()))
        .where((m) => m.id.isNotEmpty)
        .toList();
  }

  // ── Sessions ───────────────────────────────────────────────────────

  Future<List<HermesSession>> listSessions({
    int limit = 50,
    int offset = 0,
    String? source,
    bool includeChildren = false,
  }) async {
    final res = await dio.get<Map<String, dynamic>>(
      '/api/sessions',
      queryParameters: {
        'limit': limit,
        'offset': offset,
        'source': ?source,
        'include_children': includeChildren,
      },
    );
    final data = res.data?['data'];
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((m) => HermesSession.fromJson(m.cast<String, dynamic>()))
        .where((s) => s.id.isNotEmpty)
        .toList();
  }

  Future<HermesSession> createSession({
    String? title,
    String? model,
    String? id,
  }) async {
    final res = await dio.post<Map<String, dynamic>>(
      '/api/sessions',
      data: {'id': ?id, 'title': ?title, 'model': ?model},
    );
    final session = res.data?['session'];
    if (session is Map) {
      return HermesSession.fromJson(session.cast<String, dynamic>());
    }
    throw DioException(
      requestOptions: res.requestOptions,
      message: 'createSession: missing session payload',
    );
  }

  Future<HermesSession> getSession(String sessionId) async {
    final res = await dio.get<Map<String, dynamic>>('/api/sessions/$sessionId');
    final session = res.data?['session'];
    if (session is Map) {
      return HermesSession.fromJson(session.cast<String, dynamic>());
    }
    throw DioException(
      requestOptions: res.requestOptions,
      message: 'getSession: missing session payload',
    );
  }

  Future<HermesSession> patchSession(
    String sessionId, {
    String? title,
    String? endReason,
  }) async {
    final res = await dio.patch<Map<String, dynamic>>(
      '/api/sessions/$sessionId',
      data: {'title': ?title, 'end_reason': ?endReason},
    );
    final session = res.data?['session'];
    if (session is Map) {
      return HermesSession.fromJson(session.cast<String, dynamic>());
    }
    throw DioException(
      requestOptions: res.requestOptions,
      message: 'patchSession: missing session payload',
    );
  }

  Future<void> deleteSession(String sessionId) async {
    await dio.delete<Map<String, dynamic>>('/api/sessions/$sessionId');
  }

  Future<List<HermesMessage>> listMessages(String sessionId) async {
    final res = await dio.get<Map<String, dynamic>>(
      '/api/sessions/$sessionId/messages',
    );
    final data = res.data?['data'];
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((m) => HermesMessage.fromJson(m.cast<String, dynamic>()))
        .toList();
  }

  /// Synchronous one-turn chat (fallback when SSE is unavailable).
  Future<Map<String, dynamic>> chat(
    String sessionId, {
    required String input,
    String? model,
  }) async {
    final res = await dio.post<Map<String, dynamic>>(
      '/api/sessions/$sessionId/chat',
      data: {
        'input': input,
        if (model != null && model.isNotEmpty) 'model': model,
      },
    );
    return res.data ?? const {};
  }

  /// SSE stream for a single agent turn.
  ///
  /// Yields decoded JSON event maps. Event type is under `event` or `type`
  /// depending on server version; callers should accept both.
  Stream<Map<String, dynamic>> chatStream(
    String sessionId, {
    required String input,
    String? model,
  }) async* {
    final uri = Uri.parse(
      '${_normalizeBase(baseUrl)}/api/sessions/$sessionId/chat/stream',
    );
    final client = http.Client();
    try {
      final request = http.Request('POST', uri)
        ..headers.addAll({
          'Authorization': 'Bearer $apiKey',
          'Accept': 'text/event-stream',
          'Content-Type': 'application/json',
        })
        ..body = jsonEncode({
          'input': input,
          if (model != null && model.isNotEmpty) 'model': model,
        });

      final response = await client.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await response.stream.bytesToString();
        throw DioException(
          requestOptions: RequestOptions(path: uri.path),
          response: Response(
            requestOptions: RequestOptions(path: uri.path),
            statusCode: response.statusCode,
            data: body,
          ),
          message: 'chatStream failed (${response.statusCode})',
        );
      }

      var buffer = '';
      await for (final chunk in response.stream.transform(utf8.decoder)) {
        buffer += chunk;
        while (true) {
          final sep = buffer.indexOf('\n\n');
          if (sep < 0) break;
          final block = buffer.substring(0, sep);
          buffer = buffer.substring(sep + 2);
          final event = _parseSseBlock(block);
          if (event != null) yield event;
        }
      }
      if (buffer.trim().isNotEmpty) {
        final event = _parseSseBlock(buffer);
        if (event != null) yield event;
      }
    } finally {
      client.close();
    }
  }

  Map<String, dynamic>? _parseSseBlock(String block) {
    String? eventName;
    final dataLines = <String>[];
    for (final line in block.split('\n')) {
      if (line.startsWith('event:')) {
        eventName = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trim());
      }
    }
    if (dataLines.isEmpty) return null;
    final dataStr = dataLines.join('\n');
    if (dataStr == '[DONE]') {
      return {'event': 'done', 'type': 'done'};
    }
    try {
      final parsed = jsonDecode(dataStr);
      if (parsed is Map<String, dynamic>) {
        return {
          ...parsed,
          'event': ?eventName,
          if (eventName != null && !parsed.containsKey('type'))
            'type': eventName,
        };
      }
      return {'event': eventName ?? 'message', 'data': parsed};
    } catch (_) {
      return {'event': eventName ?? 'message', 'data': dataStr};
    }
  }

  // ── Jobs (cron) ────────────────────────────────────────────────────

  Future<List<HermesJob>> listJobs({bool includeDisabled = true}) async {
    // Prefer dashboard-compatible path; some hosts only expose this under cron.
    for (final path in ['/api/cron/jobs', '/api/jobs']) {
      try {
        final res = await dio.get<dynamic>(
          path,
          queryParameters: {
            if (includeDisabled) 'include_disabled': 'true',
            'profile': 'all',
          },
        );
        final body = res.data;
        List? raw;
        if (body is List) {
          raw = body;
        } else if (body is Map) {
          final jobs = body['jobs'];
          final data = body['data'];
          raw = jobs is List ? jobs : (data is List ? data : null);
        }
        if (raw == null) continue;
        final jobs = raw
            .whereType<Map>()
            .map((m) => HermesJob.fromJson(m.cast<String, dynamic>()))
            .where((j) => j.id.isNotEmpty)
            .toList();
        return jobs;
      } catch (_) {
        continue;
      }
    }
    return const [];
  }

  Future<void> pauseJob(String jobId) async {
    await dio.post<Map<String, dynamic>>('/api/jobs/$jobId/pause');
  }

  Future<void> resumeJob(String jobId) async {
    await dio.post<Map<String, dynamic>>('/api/jobs/$jobId/resume');
  }

  Future<void> runJobNow(String jobId) async {
    await dio.post<Map<String, dynamic>>('/api/jobs/$jobId/run');
  }
}
