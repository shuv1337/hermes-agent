/// Shared DTOs for the Hermes API server surface used by the mobile connector.
library;

/// One saved Hermes gateway the phone can talk to.
///
/// Desktop remote flow (not API_SERVER_KEY):
/// - authMode `session` → username/password login → cookies + ws-ticket
/// - authMode `open`    → loopback/insecure gateway, no password gate
///
/// [apiKey] is only for rare legacy token mode; password gateways leave it empty.
class ConnectionProfile {
  const ConnectionProfile({
    required this.id,
    required this.baseUrl,
    this.apiKey = '',
    this.authMode = 'session',
    this.username,
    this.provider,
    this.label,
    this.displayName,
    this.createdAt,
    this.lastUsedAt,
  });

  /// Stable client-side id (uuid). Not the host session id.
  final String id;

  /// User-facing name ("Home", "Spark", "VPS"). Falls back to host/url.
  final String? label;

  final String baseUrl;

  /// Legacy static token only. Empty for password/session auth.
  final String apiKey;

  /// `session` (password/OAuth cookies), `open` (no gate), `token` (legacy).
  final String authMode;

  /// Signed-in username (password providers). Not the password.
  final String? username;

  /// Auth provider name used at login (e.g. `basic`).
  final String? provider;

  /// Optional host-advertised model / nickname from capabilities probe.
  final String? displayName;

  final String? createdAt;
  final String? lastUsedAt;

  bool get usesSessionCookies =>
      authMode == 'session' || authMode == 'oauth' || authMode == 'password';

  bool get hasLegacyToken => apiKey.trim().isNotEmpty;

  String get displayLabel {
    final l = label?.trim();
    if (l != null && l.isNotEmpty) return l;
    final u = username?.trim();
    if (u != null && u.isNotEmpty) {
      try {
        return '$u@${Uri.parse(baseUrl).host}';
      } catch (_) {
        return u;
      }
    }
    final d = displayName?.trim();
    if (d != null && d.isNotEmpty) return d;
    try {
      return Uri.parse(baseUrl).host;
    } catch (_) {
      return baseUrl;
    }
  }

  ConnectionProfile copyWith({
    String? id,
    String? label,
    String? baseUrl,
    String? apiKey,
    String? authMode,
    String? username,
    String? provider,
    String? displayName,
    String? createdAt,
    String? lastUsedAt,
  }) {
    return ConnectionProfile(
      id: id ?? this.id,
      label: label ?? this.label,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      authMode: authMode ?? this.authMode,
      username: username ?? this.username,
      provider: provider ?? this.provider,
      displayName: displayName ?? this.displayName,
      createdAt: createdAt ?? this.createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'authMode': authMode,
    if (username != null) 'username': username,
    if (provider != null) 'provider': provider,
    if (label != null) 'label': label,
    if (displayName != null) 'displayName': displayName,
    if (createdAt != null) 'createdAt': createdAt,
    if (lastUsedAt != null) 'lastUsedAt': lastUsedAt,
  };

  factory ConnectionProfile.fromJson(Map<String, dynamic> json) {
    final id = '${json['id'] ?? ''}'.trim();
    final key = '${json['apiKey'] ?? ''}';
    // Infer auth mode for older saved profiles.
    var mode = '${json['authMode'] ?? ''}'.trim();
    if (mode.isEmpty) {
      mode = key.isNotEmpty ? 'token' : 'session';
    }
    return ConnectionProfile(
      id: id.isEmpty ? 'legacy' : id,
      label: _asString(json['label']),
      baseUrl: '${json['baseUrl'] ?? ''}'.trim(),
      apiKey: key,
      authMode: mode,
      username: _asString(json['username']),
      provider: _asString(json['provider']),
      displayName: _asString(json['displayName']),
      createdAt: json['createdAt']?.toString(),
      lastUsedAt: json['lastUsedAt']?.toString(),
    );
  }
}

/// Multi-gateway book on device.
///
/// - [gateways] — all saved connections (v1: length 0 or 1)
/// - [defaultGatewayId] — boots the app / "home" gateway
/// - [activeGatewayId] — currently selected for Sessions/Jobs/Chat
///
/// Active and default can diverge later (browse another host without changing
/// default). v1 keeps them equal.
class GatewayBook {
  const GatewayBook({
    this.gateways = const [],
    this.defaultGatewayId,
    this.activeGatewayId,
  });

  static const empty = GatewayBook();

  final List<ConnectionProfile> gateways;
  final String? defaultGatewayId;
  final String? activeGatewayId;

  bool get isEmpty => gateways.isEmpty;
  bool get isNotEmpty => gateways.isNotEmpty;

  ConnectionProfile? get active => _byId(activeGatewayId);
  ConnectionProfile? get defaultGateway => _byId(defaultGatewayId);

