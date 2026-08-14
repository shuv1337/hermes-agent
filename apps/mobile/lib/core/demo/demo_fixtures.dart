/// Seed data for the in-process demo gateway (see `demo_gateway_server.dart`).
///
/// Apple's App Review guidance (Guideline 2.1(a)) asks for "a demonstration
/// mode that exhibits the app's full features and functionality" when a real
/// login cannot be provisioned for reviewers. This file is the content half
/// of that demo mode: a small, plausible, lived-in agent workspace — real
/// enough that a reviewer scrolling through it believes the app works.
///
/// Everything here is pure Dart data. No Flutter imports, no network, no
/// server logic — [demo_gateway_server.dart] owns the mutable runtime state
/// and seeds it once from the builders below.
library;

import 'dart:convert';

import 'package:hermes_mobile/core/demo/demo_workspace_files.dart';

/// One message in a seeded session transcript.
///
/// Mirrors the wire shape `HermesMessage.fromJson` expects
/// (`lib/core/models/hermes_models.dart`): `id`, `session_id`, `role`,
/// `content`, `timestamp`, plus optional tool/reasoning fields we don't need
/// for static seed transcripts (the live [DemoAgentScript] turns exercise
/// those instead).
class DemoMessage {
  DemoMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.toolName,
    this.toolCallId,
    this.finishReason,
  });

  final String id;

  /// `user` | `assistant` | `tool` | `system`.
  final String role;
  String content;
  final String timestamp;
  final String? toolName;
  final String? toolCallId;
  final String? finishReason;

  Map<String, dynamic> toJson(String sessionId) => {
    'id': id,
    'session_id': sessionId,
    'role': role,
    'content': content,
    'timestamp': timestamp,
    if (toolName != null) 'tool_name': toolName,
    if (toolCallId != null) 'tool_call_id': toolCallId,
    if (finishReason != null) 'finish_reason': finishReason,
  };
}

/// One seeded (or later, live-created) session in the demo workspace.
///
/// Mutable — `demo_gateway_server.dart` mutates [title], [archived],
/// [model]/[provider]/[reasoningEffort]/[fastMode] (via `session.title`,
/// `PATCH /api/sessions/{id}`, and `config.set`), and appends to [messages]
/// as turns run. This is what makes the sandbox feel real: every button a
/// reviewer taps actually changes state for the rest of the process.
class DemoSession {
  DemoSession({
    required this.id,
    required this.title,
    required this.startedAt,
    required this.lastActive,
    required this.model,
    required this.provider,
    List<DemoMessage>? messages,
    this.source = 'mobile',
    this.archived = false,
    this.reasoningEffort,
    this.fastMode = false,
  }) : messages = messages ?? <DemoMessage>[];

  final String id;
  String title;
  final String startedAt;
  String lastActive;
  String model;
  String provider;
  String? reasoningEffort;
  bool fastMode;
  final String source;
  bool archived;
  String? endedAt;
  String? endReason;
  final List<DemoMessage> messages;

  /// Trimmed tail of the last message — Desktop-parity session list preview.
  String get preview {
    if (messages.isEmpty) return '';
    final last = messages.last.content.trim();
    return last.length > 140 ? '${last.substring(0, 140)}…' : last;
  }

  int get toolCallCount => messages.where((m) => m.role == 'tool').length;

  /// `HermesSession.fromJson` shape (`lib/core/models/hermes_models.dart`).
  Map<String, dynamic> summaryJson() => {
    'id': id,
    'source': source,
    'model': model,
    'provider': provider,
    'title': title,
    'started_at': startedAt,
    'ended_at': endedAt,
    'end_reason': endReason,
    'message_count': messages.length,
    'tool_call_count': toolCallCount,
    'last_active': lastActive,
    'preview': preview,
    'archived': archived,
  };

  /// `SessionRuntimeState.fromJson` shape — returned as `session.resume`'s
  /// nested `info`.
  Map<String, dynamic> runtimeInfoJson() => {
    'model': model,
    'provider': provider,
    if (reasoningEffort != null) 'reasoning_effort': reasoningEffort,
    'fast': fastMode,
  };
}

/// A `reasoning_effort` option offered for one model — matches
/// `ReasoningEffortOption` / `ModelCapabilities.fromJson`.
class DemoReasoningEffort {
  const DemoReasoningEffort(this.effort, [this.description]);

  final String effort;
  final String? description;

  Map<String, dynamic> toJson() => {
    'effort': effort,
    if (description != null) 'description': description,
  };
}

/// One selectable model, grouped by [providerSlug] into the
/// `/api/model/options` and `/v1/models` payloads.
class DemoModelEntry {
  const DemoModelEntry({
    required this.id,
    required this.providerSlug,
    required this.providerName,
    this.reasoning = true,
    this.thinking = false,
    this.fast = false,
    this.reasoningEfforts = const [],
    this.defaultReasoningEffort,
  });

