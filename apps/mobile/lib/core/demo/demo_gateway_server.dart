/// The in-process fake Hermes gateway that powers demo mode.
///
/// Apple rejected the real App Store submission (Guideline 2.1(a)) because
/// reviewers cannot sign in without running their own Hermes gateway. This
/// server is the fix: it binds `127.0.0.1:<ephemeral>` and impersonates a
/// real gateway closely enough that the app's *real* networking code — Dio
/// HTTP with cookie auth, real `dart:io` WebSocket JSON-RPC — never has to
/// know it isn't talking to one. Nothing in `dashboard_client.dart`,
/// `gateway_ws_client.dart`, `gateway_realtime.dart`, or
/// `session_sync_repository.dart` is touched or branched for demo mode.
///
/// Every response shape here was derived from those files' parsers, not
/// guessed — see the wave-1 implementation report for the full contract.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:hermes_mobile/core/demo/demo_agent_script.dart';
import 'package:hermes_mobile/core/demo/demo_fixtures.dart';

/// Username / password the demo gateway's `/auth/password-login` accepts.
///
/// Single source of truth for the demo credentials — `demo_mode.dart`
/// re-exports these two constants instead of redeclaring them, so the UI's
/// hint text and this server's [DemoGatewayServer._handlePasswordLogin]
/// check can never drift apart. Username matching is case-insensitive,
/// password matching is exact. Any other credentials fail with a genuine
/// 401 so the real login-error UI path is exercised.
const demoUsername = 'demo';
const demoPassword = 'demo';

/// A fake Hermes gateway with real HTTP + WebSocket transport but scripted,
/// in-memory state. One instance = one demo "workspace" for the lifetime of
/// the process; state resets on every [start] after a [stop] (matching a
/// real app relaunch, since the phone's OS never keeps the old process).
class DemoGatewayServer {
  /// [demoSpeedFactor] scales every scripted agent-turn delay (see
  /// [DemoAgentScript.plan]) — the running app never passes this, so it
  /// always gets the real ~8-15s pacing a reviewer is meant to see. Tests
  /// that boot a real server (`demo_gateway_server_test.dart`) pass a small
  /// factor instead: full-turn tests want the suite to stay fast, and the
  /// interrupt test wants a real-but-short time window to land the
  /// interrupt inside rather than waiting out a full ~10s turn.
  DemoGatewayServer({double demoSpeedFactor = 1.0})
    : _speedFactor = demoSpeedFactor;

  final double _speedFactor;

  static const _uuid = Uuid();

  HttpServer? _http;
  Uri? _baseUri;
  final List<WebSocket> _sockets = [];

  /// Single-flight guard for [start] — concurrent callers (e.g. the
  /// connect-screen probe racing app-boot rehydration) join the same
  /// in-flight bind instead of each passing the `_http == null` check and
  /// binding a second server, leaking the first one's port.
  Future<Uri>? _startInflight;

  DateTime _bootedAt = DateTime.now();
  List<DemoSession> _sessions = const [];
  List<DemoModelEntry> _models = const [];
  List<DemoJob> _jobs = const [];
  List<DemoSkillFixture> _skills = const [];
  List<DemoCommandFixture> _commands = const [];
  String _currentModel = DemoFixtures.defaultModel;
  String _currentProvider = DemoFixtures.defaultProvider;
  int _sessionSeq = 0;

  /// One cancel token per session with an agent turn in flight, so
  /// `session.interrupt` can stop `prompt.submit`'s streaming loop.
  final Map<String, _CancelToken> _inflight = {};

  bool get isRunning => _http != null;
  Uri? get baseUri => _baseUri;

  /// Starts the server, seeding a fresh workspace. Idempotent: calling this
  /// again while already running just returns the existing URL — wave 2
  /// calls this both at app boot and from the connect screen, and it must be
  /// safe to call repeatedly.
  Future<Uri> start() async {
    final existing = _baseUri;
    if (existing != null && _http != null) return existing;

    final inflight = _startInflight;
    if (inflight != null) return inflight;

    final attempt = _startLocked();
    _startInflight = attempt;
    try {
      return await attempt;
    } finally {
      if (identical(_startInflight, attempt)) {
        _startInflight = null;
      }
    }
  }

