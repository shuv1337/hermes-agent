# Mobile ↔ Desktop API map

**Source of truth:** `apps/desktop/src/hermes.ts` + `apps/desktop/src/store/*`
+ `apps/shared` JSON-RPC gateway client.

Mobile must not invent API_SERVER-only shapes for dashboard data.

## Auth (remote)

| Step | Desktop | Mobile |
|------|---------|--------|
| Probe | GET `/api/status` | `GatewayAuthClient.probe` |
| Providers | GET `/api/auth/providers` | same |
| Password | POST `/auth/password-login` | same → PersistCookieJar |
| WS ticket | POST `/api/auth/ws-ticket` | same |
| Live WS | `ws…/api/ws?ticket=` | `GatewayWsClient` |

## Read APIs we use

| Data | Desktop | Mobile |
|------|---------|--------|
| Sessions | GET `/api/sessions?limit&order=recent&min_messages&archived&exclude_sources` | `DashboardClient.listSessions` |
| Messages | GET `/api/sessions/{id}/messages` | `DashboardClient.listMessages` |
| Models | GET `/api/model/options?explicit_only=1` | `DashboardClient.listModelOptions` |
| Cron | GET `/api/cron/jobs` | `DashboardClient.listCronJobs` |
| Projects | WS `projects.tree` / `projects.project_sessions` | `GatewayRealtime` |

## Response shapes (dashboard)

- Sessions: `{ sessions: SessionInfo[], total, limit, offset }` — **not** `{ data: [] }`
- Messages: `{ session_id, messages: SessionMessage[] }`
- Model options: `{ model, provider, providers: [{ slug, name, models: string[] }] }`
- Cron jobs: **JSON array** of CronJob (schedule may be `{ display, expr }`)

## WS events (live)

From `apps/shared` / tui_gateway: `message.complete`, `session.info`,
`background.complete`, `tool.*`, `status.update` → refresh local cache + notify.
