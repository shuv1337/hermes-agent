import 'package:flutter/foundation.dart';

/// Desktop/web parity: messages that look like slash commands.
/// See `apps/desktop/src/lib/chat-runtime.ts` `SLASH_COMMAND_RE`.
final RegExp kSlashCommandRe = RegExp(r'^/[^\s/]*(?:\s|$)');

bool looksLikeSlashCommand(String text) {
  final t = text.trimLeft();
  return kSlashCommandRe.hasMatch(t);
}

class SlashParse {
  const SlashParse({required this.name, required this.arg});
  final String name;
  final String arg;
}

/// Split `/name arg…` — arg may span newlines (Desktop #41323).
SlashParse parseSlashCommand(String command) {
  final match = RegExp(
    r'^(\S+)([\s\S]*)$',
  ).firstMatch(command.replaceFirst(RegExp(r'^/+'), ''));
  if (match == null) return const SlashParse(name: '', arg: '');
  return SlashParse(
    name: match.group(1) ?? '',
    arg: (match.group(2) ?? '').trim(),
  );
}

/// Result of `command.dispatch` / a typed `slash.exec` payload.
sealed class CommandDispatch {
  const CommandDispatch();
}

class DispatchExec extends CommandDispatch {
  const DispatchExec({this.output, this.isPlugin = false});
  final String? output;
  final bool isPlugin;
}

class DispatchAlias extends CommandDispatch {
  const DispatchAlias(this.target);
  final String target;
}

class DispatchSkill extends CommandDispatch {
  const DispatchSkill({required this.name, this.message});
  final String name;
  final String? message;
}

class DispatchSend extends CommandDispatch {
  const DispatchSend({required this.message, this.notice});
  final String message;
  final String? notice;
}

class DispatchPrefill extends CommandDispatch {
  const DispatchPrefill({required this.message, this.notice});
  final String message;
  final String? notice;
}

CommandDispatch? parseCommandDispatch(Object? raw) {
  if (raw is! Map) return null;
  final row = raw.map((k, v) => MapEntry('$k', v));
  String? str(Object? v) => v is String ? v : null;

  switch (row['type']) {
    case 'exec':
      return DispatchExec(output: str(row['output']));
    case 'plugin':
      return DispatchExec(output: str(row['output']), isPlugin: true);
    case 'alias':
      final t = str(row['target']);
      return t == null ? null : DispatchAlias(t);
    case 'skill':
      final n = str(row['name']);
      return n == null
          ? null
          : DispatchSkill(name: n, message: str(row['message']));
    case 'send':
      final m = str(row['message']);
      return m == null
          ? null
          : DispatchSend(message: m, notice: str(row['notice']));
    case 'prefill':
      final m = str(row['message']);
      return m == null
          ? null
          : DispatchPrefill(message: m, notice: str(row['notice']));
    default:
      return null;
  }
}

enum SlashExecResult { done, sent, prefill, error, client }

/// Client hooks the slash pipeline needs (mirror web `slashExec.ts`).
class SlashCallbacks {
  const SlashCallbacks({
    required this.sys,
    required this.send,
    this.prefill,
    this.onClientCommand,
  });

  /// Render a system / slash status line in the transcript.
  final void Function(String text) sys;

  /// Submit a user message to the agent (`prompt.submit`).
  final Future<void> Function(String message) send;

  /// Drop text into the composer (e.g. `/undo` prefill).
  final void Function(String text)? prefill;

  /// Mobile-local handlers (`/new`, bare `/model`, …).
  /// Return `true` if fully handled (skip gateway).
  final Future<bool> Function(String name, String arg, String raw)?
  onClientCommand;
}

/// JSON-RPC request on the live gateway (Desktop WS).
typedef SlashGatewayRequest =
    Future<Map<String, dynamic>> Function(
      String method,
      Map<String, dynamic> params,
    );

