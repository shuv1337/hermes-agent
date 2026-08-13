/// The demo workspace's "files on disk" — the content half of the demo
/// gateway's managed-files surface (`GET /api/files/read`, served by
/// `demo_gateway_server.dart`).
///
/// Why this exists: the app can open agent-written `.md`/`.html` files in an
/// in-app viewer (`lib/features/artifacts/`). A chip appears in the
/// transcript wherever the transcript shows the agent having written one, and
/// tapping it fetches the bytes from the gateway. Without a files surface and
/// something to serve, the demo workspace silently hides that whole feature
/// from an App Review reviewer — they would never learn it exists.
///
/// So the seeded "API latency review" session in `demo_fixtures.dart` writes
/// exactly the two files below, at exactly the paths named here — the fixture
/// and this registry are wired to the same constants so a rename can't leave
/// a chip pointing at nothing.
///
/// Pure Dart data + one `dart:convert` base64 encode. No Flutter, no server
/// logic: `demo_gateway_server.dart` owns the routing and the error codes.
library;

import 'dart:convert';

/// One file in the demo workspace.
///
/// [contents] is the literal text the reviewer sees in the viewer;
/// everything else on the wire (size, the base64 data URL) is derived from
/// it, so the response can never disagree with the bytes — exactly like the
/// real gateway, which stats and reads the same file.
class DemoWorkspaceFile {
  DemoWorkspaceFile({
    required this.path,
    required this.mimeType,
    required this.contents,
  }) : bytes = utf8.encode(contents);

  /// Absolute gateway-side path — what the transcript's `write_file` result
  /// reports as `resolved_path`, and therefore what the artifact chip passes
  /// back as `?path=`.
  final String path;

  /// What the real gateway derives with `mimetypes.guess_type(name)`. Note
  /// the viewer deliberately ignores this when picking a renderer (see
  /// `rendererKindFor`) — it is served for contract fidelity, not because
  /// anything downstream trusts it.
  final String mimeType;

  final String contents;
  final List<int> bytes;

  String get name => path.split('/').last;

  /// Byte length, not character length — the real gateway reports
  /// `st_size`, and a multi-byte character (the report bodies contain
  /// en-dashes and arrows) would otherwise make the two disagree.
  int get size => bytes.length;

  /// The exact `GET /api/files/read` 200 body, per `hermes_cli/
  /// web_server.py:2413` — the five fields `ManagedFileContent.fromJson`
  /// parses, plus the same `_managed_response_meta` trailer the real handler
  /// splats in (the mobile client ignores those three, but serving them
  /// keeps the demo response byte-shaped like the real one).
  Map<String, dynamic> readJson() => {
    'name': name,
    'path': path,
    'size': size,
    'mime_type': mimeType,
    'data_url': 'data:$mimeType;base64,${base64.encode(bytes)}',
    'root': DemoWorkspaceFiles.workspaceRoot,
    'locked_root': DemoWorkspaceFiles.workspaceRoot,
    'can_change_path': false,
  };
}

/// Builders + path constants for the demo workspace's files.
class DemoWorkspaceFiles {
  DemoWorkspaceFiles._();

  /// The workspace the demo agent "runs in". Every served path resolves
  /// under this root; anything else is refused the way the real gateway
  /// refuses a path outside its locked root.
  static const workspaceRoot = '/home/demo/workspace';

  /// The Markdown artifact — written by the seeded session's first
  /// `write_file` call and later touched by its `patch` call.
  ///
  /// Both artifacts sit at the workspace *root*, not in a `reports/`
  /// subdirectory, and that is deliberate. The detector also raises a chip
  /// from a backticked filename in assistant prose (`` `latency-review.md`
  /// ``), and a bare filename resolves relative to the managed root — on the
  /// real gateway as much as here. A file one directory down would give a
  /// chip that 404s on tap for exactly the phrasing an agent uses most
  /// naturally, so the fixture keeps every artifact where a bare filename
  /// resolves.
  static const latencyReviewMarkdownPath = '$workspaceRoot/latency-review.md';

  /// The HTML artifact — written by the seeded session's second `write_file`
  /// call.
  static const latencyReportHtmlPath = '$workspaceRoot/latency-report.html';

  /// A path that is deliberately **not** in the registry.
  ///
  /// The viewer has a not-found state, and it should be reachable — but not
  /// by shipping a chip that 404s on tap. A chip that fails when a reviewer
  /// taps it reads as the app being broken, which is the opposite of what
  /// this whole demo mode is for. So no seeded transcript message names this
  /// path: it exists so the 404 branch can be exercised from a test (and by
  /// anyone poking the API directly), while every chip a reviewer can
  /// actually see resolves.
  static const absentPath = '$workspaceRoot/latency-review-q2.md';

  /// A file that exists but must never be served — see [isSensitivePath].
  /// Also never named in a transcript.
  static const sensitivePath = '$workspaceRoot/.env';

