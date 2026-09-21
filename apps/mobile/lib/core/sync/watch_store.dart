import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Sessions the user is waiting on for an agent result (notify when done).
class SessionWatch {
  const SessionWatch({
    required this.gatewayId,
    required this.sessionId,
    required this.baselineMessageCount,
    this.baselineLastMessageId,
    this.title,
    required this.watchingSinceIso,
    this.aliases = const [],
  });

  final String gatewayId;

  /// Primary stored / durable session id when known.
  final String sessionId;
  final int baselineMessageCount;
  final String? baselineLastMessageId;
  final String? title;
  final String watchingSinceIso;

  /// Extra ids (live WS runtime id, local_* draft) that must also match events.
  final List<String> aliases;

  Set<String> get allIds => {sessionId, ...aliases.where((a) => a.isNotEmpty)};

  bool matchesSession(String sid) {
    if (sid.isEmpty) return false;
    return allIds.contains(sid);
  }

  Map<String, dynamic> toJson() => {
    'gatewayId': gatewayId,
    'sessionId': sessionId,
    'baselineMessageCount': baselineMessageCount,
    'baselineLastMessageId': baselineLastMessageId,
    'title': title,
    'watchingSinceIso': watchingSinceIso,
    'aliases': aliases,
  };

  factory SessionWatch.fromJson(Map<String, dynamic> json) {
    final rawAliases = json['aliases'];
    final aliases = <String>[];
    if (rawAliases is List) {
      for (final a in rawAliases) {
        final s = '$a'.trim();
        if (s.isNotEmpty) aliases.add(s);
      }
    }
    return SessionWatch(
      gatewayId: '${json['gatewayId'] ?? ''}',
      sessionId: '${json['sessionId'] ?? ''}',
      baselineMessageCount:
          (json['baselineMessageCount'] as num?)?.toInt() ?? 0,
      baselineLastMessageId: json['baselineLastMessageId'] as String?,
      title: json['title'] as String?,
      watchingSinceIso: '${json['watchingSinceIso'] ?? ''}',
      aliases: aliases,
    );
  }
}

class WatchStore {
  static const _fileName = 'session_watches_v1.json';

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<List<SessionWatch>> list() async {
    final file = await _file();
    if (!await file.exists()) return const [];
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((m) => SessionWatch.fromJson(m.cast<String, dynamic>()))
          .where((w) => w.gatewayId.isNotEmpty && w.sessionId.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _write(List<SessionWatch> watches) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(watches.map((w) => w.toJson()).toList()),
      flush: true,
    );
  }

  Future<void> watch({
    required String gatewayId,
    required String sessionId,
    required int baselineMessageCount,
    String? baselineLastMessageId,
    String? title,
    Iterable<String> aliases = const [],
  }) async {
    final aliasList = {
      for (final a in aliases)
        if (a.trim().isNotEmpty && a.trim() != sessionId) a.trim(),
    }.toList();

    final all = await list();
    // Drop any watch that overlaps this session family, then write one merged.
    final next = <SessionWatch>[
      for (final w in all)
        if (w.gatewayId != gatewayId ||
            !(w.matchesSession(sessionId) || aliasList.any(w.matchesSession)))
          w,
      SessionWatch(
        gatewayId: gatewayId,
        sessionId: sessionId,
        baselineMessageCount: baselineMessageCount,
        baselineLastMessageId: baselineLastMessageId,
        title: title,
        watchingSinceIso: DateTime.now().toUtc().toIso8601String(),
        aliases: aliasList,
      ),
    ];
    await _write(next);
  }

  Future<void> unwatch(String gatewayId, String sessionId) async {
    final all = await list();
    await _write([
      for (final w in all)
        if (!(w.gatewayId == gatewayId && w.matchesSession(sessionId))) w,
    ]);
  }

  Future<void> unwatchAllMatching(
    String gatewayId,
    Iterable<String> ids,
  ) async {
    final set = ids.where((i) => i.isNotEmpty).toSet();
    if (set.isEmpty) return;
    final all = await list();
    await _write([
      for (final w in all)
        if (w.gatewayId != gatewayId || !w.allIds.any(set.contains)) w,
    ]);
  }

  Future<List<SessionWatch>> forGateway(String gatewayId) async {
    final all = await list();
    return all.where((w) => w.gatewayId == gatewayId).toList();
  }

  Future<SessionWatch?> find(String gatewayId, String sessionId) async {
    final all = await forGateway(gatewayId);
    for (final w in all) {
      if (w.matchesSession(sessionId)) return w;
    }
    return null;
  }
}
