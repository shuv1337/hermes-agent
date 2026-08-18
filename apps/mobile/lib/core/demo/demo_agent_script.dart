/// A deterministic, scripted "agent" for the demo gateway.
///
/// Real Hermes turns stream reasoning, tool calls, and assistant tokens over
/// the gateway WebSocket. This file reproduces that *shape* — without a real
/// model behind it — so the demo gateway's `prompt.submit` handler can push
/// a believable sequence of events for any prompt a reviewer types.
///
/// Pure Dart (`dart:async` / `dart:math` only, no Flutter) so the whole plan
/// can be unit-tested synchronously: [DemoAgentScript.plan] returns a static,
/// inspectable list of events with no timers involved. [DemoAgentScript.run]
/// is the small async driver that actually paces and emits them, and is the
/// only part that needs `await`/timers.
library;

import 'dart:async';

/// One scripted event in an agent turn.
///
/// [type] mirrors real gateway push-event names (`reasoning.delta`,
/// `tool.start`, `message.delta`, …) and [payload] mirrors the nested
/// `payload` object the gateway WebSocket wire format nests them in — see
/// `demo_gateway_server.dart` for how this gets wrapped into a JSON-RPC
/// notification frame. [delay] is how long to wait *before* emitting this
/// event, relative to the previous one.
class DemoAgentEvent {
  const DemoAgentEvent({
    required this.type,
    this.payload = const {},
    this.delay = Duration.zero,
  });

  final String type;
  final Map<String, dynamic> payload;
  final Duration delay;
}

/// The full scripted turn: the ordered events plus the assistant text they
/// stream (concatenation of every `message.delta` chunk, exactly equal to
/// the `message.complete` text).
class DemoAgentTurnPlan {
  const DemoAgentTurnPlan({required this.events, required this.finalText});

  final List<DemoAgentEvent> events;
  final String finalText;
}

/// Builds and drives one scripted agent turn.
class DemoAgentScript {
  DemoAgentScript._();

  /// Realistic-feeling per-chunk pacing for `message.delta` (20-40ms), cycled
  /// deterministically rather than drawn from a `Random` — keeps [plan] a
  /// pure function so tests don't need to seed or mock randomness. This is
  /// intentionally left alone by [speedFactor] tuning below the "believable
  /// typing speed" range — a longer turn should come from a longer reply,
  /// not from slower-than-real streaming (see [plan] doc comment).
  static const _chunkPacesMs = [22, 35, 28, 40, 24, 31, 20, 38, 26, 33, 29, 36];

  /// Build the ordered event list for one turn, given the user's [prompt].
  ///
  /// Shape: a reasoning/thinking phase (~1.5-2.5s of real time — long enough
  /// for a reviewer to actually read it before it's gone), one tool call
  /// that visibly dwells between `tool.start` and `tool.complete` (~2-3s —
  /// long enough to watch it run rather than blink and miss it), then the
  /// assistant answer streamed token-by-token (`message.start` → N ×
  /// `message.delta` → `message.complete`) at a believable typing pace. A
  /// full turn lands around 8-15s end to end: the *streaming* pace stays in
  /// a natural 20-40ms/chunk range (see [_chunkPacesMs]) and the extra
  /// duration comes from the reply itself being substantial (3-5
  /// paragraphs), not from artificially slow typing — a reviewer who's
  /// actually reading along should never feel like the app is stalling for
  /// effect.
  ///
  /// [speedFactor] scales every scripted delay uniformly — `1.0` (the
  /// default, and what the running app always uses) is the real pacing
  /// described above. Tests that only care about the event *sequence* and
  /// final text (not the live pacing) pass a tiny factor like `0.0` so
  /// [run] resolves with no `Future.delayed` waits and the suite stays
  /// fast; a test that specifically exercises `session.interrupt` picks a
  /// small-but-nonzero factor so there's still a real time window to land
  /// the interrupt inside. Deterministic: the same prompt + speedFactor
  /// always produces the same plan.
  static DemoAgentTurnPlan plan(String prompt, {double speedFactor = 1.0}) {
    final trimmed = prompt.trim();
    final reply = _composeReply(trimmed);
    final tool = _pickTool(trimmed);

    Duration scaled(int ms) =>
        Duration(milliseconds: (ms * speedFactor).round());

    final events = <DemoAgentEvent>[
      DemoAgentEvent(
        type: 'reasoning.delta',
        payload: {'text': 'Reading through the conversation so far'},
        delay: scaled(900),
      ),
      DemoAgentEvent(
        type: 'reasoning.delta',
        payload: {'text': ' and weighing which tool call would actually help.'},
        delay: scaled(900),
      ),
      DemoAgentEvent(
        type: 'tool.start',
        payload: {'name': tool.name, 'input': tool.input},
        delay: scaled(300),
      ),
      DemoAgentEvent(
        type: 'tool.complete',
        payload: {'name': tool.name, 'output': tool.output},
        delay: scaled(2500),
      ),
      DemoAgentEvent(type: 'message.start', delay: scaled(250)),
    ];

    final chunks = _chunkText(reply);
    for (var i = 0; i < chunks.length; i++) {
      events.add(
        DemoAgentEvent(
          type: 'message.delta',
          payload: {'text': chunks[i]},
          delay: scaled(_chunkPacesMs[i % _chunkPacesMs.length]),
        ),
      );
    }

    events.add(
      DemoAgentEvent(
        type: 'message.complete',
        payload: {'text': reply},
        delay: scaled(80),
      ),
    );

    return DemoAgentTurnPlan(events: events, finalText: reply);
  }