  /// `hermes_cli/web_server.py`'s `_MANAGED_FILE_MAX_BYTES`. Nothing seeded
  /// here comes close (the two artifacts are a few KB), so the 413 branch is
  /// implemented for contract fidelity rather than exercised — faking a
  /// 100 MB response would mean serving 100 MB.
  static const maxBytes = 100 * 1024 * 1024;

  /// Mirrors `_is_sensitive_filename` / `_is_sensitive_path`: `.env`,
  /// `.env.<suffix>`, `.envrc`, the Hermes credential-store basenames, and
  /// anything under a `mcp-tokens/` or `pairing/` directory. Case-insensitive
  /// for the same reason the real one is.
  static const _sensitiveBasenames = {
    'auth.json',
    'auth.lock',
    'credentials',
    'config.yaml',
    '.anthropic_oauth.json',
    'google_token.json',
    'webhook_subscriptions.json',
    '.git-credentials',
  };

  static const _sensitiveDirNames = {'mcp-tokens', 'pairing'};

  static bool isSensitivePath(String path) {
    final parts = path
        .split('/')
        .where((p) => p.isNotEmpty)
        .map((p) => p.toLowerCase())
        .toList();
    if (parts.isEmpty) return false;
    for (final dir in parts.take(parts.length - 1)) {
      if (_sensitiveDirNames.contains(dir)) return true;
    }
    final name = parts.last;
    if (name == '.env' || name.startsWith('.env.') || name == '.envrc') {
      return true;
    }
    return _sensitiveBasenames.contains(name);
  }

