# Hermes Go — RST-style analysis pass

**Method:** Rapid Software Testing (Bach/Bolton). Static/analytical pass only —
no device, no simulator, no `flutter run`. Coverage modeled against SFDIPOT
(Structure/Function/Data/Interfaces/Platform/Operations/Time) and CRUSSPIC
STMPL, oracles selected per finding from the FEW HICCUPPSS consistency
categories (named inline as `[oracle: History]` etc.), risk framed as the
four-part story (someone / harm / vulnerability / threat), work organized as
chartered sessions per the mobile pack's technique priority (Flow → Risk →
Scenario → ...). This document is my own analysis of this codebase; it does
not reproduce the source material.

**Who matters / mission:** the user is a Hermes gateway operator who wants a
phone client that doesn't lose their messages or lie about connection state,
and the immediate decision this report informs is "is this build safe to
resubmit to App Review." Danger: nothing here touches a live gateway, a real
device, or any store account — read-only analysis of the checked-out tree at
`mobile-gateway` HEAD.

**Every finding below is tagged `Confirmed` (I can point at the exact code
path and trace the failure) or `Suspected` (plausible from the code, needs a
device run to confirm) — with manual repro steps given for every `Suspected`
item.**

---

## Charter 1 — Is the "4018 misclassified as offline" bug class actually closed?

**Risk:** the task brief names one specific fixed bug: a gateway rewind error
(code 4018) misclassified as an offline condition and queued forever. Risk
heuristic: a fix for one symptom of a class of bug rarely closes the whole
class. I went looking for siblings.

**Examined:** `GatewayWsClient._handleFrame` (error propagation),
`SessionSyncRepository.sendMessage` / `_sendViaGateway` / `flushPendingOverWs`
(the terminal-vs-retryable error classification), `AppDatabase.bumpOpFailure`
(outbox retry policy), and the gateway-side error taxonomy that produces the
messages the client has to classify (`tui_gateway/methods_prompt.py`,
`tui_gateway/methods_tools.py`).

**What I found — Confirmed:**

The gateway uses JSON-RPC error code `4018` as a generic "fail-closed
validation" code, reused across many semantically permanent (non-retryable)
conditions: `tui_gateway/methods_prompt.py:506` — *"target user message is no
longer in session history"* (a stale rewind target); `methods_tools.py:711,729`
*"no previous user message to retry"*; `methods_tools.py:738` *"last user
message is empty"*; `methods_tools.py:870` *"no user messages to undo"*;
`methods_tools.py:521,524` bundle dispatch/load failures; and others. All of
these share one property: resubmitting the identical request will fail
identically forever — none of them are network/offline conditions.

On the wire, `GatewayWsClient._handleFrame`
(`lib/core/network/gateway_ws_client.dart:232-236`) discards the JSON-RPC
error `code` entirely and keeps only the `message` string:

```dart
if (map['error'] != null) {
  final err = map['error'];
  final msg = err is Map ? '${err['message'] ?? err}' : '$err';
  pending.completeError(StateError(msg));
```

The only place the client tells a permanent server-side rejection apart from
a transient/offline one is `SessionSyncRepository._isSessionNotFound`
(`lib/core/sync/session_sync_repository.dart:698-703`), which matches three
literal substrings: `"session not found"`, `"unknown session"`, `"no such
session"`. This is the fix the brief describes — and it is real, and it does
work for that one message shape (verified at `session_sync_repository.dart:
1510-1522`, which persists a durable terminal error instead of queuing when
`_isSessionNotFound` matches).

It does **not** match `"target user message is no longer in session
history"` — the actual message text `tui_gateway/methods_prompt.py:506`
returns for a stale rewind target, which is precisely the rewind scenario the
fix is supposed to cover. Nor does it match any of the other 4018 message
shapes above. When `prompt.submit` is rejected with one of these,
`_sendViaGateway` (`session_sync_repository.dart:1998-2008`) has no `catch`
of its own around the `rt.request('prompt.submit', ...)` call (only a
`finally` at line 2115) — the raw `StateError` propagates to `sendMessage`'s
retry loop (`session_sync_repository.dart:1496-1507`), which retries once,
then — since `_isSessionNotFound` returns false — falls through to the
generic offline-queue path at `session_sync_repository.dart:1524-1586` and
enqueues a `PendingOp`.

That op is later replayed by `flushPendingOverWs` →
`_runOpOverWs` → `_sendViaGateway` again (`session_sync_repository.dart:
2246-2276, 2291-2326`), submitting the byte-identical `prompt.submit`. It
fails identically. `flushPendingOverWs`'s catch-all
(`session_sync_repository.dart:2268-2270`) calls
`AppDatabase.bumpOpFailure` (`lib/core/db/app_database.dart:334-352`), which
increments `attemptCount` and reschedules `nextAttemptAt` with a capped
backoff (`(attemptCount+1).clamp(1,8) * 5` seconds, i.e. max ~40s) — **there
is no maximum attempt count and no give-up.** The op is retried forever, on
a fixed short cycle, every time the socket is live.