  /// Drive [planned], invoking [onEvent] for each event in order, honoring
  /// each event's [DemoAgentEvent.delay]. Checked between (and before) every
  /// wait so a mid-stream `session.interrupt` — surfaced via [isCancelled] —
  /// stops emission promptly.
  ///
  /// On cancellation, emits a synthetic `status.update` event with
  /// `kind: interrupted` (the same shape `session_sync_repository.dart`
  /// already treats as a clean stop, not an error) and returns immediately.
  /// Returns the assistant text actually produced — the concatenation of
  /// every `message.delta` chunk emitted before the stop (or the full
  /// [DemoAgentTurnPlan.finalText] if it ran to completion).
  static Future<String> run({
    required DemoAgentTurnPlan planned,
    required void Function(DemoAgentEvent event) onEvent,
    bool Function()? isCancelled,
  }) async {
    final buffer = StringBuffer();
    bool cancelled() => isCancelled?.call() ?? false;

    for (final event in planned.events) {
      if (cancelled()) {
        onEvent(_interruptedEvent());
        return buffer.toString();
      }
      if (event.delay > Duration.zero) {
        await Future<void>.delayed(event.delay);
      }
      if (cancelled()) {
        onEvent(_interruptedEvent());
        return buffer.toString();
      }
      onEvent(event);
      if (event.type == 'message.delta') {
        buffer.write('${event.payload['text'] ?? ''}');
      }
    }
    return buffer.toString();
  }

  static DemoAgentEvent _interruptedEvent() => const DemoAgentEvent(
    type: 'status.update',
    payload: {'kind': 'interrupted', 'text': 'Interrupted by user'},
  );

  // ── Tool selection ────────────────────────────────────────────────────

  static _ToolCall _pickTool(String prompt) {
    final lower = prompt.toLowerCase();
    if (lower.contains('search') ||
        lower.contains('news') ||
        lower.contains('research') ||
        lower.contains('digest')) {
      return _ToolCall(
        name: 'web_search',
        input: {'query': prompt.isEmpty ? 'latest updates' : prompt},
        output: {
          'results': [
            {
              'title': 'Context compression patterns for long-lived agents',
              'snippet':
                  'Teams are converging on hierarchical summarization '
                  'instead of naive truncation…',
            },
            {
              'title': 'Structured decoding becomes the default',
              'snippet':
                  'Schema-constrained output is now table stakes for '
                  'tool-calling agents…',
            },
          ],
        },
      );
    }
    return _ToolCall(
      name: 'shell',
      input: {'command': 'ls -la'},
      output: {
        'stdout':
            'total 32\ndrwxr-xr-x  6 demo  staff  192 workspace\n'
            '-rw-r--r--  1 demo  staff 1821 README.md\n'
            '-rw-r--r--  1 demo  staff  944 config.yaml',
        'exit_code': 0,
      },
    );
  }