  /// Boot target: active if set, else default, else sole gateway.
  ConnectionProfile? get resolved {
    return active ??
        defaultGateway ??
        (gateways.length == 1 ? gateways.first : null);
  }

  ConnectionProfile? _byId(String? id) {
    if (id == null) return null;
    for (final g in gateways) {
      if (g.id == id) return g;
    }
    return null;
  }

  GatewayBook copyWith({
    List<ConnectionProfile>? gateways,
    String? defaultGatewayId,
    String? activeGatewayId,
    bool clearDefault = false,
    bool clearActive = false,
  }) {
    return GatewayBook(
      gateways: gateways ?? this.gateways,
      defaultGatewayId: clearDefault
          ? null
          : (defaultGatewayId ?? this.defaultGatewayId),
      activeGatewayId: clearActive
          ? null
          : (activeGatewayId ?? this.activeGatewayId),
    );
  }

  Map<String, dynamic> toJson() => {
    'version': 2,
    'gateways': gateways.map((g) => g.toJson()).toList(),
    'defaultGatewayId': defaultGatewayId,
    'activeGatewayId': activeGatewayId,
  };

  factory GatewayBook.fromJson(Map<String, dynamic> json) {
    final rawList = json['gateways'];
    final list = <ConnectionProfile>[];
    if (rawList is List) {
      for (final item in rawList) {
        if (item is Map) {
          final p = ConnectionProfile.fromJson(
            item.map((k, v) => MapEntry('$k', v)),
          );
          // Session/password profiles may have empty apiKey (cookies hold auth).
          if (p.baseUrl.isNotEmpty) {
            list.add(p);
          }
        }
      }
    }
    String? def = _asString(json['defaultGatewayId']);
    String? act = _asString(json['activeGatewayId']);
    if (def != null && !list.any((g) => g.id == def)) def = null;
    if (act != null && !list.any((g) => g.id == act)) act = null;
    if (list.length == 1) {
      def ??= list.first.id;
      act ??= list.first.id;
    }
    return GatewayBook(
      gateways: list,
      defaultGatewayId: def,
      activeGatewayId: act,
    );
  }
}

class HermesSession {
  const HermesSession({
    required this.id,
    this.source,
    this.userId,
    this.model,
    this.title,
    this.startedAt,
    this.endedAt,
    this.endReason,
    this.messageCount,
    this.toolCallCount,
    this.lastActive,
    this.preview,
    this.parentSessionId,
  });

  final String id;
  final String? source;
  final String? userId;
  final String? model;
  final String? title;
  final String? startedAt;
  final String? endedAt;
  final String? endReason;
  final int? messageCount;
  final int? toolCallCount;
  final String? lastActive;
  final String? preview;
  final String? parentSessionId;

  String get displayTitle {
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    final p = preview?.trim();
    if (p != null && p.isNotEmpty) {
      return p.length > 48 ? '${p.substring(0, 48)}…' : p;
    }
    return id;
  }

  factory HermesSession.fromJson(Map<String, dynamic> json) {
    return HermesSession(
      id: '${json['id'] ?? ''}',
      source: _asString(json['source']),
      userId: _asString(json['user_id']),
      model: _asString(json['model']),
      title: _asString(json['title']),
      startedAt: json['started_at']?.toString(),
      endedAt: json['ended_at']?.toString(),
      endReason: _asString(json['end_reason']),
      messageCount: _asInt(json['message_count']),
      toolCallCount: _asInt(json['tool_call_count']),
      lastActive: json['last_active']?.toString(),
      preview: _asString(json['preview']),
      parentSessionId: _asString(json['parent_session_id']),
    );
  }
}

/// Runtime identity returned by the gateway for one live/resumed session.
/// This is deliberately separate from the global model preference: opening a
/// historical chat must restore the model/provider/options that chat actually
/// used, even when another device has since changed the global default.
class SessionRuntimeState {
  const SessionRuntimeState({
    this.model,
    this.provider,
    this.reasoningEffort,
    this.fastMode,
  });

  final String? model;
  final String? provider;
  final String? reasoningEffort;
  final bool? fastMode;

  factory SessionRuntimeState.fromJson(Map<String, dynamic>? raw) {
    if (raw == null) return const SessionRuntimeState();
    final model = raw['model']?.toString().trim();
    final provider = raw['provider']?.toString().trim();
    final effort = raw['reasoning_effort']?.toString().trim();
    final fastRaw = raw['fast'];
    final tier = raw['service_tier']?.toString().trim().toLowerCase();
    return SessionRuntimeState(
      model: model == null || model.isEmpty ? null : model,
      provider: provider == null || provider.isEmpty ? null : provider,
      reasoningEffort: effort == null || effort.isEmpty ? null : effort,
      fastMode: fastRaw is bool ? fastRaw : (tier == 'priority' ? true : null),
    );
  }
}

class HermesMessage {
  const HermesMessage({
    required this.id,
    required this.sessionId,
    required this.role,
    this.content,
    this.toolCallId,
    this.toolCalls,
    this.toolName,
    this.timestamp,
    this.tokenCount,
    this.finishReason,
    this.reasoning,
  });