The user-visible result is exactly the bug class already fixed once: the
composer shows *"Saved on phone — waiting for live WebSocket (Settings may
show HTTPS only)."* (`app_localizations_en.dart:544-545`, wired at
`session_chat_screen.dart:1387-1388`) and a persistent "Queued for sync to
gateway…" chip (`app_localizations_en.dart:548`, `session_chat_screen.dart:
1707-1716`) — while the WebSocket is, in fact, live and connected. The
message never sends, no permanent error ever appears, and the outbox retries
silently forever.

**Confirmed reachability (not just theoretical):** the client itself invokes
the rewind path. Edit and Retry/Regenerate in the chat UI both call
`sendMessage(..., truncateBeforeUserOrdinal: ...)` (reachable at
`session_chat_screen.dart:795` and `:858`, plumbed through to
`prompt.submit`'s `truncate_before_user_ordinal` param at
`session_sync_repository.dart:2004`) — the exact parameter whose stale value
produces the gateway's 4018 in `methods_prompt.py:506`. A user who edits or
retries an older message after the session has been rewound elsewhere (a
second device, a gateway restart re-aligning row ids — see
`gateway/methods_prompt.py` comments around row-id staleness) hits this.

**Suspected — manual repro to try:**
1. Open a session on two connected clients (or use `/undo` / a prior
   rewind on Desktop) so the mobile app's cached user-message ordinal is
   stale relative to the gateway's transcript.
2. On the phone, use Edit or Retry on an older message in that session.
3. Expect: composer shows "Saved on phone — waiting for live WebSocket" and
   a "Queued for sync" chip, indefinitely, while Settings shows the socket
   as Live.

**Oracle:** `[History]` — this is the same failure shape as the bug the
project already fixed and described in its own commit history this week;
`[Product]` — the fix's own code comment at `session_sync_repository.dart:
1510-1513` states the design intent ("a connected gateway explicitly saying
the [operation] cannot be [done] is not an offline condition... queuing here
creates a misleading banner") — the code around it doesn't fully deliver on
that intent for sibling error messages.

**Severity: High — recommend blocking or fast-following.** This is a
silent, permanent data-non-delivery bug (not data corruption, but a "sent"
message that never sends, with no error ever surfacing) reachable through a
documented, ordinary UI action (Edit/Retry), and it's the same failure class
the team already spent effort finding and fixing once. There is no test
coverage for it: `grep` across `test/session_sync_test.dart` for
`isSessionNotFound`, `4018`, `rewind`, `ordinal`, or `flushPendingOverWs`
returns nothing.

**Fix direction (not implemented, out of scope for this pass):** stop
discarding the JSON-RPC error `code` in `GatewayWsClient._handleFrame`;
classify by code (any 4xxx application-error code from a *pre-stream*
`prompt.submit` rejection is definitionally a validation failure, never an
offline condition) rather than by matching message substrings, and give the
outbox a real give-up threshold with a surfaced terminal error either way.

---

## Charter 2 — Background/killed-process delivery for the auth mode the app actually ships

**Risk:** DESIGN.md's own background-catch-up table
(`DESIGN.md:162-174`) claims: *"Process killed by OS → Workmanager one-off /
rare periodic poll flushes outbox + checks watches."* README states the
mobile app has no `API_SERVER_KEY` mode in practice — the shipped, documented
auth path is username/password → session cookies (`README.md:114-117`,
`DESIGN.md:53-67`, `AGENTS.md`'s entire WebSocket-auth section). I checked
whether the documented background flush claim is true for that auth mode.

**Examined:** `BackgroundSync.run` (`lib/core/sync/background_sync.dart:
106-208`), `SessionSyncRepository.flushOutbox` vs `.flushPendingOverWs`
(`session_sync_repository.dart:2221-2276`).

**What I found — Confirmed:** `BackgroundSync.run` constructs the API client
conditionally on legacy-token auth only:

```dart
// background_sync.dart:114-117
final api = profile.hasLegacyToken
    ? HermesApi(baseUrl: profile.baseUrl, apiKey: profile.apiKey)
    : null;