  Future<Uri> _startLocked() async {
    _bootedAt = DateTime.now();
    _sessions = DemoFixtures.buildSessions(_bootedAt);
    _models = DemoFixtures.buildModels();
    _jobs = DemoFixtures.buildJobs(_bootedAt);
    _skills = DemoFixtures.buildSkills();
    _commands = DemoFixtures.buildCommands();
    _currentModel = DemoFixtures.defaultModel;
    _currentProvider = DemoFixtures.defaultProvider;
    _sessionSeq = 0;
    _inflight.clear();

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _http = server;
    final uri = Uri(scheme: 'http', host: '127.0.0.1', port: server.port);
    _baseUri = uri;

    server.listen(
      (request) => unawaited(_handleRequest(request)),
      onError: (Object e) => debugPrint('DemoGatewayServer: listen error: $e'),
      cancelOnError: false,
    );
    debugPrint('DemoGatewayServer: listening on $uri');
    return uri;
  }

  /// Stops the server and closes every open socket.
  Future<void> stop() async {
    for (final socket in List<WebSocket>.of(_sockets)) {
      try {
        await socket.close();
      } catch (_) {
        // Best-effort — the client may already be gone.
      }
    }
    _sockets.clear();
    _inflight.clear();

    final server = _http;
    _http = null;
    _baseUri = null;
    if (server != null) {
      try {
        await server.close(force: true);
      } catch (e) {
        debugPrint('DemoGatewayServer: close failed: $e');
      }
    }
  }

  // ── Top-level request dispatch ───────────────────────────────────────