  final String id;
  final String providerSlug;
  final String providerName;
  final bool reasoning;
  final bool thinking;
  final bool fast;
  final List<DemoReasoningEffort> reasoningEfforts;
  final String? defaultReasoningEffort;

  /// `ModelCapabilities.fromJson` shape.
  Map<String, dynamic> capabilitiesJson() => {
    'reasoning': reasoning,
    'thinking': thinking,
    'fast': fast,
    if (reasoningEfforts.isNotEmpty)
      'reasoning_efforts': [for (final e in reasoningEfforts) e.toJson()],
    if (defaultReasoningEffort != null)
      'default_reasoning_effort': defaultReasoningEffort,
  };
}

/// One scheduled automation for `/api/cron/jobs`.
///
/// Mutable — `pause`/`resume`/`trigger` flip [enabled] and stamp
/// [lastRunAt]/[lastStatus] so the Jobs screen shows a real effect.
class DemoJob {
  DemoJob({
    required this.id,
    required this.name,
    required this.scheduleExpr,
    required this.scheduleDisplay,
    required this.prompt,
    required this.deliver,
    required this.enabled,
    this.lastRunAt,
    this.lastStatus,
    this.nextRunAt,
  });

  final String id;
  final String name;
  final String scheduleExpr;
  final String scheduleDisplay;
  final String prompt;
  final String deliver;
  bool enabled;
  String? lastRunAt;
  String? lastStatus;
  String? nextRunAt;

  /// `HermesJob.fromJson` shape (nested `schedule` map form).
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'schedule': {
      'kind': 'cron',
      'expr': scheduleExpr,
      'display': scheduleDisplay,
    },
    'prompt': prompt,
    'deliver': deliver,
    'enabled': enabled,
    'state': enabled ? 'active' : 'paused',
    'last_run_at': lastRunAt,
    'last_status': lastStatus,
    'next_run_at': nextRunAt,
  };
}

/// One installed skill for `GET /api/skills` / `skills.manage`.
class DemoSkillFixture {
  DemoSkillFixture({
    required this.name,
    required this.description,
    required this.category,
    this.enabled = true,
    this.provenance = 'bundled',
    this.usage = 0,
  });

  final String name;
  final String description;
  final String category;
  bool enabled;
  final String provenance;
  int usage;

  /// `HermesSkill.fromJson` shape.
  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'category': category,
    'enabled': enabled,
    'provenance': provenance,
    'usage': usage,
  };
}

/// One entry in the slash-command cheat sheet (`GET /api/commands`).
///
/// A representative subset copied from the real registry
/// (`hermes_cli/commands.py` `COMMAND_REGISTRY`) so the cheat sheet in
/// Settings looks like the genuine article, not a placeholder.
class DemoCommandFixture {
  const DemoCommandFixture({
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

  /// `SlashCommand.fromJson` shape.
  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'category': category,
    'aliases': aliases,
    'args_hint': argsHint,
    'cli_only': cliOnly,
    'gateway_only': gatewayOnly,
    'config_gated': configGated,
  };
}

/// Builders for every fixture collection. All timestamps are computed
/// relative to the `now` passed in (server boot time) so the workspace never
/// looks stale, no matter when the reviewer opens the app.
class DemoFixtures {
  DemoFixtures._();

  static const defaultModel = 'anthropic/claude-sonnet-5';
  static const defaultProvider = 'nous';

  // ── Models ────────────────────────────────────────────────────────────

  static List<DemoModelEntry> buildModels() => const [
    DemoModelEntry(
      id: 'anthropic/claude-opus-4.8',
      providerSlug: 'nous',
      providerName: 'Nous',
      reasoning: true,
      thinking: true,
      reasoningEfforts: [
        DemoReasoningEffort('max', 'Deepest reasoning, slowest'),
        DemoReasoningEffort('high'),
        DemoReasoningEffort('medium', 'Balanced default'),
        DemoReasoningEffort('low'),
      ],
      defaultReasoningEffort: 'medium',
    ),
    DemoModelEntry(
      id: defaultModel,
      providerSlug: defaultProvider,
      providerName: 'Nous',
      reasoning: true,
      thinking: true,
      reasoningEfforts: [
        DemoReasoningEffort('max'),
        DemoReasoningEffort('high'),
        DemoReasoningEffort('medium', 'Balanced default'),
        DemoReasoningEffort('low'),
      ],
      defaultReasoningEffort: 'medium',
    ),
    DemoModelEntry(
      id: 'anthropic/claude-haiku-4.5',
      providerSlug: 'nous',
      providerName: 'Nous',
      reasoning: false,
      thinking: false,
      fast: true,
    ),
    DemoModelEntry(
      id: 'openai/gpt-5.6-sol',
      providerSlug: 'nous',
      providerName: 'Nous',
      reasoning: true,
      thinking: true,
      fast: true,
      reasoningEfforts: [
        DemoReasoningEffort('high'),
        DemoReasoningEffort('medium', 'Balanced default'),
        DemoReasoningEffort('low'),
      ],
      defaultReasoningEffort: 'medium',
    ),
    DemoModelEntry(
      id: 'grok-4.5',
      providerSlug: 'xai-oauth',
      providerName: 'xAI',
      reasoning: true,
      thinking: false,
      reasoningEfforts: [
        DemoReasoningEffort('high'),
        DemoReasoningEffort('medium'),
        DemoReasoningEffort('low'),
      ],
      defaultReasoningEffort: 'medium',
    ),
    DemoModelEntry(
      id: 'gemini-3-pro',
      providerSlug: 'google',
      providerName: 'Google',
      reasoning: true,
      thinking: false,
    ),
  ];

