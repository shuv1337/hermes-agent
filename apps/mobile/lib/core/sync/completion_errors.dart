import 'package:hermes_mobile/core/models/hermes_models.dart';

/// Desktop-parity detection for provider/gateway failures that arrive as
/// assistant `message.complete` text (not only as WS `error` events).
///
/// Mirrors `apps/desktop/.../use-message-stream/utils.ts` `completionErrorText`.

final _completionErrorPatterns = <RegExp>[
  RegExp(r'^API call failed after \d+ retries:', caseSensitive: false),
  RegExp(r'^API call failed\b', caseSensitive: false),
  RegExp(r'^Invalid API response after \d+ retries:', caseSensitive: false),
  RegExp(r'^Billing or credits exhausted:', caseSensitive: false),
  RegExp(r'^HTTP\s+\d{3}\b', caseSensitive: false),
  RegExp(r'^(Provider|Gateway)\s+error:', caseSensitive: false),
  RegExp(r'^Rate limited after \d+ retries', caseSensitive: false),
  RegExp(r'^API failed after \d+ retries', caseSensitive: false),
];

/// Returns the trimmed text when it is a known provider/API failure banner.
String? completionErrorText(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return null;
  for (final re in _completionErrorPatterns) {
    if (re.hasMatch(text)) return text;
  }
  return null;
}

bool isCompletionErrorText(String? raw) => completionErrorText(raw) != null;

/// Normalize transport / turn-failure strings into something users should see.
///
/// Prefer the agent's own banner when present:
/// `API call failed after 3 retries: Connection error.`
String formatTurnErrorForUser(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return 'API call failed.';

  // Strip our own wrappers so we don't stack prefixes.
  var msg = t;
  const prefixes = ['Agent turn failed: ', 'TurnFailedAfterSubmit: '];
  for (final p in prefixes) {
    if (msg.startsWith(p)) {
      msg = msg.substring(p.length).trim();
    }
  }

  final known = completionErrorText(msg);
  if (known != null) return known;

  // Bare transport phrases — match Desktop/agent wording when we only got
  // the summary without the "after N retries" wrapper.
  final lower = msg.toLowerCase();
  if (lower == 'connection error' ||
      lower == 'connection error.' ||
      lower.startsWith('connection error:') ||
      lower.contains('connection refused') ||
      lower.contains('connection reset') ||
      lower == 'network error' ||
      lower == 'network error.') {
    final summary = msg.endsWith('.') ? msg : '$msg.';
    if (summary.toLowerCase().startsWith('api call failed')) return summary;
    return 'API call failed after 3 retries: $summary';
  }

  if (lower.startsWith('api call failed')) return msg;
  return msg;
}

/// True when [messages] already ends with an assistant/system row carrying
/// [errorText] (or any completion-error banner).
bool transcriptHasErrorAssistant(
  List<HermesMessage> messages, {
  required String errorText,
}) {
  final want = errorText.trim();
  if (want.isEmpty) return false;
  for (var i = messages.length - 1; i >= 0; i--) {
    final m = messages[i];
    if (!m.isAssistant && !m.isSystem) continue;
    final content = (m.content ?? '').trim();
    if (content.isEmpty) continue;
    if (content == want) return true;
    if (isCompletionErrorText(content)) return true;
    return false;
  }
  return false;
}

/// Id prefix for the locally-generated assistant error bubbles this file
/// mints. They are a client artifact, never server history — the sync merge
/// keys off this prefix to stop an expired one outliving the failure it
/// describes (see `SessionSyncRepository.syncMessages`).
const kLocalErrorIdPrefix = 'local_error_';

/// Append an assistant error bubble when the transcript is missing it.
List<HermesMessage> ensureErrorAssistantMessage(
  List<HermesMessage> messages, {
  required String sessionId,
  required String errorText,
}) {
  final text = formatTurnErrorForUser(errorText);
  if (transcriptHasErrorAssistant(messages, errorText: text)) {
    return messages;
  }
  return [
    ...messages,
    HermesMessage(
      id: '$kLocalErrorIdPrefix${DateTime.now().microsecondsSinceEpoch}',
      sessionId: sessionId,
      role: 'assistant',
      content: text,
      timestamp: DateTime.now().toUtc().toIso8601String(),
      finishReason: 'error',
    ),
  ];
}

/// Preserve a locally-cached terminal provider error when the authoritative
/// transcript has the user turn but no assistant response yet.
///
/// Gateway/dashboard transcripts do not always persist failed assistant turns.
/// A later background sync must not therefore erase the error bubble the user
/// just saw. Once the server has any assistant/system response after its last
/// user turn (for example after a successful retry), the server wins and the
/// stale local error is no longer carried forward.
List<HermesMessage> preserveTerminalErrorAfterSync(
  List<HermesMessage> remote,
  List<HermesMessage> local,
) {
  final lastRemoteUser = remote.lastIndexWhere((m) => m.isUser);
  if (lastRemoteUser < 0) return remote;

  final hasRemoteReply = remote
      .skip(lastRemoteUser + 1)
      .any(
        (m) =>
            (m.isAssistant || m.isSystem) &&
            (m.content ?? '').trim().isNotEmpty,
      );
  if (hasRemoteReply) return remote;

  final lastLocalUser = local.lastIndexWhere((m) => m.isUser);
  if (lastLocalUser < 0) return remote;
  HermesMessage? terminalError;
  for (final message in local.skip(lastLocalUser + 1)) {
    if ((message.isAssistant || message.isSystem) &&
        (message.finishReason == 'error' ||
            isCompletionErrorText(message.content))) {
      terminalError = message;
    }
  }
  if (terminalError == null) return remote;

  final errorText = (terminalError.content ?? '').trim();
  if (remote.any(
    (m) =>
        m.id == terminalError!.id ||
        ((m.isAssistant || m.isSystem) &&
            (m.content ?? '').trim() == errorText),
  )) {
    return remote;
  }
  return [...remote, terminalError];
}

/// Collapse consecutive same-body user rows (optimistic + server twin).
List<HermesMessage> dedupeAdjacentUserMessages(List<HermesMessage> messages) {
  if (messages.length < 2) return messages;
  final out = <HermesMessage>[];
  for (final m in messages) {
    if (out.isNotEmpty && m.isUser && out.last.isUser) {
      final a = (out.last.content ?? '').trim();
      final b = (m.content ?? '').trim();
      if (a.isNotEmpty && a == b) {
        // Prefer durable (non-local_*) id when collapsing.
        final keepLocal =
            out.last.id.startsWith('local_') && !m.id.startsWith('local_');
        if (keepLocal) {
          out[out.length - 1] = m;
        }
        continue;
      }
    }
    out.add(m);
  }
  return out;
}