  final String id;
  final String sessionId;
  final String role;
  final String? content;
  final String? toolCallId;
  final dynamic toolCalls;
  final String? toolName;
  final String? timestamp;
  final int? tokenCount;
  final String? finishReason;
  final String? reasoning;

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';
  bool get isTool => role == 'tool' || role == 'function';
  bool get isSystem => role == 'system' || role == 'slash';

  factory HermesMessage.fromJson(Map<String, dynamic> json) {
    return HermesMessage(
      id: '${json['id'] ?? ''}',
      sessionId: '${json['session_id'] ?? ''}',
      role: '${json['role'] ?? 'assistant'}',
      content: _contentToString(json['content']),
      toolCallId: _asString(json['tool_call_id']),
      toolCalls: json['tool_calls'],
      toolName: _asString(json['tool_name']),
      timestamp: json['timestamp']?.toString(),
      tokenCount: _asInt(json['token_count']),
      finishReason: _asString(json['finish_reason']),
      reasoning: _contentToString(
        json['reasoning'] ?? json['reasoning_content'],
      ),
    );
  }

  HermesMessage copyWith({String? content, String? id}) {
    return HermesMessage(
      id: id ?? this.id,
      sessionId: sessionId,
      role: role,
      content: content ?? this.content,
      toolCallId: toolCallId,
      toolCalls: toolCalls,
      toolName: toolName,
      timestamp: timestamp,
      tokenCount: tokenCount,
      finishReason: finishReason,
      reasoning: reasoning,
    );
  }
}

class HermesModelInfo {
  const HermesModelInfo({required this.id, this.object, this.ownedBy});

  final String id;
  final String? object;
  final String? ownedBy;

  factory HermesModelInfo.fromJson(Map<String, dynamic> json) {
    return HermesModelInfo(
      id: '${json['id'] ?? ''}',
      object: _asString(json['object']),
      ownedBy: _asString(json['owned_by']),
    );
  }
}

/// Installed skill from `GET /api/skills` / `skills.manage` list.
///
/// Invoked as a slash command: `/{name}` (or `/{name} <instruction>`).
class HermesSkill {
  const HermesSkill({
    required this.name,
    this.description,
    this.category,
    this.enabled = true,
    this.provenance,
    this.usage,
  });

  final String name;
  final String? description;
  final String? category;
  final bool enabled;

  /// `agent` | `bundled` | `hub` (Desktop SkillInfo).
  final String? provenance;
  final int? usage;

  /// Slash form including leading `/`.
  String get slashCommand {
    final n = name.trim();
    if (n.isEmpty) return '/';
    return n.startsWith('/') ? n : '/$n';
  }

  factory HermesSkill.fromJson(Map<String, dynamic> json) {
    final name = '${json['name'] ?? json['slug'] ?? json['id'] ?? ''}'.trim();
    final enabledRaw = json['enabled'];
    final enabled = enabledRaw is bool
        ? enabledRaw
        : enabledRaw == null
        ? true
        : '$enabledRaw' != 'false' && '$enabledRaw' != '0';
    final usageRaw = json['usage'] ?? json['activity'];
    int? usage;
    if (usageRaw is num) {
      usage = usageRaw.round();
    } else if (usageRaw != null) {
      usage = int.tryParse('$usageRaw');
    }
    return HermesSkill(
      name: name,
      description: (json['description'] ?? json['desc'] ?? json['summary'])
          ?.toString(),
      category: (json['category'] ?? json['group'])?.toString(),
      enabled: enabled,
      provenance: json['provenance']?.toString(),
      usage: usage,
    );
  }
}

/// A slash command from `GET /api/commands`.
///
/// Invoked as a slash command: `/{name}` (or `/{name} <args>`).
class SlashCommand {
  const SlashCommand({
    required this.name,
    required this.description,
    required this.category,
    this.aliases = const [],
    this.argsHint = '',
    this.cliOnly = false,
    this.gatewayOnly = false,
    this.configGated = false,
  });

  final String name;
  final String description;
  final String category;
  final List<String> aliases;
  final String argsHint;
  final bool cliOnly;
  final bool gatewayOnly;
  final bool configGated;

  /// Slash form including leading `/`.
  String get slashCommand {
    final n = name.trim();
    if (n.isEmpty) return '/';
    return n.startsWith('/') ? n : '/$n';
  }