  /// Resolves a client-supplied `?path=` value to an absolute workspace
  /// path, or returns `null` if it escapes the workspace root.
  ///
  /// The real gateway resolves relative paths against its root and 403s
  /// anything that lands outside it; artifact chips normally carry the
  /// absolute `resolved_path` a `write_file` reported, but an `@file:` ref
  /// (`tui_gateway/methods_prompt.py`'s format, which the detector also
  /// recognizes) is workspace-relative, so both forms have to work.
  static String? resolve(String requested) {
    final trimmed = requested.trim();
    if (trimmed.isEmpty) return null;
    final joined = trimmed.startsWith('/')
        ? trimmed
        : '$workspaceRoot/${trimmed.startsWith('./') ? trimmed.substring(2) : trimmed}';

    final resolved = <String>[];
    for (final segment in joined.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (resolved.isEmpty) return null;
        resolved.removeLast();
        continue;
      }
      resolved.add(segment);
    }
    final absolute = '/${resolved.join('/')}';
    if (absolute != workspaceRoot && !absolute.startsWith('$workspaceRoot/')) {
      return null;
    }
    return absolute;
  }

  /// Every file the demo gateway serves, keyed by absolute path.
  ///
  /// [now] is the server's boot time: the reports are dated relative to it
  /// (same convention as every other fixture builder) so a reviewer opening
  /// the app in 2027 doesn't find a write-up about a week in 2026.
  static Map<String, DemoWorkspaceFile> buildIndex(DateTime now) => {
    for (final file in build(now)) file.path: file,
  };

  static List<DemoWorkspaceFile> build(DateTime now) {
    final end = now.subtract(const Duration(days: 2));
    final start = end.subtract(const Duration(days: 6));
    final range = '${_monthDay(start)} – ${_monthDay(end)}, ${end.year}';
    return [
      DemoWorkspaceFile(
        path: latencyReviewMarkdownPath,
        mimeType: 'text/markdown',
        contents: _latencyReviewMarkdown(range),
      ),
      DemoWorkspaceFile(
        path: latencyReportHtmlPath,
        mimeType: 'text/html',
        contents: _latencyReportHtml(range),
      ),
      // Exists, and is refused with a 403 — see [sensitivePath].
      DemoWorkspaceFile(
        path: sensitivePath,
        mimeType: 'application/octet-stream',
        contents: 'HERMES_GATEWAY_TOKEN=not-a-real-token\n',
      ),
    ];
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// `Jun 3`-style label. Deliberately not `intl` — this file has no Flutter
  /// dependency and the demo workspace is English-only seed content anyway
  /// (it is prose written by a fictional agent, not app chrome, so it is not
  /// localized and adds no l10n keys).
  static String _monthDay(DateTime t) => '${_months[t.month - 1]} ${t.day}';

  // ── The Markdown artifact ────────────────────────────────────────────
  //
  // Written to exercise the viewer's Markdown renderer across the features
  // it actually supports: headings at three levels, bullet and ordered
  // lists, a fenced code block, inline code spans, a table with alignment,
  // a blockquote, emphasis, and a thematic break. No images: the viewer
  // neutralizes any image whose source is not a self-contained `data:` URI
  // (`sanitizeMarkdownArtifact`), and a deliberately-neutralized image would
  // read as a rendering bug to a reviewer rather than as the security
  // measure it is.

  static String _latencyReviewMarkdown(String range) =>
      '''
# Gateway latency review — $range

Compiled from seven days of gateway access logs. **Headline: p95 response
time is up 41% week over week**, and the regression is confined to a single
endpoint.

> Sample workspace note: this file was produced by the scripted agent inside
> the Hermes Go demo sandbox. The numbers are illustrative — there is no real
> service behind them.

## What changed

- `POST /api/sessions/{id}/chat` p95 moved from **412 ms** to **581 ms**
- Every other route stayed inside its usual band (within 8%)
- Error rate was flat at 0.12%, so this is a latency regression, not a
  failure regression
- The shift starts mid-week and does *not* correlate with traffic volume

### Endpoint breakdown

| Endpoint | p50 | p95 | p99 | Change in p95 |
| --- | ---: | ---: | ---: | ---: |
| `POST /api/sessions/{id}/chat` | 96 ms | 581 ms | 1,204 ms | +41% |
| `GET /api/sessions` | 18 ms | 44 ms | 71 ms | +3% |
| `GET /api/sessions/{id}/messages` | 24 ms | 63 ms | 118 ms | -2% |
| `GET /api/skills` | 9 ms | 21 ms | 33 ms | +1% |
| `POST /auth/password-login` | 41 ms | 88 ms | 140 ms | 0% |

### Where the time goes

Splitting the slow endpoint by phase:

1. **Prompt assembly** — 34 ms, unchanged
2. **Model call** — 402 ms, unchanged
3. **Transcript persistence** — 138 ms, up from 12 ms

Phase 3 is the whole regression. It lines up with the day the transcript
table grew past ten million rows, which is the point the planner stops using
the index on `session_id` and starts scanning.

## Reproducing it

The slow path shows up on a warm cache after roughly thirty turns:

```bash
hermes-cli bench chat \\
  --session demo-latency-review \\
  --iterations 50 \\
  --phases assembly,model,persist \\
  --report p50,p95,p99
```

If `persist` comes back above ~40 ms, this is the same regression.

Discard the first five minutes after a deploy: the cache is cold and p95 is
not comparable until it warms up.

## Recommendation

- Add a composite index on `(session_id, created_at)` — the query orders by
  `created_at` and the single-column index cannot serve both
- Backfill in a migration window; the table is large enough that an online
  index build is the safer option
- Re-run the bench above afterwards and expect p95 near **450 ms**

---

*Generated by the `latency-review` skill. Companion report:
`latency-report.html`.*
''';

  // ── The HTML artifact ────────────────────────────────────────────────
  //
  // The viewer wraps untrusted HTML in a document whose `<head>` it controls
  // and applies a strict CSP: `default-src 'none'`, assets only from `data:`,
  // `style-src 'unsafe-inline'`, `connect-src 'none'`. JavaScript is off
  // unless the user explicitly turns it on for one viewing. So this document
  // is deliberately:
  //
  //  * styled with one inline `<style>` block — no external stylesheet, no
  //    remote webfont (system font stack only),
  //  * illustrated with an inline `<svg>` element rather than an `<img>` —
  //    inline SVG is part of the document, so it needs no `img-src` grant and
  //    fetches nothing,
  //  * completely static: every number is in the markup, so it reads
  //    identically with scripts disabled (which is how a reviewer will see
  //    it).
  //
  // It is written as a full document (doctype, `<html>`, `<head>`) because
  // that is what an agent actually emits; the sandbox nests it inside its own
  // `<body>` and the parser drops the duplicate structural tags, keeping the
  // `<style>` and the content. A dark-mode block is included because the
  // viewer may well be on a dark background.

  static String _latencyReportHtml(String range) =>
      '''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Gateway latency report</title>
<style>
  :root {
    --bg: #ffffff;
    --card: #f6f7f9;
    --ink: #16181d;
    --muted: #5f6672;
    --line: #e2e5ea;
    --accent: #3b62d9;
    --warn: #c2410c;
    --ok: #15803d;
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #14161a;
      --card: #1d2026;
      --ink: #eceef2;
      --muted: #9aa2b1;
      --line: #2c3039;
      --accent: #7d9bff;
      --warn: #fb923c;
      --ok: #4ade80;
    }
  }
  body {
    margin: 0;
    padding: 20px 16px 36px;
    background: var(--bg);
    color: var(--ink);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
      "Helvetica Neue", Arial, sans-serif;
    line-height: 1.5;
    -webkit-text-size-adjust: 100%;
  }
  .eyebrow {
    text-transform: uppercase;
    letter-spacing: 0.08em;
    font-size: 11px;
    font-weight: 700;
    color: var(--accent);
    margin: 0 0 6px;
  }
  h1 { font-size: 22px; line-height: 1.25; margin: 0 0 4px; }
  .range { color: var(--muted); font-size: 13px; margin: 0 0 20px; }
  .cards { display: flex; flex-wrap: wrap; gap: 10px; margin: 0 0 22px; }
  .card {
    flex: 1 1 130px;
    background: var(--card);
    border: 1px solid var(--line);
    border-radius: 10px;
    padding: 12px 14px;
  }
  .card .label {
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--muted);
  }
  .card .value { font-size: 24px; font-weight: 700; margin-top: 2px; }
  .delta { font-size: 12px; font-weight: 600; }
  .delta.up { color: var(--warn); }
  .delta.flat { color: var(--ok); }
  h2 {
    font-size: 15px;
    margin: 26px 0 10px;
    padding-bottom: 6px;
    border-bottom: 1px solid var(--line);
  }
  figure { margin: 0 0 4px; }
  figcaption { font-size: 12px; color: var(--muted); margin-top: 6px; }
  table { width: 100%; border-collapse: collapse; font-size: 13px; }
  th, td { padding: 7px 6px; border-bottom: 1px solid var(--line); }
  th { text-align: left; color: var(--muted); font-weight: 600; }
  td.num { text-align: right; font-variant-numeric: tabular-nums; }
  code {
    font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
    font-size: 12px;
    background: var(--card);
    border: 1px solid var(--line);
    border-radius: 4px;
    padding: 1px 4px;
  }
  .bar { height: 8px; border-radius: 4px; background: var(--accent); }
  .bar.slow { background: var(--warn); }
  ol { margin: 0; padding-left: 20px; }
  li { margin-bottom: 6px; }
  footer {
    margin-top: 26px;
    padding-top: 12px;
    border-top: 1px solid var(--line);
    font-size: 12px;
    color: var(--muted);
  }
</style>
</head>
<body>
  <p class="eyebrow">Hermes gateway</p>
  <h1>Latency report</h1>
  <p class="range">$range &middot; 7 days &middot; 1.2M requests</p>

  <div class="cards">
    <div class="card">
      <div class="label">p50</div>
      <div class="value">96 ms</div>
      <div class="delta flat">+2% WoW</div>
    </div>
    <div class="card">
      <div class="label">p95</div>
      <div class="value">581 ms</div>
      <div class="delta up">+41% WoW</div>
    </div>
    <div class="card">
      <div class="label">Errors</div>
      <div class="value">0.12%</div>
      <div class="delta flat">flat</div>
    </div>
  </div>

  <h2>p95 by day</h2>
  <figure>
    <svg viewBox="0 0 320 96" width="100%" height="96"
         role="img" aria-label="p95 latency by day, rising after day four">
      <polyline points="8,72 60,70 112,66 164,40 216,28 268,24 312,22"
                fill="none" stroke="currentColor" stroke-width="2.5"
                stroke-linecap="round" stroke-linejoin="round"
                opacity="0.85"></polyline>
      <line x1="0" y1="88" x2="320" y2="88" stroke="currentColor"
            stroke-width="1" opacity="0.25"></line>
      <circle cx="164" cy="40" r="4" fill="currentColor"></circle>
      <text x="150" y="30" font-size="10" fill="currentColor"
            opacity="0.7">deploy</text>
    </svg>
    <figcaption>
      The step change lands on day four, the same day the transcript table
      passed ten million rows.
    </figcaption>
  </figure>

  <h2>By endpoint</h2>
  <table>
    <thead>
      <tr>
        <th>Endpoint</th>
        <th class="num">p95</th>
        <th>Share of budget</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td><code>POST /sessions/{id}/chat</code></td>
        <td class="num">581 ms</td>
        <td><div class="bar slow" style="width: 100%"></div></td>
      </tr>
      <tr>
        <td><code>GET /sessions/{id}/messages</code></td>
        <td class="num">63 ms</td>
        <td><div class="bar" style="width: 11%"></div></td>
      </tr>
      <tr>
        <td><code>GET /sessions</code></td>
        <td class="num">44 ms</td>
        <td><div class="bar" style="width: 8%"></div></td>
      </tr>
      <tr>
        <td><code>GET /skills</code></td>
        <td class="num">21 ms</td>
        <td><div class="bar" style="width: 4%"></div></td>
      </tr>
    </tbody>
  </table>

  <h2>Recommended next steps</h2>
  <ol>
    <li>Add a composite index on
      <code>(session_id, created_at)</code>.</li>
    <li>Build it online — the table is too large for a blocking migration.</li>
    <li>Re-run the bench and confirm p95 lands near 450 ms.</li>
  </ol>

  <footer>
    Generated by the <code>latency-review</code> skill inside the Hermes Go
    sample workspace. Figures are illustrative; no real service was measured.
  </footer>
</body>
</html>
''';
}
