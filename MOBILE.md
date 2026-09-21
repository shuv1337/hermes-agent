# Mobile gateway fork

Originally developed on TheTom/hermes-go's `mobile-gateway` branch and now
integrated into this repository.

## What this fork is for

A **Flutter phone connector** under `apps/mobile` that talks to an already-running
authenticated Hermes dashboard gateway. It is **not** a full agent port.

| Product | Path | Role |
| --- | --- | --- |
| Hermes Agent + gateway | repo root | Source of truth (tools, memory, cron, sessions) |
| Hermes Desktop | `apps/desktop` | Full desktop client |
| **Hermes Mobile** | `apps/mobile` | Sessions · chat · bots · model picker · jobs · optional Apple Health sync |

See `apps/mobile/README.md` and `apps/mobile/DESIGN.md`.

## Host checklist

```bash
hermes dashboard --host 0.0.0.0 --no-open
```

## Run mobile

```bash
cd apps/mobile
flutter pub get
flutter run
```