  /// `/api/model/options` `providers` array — grouped by [DemoModelEntry.providerSlug].
  static List<Map<String, dynamic>> modelProvidersJson(
    List<DemoModelEntry> models,
  ) {
    final order = <String>[];
    final byProvider = <String, List<DemoModelEntry>>{};
    for (final m in models) {
      (byProvider[m.providerSlug] ??= []).add(m);
      if (!order.contains(m.providerSlug)) order.add(m.providerSlug);
    }
    return [
      for (final slug in order)
        {
          'slug': slug,
          'name': byProvider[slug]!.first.providerName,
          'models': [for (final m in byProvider[slug]!) m.id],
          'capabilities': {
            for (final m in byProvider[slug]!) m.id: m.capabilitiesJson(),
          },
        },
    ];
  }

  /// `/v1/models` `data` array (`HermesModelInfo.fromJson` shape).
  static List<Map<String, dynamic>> v1ModelsJson(List<DemoModelEntry> models) {
    return [
      for (final m in models)
        {'id': m.id, 'object': 'model', 'owned_by': m.providerName},
    ];
  }

  // ── Sessions ──────────────────────────────────────────────────────────

  static List<DemoSession> buildSessions(DateTime now) {
    return [
      // `_latencyReviewSession` is deliberately NOT seeded here — it exists
      // solely to demonstrate the in-app artifact viewer, which is paused
      // for v1 (see `kArtifactViewerEnabled` in
      // `lib/features/artifacts/artifact_viewer_flags.dart`). The builder
      // itself is untouched below, and reachable via
      // [latencyReviewSessionForTests], so `test/demo/demo_artifacts_test
      // .dart` keeps exercising the real detection/serving path against
      // real seed data. Re-add `_latencyReviewSession(now)` as the first
      // entry here when the viewer comes back.
      _paymentsWebhookSession(now),
      _researchDigestSession(now),
      _flakyCiSession(now),
      _kitchenRemodelSession(now),
    ];
  }

  /// Test-only accessor for [_latencyReviewSession] — see the comment in
  /// [buildSessions] for why the session it builds is not part of the
  /// seeded set while the artifact viewer is paused.
  static DemoSession latencyReviewSessionForTests(DateTime now) =>
      _latencyReviewSession(now);

  static String _iso(DateTime t) => t.toUtc().toIso8601String();