  factory SlashCommand.fromJson(Map<String, dynamic> json) {
    final name = '${json['name'] ?? json['slug'] ?? json['id'] ?? ''}'.trim();
    final aliasesRaw = json['aliases'];
    final aliases = aliasesRaw is List
        ? aliasesRaw.map((a) => '$a').where((a) => a.isNotEmpty).toList()
        : const <String>[];
    bool asBool(dynamic raw) {
      if (raw is bool) return raw;
      if (raw == null) return false;
      return '$raw' == 'true' || '$raw' == '1';
    }

    return SlashCommand(
      name: name,
      description:
          (json['description'] ?? json['desc'] ?? json['summary'] ?? '')
              .toString(),
      category: (json['category'] ?? json['group'] ?? '').toString(),
      aliases: aliases,
      argsHint: (json['args_hint'] ?? json['argsHint'] ?? '').toString(),
      cliOnly: asBool(json['cli_only'] ?? json['cliOnly']),
      gatewayOnly: asBool(json['gateway_only'] ?? json['gatewayOnly']),
      configGated: asBool(json['config_gated'] ?? json['configGated']),
    );
  }
}

class HermesJob {
  const HermesJob({
    required this.id,
    this.name,
    this.schedule,
    this.prompt,
    this.deliver,
    this.enabled,
    this.state,
    this.lastRunAt,
    this.lastStatus,
    this.nextRunAt,
  });

  final String id;
  final String? name;
  final String? schedule;
  final String? prompt;
  final String? deliver;
  final bool? enabled;
  final String? state;
  final String? lastRunAt;
  final String? lastStatus;
  final String? nextRunAt;

  String get displayName {
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    return id;
  }

  factory HermesJob.fromJson(Map<String, dynamic> json) {
    // Cron payloads vary slightly; accept both nested and flat shapes.
    // Desktop CronJob.schedule is often `{ kind, expr, display }`.
    // Never `as String?` cast — non-string name/prompt would throw and drop
    // the entire jobs list.
    final nested = json['job'];
    final map = nested is Map
        ? nested.map((k, v) => MapEntry('$k', v))
        : Map<String, dynamic>.from(json);

    String? schedule;
    final rawSchedule =
        map['schedule'] ?? map['schedule_display'] ?? map['cron'];
    if (rawSchedule is Map) {
      schedule =
          (rawSchedule['display'] ?? rawSchedule['expr'] ?? rawSchedule['kind'])
              ?.toString();
    } else if (rawSchedule != null) {
      schedule = '$rawSchedule';
    }

    String? str(dynamic v) {
      if (v == null) return null;
      if (v is String) return v;
      if (v is Map || v is List) return null;
      final s = '$v'.trim();
      return s.isEmpty ? null : s;
    }

    final id = str(map['id'] ?? map['job_id'] ?? map['jobId']) ?? '';

    return HermesJob(
      id: id,
      name: str(map['name'] ?? map['title'] ?? map['label']),
      schedule: schedule,
      prompt: str(map['prompt']),
      deliver: str(map['deliver'] ?? map['delivery']),
      enabled: map['enabled'] is bool
          ? map['enabled'] as bool
          : map['enabled']?.toString().toLowerCase() == 'true',
      state: str(map['state'] ?? map['status']),
      lastRunAt: str(map['last_run_at'] ?? map['last_run'] ?? map['lastRunAt']),
      lastStatus: str(
        map['last_status'] ??
            map['last_run_status'] ??
            map['last_error'] ??
            map['lastError'],
      ),
      nextRunAt: str(map['next_run_at'] ?? map['next_run'] ?? map['nextRunAt']),
    );
  }
}

class HermesCapabilities {
  const HermesCapabilities({
    required this.raw,
    this.model,
    this.features = const {},
  });

  final Map<String, dynamic> raw;
  final String? model;
  final Map<String, dynamic> features;

  bool feature(String key) {
    final v = features[key];
    if (v is bool) return v;
    return false;
  }

  factory HermesCapabilities.fromJson(Map<String, dynamic> json) {
    final features = json['features'];
    return HermesCapabilities(
      raw: json,
      model: _asString(json['model']),
      features: features is Map<String, dynamic>
          ? features
          : features is Map
          ? features.map((k, v) => MapEntry('$k', v))
          : const {},
    );
  }
}

int? _asInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value');
}

String? _asString(dynamic value) {
  if (value == null) return null;
  if (value is String) return value;
  if (value is num || value is bool) return '$value';
  return null;
}

String? _contentToString(dynamic content) {
  if (content == null) return null;
  if (content is String) return content;
  if (content is List) {
    final parts = <String>[];
    for (final item in content) {
      if (item is String) {
        parts.add(item);
      } else if (item is Map) {
        final text = item['text'] ?? item['content'] ?? item['output_text'];
        if (text != null) parts.add('$text');
      }
    }
    return parts.join('\n');
  }
  if (content is Map) {
    final text = content['text'] ?? content['content'];
    if (text != null) return '$text';
  }
  return content.toString();
}