  /// Every request lands here first. A malformed request or a bug in one
  /// handler must never kill the server for the rest of the demo session —
  /// this is the single catch-all that guarantees that.
  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (WebSocketTransformer.isUpgradeRequest(request) &&
          request.uri.path == '/api/ws') {
        final socket = await WebSocketTransformer.upgrade(request);
        _sockets.add(socket);
        _handleSocket(socket);
        return;
      }
      await _routeHttp(request);
    } catch (e, st) {
      debugPrint('DemoGatewayServer: request failed: $e\n$st');
      try {
        request.response.statusCode = 500;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'detail': 'internal demo gateway error'}),
        );
        await request.response.close();
      } catch (_) {
        // Response may already be partially written/closed — nothing more
        // we can do, but we must not let this throw out of the listener.
      }
    }
  }

  Future<void> _routeHttp(HttpRequest request) async {
    final method = request.method;
    final segments = request.uri.pathSegments;
    final path = '/${segments.join('/')}';

    // ── Public — bootstrap + health, no cookie/ticket required ──────────
    if (method == 'GET' && path == '/api/status') {
      return _respond(
        request,
        200,
        DemoFixtures.statusJson(bootedAt: _bootedAt),
      );
    }
    if (method == 'GET' && path == '/api/auth/providers') {
      return _respond(request, 200, {
        'providers': [
          {
            'name': 'demo',
            'display_name': 'Demo Login',
            'supports_password': true,
          },
        ],
      });
    }
    if (method == 'POST' && path == '/auth/password-login') {
      return _handlePasswordLogin(request);
    }
    if (method == 'GET' && path == '/health') {
      return _respond(request, 200, DemoFixtures.healthJson());
    }
    if (method == 'GET' && path == '/health/detailed') {
      return _respond(
        request,
        200,
        DemoFixtures.healthDetailedJson(bootedAt: _bootedAt),
      );
    }
    if (method == 'GET' && path == '/v1/capabilities') {
      return _respond(
        request,
        200,
        DemoFixtures.capabilitiesJson(_currentModel),
      );
    }
    if (method == 'GET' && path == '/v1/models') {
      return _respond(request, 200, {
        'data': DemoFixtures.v1ModelsJson(_models),
      });
    }

    // ── Everything else under /api is gated ──────────────────────────
    //
    // The real gateway restarts with fresh state on every app launch while
    // the phone's cookie jar persists across launches, so validation here is
    // deliberately permissive: any request that carries a cookie at all (or
    // a legacy bearer token) is accepted. Rejecting stale-but-present
    // cookies would strand a reviewer who force-quit and reopened the app.
    if (!_isAuthed(request)) {
      return _respond(request, 401, {'detail': 'Unauthorized'});
    }

    if (method == 'POST' && path == '/api/auth/ws-ticket') {
      return _respond(request, 200, {'ticket': _uuid.v4(), 'ttl_seconds': 30});
    }
    if (method == 'GET' && path == '/api/sessions') {
      return _handleListSessions(request);
    }
    if (method == 'POST' && path == '/api/sessions') {
      return _handleCreateSessionRest(request);
    }
    if (segments.length == 3 &&
        segments[0] == 'api' &&
        segments[1] == 'sessions') {
      final id = Uri.decodeComponent(segments[2]);
      if (method == 'GET') return _handleGetSession(request, id);
      if (method == 'PATCH') return _handlePatchSession(request, id);
      if (method == 'DELETE') return _handleDeleteSession(request, id);
    }
    if (segments.length == 4 &&
        segments[0] == 'api' &&
        segments[1] == 'sessions' &&
        segments[3] == 'messages' &&
        method == 'GET') {
      return _handleMessages(request, Uri.decodeComponent(segments[2]));
    }
    if (segments.length == 4 &&
        segments[0] == 'api' &&
        segments[1] == 'sessions' &&
        segments[3] == 'chat' &&
        method == 'POST') {
      return _handleChat(request, Uri.decodeComponent(segments[2]));
    }
    if (method == 'GET' && path == '/api/model/options') {
      return _handleModelOptions(request);
    }
    if (method == 'GET' && path == '/api/skills') {
      return _respond(request, 200, [for (final s in _skills) s.toJson()]);
    }
    if (method == 'GET' && path == '/api/commands') {
      return _respond(request, 200, {
        'commands': DemoFixtures.commandsJson(_commands),
        'total': _commands.length,
      });
    }
    if (method == 'GET' && (path == '/api/cron/jobs' || path == '/api/jobs')) {
      return _respond(request, 200, [for (final j in _jobs) j.toJson()]);
    }
    if (method == 'POST' &&
        segments.length == 5 &&
        segments[0] == 'api' &&
        segments[1] == 'cron' &&
        segments[2] == 'jobs') {
      return _handleJobAction(request, segments[3], segments[4]);
    }
    if (method == 'POST' &&
        segments.length == 4 &&
        segments[0] == 'api' &&
        segments[1] == 'jobs') {
      final action = segments[3] == 'run' ? 'trigger' : segments[3];
      return _handleJobAction(request, segments[2], action);
    }

    return _respond(request, 404, {'detail': 'not found: $method $path'});
  }

  // ── Response / body helpers ──────────────────────────────────────────

  Future<void> _respond(
    HttpRequest request,
    int status,
    Object? body, {
    List<Cookie>? cookies,
  }) async {
    final res = request.response;
    res.statusCode = status;
    res.headers.contentType = ContentType.json;
    if (cookies != null) {
      res.cookies.addAll(cookies);
    }
    res.write(jsonEncode(body));
    await res.close();
  }

  Future<Map<String, dynamic>> _readJsonBody(HttpRequest request) async {
    try {
      final raw = await utf8.decoder.bind(request).join();
      if (raw.trim().isEmpty) return const {};
      final decoded = jsonDecode(raw);
      if (decoded is Map) return decoded.cast<String, dynamic>();
      return const {};
    } catch (e) {
      debugPrint('DemoGatewayServer: malformed JSON body: $e');
      return const {};
    }
  }

  bool _isAuthed(HttpRequest request) {
    if (request.cookies.isNotEmpty) return true;
    final auth = request.headers.value(HttpHeaders.authorizationHeader);
    return auth != null && auth.trim().isNotEmpty;
  }

  // ── Auth handlers ─────────────────────────────────────────────────────

  Future<void> _handlePasswordLogin(HttpRequest request) async {
    final body = await _readJsonBody(request);
    final username = '${body['username'] ?? ''}'.trim().toLowerCase();
    final password = '${body['password'] ?? ''}';
    if (username != demoUsername || password != demoPassword) {
      return _respond(request, 401, {'detail': 'Invalid credentials'});
    }
    final cookies = [
      Cookie('hermes_session_at', _uuid.v4())
        ..path = '/'
        ..httpOnly = true,
      Cookie('hermes_session_rt', _uuid.v4())
        ..path = '/'
        ..httpOnly = true,
    ];
    return _respond(request, 200, {'ok': true, 'next': '/'}, cookies: cookies);
  }

  // ── Session helpers ───────────────────────────────────────────────────

  DemoSession? _findSession(String id) {
    for (final s in _sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  List<DemoSession> _visibleSessions(String archivedParam) {
    switch (archivedParam) {
      case 'only':
        return _sessions.where((s) => s.archived).toList();
      case 'include':
      case 'all':
        return List<DemoSession>.of(_sessions);
      default:
        return _sessions.where((s) => !s.archived).toList();
    }
  }

  DemoSession _createSession({
    String? id,
    String? title,
    String? model,
    String? provider,
  }) {
    _sessionSeq += 1;
    final now = DateTime.now().toUtc().toIso8601String();
    final session = DemoSession(
      id: (id != null && id.isNotEmpty)
          ? id
          : 'demo-live-$_sessionSeq-${DateTime.now().microsecondsSinceEpoch}',
      title: (title != null && title.trim().isNotEmpty)
          ? title.trim()
          : 'New session',
      startedAt: now,
      lastActive: now,
      model: (model != null && model.isNotEmpty) ? model : _currentModel,
      provider: (provider != null && provider.isNotEmpty)
          ? provider
          : _currentProvider,
    );
    _sessions.insert(0, session);
    return session;
  }

  // ── Session REST handlers ────────────────────────────────────────────

  Future<void> _handleListSessions(HttpRequest request) async {
    final q = request.uri.queryParameters;
    final archived = (q['archived'] ?? 'exclude').toLowerCase();
    final list = _visibleSessions(archived)
      ..sort((a, b) => b.lastActive.compareTo(a.lastActive));
    final limit = int.tryParse(q['limit'] ?? '') ?? list.length;
    final bounded = limit > 0 && limit < list.length
        ? list.take(limit).toList()
        : list;
    final json = [for (final s in bounded) s.summaryJson()];
    // DashboardClient reads `sessions` (or `data`); HermesApi reads `data`.
    return _respond(request, 200, {'sessions': json, 'data': json});
  }

  Future<void> _handleCreateSessionRest(HttpRequest request) async {
    final body = await _readJsonBody(request);
    final session = _createSession(
      id: body['id']?.toString(),
      title: body['title']?.toString(),
      model: body['model']?.toString(),
    );
    return _respond(request, 200, {'session': session.summaryJson()});
  }

  Future<void> _handleGetSession(HttpRequest request, String id) async {
    final session = _findSession(id);
    if (session == null) {
      return _respond(request, 404, {'detail': 'session not found'});
    }
    return _respond(request, 200, {'session': session.summaryJson()});
  }

  Future<void> _handlePatchSession(HttpRequest request, String id) async {
    final session = _findSession(id);
    if (session == null) {
      return _respond(request, 404, {'detail': 'session not found'});
    }
    final body = await _readJsonBody(request);
    if (body.containsKey('title')) {
      final title = '${body['title'] ?? ''}'.trim();
      if (title.isNotEmpty) session.title = title;
    }
    if (body.containsKey('archived')) {
      session.archived = body['archived'] == true;
    }
    if (body.containsKey('end_reason')) {
      session.endReason = body['end_reason']?.toString();
    }
    session.lastActive = DateTime.now().toUtc().toIso8601String();
    return _respond(request, 200, {'session': session.summaryJson()});
  }

  Future<void> _handleDeleteSession(HttpRequest request, String id) async {
    _sessions.removeWhere((s) => s.id == id);
    _inflight.remove(id);
    return _respond(request, 200, {'ok': true});
  }

  Future<void> _handleMessages(HttpRequest request, String id) async {
    final session = _findSession(id);
    if (session == null) {
      return _respond(request, 404, {'detail': 'session not found'});
    }
    final json = [for (final m in session.messages) m.toJson(session.id)];
    return _respond(request, 200, {'messages': json, 'data': json});
  }

  /// Synchronous one-turn chat fallback (`HermesApi.chat`). The mobile app's
  /// primary chat path is the WebSocket (`prompt.submit`); this exists only
  /// so the legacy REST fallback endpoint isn't a dead 404.
  Future<void> _handleChat(HttpRequest request, String id) async {
    final session = _findSession(id) ?? _createSession(id: id);
    final body = await _readJsonBody(request);
    final input = '${body['input'] ?? body['text'] ?? ''}';

    session.messages.add(
      DemoMessage(
        id: _uuid.v4(),
        role: 'user',
        content: input,
        timestamp: DateTime.now().toUtc().toIso8601String(),
      ),
    );
    final plan = DemoAgentScript.plan(input);
    final now = DateTime.now().toUtc().toIso8601String();
    session.messages.add(
      DemoMessage(
        id: _uuid.v4(),
        role: 'assistant',
        content: plan.finalText,
        timestamp: now,
        finishReason: 'stop',
      ),
    );
    session.lastActive = now;
    return _respond(request, 200, {
      'session_id': session.id,
      'reply': plan.finalText,
      'message': {'role': 'assistant', 'content': plan.finalText},
    });
  }

  Future<void> _handleModelOptions(HttpRequest request) async {
    return _respond(request, 200, {
      'model': _currentModel,
      'provider': _currentProvider,
      'providers': DemoFixtures.modelProvidersJson(_models),
    });
  }

  Future<void> _handleJobAction(
    HttpRequest request,
    String id,
    String action,
  ) async {
    DemoJob? job;
    for (final j in _jobs) {
      if (j.id == id) {
        job = j;
        break;
      }
    }
    if (job == null) {
      return _respond(request, 404, {'detail': 'job not found'});
    }
    switch (action) {
      case 'pause':
        job.enabled = false;
        break;
      case 'resume':
        job.enabled = true;
        break;
      case 'trigger':
        job.lastRunAt = DateTime.now().toUtc().toIso8601String();
        job.lastStatus = 'success';
        break;
      default:
        return _respond(request, 404, {'detail': 'unknown action: $action'});
    }
    return _respond(request, 200, {'ok': true, 'job': job.toJson()});
  }

  // ── WebSocket: /api/ws ────────────────────────────────────────────────

  void _handleSocket(WebSocket socket) {
    _sendFrame(socket, {
      'jsonrpc': '2.0',
      'method': 'event',
      'params': {'type': 'gateway.ready', 'session_id': null, 'payload': {}},
    });

    socket.listen(
      (dynamic raw) => _onSocketMessage(socket, raw),
      onDone: () => _sockets.remove(socket),
      onError: (Object e) {
        debugPrint('DemoGatewayServer: socket error: $e');
        _sockets.remove(socket);
      },
      cancelOnError: false,
    );
  }

  void _onSocketMessage(WebSocket socket, dynamic raw) {
    final text = raw is String ? raw : utf8.decode(raw as List<int>);
    // Newline-delimited JSON — same framing GatewayWsClient writes/reads.
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      Map<String, dynamic> frame;
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is! Map) continue;
        frame = decoded.cast<String, dynamic>();
      } catch (e) {
        debugPrint('DemoGatewayServer: malformed WS frame: $e');
        continue;
      }
      unawaited(_handleRpc(socket, frame));
    }
  }

  Future<void> _handleRpc(WebSocket socket, Map<String, dynamic> frame) async {
    final id = frame['id'];
    final method = '${frame['method'] ?? ''}';
    final rawParams = frame['params'];
    final params = rawParams is Map
        ? rawParams.cast<String, dynamic>()
        : <String, dynamic>{};

    try {
      final result = await _dispatchRpc(socket, method, params);
      if (id != null) {
        _sendFrame(socket, {'jsonrpc': '2.0', 'id': id, 'result': result});
      }
    } catch (e) {
      debugPrint('DemoGatewayServer: RPC $method failed: $e');
      if (id != null) {
        final code = e is DemoRpcException ? e.code : -32000;
        _sendFrame(socket, {
          'jsonrpc': '2.0',
          'id': id,
          'error': {'code': code, 'message': '$e'},
        });
      }
    }
  }

  Future<Map<String, dynamic>> _dispatchRpc(
    WebSocket socket,
    String method,
    Map<String, dynamic> params,
  ) async {
    switch (method) {
      case 'session.list':
        final list = _visibleSessions('exclude')
          ..sort((a, b) => b.lastActive.compareTo(a.lastActive));
        return {
          'sessions': [for (final s in list) s.summaryJson()],
        };
      case 'session.create':
        return _rpcSessionCreate(params);
      case 'session.resume':
        return _rpcSessionResume(params);
      case 'session.close':
        return _rpcSessionClose(params);
      case 'session.title':
        return _rpcSessionTitle(params);
      case 'session.interrupt':
        return _rpcSessionInterrupt(params);
      case 'session.usage':
        return _rpcSessionUsage(params);
      case 'session.context_breakdown':
        return _rpcSessionContextBreakdown(params);
      case 'prompt.submit':
        return _rpcPromptSubmit(params);
      case 'config.set':
        return _rpcConfigSet(params);
      case 'commands.catalog':
        return DemoFixtures.commandsCatalogJson(_commands);
      case 'skills.manage':
        return _rpcSkillsManage(params);
      case 'skills.reload':
        return {
          'output': 'Reloaded ${_skills.length} skills.',
          'result': {'total': _skills.length},
        };
      case 'image.attach_bytes':
        return {'attached': true};
      default:
        throw DemoRpcException('Method not found: $method', code: -32601);
    }
  }

  Map<String, dynamic> _rpcSessionCreate(Map<String, dynamic> params) {
    final session = _createSession(
      title: params['title']?.toString(),
      model: params['model']?.toString(),
      provider: params['provider']?.toString(),
    );
    final effort = params['reasoning_effort']?.toString();
    if (effort != null && effort.isNotEmpty) session.reasoningEffort = effort;
    if (params['fast'] == true) session.fastMode = true;
    return {
      'session_id': session.id,
      'stored_session_id': session.id,
      'info': session.runtimeInfoJson(),
    };
  }

  Map<String, dynamic> _rpcSessionResume(Map<String, dynamic> params) {
    final id = '${params['session_id'] ?? ''}';
    final session = _findSession(id) ?? _createSession(id: id);
    return {'session_id': session.id, 'info': session.runtimeInfoJson()};
  }

  Map<String, dynamic> _rpcSessionClose(Map<String, dynamic> params) {
    final session = _findSession('${params['session_id'] ?? ''}');
    if (session != null) {
      session.endedAt = DateTime.now().toUtc().toIso8601String();
      session.endReason = 'closed';
    }
    return {'ok': true};
  }

  Map<String, dynamic> _rpcSessionTitle(Map<String, dynamic> params) {
    final session = _findSession('${params['session_id'] ?? ''}');
    final title = '${params['title'] ?? ''}'.trim();
    if (session != null && title.isNotEmpty) {
      session.title = title;
      session.lastActive = DateTime.now().toUtc().toIso8601String();
    }
    return {'ok': true};
  }

  Map<String, dynamic> _rpcSessionInterrupt(Map<String, dynamic> params) {
    final id = '${params['session_id'] ?? ''}';
    _inflight[id]?.cancelled = true;
    return {'ok': true};
  }

  Map<String, dynamic> _rpcSessionUsage(Map<String, dynamic> params) {
    final session = _findSession('${params['session_id'] ?? ''}');
    final turns = session?.messages.length ?? 0;
    final input = 900 + turns * 180;
    final output = 400 + turns * 140;
    const contextMax = 200000;
    final contextUsed = (input + output).clamp(0, contextMax);
    return {
      'input': input,
      'output': output,
      'reasoning': (output * 0.2).round(),
      'total': input + output,
      'calls': turns,
      'context_used': contextUsed,
      'context_max': contextMax,
      'context_percent': contextUsed / contextMax * 100,
      'model': session?.model ?? _currentModel,
    };
  }

  Map<String, dynamic> _rpcSessionContextBreakdown(
    Map<String, dynamic> params,
  ) {
    final session = _findSession('${params['session_id'] ?? ''}');
    final turns = session?.messages.length ?? 0;
    const systemPrompt = 4200;
    const toolDefinitions = 3100;
    final skillsTokens = 900 + (_skills.where((s) => s.enabled).length * 60);
    final conversation = 800 + turns * 220;
    final total = systemPrompt + toolDefinitions + skillsTokens + conversation;
    const contextMax = 200000;
    return {
      'categories': [
        {
          'id': 'system_prompt',
          'label': 'System prompt',
          'tokens': systemPrompt,
        },
        {
          'id': 'tool_definitions',
          'label': 'Tool definitions',
          'tokens': toolDefinitions,
        },
        {'id': 'skills', 'label': 'Skills', 'tokens': skillsTokens},
        {'id': 'conversation', 'label': 'Conversation', 'tokens': conversation},
      ],
      'context_max': contextMax,
      'context_used': total,
      'context_percent': total / contextMax * 100,
      'estimated_total': total,
      'model': session?.model ?? _currentModel,
    };
  }

  Map<String, dynamic> _rpcConfigSet(Map<String, dynamic> params) {
    final sessionId = '${params['session_id'] ?? ''}';
    final key = '${params['key'] ?? ''}';
    final value = '${params['value'] ?? ''}';
    final session = sessionId.isEmpty ? null : _findSession(sessionId);
    switch (key) {
      case 'model':
        _applyModelValue(session, value);
        break;
      case 'reasoning':
        if (session != null) {
          session.reasoningEffort = value.isEmpty ? null : value;
        }
        break;
      case 'fast':
        if (session != null) session.fastMode = value == 'fast';
        break;
      default:
        debugPrint('DemoGatewayServer: config.set ignored key=$key');
    }
    if (session != null) {
      session.lastActive = DateTime.now().toUtc().toIso8601String();
    }
    return {'ok': true};
  }

  /// Parses `SessionSyncRepository.modelConfigValue`'s
  /// `"<model> --provider <provider> --session"` shape.
  void _applyModelValue(DemoSession? session, String rawValue) {
    String? provider;
    final providerMatch = RegExp(r'--provider\s+(\S+)').firstMatch(rawValue);
    if (providerMatch != null) provider = providerMatch.group(1);
    final model = rawValue
        .replaceAll(RegExp(r'--provider\s+\S+'), '')
        .replaceAll('--session', '')
        .replaceAll('--global', '')
        .trim();
    if (model.isEmpty) return;
    if (session != null) {
      session.model = model;
      if (provider != null) session.provider = provider;
    } else {
      _currentModel = model;
      if (provider != null) _currentProvider = provider;
    }
  }

  Map<String, dynamic> _rpcSkillsManage(Map<String, dynamic> params) {
    final action = '${params['action'] ?? 'list'}';
    final name = '${params['name'] ?? ''}';
    switch (action) {
      case 'enable':
      case 'disable':
      case 'toggle':
        for (final s in _skills) {
          if (s.name == name) {
            s.enabled = action == 'enable'
                ? true
                : action == 'disable'
                ? false
                : !s.enabled;
          }
        }
        break;
    }
    return {
      'skills': [for (final s in _skills) s.toJson()],
    };
  }

  /// `prompt.submit` — the WebSocket streaming chat turn. Acks immediately
  /// (Desktop parity: the RPC result just confirms the turn started) and
  /// drives [DemoAgentScript] in the background, broadcasting every scripted
  /// event to all connected sockets as it goes.
  Map<String, dynamic> _rpcPromptSubmit(Map<String, dynamic> params) {
    final sessionId = '${params['session_id'] ?? ''}';
    final text = '${params['text'] ?? ''}';
    final session = _findSession(sessionId) ?? _createSession(id: sessionId);

    session.messages.add(
      DemoMessage(
        id: _uuid.v4(),
        role: 'user',
        content: text,
        timestamp: DateTime.now().toUtc().toIso8601String(),
      ),
    );
    session.lastActive = DateTime.now().toUtc().toIso8601String();

    final token = _CancelToken();
    _inflight[session.id] = token;
    final plan = DemoAgentScript.plan(text, speedFactor: _speedFactor);

    unawaited(
      DemoAgentScript.run(
        planned: plan,
        onEvent: (event) {
          _broadcastEvent(session.id, event);
          // A real gateway persists the tool call into the transcript, not
          // just a transient "running tool…" status line — the app already
          // knows how to render a persisted `role: tool` message (see
          // `session_chat_screen.dart`'s tool-name label), it just never
          // gets one from the demo gateway without this. Persisting here
          // (rather than only in the completion callback below) means it's
          // already in `session.messages` — and so picked up by the next
          // `tool.start`/`tool.complete`-triggered resync
          // (`gateway_realtime.dart`'s `_scheduleEventRefresh`) — well
          // before the assistant's final answer lands.
          if (event.type == 'tool.complete') {
            _persistToolMessage(session, event);
          }
        },
        isCancelled: () => token.cancelled,
      ).then((produced) {
        final now = DateTime.now().toUtc().toIso8601String();
        session.messages.add(
          DemoMessage(
            id: _uuid.v4(),
            role: 'assistant',
            content: produced,
            timestamp: now,
            finishReason: token.cancelled ? 'interrupted' : 'stop',
          ),
        );
        session.lastActive = now;
        if (identical(_inflight[session.id], token)) {
          _inflight.remove(session.id);
        }
      }),
    );

    return {'status': 'streaming', 'session_id': session.id};
  }

  /// Appends a `role: tool` message to [session] for a `tool.complete`
  /// [event] — see the doc comment on the `onEvent` callback above for why.
  /// Placed between the user message already appended and the eventual
  /// assistant reply, matching the order a real transcript would have.
  void _persistToolMessage(DemoSession session, DemoAgentEvent event) {
    final name = '${event.payload['name'] ?? 'tool'}';
    final rawOutput = event.payload['output'];
    final output = rawOutput is Map
        ? rawOutput.cast<String, dynamic>()
        : <String, dynamic>{};
    session.messages.add(
      DemoMessage(
        id: _uuid.v4(),
        role: 'tool',
        content: DemoAgentScript.describeToolOutput(name, output),
        timestamp: DateTime.now().toUtc().toIso8601String(),
        toolName: name,
        toolCallId: _uuid.v4(),
      ),
    );
  }

  void _broadcastEvent(String sessionId, DemoAgentEvent event) {
    final frame = {
      'jsonrpc': '2.0',
      'method': 'event',
      'params': {
        'type': event.type,
        'session_id': sessionId,
        'payload': event.payload,
      },
    };
    for (final socket in List<WebSocket>.of(_sockets)) {
      _sendFrame(socket, frame);
    }
  }

  void _sendFrame(WebSocket socket, Map<String, dynamic> frame) {
    if (socket.closeCode != null) return;
    try {
      socket.add(jsonEncode(frame));
    } catch (e) {
      debugPrint('DemoGatewayServer: send failed: $e');
    }
  }
}

/// Cancellation flag for one in-flight `prompt.submit` turn.
class _CancelToken {
  bool cancelled = false;
}

/// A JSON-RPC error with an explicit code (defaults to a generic server
/// error; unknown methods use `-32601` per the JSON-RPC spec).
class DemoRpcException implements Exception {
  DemoRpcException(this.message, {this.code = -32000});

  final String message;
  final int code;

  @override
  String toString() => message;
}