  /// The session that produces the two openable artifacts.
  ///
  /// This is the *only* session whose transcript contains a file the app can
  /// open in the artifact viewer, and it exists specifically so that feature
  /// is discoverable: an App Review reviewer (or anyone trying the sandbox)
  /// sees a chip in the transcript, taps it, and the file renders. **Not
  /// currently in [buildSessions]** — the artifact viewer is paused for v1
  /// (see `kArtifactViewerEnabled`), so this builder is only reached via
  /// [latencyReviewSessionForTests] for now. When the viewer returns, put
  /// this back first in [buildSessions] so it is the most recent session,
  /// and therefore the one at the top of the drawer.
  ///
  /// The tool messages here are shaped to satisfy the *real*
  /// `detectArtifactsInMessage` (`lib/features/artifacts/
  /// artifact_detection.dart`) rather than the other way around — it only
  /// recognizes a file from a `write_file`/`patch` tool result, read out of
  /// that result's own structured fields (`resolved_path`, `path`,
  /// `files_modified`, `files_created`) with a truthy `error` suppressing the
  /// chip entirely. So each tool message's content is the literal JSON those
  /// tools return (`tools/file_tools.py` `write_file` →
  /// `WriteResult.to_dict()` plus the `resolved_path`/`files_modified` keys
  /// the tool layer splats on top; `tools/file_operations.py`
  /// `PatchResult.to_dict()` for the patch), not a prose summary. The paths
  /// come from [DemoWorkspaceFiles] so the chip and the file the demo
  /// gateway serves can never drift apart, and `bytes_written` is the real
  /// byte length of the served content.
  static DemoSession _latencyReviewSession(DateTime now) {
    final started = now.subtract(const Duration(hours: 1, minutes: 20));
    var t = started;
    final files = DemoWorkspaceFiles.buildIndex(now);
    final markdownPath = DemoWorkspaceFiles.latencyReviewMarkdownPath;
    final htmlPath = DemoWorkspaceFiles.latencyReportHtmlPath;
    final markdownBytes = files[markdownPath]?.size ?? 0;
    final htmlBytes = files[htmlPath]?.size ?? 0;

    var seq = 0;
    DemoMessage msg(
      String role,
      String content, {
      String? toolName,
      Duration gap = const Duration(minutes: 2),
    }) {
      t = t.add(gap);
      seq += 1;
      return DemoMessage(
        id: 'seed-latency-$seq-${t.microsecondsSinceEpoch}',
        role: role,
        content: content,
        timestamp: _iso(t),
        toolName: toolName,
        toolCallId: toolName == null ? null : 'call_seed_latency_$seq',
      );
    }

    final messages = [
      msg(
        'user',
        'Go through last week\'s gateway access logs and work out why chat '
            'requests got slower. Write it up as a markdown summary I can '
            'read on my phone, plus a small HTML report I can send to the '
            'team.',
      ),
      msg(
        'tool',
        '{"stdout": "logs/\\n  gateway-access.log      412M\\n'
            '  gateway-access.log.1    398M\\n", "exit_code": 0}',
        toolName: 'shell',
        gap: const Duration(seconds: 40),
      ),
      msg(
        'assistant',
        'Logs are there — 810 MB across two files, seven days. Aggregating '
            'by route and percentile now.\n\n'
            'First pass: **p95 is up 41% week over week**, and it is only '
            'the chat endpoint. Everything else is inside its usual band, '
            'and the error rate never moved, so this is latency and not '
            'failures. Splitting the slow endpoint by phase, prompt assembly '
            'and the model call are both unchanged — the entire regression '
            'is in transcript persistence, which went from 12 ms to 138 ms '
            'mid-week.\n\n'
            'Writing both files now.',
        gap: const Duration(minutes: 3),
      ),
      msg(
        'tool',
        jsonEncode({
          'bytes_written': markdownBytes,
          'dirs_created': false,
          'verified': true,
          'resolved_path': markdownPath,
          'files_modified': [markdownPath],
        }),
        toolName: 'write_file',
        gap: const Duration(seconds: 25),
      ),
      msg(
        'tool',
        jsonEncode({
          'bytes_written': htmlBytes,
          'dirs_created': false,
          'verified': true,
          'resolved_path': htmlPath,
          'files_modified': [htmlPath],
        }),
        toolName: 'write_file',
        gap: const Duration(seconds: 18),
      ),
      msg(
        'assistant',
        'Both are written.\n\n'
            '- `latency-review.md` — the full write-up: per-endpoint table, '
            'the phase split, and a bench command to reproduce the slow path '
            'locally.\n'
            '- `latency-report.html` — a one-screen version for the team, '
            'with the p95 trend and the share-of-budget bars.\n\n'
            '**The finding in one line:** the transcript table passed ten '
            'million rows mid-week, and the planner stopped using the '
            '`session_id` index once it did — the query orders by '
            '`created_at`, which that index cannot serve. A composite index '
            'on `(session_id, created_at)`, built online, should put p95 back '
            'around 450 ms.\n\n'
            'Tap either file above to read it.',
        gap: const Duration(minutes: 2),
      ),
      msg(
        'user',
        'Nice. Add a note to the markdown that the first few minutes after a '
            'deploy are cold-cache and should be excluded.',
      ),
      msg(
        'tool',
        jsonEncode({
          'success': true,
          'diff':
              '--- a/latency-review.md\n'
              '+++ b/latency-review.md\n'
              '@@ -58,6 +58,9 @@\n'
              ' If `persist` comes back above ~40 ms, this is the same '
              'regression.\n'
              '+\n'
              '+Discard the first five minutes after a deploy: the cache is '
              'cold\n'
              '+and p95 is not comparable until it warms up.\n',
          'files_modified': [markdownPath],
        }),
        toolName: 'patch',
        gap: const Duration(seconds: 30),
      ),
      msg(
        'assistant',
        'Added, under **Reproducing it** — the note says to discard the '
            'first five minutes after a deploy while the cache is cold. '
            '`latency-review.md` is updated; the HTML report did not need '
            'the caveat since it only shows the weekly aggregate.',
        gap: const Duration(minutes: 1),
      ),
    ];

    return DemoSession(
      id: 'demo-latency-review',
      title: 'API latency review',
      startedAt: _iso(started),
      lastActive: _iso(t),
      model: defaultModel,
      provider: defaultProvider,
      reasoningEffort: 'high',
      messages: messages,
    );
  }