  /// Renders a `tool.complete` event's `output` payload as plain, readable
  /// text — this is what gets persisted as the `tool`-role transcript
  /// message's content (see `DemoGatewayServer._rpcPromptSubmit`), so it
  /// needs to read like a real tool result, not a JSON dump the reviewer
  /// has to parse themselves.
  static String describeToolOutput(String name, Map<String, dynamic> output) {
    if (name == 'web_search') {
      final results = output['results'];
      if (results is List) {
        final lines = <String>[];
        for (final r in results) {
          if (r is Map) {
            final title = r['title'];
            final snippet = r['snippet'];
            lines.add('- **$title** — $snippet');
          }
        }
        if (lines.isNotEmpty) return lines.join('\n');
      }
    }
    if (name == 'shell') {
      final stdout = output['stdout'];
      if (stdout != null) return '```\n$stdout\n```';
    }
    return output.toString();
  }

  // ── Reply composition ────────────────────────────────────────────────

  static String _composeReply(String prompt) {
    final lower = prompt.toLowerCase();
    if (prompt.isEmpty) {
      return _fallbackReply('');
    }
    if (_isGreeting(lower)) {
      return _greetingReply();
    }
    if (lower.contains('code') ||
        lower.contains('bug') ||
        lower.contains('error') ||
        lower.contains('fix') ||
        lower.contains('crash')) {
      return _codeReply(prompt);
    }
    if (lower.contains('search') ||
        lower.contains('news') ||
        lower.contains('research') ||
        lower.contains('digest')) {
      return _searchReply(prompt);
    }
    return _fallbackReply(prompt);
  }

  static bool _isGreeting(String lower) {
    const greetings = ['hello', 'hi ', 'hi there', 'hey', 'yo ', 'howdy'];
    if (lower == 'hi' || lower == 'hey' || lower == 'yo') return true;
    return greetings.any(lower.startsWith);
  }

  static String _greetingReply() =>
      "Hey! I'm the scripted agent running inside this demo workspace, not "
      "a live model — but I'm wired up to behave like one so you can see "
      'the real shape of a Hermes turn end to end.\n\n'
      "A few things worth trying while you're here:\n\n"
      '- Ask me about a **bug or a fix** and I\'ll walk through a scripted '
      'code change, tool call included.\n'
      '- Ask me to **search for something** (try "search for the latest '
      'news") and I\'ll run a scripted `web_search` and summarize what '
      'comes back, table and all.\n'
      "- Send anything else and I'll give you an honest, scripted "
      "best-effort answer — I'll always tell you when I'm not actually "
      'reasoning about it.\n\n'
      'Every reply here streams in three phases — reasoning, a tool call, '
      'then the answer — the same events a real gateway would push over '
      "the WebSocket. I just don't have a model or real tools behind me "
      'in this sandbox, so treat everything I say as a demonstration of '
      'the shape of a Hermes turn rather than a real answer. While '
      "you're poking around, the Jobs tab and the skills picker are "
      'worth a look too — both are seeded with the same kind of static, '
      'but realistic, data as this chat.';

  static String _codeReply(String prompt) =>
      '## Fix\n\n'
      'I dug into the report and matched it to a retry-duplication '
      'pattern we\'ve seen before: the handler processes the same event '
      'twice when the upstream queue redelivers before the first attempt '
      'acknowledges. Here\'s a fix that guards on the event id before '
      'doing any work, so a redelivery is a cheap no-op instead of a '
      'double side effect.\n\n'
      '```python\n'
      'def handle_request(event: dict) -> dict:\n'
      '    if not event.get("id"):\n'
      '        raise ValueError("missing event id")\n'
      '    if already_processed(event["id"]):\n'
      '        return {"status": "duplicate"}\n'
      '    mark_processing(event["id"])\n'
      '    try:\n'
      '        result = process(event)\n'
      '    except Exception:\n'
      '        unmark_processing(event["id"])\n'
      '        raise\n'
      '    mark_processed(event["id"])\n'
      '    return result\n'
      '```\n\n'
      'The key change is the `already_processed` guard up front, paired '
      'with `mark_processing`/`unmark_processing` around the actual work '
      "so a crash mid-handler doesn't leave the event permanently \"in "
      'flight" and unretryable. Without that pairing you\'d trade one '
      'bug (double-processing) for another (a wedged event that never '
      'gets picked back up).\n\n'
      "A few things worth checking in your own code before you ship "
      'this:\n\n'
      '- Where `already_processed` reads from — an in-memory set '
      "won't survive a restart, so it needs to be backed by the same "
      'store the handler itself writes to.\n'
      '- Whether `process(event)` is itself idempotent for the '
      'operations that matter (writes, side-effecting API calls) — the '
      "id guard helps at the boundary, but doesn't save you if `process` "
      'fans out to something non-idempotent internally.\n'
      '- The TTL on `already_processed` records, if any — keeping them '
      'forever is safest but not always cheap at scale.\n\n'
      'Want me to walk through a concrete `already_processed` '
      'implementation backed by your existing store, or look at how the '
      'retries are being generated upstream in the first place?';

