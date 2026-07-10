# Mobile gateway fork

Branch: **`mobile-gateway`**

Upstream: [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent)  
Remote name in this clone: `upstream`  
(Add your GitHub fork as `origin` when ready:  
`git remote add origin git@github.com:<you>/hermes-agent.git`)

## What this fork is for

A **Flutter phone connector** under `apps/mobile` that talks to an already-running
Hermes Agent gateway (`API_SERVER_*`). It is **not** a full agent port.

| Product | Path | Role |
| --- | --- | --- |
| Hermes Agent + gateway | repo root | Source of truth (tools, memory, cron, sessions) |
| Hermes Desktop | `apps/desktop` | Full desktop client |
| **Hermes Mobile** | `apps/mobile` | Sessions · chat · model picker · jobs/notifications |

See `apps/mobile/README.md` and `apps/mobile/DESIGN.md`.

## Host checklist

```bash
# ~/.hermes/.env
API_SERVER_ENABLED=true
API_SERVER_KEY=<long-random-secret>
# LAN/VPN only if the phone must reach it:
API_SERVER_HOST=0.0.0.0
API_SERVER_PORT=8642

hermes gateway
```

## Run mobile

```bash
cd apps/mobile
flutter pub get
flutter run
```