  static DemoSession _paymentsWebhookSession(DateTime now) {
    final started = now.subtract(const Duration(hours: 3, minutes: 12));
    var t = started;
    DemoMessage msg(String role, String content) {
      t = t.add(const Duration(minutes: 2));
      return DemoMessage(
        id: 'seed-payments-${t.microsecondsSinceEpoch}',
        role: role,
        content: content,
        timestamp: _iso(t),
      );
    }

    final messages = [
      msg(
        'user',
        'Our Stripe webhook handler is double-processing refunds when '
            'Stripe retries a delivery. Can you help me harden it?',
      ),
      msg(
        'assistant',
        'Sample workspace note: this is a simulated agent inside a demo '
            "Hermes workspace — there's no live model or gateway behind it, "
            'just scripted answers so you can see how the app works.\n\n'
            "That said — the fix is straightforward: Stripe's retry policy "
            'means your handler **must** be idempotent. Two things are '
            'usually missing:\n\n'
            '- No dedupe on `event.id` before applying side effects\n'
            '- The signature check happens *after* the handler starts work\n\n'
            'Here\'s a patched version:\n\n'
            '```python\n'
            'def process_payment(event: dict) -> None:\n'
            '    if not verify_signature(event):\n'
            '        raise ValueError("bad webhook signature")\n'
            '    if seen_before(event["id"]):\n'
            '        return  # Stripe retried a delivery we already handled\n'
            '    mark_seen(event["id"])\n'
            '    handle(event)\n'
            '```\n\n'
            'The key line is `seen_before(event["id"])` — store processed '
            'event ids for at least 24h (Stripe\'s retry window) and this '
            'class of bug goes away.',
      ),
      msg(
        'user',
        'Good call. Where should `seen_before` / `mark_seen` live — Redis, '
            'or just a table in Postgres?',
      ),
      msg(
        'assistant',
        "Either works; I'd lean Postgres since you already have a "
            '`webhook_events` table pattern elsewhere in this codebase. Add a '
            'unique constraint on `stripe_event_id` and let the insert '
            'itself be the dedupe check — an `IntegrityError` means "already '
            'handled," no separate read needed:\n\n'
            '```sql\n'
            'CREATE UNIQUE INDEX ux_webhook_events_stripe_id\n'
            '  ON webhook_events (stripe_event_id);\n'
            '```\n\n'
            'That collapses `seen_before` + `mark_seen` into one atomic '
            'insert, so there\'s no race between two retried deliveries '
            'landing at the same time either.',
      ),
    ];

    return DemoSession(
      id: 'demo-payments-webhook',
      title: 'Refactor the payments webhook',
      startedAt: _iso(started),
      lastActive: _iso(t),
      model: defaultModel,
      provider: defaultProvider,
      reasoningEffort: 'medium',
      messages: messages,
    );
  }

  static DemoSession _researchDigestSession(DateTime now) {
    final started = now.subtract(const Duration(days: 1, hours: 4));
    var t = started;
    DemoMessage msg(String role, String content) {
      t = t.add(const Duration(minutes: 3));
      return DemoMessage(
        id: 'seed-digest-${t.microsecondsSinceEpoch}',
        role: role,
        content: content,
        timestamp: _iso(t),
      );
    }

    final messages = [
      msg(
        'user',
        'Put together this week\'s research digest — the usual format.',
      ),
      msg(
        'assistant',
        '## Weekly Research Digest\n\n'
            'Here\'s what stood out this week:\n\n'
            '### Highlights\n\n'
            '- **Agent context management** — several teams are converging '
            'on hierarchical summarization for long-running sessions\n'
            '- **On-device inference** — quantized small models are closing '
            'the gap on routine tool-use tasks\n'
            '- **Structured output** — schema-constrained decoding is '
            'becoming the default rather than the exception\n\n'
            '### By the numbers\n\n'
            '| Topic | Mentions | Trend |\n'
            '| --- | --- | --- |\n'
            '| Context compression | 14 | ↑ |\n'
            '| Structured decoding | 9 | ↑ |\n'
            '| On-device models | 7 | → |\n'
            '| Multi-agent orchestration | 5 | ↓ |\n\n'
            'Want me to expand on any of these, or file this under the '
            '`research` skill for next week\'s comparison?',
      ),
      msg('user', 'Expand on the context compression one.'),
      msg(
        'assistant',
        'Sure — the throughline is that naive truncation is out of favor. '
            'The pattern people are landing on:\n\n'
            '1. Summarize completed sub-tasks into a compact log entry\n'
            '2. Keep the last N raw turns verbatim for local coherence\n'
            '3. Re-inject a rolling "state of the world" block instead of '
            'full history on every turn\n\n'
            'It trades a bit of recall fidelity for a context budget that '
            'stays flat instead of growing linearly with session length — '
            'which is exactly the shape you want for anything that runs '
            'for hours, like a background job.',
      ),
    ];

    return DemoSession(
      id: 'demo-research-digest',
      title: 'Weekly research digest',
      startedAt: _iso(started),
      lastActive: _iso(t),
      model: 'openai/gpt-5.6-sol',
      provider: 'nous',
      reasoningEffort: 'low',
      messages: messages,
    );
  }