  static String _searchReply(String prompt) =>
      '## What I found\n\n'
      'A few threads stood out while going through recent coverage on '
      'this. The short version: teams are moving away from ad-hoc '
      'context management toward more structured approaches, and '
      'tooling is starting to catch up.\n\n'
      '| Theme | Why it matters |\n'
      '| --- | --- |\n'
      '| Hierarchical summarization | Long-lived agents stay coherent '
      "past the context window instead of degrading once history gets "
      'truncated. |\n'
      '| Structured decoding | Schema-constrained output is becoming '
      'the default for tool-calling agents, cutting down on malformed '
      'calls. |\n'
      "| Retrieval over raw context | Pulling in only what's relevant "
      'per turn keeps prompts smaller and answers more grounded. |\n'
      '| Eval-driven iteration | Teams are scoring agent runs against '
      'fixed task suites instead of eyeballing transcripts, which makes '
      'regressions from a prompt change much easier to catch. |\n\n'
      "A couple of things worth digging into further if this is "
      "relevant to what you're building:\n\n"
      '- How the summarization boundary gets chosen — naive '
      'fixed-window truncation is easy but loses exactly the details '
      'that matter most in long sessions.\n'
      "- Whether your tool definitions already enforce a schema (most "
      'SDKs support this now via `response_format` or similar), since '
      "that's the cheapest of these to adopt.\n"
      "- Where retrieval fits relative to the model's own context — "
      'some teams over-retrieve and end up right back where they '
      'started.\n\n'
      'Let me know if you want me to go deeper on any of these, or '
      'pull more specific sources.';

  static String _fallbackReply(String prompt) {
    if (prompt.isEmpty) {
      return "I didn't catch a question there — try asking me something "
          "and I'll give it a shot.";
    }
    return '## Taking a look\n\n'
        "Here's my best-effort take on that, though I want to be "
        'upfront: this is a scripted sample workspace, so there\'s no '
        'real model or live tool access behind this reply — everything '
        "you're seeing is pre-written to demonstrate the shape of a real "
        'Hermes turn (reasoning, a tool call, then a streamed answer), '
        'not an actual response to what you asked.\n\n'
        'In a connected workspace, answering something like "$prompt" '
        'would typically involve:\n\n'
        '- Pulling in relevant context from the current session and any '
        'linked files or repos.\n'
        '- Deciding whether a tool call (search, shell, a skill) would '
        'actually help before answering, rather than guessing.\n'
        '- Streaming the answer back token by token, the same way this '
        'scripted reply is being sent to you right now.\n\n'
        'If you want to see the tool-calling path specifically, try '
        "asking about a bug or a fix (I'll route to a code-flavored "
        "scripted reply), or ask me to search for something (I'll route "
        'to a research-flavored one). Both exercise the same reasoning '
        '→ tool call → streamed answer shape you\'re seeing here, just '
        'with different scripted content.\n\n'
        'Everything in this workspace — the sessions, the jobs, the '
        'skills catalog — is static seed data plus this small scripted '
        'agent, built so this app can be reviewed without a real Hermes '
        'gateway.';
  }

  // ── Streaming chunking ──────────────────────────────────────────────

  /// Splits [text] into small (~2 word) chunks for `message.delta`, without
  /// losing or reordering a single character — concatenating every chunk in
  /// order must reproduce [text] exactly.
  static List<String> _chunkText(String text) {
    if (text.isEmpty) return const [];
    final chunks = <String>[];
    final buffer = StringBuffer();
    var wordsInChunk = 0;
    for (final match in RegExp(r'\S+\s*').allMatches(text)) {
      buffer.write(match.group(0));
      wordsInChunk++;
      if (wordsInChunk >= 2) {
        chunks.add(buffer.toString());
        buffer.clear();
        wordsInChunk = 0;
      }
    }
    if (buffer.isNotEmpty) chunks.add(buffer.toString());
    return chunks;
  }
}

class _ToolCall {
  const _ToolCall({
    required this.name,
    required this.input,
    required this.output,
  });

  final String name;
  final Map<String, dynamic> input;
  final Map<String, dynamic> output;
}