```

For a password/session-cookie profile (`ConnectionProfile.authMode ==
'session'`, the only auth mode the app's connect flow produces for a
password gateway — see `connect_screen.dart:171-199`), `api` is `null`. The
background pass then calls only `sync.flushOutbox()`
(`background_sync.dart:145`), never `sync.flushPendingOverWs()`. But
`flushOutbox` itself is a guaranteed no-op without an API client:

```dart
// session_sync_repository.dart:2221-2224
Future<void> flushOutbox() async {
  final api = _api;
  if (api == null || _flushing) return;
```

So for the documented, primary auth mode, the WorkManager background task —
the app's own documented "last resort" recovery for a killed process — pulls
sessions, checks watches, and reconciles job status, but **silently never
attempts to deliver a queued chat message or session-create op.** It will
even report success: `background_sync.dart:193-201` only sends a "Hermes
synced / N pending actions sent" notification when `flushedOps > 0`, and
`flushedOps` is computed from a no-op flush, so it's always 0 for this auth
mode — the notification path is silently dead too, and nothing signals the
difference between "nothing was queued" and "something was queued and
couldn't be sent."

**Consequence:** a queued outbound message (from Charter 1's scenario, or
simply from being offline when the user hit send) will *not* be delivered by
the OS-scheduled background task while the app is backgrounded or killed —
only by the foreground WebSocket reconnect path
(`gateway_realtime.dart:660-667`, `session_sync_repository.dart:1547,1577`).
If the user backgrounds or force-quits the app right after a message queues,
it sits until they next foreground the app and the socket reconnects, not
within the next 15-minute background window as DESIGN.md claims.

**Oracle:** `[Claims]` — DESIGN.md's own background-catch-up table directly
contradicts this code path for the auth mode the app ships;
`[Purpose]` — the whole reason WorkManager exists per the header comment on
`background_sync.dart:17-22` is to cover exactly this "process killed"
case, and it doesn't, for the only auth mode in the connect flow.

**Severity: High.** Combined with Charter 1 (an outbox entry that can never
succeed) and Charter 4 (no draft persistence), this closes off every non-
foreground recovery path for a pending user message at once. Individually it
is "a message sends a bit later than documented," which is tolerable; the
gap is that nothing tells the user this is happening, and DESIGN.md
describes a safety net that isn't wired up for the app's actual auth mode.

**Suspected — manual repro:** send a message while offline (airplane mode)
on a password-auth gateway, then force-quit the app (not just background
it), stay offline→online without reopening the app for >15 minutes, and
check whether the message ever arrives without the user reopening the app.
Expect: it does not, and no notification explains why.

---

## Charter 3 — Draft durability across process death

**Risk:** the mobile pack's top risk #2 (process death vs. backgrounding) —
these are different code paths, and testers who only background-and-resume
never exercise the one that matters. Applied here to the most valuable
piece of ephemeral state in a chat app: text the user has typed but not yet
sent.

**Examined:** `SessionChatScreen`'s composer state
(`lib/features/sessions/session_chat_screen.dart`), searched the whole tree
for any persistence of in-progress composer text.

**What I found — Confirmed:** the composer's text lives in a plain
`TextEditingController _composer` on `SessionChatScreen`'s `State`
(`session_chat_screen.dart:129`), with no backing store. A repo-wide search
for `RestorationMixin`, `restorationId`, or any draft-related persistence key
(`draft`, `Draft`, `composerDraft`) returns nothing anywhere in `lib/`. This
is a deliberate, correctly-scoped fix from this week's commit `fc3aef1fe`
("Drafts typed mid-stream survive the turn completing") — but that fix is
about *in-memory* survival across a stream completing while the widget stays
mounted, not survival across the widget (and process) being torn down.

**Consequence:** the OS reclaiming the app's process while backgrounded — a
routine, not exceptional, mobile operating condition — silently erases
whatever the user had typed and not yet sent, with no warning at any point
(not on backgrounding, not on relaunch). Attachments picked but not yet sent
(`_attachments`, same screen, same lack of persistence) are lost the same
way.

**Oracle:** `[World]` — every comparable messaging/chat client (iMessage,
WhatsApp, Slack, and the Claude/Codex mobile apps this app explicitly cites
as its UX reference in DESIGN.md's principle 5) preserves an unsent draft
across a relaunch; `[Purpose]` — DESIGN.md's product principle 1 is "Host is
source of truth... never invents sessions the server doesn't know about,"
but says nothing that would excuse losing *client-side, not-yet-submitted*
input, which is squarely the phone's own responsibility, not the host's.

**Severity: Medium.** Not data corruption and not a lie (nothing claims the
draft is saved), but a believable, easy-to-hit loss of user work with zero
runtime signal, on the RST mobile pack's #1-ranked mobile-specific risk
category (Reliability under process death).

**Suspected — manual repro:** type a non-trivial message in an existing
session, background the app, use several other memory-heavy apps to
encourage the OS to reclaim Hermes Go's process (or use Xcode's
"Simulate Memory Warning" / Android's `adb shell am kill`), then reopen
Hermes Go via the home screen (not the app switcher) and check the composer.

---

## Charter 4 — Credential-at-rest: the Application Support gateway-book mirror

**Risk:** security/privacy — token and cookie handling was named explicitly
as an area of interest. DESIGN.md's security notes state: *"Dashboard
cookies in platform secure storage only"* (`DESIGN.md:222`). I checked
whether that's the complete picture for everything the app persists to
survive an upgrade install.

**Examined:** `ConnectionStore` mirror mechanism
(`lib/core/network/connection_store.dart:123-172, 278-282`),
`ConnectionProfile`/`GatewayBook` serialization
(`lib/core/models/hermes_models.dart:11-136, 198-204`).

**What I found — Confirmed:** cookies genuinely only ever go through
`SecureCookieStorage`, which is Keychain/EncryptedSharedPreferences-backed
(`lib/core/network/secure_cookie_storage.dart`) — that part of the claim
holds. But the *gateway book* (the list of saved `ConnectionProfile`s,
including the `apiKey` field) is dual-written: once to secure storage
(`connection_store.dart:280`, correct), and once as a **plaintext JSON file**
in the app's ordinary Application Support directory, unencrypted beyond
whatever the OS filesystem provides:

```dart
// connection_store.dart:136-145
Future<void> _writeMirror(GatewayBook book) async {
  final file = await _mirrorFile();     // gateway_book_v2.json, App Support
  ...
  await file.writeAsString(jsonEncode(book.toJson()), flush: true);
```

`ConnectionProfile.toJson()` (`hermes_models.dart:102-113`) unconditionally
includes `apiKey` in that plaintext blob:

```dart
Map<String, dynamic> toJson() => {
  'id': id, 'baseUrl': baseUrl, 'apiKey': apiKey, 'authMode': authMode, ...
```

`apiKey` is documented as "rare legacy token mode" (`hermes_models.dart:10,
34`), and is empty for the password/session flow the app's connect screen
actually produces — so *for the shipped, documented auth path* this mirror
is inert (no secret in it beyond `username`, `baseUrl`, `label`). But the
model still explicitly supports and serializes a bearer-equivalent secret
(`dashboard_client.dart:79-80` sends it as `Authorization: Bearer
${profile.apiKey}`) into a file whose entire purpose (per its own doc
comment, `connection_store.dart:19-20`) is to survive precisely the
conditions — app deletion from Application Support, keychain hiccups — where
"survives" and "is protected" are two different properties. The mirror's
existence is intentional and necessary for the durability guarantee the app
promises (`AGENTS.md`'s "Connection persistence" section); its content isn't
scoped to exclude secrets.

**Oracle:** `[Claims]` — DESIGN.md states cookies-in-secure-storage as if it
were the whole credential-storage story; `[Standards]` — storing any
bearer-equivalent token in an app-sandbox plaintext file rather than the
platform secure-storage API it's available right next to is inconsistent
with the app's own stated practice for the *other* credential type it
handles (cookies) two files away.

**Severity: Medium (Low in practice today, since the field is unused by the
shipped auth flow; would become High the moment legacy-token mode is
exercised, e.g. a future `open`+`apiKey` gateway type, or if a user hand-fills
`apiKey` via any future edit-profile screen).** Recommend either dropping
`apiKey`/other secrets from `GatewayBook.toJson()`'s mirror path specifically
(keep it in the secure-storage copy only) or documenting the exception in
DESIGN.md so the claim is accurate.

**Secondary, related, minor finding:** `ConnectionStore.keychainAccessGroup`
(`connection_store.dart:38`, value `4WF3G6AN6G.ai.hermes.go`) is declared but
never referenced anywhere in `lib/` or `ios/` — `durableSecureStorage()`'s own
doc comment (`connection_store.dart:67-72`) explains the group is
*intentionally* not used ("a mismatched keychain-access-groups entitlement
crashes/fails reads on device"). DESIGN.md's persistence table
(`DESIGN.md:111`) still describes the iOS Keychain layer as "`accountName` +
access group stable," which reads as if group-scoped (e.g. widget/extension)
sharing were wired up. `[History]` oracle: a maintainer reading the constant
and the design doc without reading the code comment would reasonably expect
keychain sharing across an app extension that doesn't exist yet. Cosmetic —
does not block submission — but worth pruning the dead constant or fixing
the doc.

---

## Charter 5 — Logging audit: does anything sensitive reach `debugPrint`?

**Risk:** "are secrets or message content leaking into device logs" was
named explicitly. `debugPrint` output is visible via `flutter logs` /
Xcode console / `adb logcat` on a connected dev machine, and on some older
Android versions historically reached other apps with log-read permission.

**Examined:** all 154 `debugPrint` call sites across `lib/` (full listing
grepped and read in context for `lib/core/network`, `lib/core/sync`,
`lib/core/demo`).

**What I found — Confirmed, clean:** the app is deliberately careful here.
`GatewayWsClient.redactUrl` (`gateway_ws_client.dart:64-75`) strips
`ticket`/`token` query params before every URL that reaches `debugPrint`, and
every WS-URL log site in `gateway_realtime.dart` (lines 616, 661) routes
through it. `DashboardClient`'s cookie-related log
(`dashboard_client.dart:44-48`) prints cookie *names* only, never values.
Chat-content-adjacent logs (e.g. `session_sync_repository.dart:349, 470, 532,
596, 631`) log session ids, model ids, and boolean flags — not message
`content`. I did not find a single `debugPrint` call that includes
`input`, `content`, `password`, `apiKey`, or a raw cookie/ticket value
anywhere in the 154 sites.

**One residual note (Suspected, low severity):** `debugPrint` calls that
interpolate a raw exception (`'$e'`) after a failed RPC could theoretically
echo part of a request payload if a future gateway error message ever
echoes the offending prompt text back (some validation errors, e.g. "last
user message is empty," are unlikely to, but I did not enumerate every
current or future gateway error string for this property). Not a finding
against current code, just a boundary condition worth keeping in mind if the
gateway's error-message shapes change. `[Purpose]` oracle: logging is for
debugging, not user data — the current code respects that; the coupling to
gateway-controlled error text is the only place that boundary isn't
enforced by the client itself.

**Severity: informational — no defect found.** This charter came back
clean; I'm reporting the coverage, not a bug, per the report's own honesty
requirement (a clean charter is still worth stating explicitly, and it
constrains where else I looked for the "any other lies" instruction).

---

## Charter 6 — App Review path: does the bundled demo sandbox hold up?

**Risk:** highest-consequence charter for the immediate goal — this app was
already rejected once (Guideline 2.1(a)) and the demo sandbox is the fix; if
it fails in front of a reviewer, the resubmission fails again.

**Examined:** `DemoGatewayServer` (`lib/core/demo/demo_gateway_server.dart`,
967 lines — read request dispatch, error handling, and startup/shutdown in
full; sampled the RPC handler bodies), `demo_mode.dart`, and the connect-
screen interception point (`connect_screen.dart:81-108`).

**What I found — Confirmed, largely a clean bill:**

- **Host interception happens before any network call**, matching
  `APP_REVIEW_NOTES.md`'s claim that `demo.hermes.go` never reaches DNS:
  `connect_screen.dart:92-108` checks `isDemoGatewayUrl` and boots the
  loopback server *before* `GatewayAuthClient.probe(baseUrl)` is ever called.
  `[Claims]` oracle satisfied — the documented behavior matches the code.
- **The server binds loopback-only** (`InternetAddress.loopbackIPv4, 0`,
  `demo_gateway_server.dart:117`) with an ephemeral port, matching the
  "no network calls leave the device" claim.
- **Every request is wrapped in a top-level catch-all**
  (`demo_gateway_server.dart:160-184`): a malformed request or a bug in any
  one RPC handler returns a generic 500 rather than killing the server for
  the rest of the review session — exactly the defensive posture a
  reviewer-facing sandbox needs. Malformed JSON bodies and bad WS frames are
  separately caught (`:337, :591`) rather than propagating.
- **`start()`/`stop()` are single-flight and idempotent**
  (`demo_gateway_server.dart:60-103`), guarding against the connect-screen
  probe and app-boot rehydration racing to bind two servers.
- **Credentials are exact-match, not guessable-by-accident**: username
  case-insensitive, password exact (`demo_gateway_server.dart:31-35`), and
  any other credentials produce a genuine 401 through the same code path a
  real gateway would use — so the login-failure UI is exercised, not
  bypassed.

**Suspected — not verified by a run:** I did not execute the demo agent
script (`demo_agent_script.dart`) or trace its scripted tool-call event
sequence against what `session_chat_screen.dart`'s stream-event parser
expects turn-by-turn (the "reasoning, tool-start/tool-complete, and streamed
text" tour APP_REVIEW_NOTES.md promises at step 2). A mismatch there
(demo script emits an event shape the real-gateway parser doesn't expect, or
vice versa) would only surface at runtime and is exactly the class of thing
a static read can miss — this is the single highest-value place I'd spend
the next hour of *dynamic* testing before resubmission, precisely because
it's the one path a reviewer is certain to exercise.

**Severity: no confirmed defect; the one Suspected gap above is worth a
manual run before resubmission** given the review history.

---

## Charter 7 — Protocol skew: defensive parsing survey

**Risk:** named directly in the task — "the client parses gateway JSON
defensively in places and not others... where would it crash vs. degrade?"
This charter is a targeted sweep of `fromJson` factories and RPC-result
readers, specifically hunting for hard casts (`as String`, `as int` without
a type guard) on gateway-controlled data.

**Examined:** every model `fromJson` in `hermes_models.dart` and
`dashboard_client.dart`; RPC-result readers in `gateway_realtime.dart` and
`session_sync_repository.dart` (via `grep` for ` as String`, ` as int`,
` as bool`, ` as Map`, ` as List` across `lib/core/network` and
`lib/core/sync`, then manually inspected every hit for whether the cast
target is gateway-controlled or the app's own previously-serialized data).

**What I found:**

The overwhelming majority of the codebase is careful: `HermesSession`,
`HermesMessage`, `HermesJob`, `SlashCommand`, `HermesSkill`,
`ModelOptionProvider`/`ModelCapabilities` all go through `_asString`/`_asInt`
helpers (`hermes_models.dart:642-654`) that type-check before casting and
degrade to `null` rather than throwing. `HermesJob.fromJson`
(`hermes_models.dart:558-608`) explicitly comments on this: *"Never `as
String?` cast — non-string name/prompt would throw and drop the entire jobs
list"* — a defensive pattern applied consistently.

**One Confirmed exception:** `GatewayRealtime.listSessionsRpc`
(`gateway_realtime.dart:903-926`), the WS-path session-list reader used when
the socket is up, builds `HermesSession` directly from raw RPC JSON with hard
casts:

```dart
// gateway_realtime.dart:911-921
HermesSession(
  id: '${item['id'] ?? ''}',
  title: item['title'] as String?,        // throws if title is non-null, non-String
  preview: item['preview'] as String?,
  startedAt: item['started_at']?.toString(),
  messageCount: item['message_count'] is int
      ? item['message_count'] as int
      : int.tryParse('${item['message_count']}'),
  source: item['source'] as String?,
),
```

Unlike every other model in the codebase, `title`/`preview`/`source` here
are unguarded `as String?` casts against gateway-supplied JSON — if a future
gateway version ever sends a non-string `title` (e.g. a structured/localized
title object, a plausible protocol evolution), this throws a `TypeError`
inside the list comprehension. It doesn't crash the app: the whole method is
wrapped in a `try { ... } catch (_) { return _sessionSync.loadSessionsLocal();
}` (`:922-925`), so it silently falls back to the stale local cache — but
that `catch (_)` has **no `debugPrint`**, unlike the rest of the codebase's
consistent pattern of logging every other silent fallback. A protocol
mismatch here is invisible: the session list just quietly stops updating
over WS with zero trace in the logs, until the next successful pull
papers over it.

**Oracle:** `[Product]` — this diverges from the file's own established
sibling pattern (every other similar catch in this codebase, e.g.
`session_sync_repository.dart:174-179`, logs via `debugPrint` before
degrading); `[History]` — `hermes_models.dart:558-563`'s comment shows the
team is already aware of exactly this failure mode and had fixed it there.

**Severity: Low.** Graceful degradation, not a crash — but it's the one
place in the survey where the "crash vs. degrade" line the task asked about
actually depends on a JSON shape the client doesn't control, and the
silent-catch means a real protocol-skew incident here would be very hard to
diagnose from a user bug report (no log line, just "the session list is
stale").

**Coverage note:** I did not fuzz or hand-construct malformed gateway
payloads to actually trigger this cast — this is a static read of the
parsing code, not an executed test. I also did not review the Android/Kotlin
or iOS/Swift platform-channel boundary code for equivalent issues (out of
scope for a Dart-focused static pass; flagged under coverage gaps below).

---

## Charter 8 — Testability

**Risk:** the task's own framing — code that makes itself hard to verify
predicts where bugs hide, and that's a finding worth reporting on its own
merit, independent of any specific bug.

**Examined:** test suite composition (`test/*.dart`, 18 files), and whether
the bugs found in Charters 1–4 have any test surface at all.

**What I found:**

- **Positive:** the test suite already targets several of the exact classes
  of bug this pass is looking for — `ws_backoff_test.dart`,
  `completion_errors_test.dart`, `session_chat_autoscroll_test.dart`,
  `single_flight_test.dart`, `gateway_book_test.dart` all read like
  regression tests for specific, previously-found defects (the naming
  matches the fixed-bug list in the task brief closely enough that this is
  clearly an established practice on this project, not an accident).
- **Gap, Confirmed:** `session_sync_test.dart` — the file that would be the
  natural home for Charter 1's finding — has zero references to
  `isSessionNotFound`, `4018`, `rewind`, `truncateBeforeUserOrdinal`,
  `flushPendingOverWs`, or `bumpOpFailure` (checked by direct grep). The
  outbox retry-forever behavior in `AppDatabase.bumpOpFailure`
  (`app_database.dart:334-352`) has no attempt-count ceiling to even write a
  test against — there's no "give up after N" behavior to assert, which is
  itself the testability gap: the code has no observable terminal state for
  a permanently-failing queued op, so a test can only assert "it keeps
  retrying," which is exactly the bug.
- **Structural testability strength:** the outbox, watch store, and
  connection store all read from disk/DB with deterministic, mockable
  interfaces (`AppDatabase`, `ConnectionStore.memory()` constructor at
  `connection_store.dart:31-34` exists specifically for tests) — this is
  good design and is *why* Charter 1 and 2's gaps are fixable without a
  rewrite, just missing test cases.
- **Structural testability weakness:** `BackgroundSync.run`
  (`background_sync.dart:106-208`) constructs its own `ConnectionStore()`,
  `AppDatabase()`, `DashboardClient`, and `WatchStore()` internally with no
  injection seams — there is no test in `test/` that exercises this function
  at all (`grep -rn "BackgroundSync" test/` returns nothing). Charter 2's
  finding (background flush is a no-op for session-cookie auth) would have
  been caught immediately by a single unit test asserting `flushedOps`
  behavior for a session-auth profile with a queued op — the function's own
  design (concrete `new`s, no DI) is why that test doesn't exist yet.

**Oracle:** `[Purpose]` — the mobile pack's testability doctrine explicitly
names "the ability to force process death... from a test harness" and crash
telemetry as the levers this domain needs; this app has neither a background-
task test harness nor (as far as this static pass can see) any crash-
telemetry/remote-log wiring (no Crashlytics/Sentry import found in
`pubspec.yaml` — grepped and confirmed absent), which limits how anyone,
this report included, can *observe* whether Charters 1–4 actually fire on
real devices in the field.

---

## Consolidated findings, ranked

| # | Finding | file:line | Confirmed/Suspected | Severity | Block resubmission? |
|---|---|---|---|---|---|
| 1 | 4018-class validation errors on `prompt.submit` (stale rewind target, empty-message retry, etc.) fall through `_isSessionNotFound`'s narrow text match and get queued forever with a false "will send" message | `session_sync_repository.dart:698-703, 1510-1586, 2246-2276`; `app_database.dart:334-352`; `gateway_ws_client.dart:232-236` | Confirmed (code path); Suspected (device repro) | High | **Recommend fixing before/alongside resubmission** — same bug class the store rejection cycle already burned time on once |
| 2 | Background/killed-process WorkManager task never delivers queued chat/session ops for the password/session-cookie auth mode (the only mode the connect flow produces) | `background_sync.dart:106-208`; `session_sync_repository.dart:2221-2224` | Confirmed | High | Recommend fixing — silent, contradicts DESIGN.md's own documented behavior |
| 3 | Unsent composer draft (and picked-but-unsent attachments) has no persistence; OS process death silently erases it | `session_chat_screen.dart:129`; no restoration code anywhere in `lib/` | Confirmed (no persistence exists); Suspected (device repro of the loss itself) | Medium | Does not block; recommend a fast-follow (SharedPreferences-backed draft save on `didChangeAppLifecycleState`/dispose would close most of the gap cheaply) |
| 4 | `ConnectionProfile.apiKey` (legacy bearer token) is serialized in plaintext to an unencrypted Application Support mirror file, contradicting DESIGN.md's "secure storage only" claim | `connection_store.dart:136-145`; `hermes_models.dart:102-113` | Confirmed | Medium (Low impact today — field unused by shipped auth flow) | Does not block; low urgency given current auth flow, but should be fixed before any legacy-token UI ships |
| 5 | `GatewayRealtime.listSessionsRpc`'s hard `as String?` casts on gateway JSON degrade silently with no log line, unlike every sibling parser in the codebase | `gateway_realtime.dart:903-926` | Confirmed | Low | Does not block |
| 6 | `keychainAccessGroup` constant is dead/unused; DESIGN.md's persistence table reads as if keychain-group sharing is wired up | `connection_store.dart:38, 67-72`; `DESIGN.md:111` | Confirmed | Cosmetic | Does not block |
| 7 | Demo agent-script event shapes vs. the real chat stream parser — not verified end-to-end | `demo_agent_script.dart`; `session_chat_screen.dart` stream handling | Suspected — needs a run | Unknown until tested | **Recommend a manual run through APP_REVIEW_NOTES.md's own review tour before resubmission**, given this app's rejection history is specifically about the reviewer path |
| — | Logging audit (secrets/message content in `debugPrint`) | 154 sites reviewed | Confirmed clean | — | No action |
| — | Demo sandbox loopback binding, host interception order, credential matching, crash isolation | `demo_gateway_server.dart`, `connect_screen.dart:92-108` | Confirmed clean | — | No action |

**Top five by severity, one line each:**
1. The 4018/rewind fix closes one text pattern, not the error class — Edit/Retry on a stale-rewind session still queues forever with a false "will send" message.
2. WorkManager's background catch-up is a documented no-op for the app's only real auth mode — killed-process delivery relies entirely on the user reopening the app.
3. An unsent draft has zero persistence and is silently destroyed by ordinary OS process death.
4. The legacy `apiKey` field writes to a plaintext mirror file, contradicting the app's own "secure storage only" security claim.
5. The demo sandbox's scripted event stream is unverified against the real parser — the one path App Review is guaranteed to exercise.

---

## Three stories

**The product.** Hermes Go is a carefully, defensively built thin client —
the WebSocket reconnect state machine, the outbox, and the JSON parsing are
all written by someone who has clearly been burned by mobile's process-death
and connectivity-flap failure modes before, and it shows in the density of
"why this and not the obvious alternative" comments throughout
`gateway_realtime.dart` and `session_sync_repository.dart`. The specific
bugs this pass found are not evidence of carelessness; they're the next
layer down of the same problem the team already found and partially fixed
once (error taxonomy for terminal-vs-retryable failures), plus one gap in
the safety net whose *existence* is well-documented but whose *coverage* for
this app's actual auth mode isn't, plus one very ordinary mobile-app gap
(draft persistence) that's easy to miss precisely because it never causes a
crash or an error message — just silence.

**How I tested it.** Eight chartered sessions, static-only: I read
`lib/core/network/`, `lib/core/sync/`, `lib/core/demo/`, and targeted slices
of `lib/features/sessions/` and `lib/features/connect/` end to end for the
files most central to the risk list, cross-referenced the gateway-side error
taxonomy in `tui_gateway/methods_prompt.py` and `methods_tools.py` against
the client's error-classification code, checked git history for the
already-fixed bugs to make sure I wasn't re-reporting them, and grepped test
files to establish what is and isn't covered. I prioritized Flow and Risk
technique (per the mobile pack's own priority order) — tracing full
send/queue/retry/background sequences rather than testing isolated
functions — because that's where this app's own commit history says its
real bugs live.

**How good was this testing.** Shallow along several axes I want to name
explicitly rather than let the report's confidence imply otherwise:

- **No dynamic testing at all.** Every "Confirmed" finding is a traced code
  path, not a witnessed failure — per the vault's own distinction, these are
  `static`, not `observed`, findings. I have high confidence the code
  reads the way I describe; I have no direct evidence these paths are hit
  as often in practice as their reachability suggests, only that they are
  reachable through ordinary, documented UI actions.
- **I did not read `lib/features/sessions/chat_composer.dart` (1074 lines),
  `sessions_screen.dart` (1019 lines), or `settings_screen.dart` (1041
  lines) in full** — I grepped them for specific patterns (draft state,
  disconnect flow, queued-state UI) and read the surrounding context, but did
  not do a line-by-line pass equivalent to what `session_sync_repository.dart`
  and `gateway_realtime.dart` got. A charter on the sessions list screen
  specifically (pinning, archiving, the sync-conflict-on-reconnect risk the
  mobile pack names as top risk #3) is real remaining work.
  `context_usage_sheet.dart`, `message_markdown.dart`,
  `command_cheat_sheet_screen.dart`, `skills_picker_sheet.dart`,
  `model_picker_sheet.dart`, and `privacy_dialog.dart` were not opened at
  all.
- **No Android/Kotlin or iOS/Swift platform code was reviewed** — the
  `android/` and `ios/` native shells, entitlements, `Info.plist`
  permission-usage strings, and `AndroidManifest.xml` permission
  declarations were not inspected. Given the app's rejection history is a
  store-policy issue, not a code-correctness one, this is a real gap for
  anyone re-litigating the App Review risk specifically.
- **Localization was not tested beyond structural existence** — I confirmed
  the 9 locale files exist and that error strings route through `L10n`, but
  did not check translation correctness or RTL Arabic layout, both called
  out in `RELEASE_CHECKLIST.md` as required manual passes.
- **No fuzzing or property-based exploration of the JSON parsers** — Charter
  7's finding was found by code reading and pattern-matching against the
  file's own sibling code, not by constructing and feeding it actual
  malformed payloads. A real Domain/Automatic-technique pass (hand-built
  malformed gateway responses, run against the parsers) would likely find
  more than the one exception I found by inspection.
- **Sync-conflict-on-reconnect (mobile pack top risk #3) was not
  investigated** — I traced the outbox and WS reconnect deeply but did not
  specifically construct or trace a two-device concurrent-write scenario
  against the merge logic in `_syncSessionsImpl`/`syncMessages`. Given how
  central this risk is to the mobile domain, this is the single largest gap
  in this pass and where I'd point the next session.
- **I did not verify the already-fixed bugs are actually fixed by running
  them** — I confirmed via `git log`/`git show` that the composer-disabled,
  autoscroll, and job-status commits exist and read as intended fixes on
  inspection, but did not execute the app to confirm. I did *not* find a
  committed fix specifically for the 4018/rewind bug in `git log -- apps/
  mobile/` under any message mentioning "4018" or "rewind" — Charter 1's
  finding is offered on the assumption that fix is either still in progress
  elsewhere in this session or was intended to be covered by the existing
  `_isSessionNotFound` code (which predates this week, per `git blame`) and
  isn't fully sufficient; if a different, more complete fix already landed
  outside what I read, that would supersede this finding and should be
  checked against the exact code paths cited above before acting on it.

**Stopping heuristic:** Mission Accomplished, provisionally — the charter
list the task specified (state/lifecycle, error honesty, protocol skew, data
loss, security/privacy, App Review path, testability) has been covered at
least once each with at least one traced finding or an explicit clean
result, and the highest-value remaining thread (sync-conflict-on-reconnect,
and dynamic verification of Charter 1/6) is now a named, scoped next
session rather than an unknown unknown. I stopped here rather than going
deeper into any single charter because the marginal next hour is worth more
spent starting the sync-conflict charter cold than going a fourth pass
deep on the outbox (which has already yielded this pass's highest-severity
findings and is showing diminishing returns).