  static DemoSession _flakyCiSession(DateTime now) {
    final started = now.subtract(const Duration(days: 2, hours: 6));
    var t = started;
    DemoMessage msg(String role, String content) {
      t = t.add(const Duration(minutes: 2));
      return DemoMessage(
        id: 'seed-ci-${t.microsecondsSinceEpoch}',
        role: role,
        content: content,
        timestamp: _iso(t),
      );
    }

    final messages = [
      msg(
        'user',
        'The `integration_tests` job in CI fails about 1 in 5 runs with a '
            'timeout, always in a different test. Any ideas before I start '
            'bisecting?',
      ),
      msg(
        'assistant',
        'A ~20% failure rate spread across different tests usually means '
            'shared state or a race, not a bug in any one test. Quick '
            'triage checklist:\n\n'
            '- Are tests sharing a database/port instead of getting a fresh '
            'one per worker?\n'
            '- Is the CI runner\'s CPU count different from local (fewer '
            'cores can surface races that never show up on a dev laptop)?\n'
            '- Any fixed `sleep()` calls standing in for a real readiness '
            'check?\n\n'
            'Run this to see if failures cluster on one runner shape:\n\n'
            '```bash\n'
            'gh run list --workflow=ci.yml --limit 50 --json conclusion,'
            'databaseId \\\n'
            '  | jq \'[.[] | select(.conclusion=="failure")] | length\'\n'
            '```\n\n'
            'If it\'s roughly evenly spread, my first bet is a shared test '
            'database — check whether `integration_tests` runs with '
            '`-p 1` (single worker) or in parallel with something like '
            '`pytest-xdist`.',
      ),
      msg('user', 'It runs with `pytest -n auto` — 4 workers on the CI box.'),
      msg(
        'assistant',
        'That\'s almost certainly it. With `pytest-xdist`, unless every '
            'test fixture is worker-scoped, workers can collide on the same '
            'database rows or ports. The fix is usually small: derive a '
            'per-worker resource name from `PYTEST_XDIST_WORKER` (e.g. '
            '`gw0`, `gw1`, …) and use that for the test database name or '
            'port offset. That alone tends to take flaky-timeout rates from '
            '~20% to ~0% without touching the tests themselves.',
      ),
    ];

    return DemoSession(
      id: 'demo-ci-flaky-job',
      title: 'Fix flaky CI job',
      startedAt: _iso(started),
      lastActive: _iso(t),
      model: 'anthropic/claude-opus-4.8',
      provider: 'nous',
      reasoningEffort: 'high',
      messages: messages,
    );
  }

  static DemoSession _kitchenRemodelSession(DateTime now) {
    final started = now.subtract(const Duration(days: 4, hours: 9));
    var t = started;
    DemoMessage msg(String role, String content) {
      t = t.add(const Duration(minutes: 4));
      return DemoMessage(
        id: 'seed-kitchen-${t.microsecondsSinceEpoch}',
        role: role,
        content: content,
        timestamp: _iso(t),
      );
    }

    final messages = [
      msg(
        'user',
        'We have about \$28k for a kitchen remodel — cabinets, counters, '
            'appliances, labor. Help me sanity-check a budget split.',
      ),
      msg(
        'assistant',
        'A reasonable starting split for a \$28,000 kitchen remodel:\n\n'
            '| Category | Typical share | Approx. budget |\n'
            '| --- | --- | --- |\n'
            '| Cabinets | 29% | \$8,120 |\n'
            '| Labor | 20% | \$5,600 |\n'
            '| Appliances | 14% | \$3,920 |\n'
            '| Countertops | 10% | \$2,800 |\n'
            '| Flooring | 7% | \$1,960 |\n'
            '| Lighting & electrical | 5% | \$1,400 |\n'
            '| Plumbing | 4% | \$1,120 |\n'
            '| Contingency | 10% | \$2,800 |\n\n'
            'A few notes:\n\n'
            '- Keep the 10% contingency untouched until week 3 — that\'s '
            'when hidden issues (old wiring, subfloor rot) usually surface\n'
            '- Cabinets are the single biggest lever: semi-custom vs. fully '
            'custom can swing that line by \$3–4k on its own\n'
            '- Get appliance quotes first — lead times run 6–10 weeks and '
            'often set the whole project schedule',
      ),
      msg('user', 'What should I prioritize if we need to cut \$3k somewhere?'),
      msg(
        'assistant',
        'In order of least painful to most:\n\n'
            '1. **Countertops** — quartz remnants or a mid-tier laminate '
            'instead of a full slab can save \$1,000–1,500 with almost no '
            'visible difference day to day\n'
            '2. **Lighting** — stock fixtures instead of designer ones, '
            'save \$400–600\n'
            '3. **Flooring** — if the existing subfloor is solid, refinish '
            'instead of replace where possible\n\n'
            'I\'d avoid cutting the labor or cabinet lines — those are '
            'where corner-cutting shows up as callbacks and redo costs '
            'later, which tends to erase the savings.',
      ),
    ];

    return DemoSession(
      id: 'demo-kitchen-remodel',
      title: 'Kitchen remodel budget',
      startedAt: _iso(started),
      lastActive: _iso(t),
      model: 'anthropic/claude-haiku-4.5',
      provider: 'nous',
      messages: messages,
    );
  }