/// Run a slash command — web/Desktop pipeline:
///
/// 1. Optional client handler
/// 2. `slash.exec`
/// 3. Fall back to `command.dispatch` (alias / skill / send / prefill)
Future<SlashExecResult> executeSlash({
  required String command,
  required String sessionId,
  required SlashGatewayRequest request,
  required SlashCallbacks callbacks,
}) async {
  final raw = command.trim();
  final parsed = parseSlashCommand(raw);
  final name = parsed.name;
  final arg = parsed.arg;

  if (name.isEmpty) {
    callbacks.sys('empty slash command');
    return SlashExecResult.error;
  }

  // Mobile-owned surfaces first (new chat, model picker, etc.).
  final client = callbacks.onClientCommand;
  if (client != null) {
    try {
      final handled = await client(name.toLowerCase(), arg, raw);
      if (handled) return SlashExecResult.client;
    } catch (e) {
      callbacks.sys('error: $e');
      return SlashExecResult.error;
    }
  }

  Future<SlashExecResult> handleDispatch(CommandDispatch dispatch) async {
    switch (dispatch) {
      case DispatchExec(:final output):
        callbacks.sys(
          output?.trim().isNotEmpty == true ? output! : '(no output)',
        );
        return SlashExecResult.done;
      case DispatchAlias(:final target):
        return executeSlash(
          command: '/$target${arg.isNotEmpty ? ' $arg' : ''}',
          sessionId: sessionId,
          request: request,
          callbacks: callbacks,
        );
      case DispatchSkill(:final name, :final message):
        final msg = message?.trim() ?? '';
        if (msg.isEmpty) {
          callbacks.sys('/$name: skill payload missing message');
          return SlashExecResult.error;
        }
        callbacks.sys('⚡ loading skill: $name');
        await callbacks.send(msg);
        return SlashExecResult.sent;
      case DispatchSend(:final message, :final notice):
        final n = notice?.trim();
        if (n != null && n.isNotEmpty) callbacks.sys(n);
        final msg = message.trim();
        if (msg.isEmpty) {
          callbacks.sys('/$name: empty message');
          return SlashExecResult.error;
        }
        await callbacks.send(msg);
        return SlashExecResult.sent;
      case DispatchPrefill(:final message, :final notice):
        final n = notice?.trim();
        if (n != null && n.isNotEmpty) callbacks.sys(n);
        final msg = message.trim();
        if (msg.isNotEmpty) callbacks.prefill?.call(msg);
        return SlashExecResult.prefill;
    }
  }

  // Primary: slash.exec (registry + skills + quick commands).
  try {
    final result = await request('slash.exec', {
      'session_id': sessionId,
      'command': raw.replaceFirst(RegExp(r'^/+'), ''),
    });

    final dispatch = parseCommandDispatch(result);
    if (dispatch != null) {
      return await handleDispatch(dispatch);
    }

    final output = result['output']?.toString();
    final warning = result['warning']?.toString();
    final body = (output != null && output.isNotEmpty)
        ? output
        : '/$name: no output';
    callbacks.sys(
      (warning != null && warning.isNotEmpty)
          ? 'warning: $warning\n$body'
          : body,
    );
    return SlashExecResult.done;
  } catch (e) {
    debugPrint('slash.exec failed, try command.dispatch: $e');
  }

  // Fallback: command.dispatch for skill/send/alias directives.
  try {
    final result = await request('command.dispatch', {
      'session_id': sessionId,
      'name': name,
      'arg': arg,
    });
    final dispatch = parseCommandDispatch(result);
    if (dispatch == null) {
      callbacks.sys('error: invalid response: command.dispatch');
      return SlashExecResult.error;
    }
    return await handleDispatch(dispatch);
  } catch (e) {
    callbacks.sys('error: $e');
    return SlashExecResult.error;
  }
}

/// One row from slash autocomplete (Desktop popover parity).
class SlashCompletion {
  const SlashCompletion({
    required this.text,
    this.display,
    this.meta,
    this.group,
    this.isSkill = false,
  });

  final String text;
  final String? display;
  final String? meta;
  final String? group;

  /// Desktop bold/highlights skill rows separately from built-ins.
  final bool isSkill;
}

/// Built-in command names (lowercase, no slash) — used to flag skills.
/// Keep in sync loosely with Desktop `isDesktopSlashExtensionCommand`:
/// anything not in the known registry is treated as a skill extension.
const Set<String> kKnownBuiltinSlashNames = {
  'new',
  'reset',
  'clear',
  'history',
  'save',
  'prompt',
  'compose',
  'retry',
  'undo',
  'title',
  'compress',
  'rollback',
  'snapshot',
  'snap',
  'stop',
  'queue',
  'q',
  'steer',
  'goal',
  'subgoal',
  'moa',
  'resume',
  'sessions',
  'switch',
  'redraw',
  'status',
  'agents',
  'tasks',
  'background',
  'bg',
  'btw',
  'branch',
  'fork',
  'handoff',
  'config',
  'model',
  'codex-runtime',
  'personality',
  'verbose',
  'fast',
  'reasoning',
  'skin',
  'statusbar',
  'sb',
  'voice',
  'yolo',
  'footer',
  'busy',
  'indicator',
  'timestamps',
  'tools',
  'toolsets',
  'browser',
  'skills',
  'memory',
  'bundles',
  'learn',
  'cron',
  'suggestions',
  'suggest',
  'blueprint',
  'bp',
  'curator',
  'kanban',
  'reload-mcp',
  'reload_mcp',
  'reload-skills',
  'reload_skills',
  'reload',
  'plugins',
  'pet',
  'hatch',
  'generate-pet',
  'help',
  'commands',
  'version',
  'usage',
  'credits',
  'billing',
  'insights',
  'platforms',
  'gateway',
  'paste',
  'copy',
  'image',
  'debug',
  'profile',
  'quit',
  'exit',
  'compact',
  'details',
  'logs',
  'mouse',
};

