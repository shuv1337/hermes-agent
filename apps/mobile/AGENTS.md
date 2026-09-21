# Hermes Go — agent notes

## Connection persistence (standing rule)

Saved gateway connections **must survive app deploys**.

1. **Never uninstall the app** as part of install/deploy (`adb uninstall`,
   delete from home screen, etc.) unless the user explicitly wants a wipe.
2. **Never use `flutter install` on iOS** — it runs “Uninstalling old version…”
   and wipes Application Support. Always use `scripts/deploy_ios.sh`
   (`flutter build ios --release` + `xcrun devicectl device install app`).
3. Do **not** call `disconnectAll` / clear secure storage during ship scripts,
   tests on device, or “fix connection” experiments on the user’s phone.
4. Storage is dual-written: iOS Keychain (stable account + access group) **and**
   Application Support mirror (`gateway_book_v2.json`). Do not rename those
   keys/account names — see `ConnectionStore` constants.

Credentials only clear when the user taps **Disconnect** in Settings.

## WebSocket robustness (`GatewayRealtime`)

Chat is **WS-only** (`/api/ws` + JSON-RPC). HTTPS/cookies alone are not enough.

### Ownership
- One `GatewayRealtime` per gateway id via `_realtimeHolderProvider` — never
  recreate on every Riverpod profile tick (that disposed sockets mid-handshake).
- `GatewayWsClient.connect` is single-flight; concurrent callers join.

### Auth
- Session gateways: mint `POST /api/auth/ws-ticket` **immediately before** open.
  Tickets are **single-use + 30s TTL**. Never reuse a ticket URL.
- 401 on mint → `forceReauth` (interactive login). **No silent password re-login.**

### Keep-alive
- Protocol ping via `IOWebSocketChannel(pingInterval: 20s)` — CF Tunnel idle is
  ~100s; 75% rule → stay under ~75s. 20s is safe.
- App-level liveness: `session.list limit=1` every 24s while foregrounded.
  Miss → treat as zombie, disconnect, reconnect.
- Resume: if socket “open”, probe first; on fail **force** remint+connect.
  Resume also clears give-up so the user gets a fresh retry window.

### Reconnect policy (Desktop-shaped)
- Backoff: `1s * 2^n` capped at **15s**, with **50–100% jitter**.
- Max **12 attempts** or **~2 minutes** elapsed → **give up**; Settings shows
  “Gave up — tap Reconnect”. Manual Reconnect resets attempt counter.
- `wantConnected` (Desktop `wantOpen`): deliberate `stop()` does not auto-loop.
- Path change (`connectivity_plus` Wi‑Fi↔cellular): force reconnect while
  foregrounded. Do not fight iOS background forever — accept death, recover on
  resume.

### UI
- Settings WebSocket line uses `uiStatus.label`
  (e.g. `Reconnecting · attempt 4 · 8s`).