  // ── Cron jobs ─────────────────────────────────────────────────────────

  static List<DemoJob> buildJobs(DateTime now) {
    return [
      DemoJob(
        id: 'demo-job-standup',
        name: 'Daily standup summary',
        scheduleExpr: '0 9 * * 1-5',
        scheduleDisplay: 'Weekdays at 9:00 AM',
        prompt:
            "Summarize yesterday's commits and open PRs into a short "
            'standup note.',
        deliver: 'telegram',
        enabled: true,
        lastRunAt: _iso(now.subtract(const Duration(hours: 16))),
        lastStatus: 'success',
        nextRunAt: _iso(_nextWeekdayNineAm(now)),
      ),
      DemoJob(
        id: 'demo-job-digest',
        name: 'Weekly research digest',
        scheduleExpr: '0 8 * * 1',
        scheduleDisplay: 'Mondays at 8:00 AM',
        prompt:
            'Compile a digest of interesting papers and news from the '
            'past week.',
        deliver: 'email',
        enabled: false,
        lastRunAt: _iso(now.subtract(const Duration(days: 6))),
        lastStatus: 'success',
        nextRunAt: null,
      ),
    ];
  }

  static DateTime _nextWeekdayNineAm(DateTime now) {
    var day = DateTime(
      now.year,
      now.month,
      now.day,
      9,
    ).add(const Duration(days: 1));
    while (day.weekday == DateTime.saturday || day.weekday == DateTime.sunday) {
      day = day.add(const Duration(days: 1));
    }
    return day;
  }

  // ── Skills ────────────────────────────────────────────────────────────

  static List<DemoSkillFixture> buildSkills() => [
    DemoSkillFixture(
      name: 'web-search',
      description: 'Search the web and summarize results with sources.',
      category: 'Research',
      provenance: 'bundled',
      usage: 42,
    ),
    DemoSkillFixture(
      name: 'pdf-summarizer',
      description: 'Extract and summarize long PDF documents.',
      category: 'Documents',
      provenance: 'bundled',
      usage: 17,
    ),
    DemoSkillFixture(
      name: 'changelog-writer',
      description: 'Turn a git diff or commit range into release notes.',
      category: 'Engineering',
      provenance: 'hub',
      usage: 9,
    ),
    DemoSkillFixture(
      name: 'sql-explainer',
      description: 'Explain and optimize slow SQL queries.',
      category: 'Engineering',
      provenance: 'hub',
      usage: 5,
    ),
    DemoSkillFixture(
      name: 'meeting-notes',
      description: 'Turn a transcript into action items and a summary.',
      category: 'Productivity',
      provenance: 'bundled',
      usage: 23,
    ),
    DemoSkillFixture(
      name: 'recipe-planner',
      description: 'Plan meals for the week from what\'s in the fridge.',
      category: 'Home',
      provenance: 'agent',
      usage: 3,
    ),
    DemoSkillFixture(
      name: 'budget-tracker',
      description: 'Track spending against a category budget over time.',
      category: 'Home',
      provenance: 'agent',
      enabled: false,
      usage: 1,
    ),
    DemoSkillFixture(
      name: 'code-reviewer',
      description: 'Review a diff for bugs, style, and missing tests.',
      category: 'Engineering',
      provenance: 'bundled',
      usage: 31,
    ),
  ];

  // ── Slash commands ───────────────────────────────────────────────────
  //
  // A representative subset of hermes_cli/commands.py COMMAND_REGISTRY —
  // real names, categories, and aliases so the Settings cheat sheet matches
  // the genuine gateway's shape.