bool isSkillSlashName(String command) {
  final n = command
      .replaceFirst(RegExp(r'^/+'), '')
      .split(RegExp(r'\s+'))
      .first;
  if (n.isEmpty) return false;
  return !kKnownBuiltinSlashNames.contains(n.toLowerCase());
}

/// Parse `commands.catalog` (Desktop bare-`/` source).
List<SlashCompletion> parseCommandsCatalog(Map<String, dynamic> raw) {
  final out = <SlashCompletion>[];
  final seen = <String>{};

  void addPair(String command, String meta, String group) {
    var cmd = command.trim();
    if (cmd.isEmpty) return;
    if (!cmd.startsWith('/')) cmd = '/$cmd';
    final key = cmd.toLowerCase();
    if (seen.contains(key)) return;
    seen.add(key);
    final skill =
        isSkillSlashName(cmd) || group.toLowerCase().contains('skill');
    out.add(
      SlashCompletion(
        text: cmd,
        display: cmd,
        meta: meta,
        group: skill ? 'Skills' : (group.isEmpty ? 'Commands' : group),
        isSkill: skill,
      ),
    );
  }

  final categories = raw['categories'];
  if (categories is List && categories.isNotEmpty) {
    for (final section in categories) {
      if (section is! Map) continue;
      final name = '${section['name'] ?? ''}'.trim();
      final pairs = section['pairs'];
      if (pairs is! List) continue;
      for (final pair in pairs) {
        if (pair is List && pair.isNotEmpty) {
          addPair('${pair[0]}', pair.length > 1 ? '${pair[1]}' : '', name);
        } else if (pair is Map) {
          addPair(
            '${pair['command'] ?? pair['name'] ?? pair['text'] ?? ''}',
            '${pair['description'] ?? pair['meta'] ?? ''}',
            name,
          );
        }
      }
    }
  }

  if (out.isEmpty) {
    final pairs = raw['pairs'];
    if (pairs is List) {
      for (final pair in pairs) {
        if (pair is List && pair.isNotEmpty) {
          addPair(
            '${pair[0]}',
            pair.length > 1 ? '${pair[1]}' : '',
            'Commands',
          );
        }
      }
    }
  }

  return out;
}

/// Desktop-parity slash completions:
/// - bare `/` → `commands.catalog` (full categorized list + skills)
/// - `/partial` → `complete.slash` (prefix filter)
Future<List<SlashCompletion>> completeSlash({
  required String text,
  required SlashGatewayRequest request,
}) async {
  final q = text.startsWith('/') ? text : '/$text';
  // Desktop: empty query after `/` uses the catalog, not complete.slash.
  final afterSlash = q.replaceFirst(RegExp(r'^/+'), '');
  final isBareRoot = afterSlash.isEmpty;

  if (isBareRoot) {
    try {
      final catalog = await request('commands.catalog', {});
      final items = parseCommandsCatalog(catalog);
      if (items.isNotEmpty) return items;
    } catch (e) {
      debugPrint('commands.catalog failed: $e');
    }
    // Fall through to complete.slash('/') if catalog empty/unavailable.
  }

  try {
    final result = await request('complete.slash', {'text': q});
    final replaceFrom = result['replace_from'];
    final replaceAt = replaceFrom is num
        ? replaceFrom.toInt()
        : (replaceFrom is int ? replaceFrom : 1);
    final isArg = replaceAt > 1;
    final prefix = isArg && replaceAt <= q.length
        ? q.substring(0, replaceAt)
        : '';

    final raw = result['items'];
    if (raw is! List) return const [];
    final out = <SlashCompletion>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final m = item.map((k, v) => MapEntry('$k', v));
      var t = '${m['text'] ?? ''}';
      if (t.isEmpty) continue;
      if (isArg) t = '$prefix$t';
      if (!t.startsWith('/')) t = '/$t';
      final groupRaw = m['group']?.toString();
      final skill = !isArg && isSkillSlashName(t);
      out.add(
        SlashCompletion(
          text: t,
          display: m['display']?.toString(),
          meta: m['meta']?.toString(),
          group: isArg
              ? 'Options'
              : (skill
                    ? 'Skills'
                    : (groupRaw?.isNotEmpty == true ? groupRaw! : 'Commands')),
          isSkill: skill,
        ),
      );
    }
    // Commands before Skills (Desktop group order).
    if (!isArg) {
      out.sort((a, b) {
        final ga = a.isSkill ? 1 : 0;
        final gb = b.isSkill ? 1 : 0;
        if (ga != gb) return ga - gb;
        return 0; // keep backend relevance order within group
      });
    }
    return out;
  } catch (e) {
    debugPrint('complete.slash failed: $e');
    return const [];
  }
}

/// Format slash status the way Desktop stores system lines.
String slashStatusText(String command, String output) {
  final o = output.trim();
  if (o.isEmpty) return 'slash:$command';
  return 'slash:$command\n$o';
}
