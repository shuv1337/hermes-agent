# Hermes Go — Design & Scope

> **Go further. Stay connected.**

## One-liner

A **gateway connector** phone app: talk to an agent that already lives on a
server. Not the whole product — just the slice a gateway user needs on a phone.

## Product principles

1. **Host is source of truth.** Phone caches for offline read + snappy UX;
   never invents sessions the server doesn't know about.
2. **Chat-first.** Sessions list → thread → composer. Settings and jobs are
   secondary tabs, not the home screen.
3. **Thin client.** No skill editors, no provider onboarding, no container
   backends. If it belongs in Desktop's settings tree, it stays there.
4. **Safe by default.** Dashboard cookies and legacy gateway tokens in
   platform secure storage only — never in the plaintext Application Support
   mirror. Remote connections require TLS.
   Clear "you're talking to full tool access" warning on connect.
5. **Codex / Claude mobile muscle memory.**
   - Left/list: sessions (title, preview, relative time)
   - Thread: user bubbles right, assistant left, tool progress as quiet chips
   - Composer: text field + send + **model chip**
   - Pull-to-refresh = sync
   - Activity / jobs as a separate tab with notification badges

## Information architecture

```
[Connect]  ──once──►  [Shell]
                        ├─ Projects  → project overview (projects.tree)
                        │               └─ Project detail (project_sessions)
                        ├─ Sessions  → flat recents + SessionChat
                        ├─ Jobs      → cron list / last run
                        └─ Settings  → connection, notifications, disconnect, about
```

### Projects (Desktop sidebar parity)

Desktop groups work by **project** (projects.db + auto repo roots), not a flat
session dump. Mobile calls the same JSON-RPC surface over `/api/ws`:

| RPC | Use |
| --- | --- |
| `projects.tree` | Overview: label, path, sessionCount, previewSessions |
| `projects.project_sessions` | Drill-in: hydrated lanes → flattened session list |
| `projects.list` | Optional light list of explicit projects.db rows |

Requires live gateway WebSocket (same token/URL as Desktop). API-server-only
hosts show an empty state pointing at Sessions.

### Connect (Desktop remote parity — no API_SERVER_KEY)

Matches Desktop (`probeRemoteAuthMode` + password login window):

1. **Base URL** only first → `GET /api/status` (public)
2. If `auth_required` → `GET /api/auth/providers`
3. When every provider has `supports_password` → username/password form
4. `POST /auth/password-login` `{ provider, username, password }` → **Set-Cookie**
   (`hermes_session_at` / `hermes_session_rt`)
5. Prove session: `POST /api/auth/ws-ticket` → single-use ticket
6. Live socket: `ws(s)://…/api/ws?ticket=…` (mint fresh ticket each connect)

Password is **not** stored. Cookies live in a per-gateway `PersistCookieJar`.
Open/loopback gateways (`auth_required: false`) connect without credentials.

### Multi-gateway design (storage ready; UI later)

Device storage is a versioned `GatewayBook` (v2), not a single URL/key blob:

| Field | Role |
| --- | --- |
| `gateways[]` | Saved `ConnectionProfile`s (`id`, `label`, `baseUrl`, `apiKey`, …) |
| `defaultGatewayId` | Boot / home gateway when the app opens |
| `activeGatewayId` | Gateway Sessions · Jobs · Chat currently talk to |

```
GatewayBook
├── gateways: [ Home, Spark, VPS, … ]   # multi later
├── defaultGatewayId → Home             # cold start
└── activeGatewayId  → Spark            # may differ while browsing
         │
         ▼
   hermesApiProvider  ── binds to active only
   selectedModel      ── scoped per gateway id
```

**v1 product rules**
- Connect → `saveAsPrimary` (book length 1; default == active)
- Disconnect → wipe entire book
- No switcher UI yet

**Later UI (no storage rewrite expected)**
- Settings list of gateways; Add / Edit / Delete
- “Set as default” + “Use now” (active)
- Shell header chip to switch active without leaving Sessions
- Per-gateway model preference (already keyed by profile id)
- Optional: concurrent multi-profile later is *not* required; switch active is enough

**Migration:** legacy single-profile key `hermes_mobile_connection` is read once
and rewritten as a one-entry `GatewayBook`.

### Connection persistence across deploys

Gateway URL and authenticated session must survive shipping a new build to the
phone. The user's password is never retained.

| Layer | What | Survives upgrade install? | Survives full uninstall? |
| --- | --- | --- | --- |
| iOS Keychain | Primary (`accountName` + access group stable) | Yes | Often yes (same team/bundle) |
| App Support mirror | `gateway_book_v2.json` connection metadata | Yes | No |
| Secure cookie store | Dashboard session cookies | Yes | Platform-dependent |
| User Disconnect | Explicit wipe | N/A | N/A |

**Deploy rule:** upgrade only — `apps/mobile/scripts/deploy_ios.sh`. Never
uninstall-then-install. Agents: see `AGENTS.md`.

### Sessions

- **Local-first SQLite** (`hermes_sessions.sqlite` in Application Support),
  scoped by `gatewayId` so multi-gateway never mixes transcripts
- Open app / Sessions tab → show local list immediately, then pull
  `GET /api/sessions` and merge (server wins; pending local creates kept)
- Open chat → show local messages immediately, then pull
  `GET /api/sessions/{id}/messages`
- Writes (create, delete, chat) → local row + **outbox** → `flushOutbox()`
  as soon as the gateway answers; retries with backoff if offline
- Pull-to-refresh / Settings “Sync” = pull + flush outbox

### Live session updates (Desktop parity) — primary path

Hermes Desktop does **not** poll on a timer. It opens a **JSON-RPC WebSocket**
to the dashboard/serve gateway:

```
wss://<host>/api/ws?ticket=<single-use ticket>
```

Shared client: `apps/shared` `JsonRpcGatewayClient`. Events include:

| Event | Meaning |
| --- | --- |
| `gateway.ready` | Socket accepted |
| `session.info` | Session metadata |
| `message.delta` / `message.complete` | Streaming assistant turn |
| `tool.*` | Tool progress |
| `background.complete` | Cron / background agent finished |
| `status.update` | Run status |

Mobile now mirrors that with `GatewayWsClient` + `GatewayRealtime`:

1. After connect, mint a ticket and open `/api/ws`.
2. On completion-like events → refresh SQLite session/messages + notify.
3. Sessions tab shows **Sessions · live** when the socket is up.
4. Dashboard REST reads and WebSocket events keep the local cache honest.

**Auth note:** Point the phone at the same authenticated dashboard base URL
Desktop uses for remote gateway access. The mobile app does not ask users for
an `API_SERVER_KEY`.

### Background catch-up — last resort only

Why **15 minutes** showed up: Android WorkManager’s minimum periodic interval.
That is an OS constraint for **dead process** recovery, **not** Hermes design.

| State | How updates arrive |
| --- | --- |
| App foreground / process alive | **WebSocket push** (Desktop path) |
| App backgrounded, process alive | Socket may stay briefly; events still apply |
| Process killed by OS | Workmanager one-off / rare periodic **poll** flushes outbox + checks watches |

Lifecycle: `paused` schedules a catch-up task; `resumed` reconnects WS + pulls.

**Outbox flush mechanism differs by auth mode** (`background_sync.dart`
`BackgroundSync.run`):

- **Legacy API-key auth**: `flushOutbox()` posts queued ops over plain REST
  (`HermesApi`) — no socket needed, works in the background unconditionally.
- **Cookie/session auth** (the mode `ConnectionScreen` actually produces —
  there is no API-key entry in onboarding): `flushOutbox()` is a no-op (no
  `HermesApi` to call), so the background task mints a short-lived WS ticket
  off the persisted session cookies (`GatewayAuthClient.persistentJar` +
  `POST /api/auth/ws-ticket`, the same call `GatewayRealtime` makes in the
  foreground), connects just long enough to let `flushPendingOverWs()` drain
  the queue, then disconnects. This is **best-effort**: it is bounded to a
  bit over a minute so a slow/unreachable gateway can't blow the OS's
  background execution budget, and either the connect or the drain can time
  out and leave ops queued for the *next* catch-up pass (Android's periodic
  minimum is still 15 minutes; iOS decides actual cadence and may skip runs
  entirely). "Queued for sync" is a real state that can outlive several
  background passes — it is not a guarantee of imminent delivery.

### Composer / send

- Send chat commands through the authenticated JSON-RPC WebSocket.
- Apply streamed message deltas, completion events, and tool progress to the
  local transcript.
- Queue writes locally while disconnected and flush them after reconnect.

### Model picker

- Source: dashboard model options / JSON-RPC
- UX: sheet from composer chip (Claude/Codex pattern)
- Reality check: API docs note the request `model` field may be **cosmetic** —
  the host's configured model wins unless server routing is set up. UI still
  shows the advertised models and selected preference for multi-route setups.

### Jobs & notifications

- List: dashboard cron jobs / JSON-RPC
- Show schedule, enabled/paused, last status
- v1 notifications: **local** notification when poll sees a job transition to
  completed/failed while app is backgrounded (or on next foreground)
- v1.1: host webhook / push relay if/when Hermes grows a mobile push channel
- Cron results that open a session deep-link into SessionChat

## Explicit non-goals (v1)

| Desktop / agent feature | Why not on phone |
| --- | --- |
| Skills hub authoring | Editing + filesystem live on host |
| Profile multi-admin | Advanced; one connection profile first |
| Terminal / workspace browser | Wrong form factor; host runs tools |
| Full config.yaml editor | Dangerous + huge surface |
| OAuth portal setup | Done once on host (`hermes setup`) |
| Pet / starmap / themes marketplace | Desktop flair, not gateway core |

## Visual direction

- Dark-first, quiet chrome (Claude / Codex night modes)
- Flat lists, no card-in-card (align with `apps/desktop/DESIGN.md` spirit)
- Mono for tool names and model IDs; system UI font for body
- Accent sparingly (send button, active session, running job)

## Security notes

- A dashboard session can reach a gateway that runs shell tools. Treat access
  to the unlocked phone as powerful access to the host.
- Require HTTPS outside loopback and prefer a private VPN over raw port-forward.
- The password is used only for login. Auth cookies are encrypted by platform
  secure storage, and Disconnect clears cookies and legacy credentials. The
  legacy static gateway token (`ConnectionProfile.apiKey`) is stored the same
  way and is never written to the plaintext Application Support gateway-book
  mirror (`gateway_book_v2.json`).
- Application data and transcripts are excluded from Android cloud backup and
  device transfer.

## Implementation stack

| Choice | Why |
| --- | --- |
| Flutter | Matches `resin_grove_mobile`; iOS + Android one codebase |
| Dio | Same HTTP pattern as resin_grove |
| flutter_secure_storage | Authenticated dashboard cookies |
| flutter_riverpod | Controllers / session state (as resin_grove) |
| flutter_local_notifications | Cron/job completion alerts |
| JSON-RPC WebSocket | Chat streaming and live gateway events |

## Roadmap sketch

1. **Bootstrap (this scaffold)** — connect, sessions list, read-only messages,
   non-stream send, model list, jobs list
2. **Streaming + cache** — WebSocket deltas, offline transcript cache, pull-sync
3. **Notifications** — local job alerts, deep links into sessions
4. **Hardening** — multi-profile hosts, cert pinning optional, biometric lock