  static List<DemoCommandFixture> buildCommands() => const [
    DemoCommandFixture(
      name: 'new',
      description: 'Start a new session (fresh session ID + history)',
      category: 'Session',
      aliases: ['reset'],
      argsHint: '[name]',
    ),
    DemoCommandFixture(
      name: 'retry',
      description: 'Retry the last message (resend to agent)',
      category: 'Session',
    ),
    DemoCommandFixture(
      name: 'undo',
      description: 'Back up N user turns and re-prompt (default 1)',
      category: 'Session',
      argsHint: '[N]',
    ),
    DemoCommandFixture(
      name: 'title',
      description: 'Set a title for the current session',
      category: 'Session',
      argsHint: '[name]',
    ),
    DemoCommandFixture(
      name: 'branch',
      description: 'Branch the current session (explore a different path)',
      category: 'Session',
      aliases: ['fork'],
      argsHint: '[name]',
    ),
    DemoCommandFixture(
      name: 'compress',
      description:
          "Compress conversation context (add 'here [N]' to keep "
          'recent N turns)',
      category: 'Session',
      aliases: ['compact'],
      argsHint: '[here [N] | focus topic]',
    ),
    DemoCommandFixture(
      name: 'background',
      description: 'Run a prompt in the background',
      category: 'Session',
      aliases: ['bg', 'btw'],
      argsHint: '<prompt>',
    ),
    DemoCommandFixture(
      name: 'agents',
      description: 'Show active agents and running tasks',
      category: 'Session',
      aliases: ['tasks'],
    ),
    DemoCommandFixture(
      name: 'status',
      description: 'Show session, model, token, and context info',
      category: 'Session',
    ),
    DemoCommandFixture(
      name: 'resume',
      description: 'Resume a previously-named session',
      category: 'Session',
      argsHint: '[name]',
    ),
    DemoCommandFixture(
      name: 'sessions',
      description: 'Browse and resume previous sessions',
      category: 'Session',
    ),
    DemoCommandFixture(
      name: 'model',
      description: 'Switch model (persists by default)',
      category: 'Configuration',
      argsHint: '[model] [--provider name] [--global|--session]',
    ),
    DemoCommandFixture(
      name: 'personality',
      description: 'Set a predefined personality',
      category: 'Configuration',
      argsHint: '[name]',
    ),
    DemoCommandFixture(
      name: 'reasoning',
      description: 'Manage reasoning effort and display',
      category: 'Configuration',
      argsHint: '[level|show|hide]',
    ),
    DemoCommandFixture(
      name: 'fast',
      description: 'Toggle fast mode (Normal/Fast)',
      category: 'Configuration',
      argsHint: '[normal|fast|status]',
    ),
    DemoCommandFixture(
      name: 'skills',
      description: 'Search, install, inspect, or manage skills',
      category: 'Tools & Skills',
      cliOnly: true,
    ),
    DemoCommandFixture(
      name: 'reload-skills',
      description: 'Re-scan for newly installed or removed skills',
      category: 'Tools & Skills',
      aliases: ['reload_skills'],
    ),
    DemoCommandFixture(
      name: 'cron',
      description: 'Manage scheduled tasks',
      category: 'Tools & Skills',
      argsHint: '[subcommand]',
    ),
    DemoCommandFixture(
      name: 'usage',
      description: 'Show token usage and rate limits for the current session',
      category: 'Info',
    ),
    DemoCommandFixture(
      name: 'help',
      description: 'Show available commands',
      category: 'Info',
    ),
  ];

  static List<Map<String, dynamic>> commandsJson(
    List<DemoCommandFixture> commands,
  ) => [for (final c in commands) c.toJson()];

  /// `commands.catalog` RPC shape (`{categories: [{name, pairs: [[cmd, desc]]}]}`)
  /// as consumed by `SessionSyncRepository._skillsFromCommandsCatalog` /
  /// the slash-completion pipeline.
  static Map<String, dynamic> commandsCatalogJson(
    List<DemoCommandFixture> commands,
  ) {
    final order = <String>[];
    final byCategory = <String, List<DemoCommandFixture>>{};
    for (final c in commands) {
      (byCategory[c.category] ??= []).add(c);
      if (!order.contains(c.category)) order.add(c.category);
    }
    return {
      'categories': [
        for (final cat in order)
          {
            'name': cat,
            'pairs': [
              for (final c in byCategory[cat]!) ['/${c.name}', c.description],
            ],
          },
      ],
    };
  }

  // ── Status / capabilities ────────────────────────────────────────────

  static Map<String, dynamic> statusJson({required DateTime bootedAt}) => {
    'auth_required': true,
    'version': 'hermes-demo-1.0.0',
    'gateway': 'hermes-demo',
    'uptime_seconds': DateTime.now().difference(bootedAt).inSeconds,
  };

  static Map<String, dynamic> capabilitiesJson(String currentModel) => {
    'model': currentModel,
    'features': {
      'streaming': true,
      'tools': true,
      'images': true,
      'skills': true,
      'cron': true,
      'background_jobs': true,
    },
  };

  static Map<String, dynamic> healthJson() => {'status': 'ok'};

  static Map<String, dynamic> healthDetailedJson({
    required DateTime bootedAt,
  }) => {
    'status': 'ok',
    'checks': {'model_provider': 'ok', 'database': 'ok', 'scheduler': 'ok'},
    'uptime_seconds': DateTime.now().difference(bootedAt).inSeconds,
  };
}
