# Hermes Go

> **Go further. Stay connected.**

Hermes Go is the iOS and Android companion for an already-running Hermes
gateway. The agent, tools, credentials, memory, and cron jobs stay on the host;
the phone provides the chat, session, project, model, and job experience.

This app uses the same dashboard authentication and JSON-RPC WebSocket surface
as Hermes Desktop:

```text
┌──────────────────┐       HTTPS + secure cookie       ┌──────────────────┐
│ Hermes Go        │ ────────────────────────────────► │ Hermes dashboard │
│ iOS / Android    │       WSS /api/ws + ticket        │ gateway :9119    │
└──────────────────┘                                   └──────────────────┘
```

The mobile app does not run Hermes locally and is not a replacement for host
setup or the full Desktop administration experience.

> **Requirement:** you need a standalone Hermes install (Desktop or headless
> gateway) already running somewhere — a home machine, VPS, or server — with
> dashboard authentication configured. Hermes Go connects to it; without a
> reachable, authenticated gateway there is nothing for the app to talk to.
> See [Host setup](#host-setup).

## Included in v1

| Area | Mobile app | Hermes host |
| --- | --- | --- |
| Connect | URL, username/password login, secure session storage | Dashboard auth and gateway |
| Projects | Browse host projects and their sessions | Project discovery and persistence |
| Sessions | Local-first list and transcript cache | Source-of-truth session data |
| Chat | Send turns, stream responses, show tool activity | Agent execution and tools |
| Models | Pick from the gateway's available options | Provider configuration and routing |
| Jobs | View cron jobs and completion state | Scheduling and execution |
| Notifications | Local completion notifications after permission is granted | Produces job/background results |

Provider onboarding, skill authoring, terminal/workspace administration, and
running the agent on the phone are intentionally out of scope.

## Host setup

Start the authenticated web dashboard on the machine running Hermes. The exact
authentication configuration is documented by Hermes; a typical launch is:

```bash
hermes dashboard --host 0.0.0.0 --no-open
# Dashboard listens on port 9119 by default.
```

Use a trusted private network and expose the dashboard through HTTPS, such as a
TLS reverse proxy or Tailscale HTTPS. Release builds reject remote plain-HTTP
URLs because they would expose credentials and agent traffic. Loopback HTTP is
accepted for simulator/emulator development.

Do not expose an unauthenticated Hermes gateway to the public internet.

### Recommended: reach your host over a VPN

The simplest safe setup is putting your phone and your Hermes host on the same
private network with a mesh VPN, instead of port-forwarding the gateway:

- **[Tailscale](https://tailscale.com)** (recommended) — install on the host
  and phone, sign into the same tailnet, done. `tailscale serve` can front the
  dashboard with automatic HTTPS certificates, which satisfies the app's
  HTTPS requirement out of the box:

  ```bash
  tailscale serve --bg https / http://localhost:9119
  # then connect the app to https://<host>.<tailnet>.ts.net
  ```

- **[WireGuard](https://www.wireguard.com)** — fully self-hosted alternative
  if you already run your own VPN server; pair it with a TLS reverse proxy
  (Caddy, nginx) in front of :9119.
- **[ZeroTier](https://www.zerotier.com)** or **[NetBird](https://netbird.io)** —
  comparable mesh options if Tailscale is not an option for you.

On a plain LAN (phone and host on the same Wi-Fi) the same HTTPS rule applies
for release builds; only loopback HTTP for simulators is exempt.

## Run locally

```bash
cd apps/mobile
flutter pub get
flutter run
```

An optional development default can be supplied at build time:

```bash
flutter run \
  --dart-define=HERMES_BASE_URL=https://hermes.example.ts.net
```

Store builds must also include the publisher's public policy URL so it is
available before sign-in and from Settings:

```bash
flutter build ipa --release \
  --dart-define=HERMES_PRIVACY_POLICY_URL=https://publisher.example/privacy
```

The connection screen first probes `/api/status`. If authentication is
required, it discovers the configured provider, submits the username/password
login, persists only the resulting session cookies in platform secure storage,
and mints a single-use WebSocket ticket. The password is not retained.

## Deploy to an iPhone without losing connections

Do not uninstall the app first. An uninstall can remove the local gateway book
and transcript cache.

```bash
./scripts/deploy_ios.sh
# or: ./scripts/deploy_ios.sh 00008150-…
```

This performs an upgrade install and preserves the existing app container.

## Build release binaries

iOS requires a signing team once per checkout: open `ios/Runner.xcworkspace`
in Xcode, select the Runner target, and pick your team under
Signing & Capabilities (or edit `DEVELOPMENT_TEAM` in
`ios/Runner.xcodeproj/project.pbxproj`). Then:

```bash
# iOS: archive + App Store-signed IPA in build/ios/ipa/
flutter build ipa --release

# Android: APK for sideloading, or an app bundle for Play
flutter build apk --release          # build/app/outputs/flutter-apk/
flutter build appbundle --release    # build/app/outputs/bundle/release/
```

Upload the IPA with Apple's Transporter app or
`xcrun altool --upload-app --type ios -f build/ios/ipa/*.ipa`. Install a
release APK directly with `adb install -r build/app/outputs/flutter-apk/app-release.apk`.

Before any store build, remember the privacy policy define from
[Run locally](#run-locally) and walk [RELEASE_CHECKLIST.md](./RELEASE_CHECKLIST.md).

## Project layout

```text
lib/
  main.dart / app.dart
  core/
    network/      connection book, dashboard client, secure cookies, WebSocket
    db/           Drift SQLite sessions/messages/outbox, scoped per gateway
    sync/         local-first pull/push and background catch-up
  features/
    connect/      URL probe and dashboard login
    projects/     project tree and project sessions
    sessions/     recents and streaming chat
    models/       model picker
    jobs/         cron jobs and completion notifications
    settings/     connection, sync, notification controls, disconnect
```

The UI reads SQLite first, then reconciles with the gateway. Foreground updates
primarily arrive over WebSocket; WorkManager provides best-effort catch-up when
the process has been backgrounded or killed. Disconnect removes saved gateway
profiles, cookies, and legacy credentials from the device.

Accessibility settings are respected without a hard text-size cap. The setup
screen scrolls at large Dynamic Type/font-scale values, and the shell gives the
bottom navigation extra room for enlarged localized labels.

## Gateway surface

The app currently uses these dashboard endpoints and RPC transports:

- `GET /api/status`
- `GET /api/auth/providers`
- `POST /auth/password-login`
- `POST /api/auth/ws-ticket`
- `GET /api/ws?ticket=…`
- dashboard REST reads under `/api/sessions`, `/api/model/options`,
  `/api/cron/jobs`, and `/api/skills`
- JSON-RPC calls over `/api/ws` for live sessions, chat, projects, jobs, and
  gateway events

See [DESIGN.md](./DESIGN.md) for the product boundaries and sync model, and
[RELEASE_CHECKLIST.md](./RELEASE_CHECKLIST.md) for store-release preparation.
