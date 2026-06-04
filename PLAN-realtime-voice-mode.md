# PLAN — Realtime Voice Mode for Hermes Desktop (GPT‑Realtime front‑end + Hermes agents as sub‑agents)

> Status: spec — all §10 decisions **LOCKED 2026‑06‑04** (see §10). Author: research pass 2026‑06‑04.
> Goal: replace Hermes Desktop's slow "Start voice conversation" mode (local STT → remote text LLM → batch TTS) with a low‑latency **OpenAI GPT‑Realtime‑2** speech‑to‑speech conversational agent that acts as a fast front‑end and **delegates heavy work by running real Hermes agents as sub‑agents**.
> Sibling reference: `../shuvagent` — a working Python OpenAI Realtime voice agent we mine for proven code/patterns.

---

## 0. TL;DR / recommendation

Build a new voice mode around the **OpenAI "Chat‑Supervisor" pattern** (OpenAI's own first‑party blueprint for exactly this): a cheap, fast realtime model carries the conversation and **delegates anything substantive to a full Hermes agent via a single tool**, masking the agent's latency with spoken filler.

- **Audio stays in the Electron renderer** over **WebRTC** to OpenAI (lowest latency, reuses all the mic/permission plumbing the desktop already has). The OpenAI API key never leaves the backend — the renderer uses a **backend‑minted ephemeral token**.
- **Heavy work is a tool call.** When the realtime model calls `run_hermes_agent(...)`, the desktop routes it to a **real Hermes agent turn** — Phase 1 over the **existing `/api/ws` `prompt.submit` gateway** (zero new backend surface), Phase 2 moved server‑side via an OpenAI **sideband connection** so Python owns tool execution directly via in‑process `AIAgent.run_conversation()`.
- **Long agent runs don't freeze the conversation** — GPT‑Realtime's **native async function calling** keeps the session fluid while a tool is pending ("the model can continue a fluid conversation while waiting on results … available natively … no code changes"). The model also speaks **preambles** ("let me pull that up") while a tool runs.
- **Cost stays sane** because reasoning is pushed into the cheap Hermes *text* agent; the realtime model stays a thin, low‑`reasoning_effort` router.

This is the smallest‑footprint path that reuses the most of what already exists in both repos.

---

## 1. Where we are today

### 1.1 `shuvagent` (the reference realtime agent — Python)
A clean, layered, tested OpenAI Realtime voice agent. **It already solves the hard realtime parts.** ([shuvagent README], [HANDOFF.md])

| Layer | File | Reuse verdict |
|---|---|---|
| OpenAI Realtime **WebSocket protocol** (session.update, audio append/commit, function_call_output, response.cancel, barge‑in, auto‑reconnect) | `shuvagent/realtime/openai_session.py` | **Crown jewel — reuse** |
| Transport seam (`RealtimeAgentSession` Protocol) + fake + Gemini provider | `shuvagent/realtime/{session.py,fake.py,providers.py}` | Reuse |
| **Gated, audited, risk‑tiered tool dispatch** (ToolRegistry, PermissionGate, confirmation, audit) | `shuvagent/tools/` | **Reuse — exactly the safety model we want for letting voice trigger sub‑agents** |
| Orchestrator (audio↔model loop, first‑audio latency telemetry, usage/duration caps, session monitors) | `shuvagent/app.py` `ConversationApp.run_streaming` | Reuse shape, **but must fix blocking tool dispatch (see §6.1)** |
| Tool‑catalogue filtering (all/keyword/llm) | `shuvagent/tool_router.py` | Optional (never wired live) |
| Mic/speaker (sounddevice), Unix‑socket control, Hyprland/Wayland/ShuVoice arbitration | `shuvagent/cli.py`, `shuvagent/audio/`, `control.py`, `window.py`, `coordination.py` | **Drop** — Linux‑desktop‑specific; audio belongs in the Electron renderer |

Key facts that shape the design:
- Model string sent on the wire is already **`gpt-realtime-2`**; default voice `marin`, `max_output_tokens=800`, `session_max_duration_sec=300` (`openai_session.py:43`, `config.py:31`, `examples/config.toml:5`).
- **Tool handlers are synchronous and dispatched one‑at‑a‑time**; a long handler blocks the event loop and all audio (`tools/types.py:64`, `registry.py:44`, `app.py:232‑254`). This is the #1 thing to re‑architect for `run_hermes_agent`.
- `reasoning_effort` is validated but **not actually placed in the `session.update` payload** today — inert on the wire (`openai_session.py:217‑252`). Fix when porting.
- Live posture is effectively **read‑only**: `PermissionGate` defaults to `DenyAllConfirmationProvider`; non‑READ tools need a confirmation UI that was never wired.

### 1.2 Hermes Desktop (the integration target — Electron + React)
- **Electron** (`electron@^40.9.3`) with a **Vite + React 19 + TS** renderer. Main = `apps/desktop/electron/main.cjs`; preload exposes `window.hermesDesktop` (`apps/desktop/electron/preload.cjs`).
- Main spawns the Python backend: `hermes dashboard --no-open --tui --host 127.0.0.1 --port <port>` (`main.cjs:3372`, `:3381`) → FastAPI in `hermes_cli/web_server.py`.
- **Two transports to the backend:**
  1. **REST‑over‑IPC** — `window.hermesDesktop.api({path,method,body})` → `ipcMain 'hermes:api'` → `fetchJson` (`preload.cjs:10`, `main.cjs:3713`). This is how STT (`/api/audio/transcribe`, `web_server.py:1320`) and TTS (`/api/audio/speak`, `web_server.py:1455`) flow.
  2. **WebSocket JSON‑RPC** — renderer opens `ws://127.0.0.1:<port>/api/ws?token=…` directly (`HermesGateway extends JsonRpcGatewayClient`, `apps/desktop/src/hermes.ts:102`). Methods: `session.create/resume/close/interrupt`, **`prompt.submit`**, `slash.exec`, etc. Streamed events: `message.start|delta|complete`, `thinking.delta`, `tool.start|progress|complete`, `approval.request`, …
- **Mic permissions + mac entitlements are already wired** (`main.cjs:3064‑3087`, `:3705`; `package.json` `NSMicrophoneUsageDescription`/`NSAudioCaptureUsageDescription`; `entitlements.mac.plist` audio‑input).
- **Remote‑backend mode** exists (`HERMES_DESKTOP_REMOTE_URL`/`_TOKEN`, `PLAN-hermes-desktop-nick-launcher.md`) — any new realtime token endpoint must work in both local‑spawn and remote modes.

### 1.3 The current "Start voice conversation" pipeline (what we're replacing)
Button: `src/app/chat/composer/controls.tsx:67‑80` → `useVoiceConversation` (`src/app/chat/composer/hooks/use-voice-conversation.ts`), a renderer state machine `idle → listening → transcribing → thinking → speaking`. Every hop is **serial**:

```
mic (getUserMedia+MediaRecorder, client RMS VAD)
  └─ waits 1250ms trailing silence to END the turn        ← fixed latency
     └─ whole clip → base64 → POST /api/audio/transcribe   ← no streaming STT
        └─ faster-whisper "base" on CPU int8 (blocking)     ← dominant non-agent latency
           └─ transcript → /api/ws prompt.submit            ← FULL agent text turn (tools+reasoning)
              └─ renderer polls $messages, chunks by sentence
                 └─ POST /api/audio/speak per chunk          ← non-streaming TTS (full file→base64→<audio>)
```
Defaults: STT = local `faster-whisper base` CPU; TTS = `edge-tts`; **no barge‑in** (mic paused during playback); the LLM is just the normal configured chat model fed a typed turn. Real‑world cascaded pipelines sit at **P50 ~1.4–1.7s**; Hermes's local‑CPU‑whisper + non‑streaming TTS is typically worse, before the agent even runs.

> Note: `/api/audio/transcribe` and `/api/audio/speak` are **also** used by one‑shot dictation and by the messaging gateway's per‑chat voice toggle (telegram/discord auto‑transcription). **Keep them**; add realtime alongside, don't rip them out.

---

## 2. Target architecture — "realtime router + Hermes brain"

OpenAI's first‑party `openai-realtime-agents` repo documents this exact shape as the **Chat‑Supervisor pattern**: a fast realtime chat agent handles the conversation while a slower, smarter model/agent handles tool calls and hard reasoning, invoked *as a tool* (`getNextResponseFromSupervisor`). The junior agent is instructed to **always speak a filler ("let me check on that") before delegating**, masking the ~2s round‑trip. We map "supervisor" → **a real Hermes agent**.

```
┌─────────────────────────── Hermes Desktop (Electron) ───────────────────────────┐
│  Renderer (React)                                                                │
│   • mic capture + playback (getUserMedia / WebAudio)  ← already wired            │
│   • WebRTC peer connection ───────────────── audio ──────────────► OpenAI        │
│   • useRealtimeConversation hook (drop-in for useVoiceConversation)              │
│        status: idle | listening | thinking | speaking | delegating              │
│                                                                                  │
│   on function_call "run_hermes_agent"(task, …):                                  │
│        Phase 1: requestGateway('prompt.submit',{session_id, text:task})  ───┐    │
│                 consume message.delta stream → final text                   │    │
│                 send function_call_output(call_id, final) + response.create │    │
│                                                                             │    │
│  Main process (main.cjs)                                                    │    │
│   • mints nothing secret; just proxies REST-over-IPC                        │    │
│                                                                             ▼    │
│  Python backend (hermes dashboard --tui, web_server.py)                  Hermes  │
│   • NEW  POST /api/realtime/session → ephemeral OpenAI client_secret      agent  │
│   • /api/ws prompt.submit → AIAgent.run_conversation()  ◄────────────────────────┘
│        (tools, reasoning, delegate_task, files, browser, …)                      │
└──────────────────────────────────────────────────────────────────────────────────┘
                              ▲
                              │  Phase 2 (north star): OpenAI **sideband** server connection
                              │  Python owns tool calls directly (no renderer round-trip),
                              └─ delegates in-process via AIAgent.run_conversation()
```

**Why this split:** audio wants to be in the client (WebRTC = Opus FEC, browser AEC, lowest latency — OpenAI explicitly recommends WebRTC for client/desktop, WebSocket for server‑to‑server). Agent delegation wants to be in Python (that's where `AIAgent` lives, and in‑process delegation is the lowest‑latency, richest‑callback path). The two are bridged either by the renderer (Phase 1) or by a sideband server connection (Phase 2).

---

## 3. The big decision: where does the realtime session live?

| Option | Audio | Tool/agent execution | Pros | Cons |
|---|---|---|---|---|
| **A. Renderer WebRTC + tools over `/api/ws`** *(recommended Phase 1)* | Renderer (WebRTC) | Renderer forwards function calls to backend `prompt.submit`; returns final text as `function_call_output` | Reuses **all** existing desktop audio + the gateway the app already speaks; ~zero new backend; key stays server‑side via ephemeral token | Renderer orchestrates tool calls; must reconcile realtime voice vs agent text stream |
| **B. Python sidecar reusing `shuvagent`** | Sidecar owns audio **or** renderer pipes PCM to sidecar | In‑process `AIAgent.run_conversation()` | Max reuse of shuvagent; cleanest in‑process delegation + streaming callbacks | New renderer↔sidecar **audio plumbing** (desktop has none today); extra process; shuvagent audio code is Linux‑specific |
| **C. Renderer WebRTC + backend **sideband*** *(recommended Phase 2)* | Renderer (WebRTC) | Backend holds a 2nd connection to the **same** realtime session and answers tool calls directly via `AIAgent.run_conversation()` | Best of both: client audio, Python owns tools in‑process; no renderer tool‑orchestration | Sideband + ephemeral WebRTC is newer/less‑trodden; more moving parts |

**DECIDED (2026‑06‑04): A → C.** Ship Option A first (fastest, reuses everything). Once stable, migrate tool handling to a sideband server connection (Option C) so Python owns delegation directly and the renderer becomes pure audio. Option B (Python sidecar reusing shuvagent) was considered and set aside — most new plumbing for the least extra benefit.

> **Sideband is real and documented:** "two active connections to the same realtime session: one from the user's client and one from your application server. The server connection can be used to monitor the session, update instructions, and respond to tool calls." (developers.openai.com/blog/realtime-api; realtime‑server‑controls guide). That is precisely the "client owns audio, server owns tools" split.

---

## 4. The delegation mechanism — `run_hermes_agent`

### 4.1 Tool surface exposed to the realtime model (keep it small)
- **`run_hermes_agent(task: string, scope?: "current_session"|"new", toolsets?: string[])`** — the one that matters. Runs a full Hermes agent turn.
- A few **fast, local** context tools the model can answer with instantly (no delegation): e.g. `get_active_session_summary`, `get_selected_text`/clipboard (mirror shuvagent's read‑only builtins), `list_recent_tasks`. These keep simple turns sub‑second.
- **`cancel_running_work()`** — explicit "stop that" intent (distinct from barge‑in; see §6.3).

Declared in `session.update` under `tools` as `{type:"function", name, description, parameters:<JSON schema>}` (verified wire shape; shuvagent's `_tool_to_openai_function` at `openai_session.py:409‑415` already produces it).

### 4.2 How the call resolves
**Phase 1 (renderer, over `/api/ws`):**
1. Realtime model emits `function_call` in `response.done` (`call_id` + `arguments` JSON).
2. Model speaks a **preamble/filler** first — either GPT‑Realtime‑2's native spoken preamble ("checking that for you"), or enforced by the system prompt (Chat‑Supervisor style), or both.
3. Renderer handler calls `requestGateway('prompt.submit', { session_id: <active or new>, text: task })` — **the same path the chat UI uses** (`use-prompt-actions.ts:332`). The Hermes agent runs with full tools/reasoning; progress streams as `message.delta`/`tool.*` events into `$messages` (so **the user sees the work happening in the chat** — a UX win).
4. On `message.complete`, renderer sends `conversation.item.create {type:"function_call_output", call_id, output: finalText}` then `response.create` over the WebRTC data channel → the realtime model **speaks a natural summary** of the result.

**Phase 2 / sidecar (in‑process Python):** the tool handler runs `AIAgent.run_conversation(user_message=task, stream_callback=…)` on a worker thread and returns `final_response`. This is the cleanest delegation surface in the whole repo — see §4.3.

### 4.3 Hermes side: the cleanest "run an agent" API
All paths bottom out at **`AIAgent` (`run_agent.py:319`)** → **`AIAgent.run_conversation()` (`agent/conversation_loop.py:351`)**, which returns a dict `{final_response, messages, completed, interrupted, …}`. Its constructor already exposes the realtime hooks we want: `stream_delta_callback` (doc literally says *"Used by the TTS pipeline to start audio generation before the full response"*), `tool_start/progress/complete_callback`, `step_callback`, `status_callback` (`run_agent.py:371‑381`). Ranking of invocation surfaces (from the survey):

1. **`delegate_task` (`tools/delegate_tool.py:1945`)** — Hermes **already has an agent‑as‑tool mechanism**. It spawns child `AIAgent`s on worker threads, handles credentials, depth limits, heartbeats, and `interrupt_subagent`/`list_active_subagents` (`:188`,`:211`). It returns **final summary only** and requires a `parent_agent`. Use it as the **reference implementation** for child construction/isolation, but for streaming voice prefer a direct `AIAgent` call.
2. **Direct in‑process `AIAgent.run_conversation()`** — best for the Python sidecar; sub‑ms hand‑off, full streaming callbacks. This is how the gateway (`gateway/stream_consumer.py:79‑92`) and ACP server (`acp_adapter/server.py:1456`) already do it.
3. **`tui_gateway` `prompt.submit` over `/api/ws` (`tui_gateway/ws.py:134`, `server.py:3925`)** — best for Node/Electron; **already what Hermes Desktop uses**, so Phase 1 needs *no new server code*. Carries dashboard ticket/token auth (`dashboard_auth/ws_tickets.py`).
4. **ACP adapter (`acp_adapter/server.py:445`)** — a clean, versioned "embed an agent + stream `session/update`" protocol (Zed's Agent Client Protocol, JSON‑RPC/stdio). Use only if you want a stable protocol boundary instead of coupling to `AIAgent` internals; it carries editor‑shaped machinery you don't need.
5. `gateway/run.py` (messaging platforms) — wrong abstraction; copy `GatewayStreamConsumer`, not the entrypoint.
6. `mcp_serve.py` — messaging bridge only; **no run‑agent tool**. Not a candidate.

> **Net:** Phase 1 reuses **`prompt.submit`** (#3) and the active chat session; the sidecar future uses **direct `AIAgent.run_conversation()`** (#2), modeling child setup on **`delegate_task`** (#1).

---

## 5. Component checklist (Phase 1)

| # | Component | Where | Notes |
|---|---|---|---|
| 1 | **Ephemeral token endpoint** `POST /api/realtime/session` | `hermes_cli/web_server.py` (next to `/api/audio/*`) | Mints an OpenAI Realtime `client_secret` server‑side; key stays server‑side (same pattern as `ELEVENLABS_API_KEY` at `web_server.py:1412`). Must work in local‑spawn **and** remote‑backend modes. Returns `{client_secret, model, voice, expires_at}`. |
| 2 | **Realtime config block** | `cli-config.yaml.example` + `web_server` config allowlist (`:370‑382`) + `.env` | New `realtime.{model,voice,reasoning_effort,turn_detection,max_session_sec,idle_timeout_ms}`; key via `VOICE_TOOLS_OPENAI_KEY` (note `.env.example:317` already separates this from the OpenRouter key). Default `model=gpt-realtime-2`, `reasoning_effort=low`. |
| 3 | **`createRealtimeSession()` client** | `apps/desktop/src/hermes.ts` (next to `transcribeAudio:571`/`speakText:582`) | Fetches the ephemeral token via the existing `window.hermesDesktop.api` IPC path. |
| 4 | **`useRealtimeConversation` hook** | `apps/desktop/src/app/chat/composer/hooks/` | **Drop‑in for `useVoiceConversation`** — same surface (`{start,end,status,level,muted,toggleMute,stopTurn}`) so `controls.tsx` / `ConversationPill` are untouched. Opens WebRTC (getUserMedia → `pc.addTrack`, `pc.ontrack` → `<audio>`, SDP offer to OpenAI with the ephemeral token). Reuse `use-mic-recorder.ts` for the level‑meter viz. |
| 5 | **Mode toggle** | `composer/index.tsx:1134‑1142`, `controls.tsx:67‑80` | Branch to the realtime hook; keep the old loop behind a setting for fallback / non‑realtime environments. |
| 6 | **Tool definitions + `run_hermes_agent` handler** | renderer (Phase 1) | Function‑call → `prompt.submit` on the active session → assemble final → `function_call_output` + `response.create`. |
| 7 | **System prompt / instructions** | realtime `session.update.instructions` | Chat‑Supervisor rules: what the model may answer alone (greetings, clarifications, reading back state) vs. **must delegate**; **mandatory filler before delegating**; speak results conversationally, don't read raw agent text verbatim unless asked. |
| 8 | **Session/cost guards** | hook + endpoint | `max_session_sec`, `idle_timeout_ms` auto‑prompt, token‑usage monitor on `response.done`, periodic context summarization for long sessions (see §7). |

**Phase 2 deltas:** move #6/#7 server‑side via a **sideband** server WebSocket to the same session; replace `prompt.submit` with in‑process `AIAgent.run_conversation()`; optionally port shuvagent's `tools/` gate + telemetry for audited, risk‑tiered tool execution.

---

## 6. Realtime behaviors that need explicit design

### 6.1 Long‑running tools must not freeze the conversation — and natively don't
GPT‑Realtime has **native asynchronous function calling**: *"the Realtime API allows clients to continue a session while a function call is pending,"* and *"Long‑running function calls will no longer disrupt the flow of a session — the model can continue a fluid conversation while waiting on results. This feature is available natively in gpt‑realtime, so developers do not need to update their code."* The GA API even **auto‑injects tuned placeholder responses** ("I'm still waiting on that"). So a 30‑second Hermes agent run is fine at the *protocol* level.

⚠️ **But shuvagent's orchestrator is synchronous and blocks** (`app.py:232‑254`; sync `ToolHandler`, `registry.py:44`). If you reuse shuvagent (Options B/C), you **must**: (a) run the handler on a worker thread / `asyncio.to_thread` so audio keeps flowing, and (b) rely on async function calling instead of awaiting the result inline. (If you ever use `openai-agents-python`, async tool calls now default on — `async_tool_calls=True`, PR #1984 — but you can set it `False`; verify, don't assume.)

### 6.2 Filler / spoken status (latency masking)
- **Before delegating:** mandatory short filler ("let me look into that") — Chat‑Supervisor measured ~2s gap as acceptable when masked this way; humans perceive >2s of silence as broken.
- **During long runs:** optionally feed periodic spoken status via **out‑of‑band responses** (`response.create` with `response.conversation:"none"`, an `item_reference` input, chosen `output_modalities`) so the model can say "still working — I've found X" without polluting the main transcript. Drive these from the agent's `tool_progress_callback`/`step_callback`.
- **On completion:** return `function_call_output` then `response.create`; the model speaks a natural summary.

### 6.3 Barge‑in & cancellation (two distinct things)
- **Barge‑in** (user starts talking over the model): handled by server‑side VAD `turn_detection` with `interrupt_response:true` (model auto‑cancels its own speech) + client `response.cancel`. shuvagent already wires both (`openai_session.py:234‑238`, `cancel_response`/`pause`). **Default policy:** barge‑in stops *speech only*; an in‑flight Hermes agent **keeps running** (it may be the long task the user wanted).
- **Cancel work**: a distinct `cancel_running_work()` tool / "stop that" intent → `session.interrupt` (Phase 1, `use-prompt-actions.ts`) or `interrupt_subagent` (`tools/delegate_tool.py:188`, Phase 2) to actually kill the agent.
- Configure `turn_detection`: start with `server_vad` (`threshold`, `prefix_padding_ms`, `silence_duration_ms`); consider `semantic_vad` (`eagerness`) for fewer false turn‑ends in a thinking‑out‑loud conversation.

### 6.4 Echo / self‑interruption
Open‑speaker desktops can collapse the session (the agent hears itself). WebRTC + browser AEC (Chrome/Safari/Edge good; avoid Firefox) mitigates most of it; the renderer already requests `echoCancellation`/`noiseSuppression`. Add double‑talk detection (compare outgoing‑TTS energy vs mic energy) if needed. This is a real reason to keep audio in the renderer/WebRTC rather than a raw PCM sidecar.

### 6.5 Session/context continuity — DECIDED: active session
Voice operates on the **user's visible active session** (delegated work appears in the chat history → transparency + the agent has the conversation's context). `run_conversation` accepts `conversation_history`/`task_id`; `prompt.submit` already binds a session. `run_hermes_agent` takes a `scope:"new"` argument to open a scratch session on request.

### 6.6 Delegation policy — what the model answers alone (DECIDED: minimal)
The realtime model's instructions enforce a tight allow‑list; everything else delegates via `run_hermes_agent`.

**May answer directly (no delegation):**
- Greetings, acknowledgements, social glue ("hi", "thanks", "one sec").
- Clarifying questions back to the user ("which repo do you mean?").
- Reading back state it was *explicitly handed* this turn (a summary the active session just produced; the current selection/clipboard from a fast context tool).
- Meta about the conversation itself ("what did you just say?").

**Must delegate (`run_hermes_agent`):** anything needing facts, files, code, the web, memory, tools, or multi‑step reasoning — i.e. essentially every substantive question. **When uncertain, delegate.**

**Hard rule:** never answer a factual/task question from the model's own parametric knowledge. This trades a little speed (filler + round‑trip) for never shipping a confident‑wrong answer in the user's own voice. Pair with the mandatory pre‑delegation filler (§6.2).

---

## 7. Latency & cost

**Latency win (the whole point):**
- GPT‑Realtime time‑to‑first‑voice ≈ **450–900 ms** (US); 800 ms voice‑to‑voice is a reasonable production target.
- Today's cascade ≈ **1.4–1.7 s P50** *and* Hermes's local‑CPU‑whisper + non‑streaming TTS is typically worse, *plus* the full agent turn with no masking.
- Net: **pure conversational turns drop from multi‑second to sub‑second**; **delegated turns** feel responsive because the filler speaks immediately while Hermes works (vs. dead air today).

**Cost reality (design around it):**
- Realtime audio is token‑priced and pricey: `gpt-realtime-2` ≈ **$32 / 1M audio‑in, $64 / 1M audio‑out** (+$4 text‑in / $24 text‑out, cached‑in $0.40). Roughly **$0.18–0.46/min uncached** — ~10× a cascade per minute. A dense 1‑hour session can exceed **$10** in audio tokens.
- **Mitigations baked into the architecture:** keep the realtime model thin (`reasoning_effort=low`, small `max_output_tokens`) and **push all real cognition into the cheaper Hermes text agent**. Add `max_session_sec` + `idle_timeout_ms`. For long sessions, **summarize old turns with a cheap text model and prune via `conversation.item.delete`**, inserting the summary as a **system** item (assistant‑role summaries can force text mode / bust the 80% prompt‑cache discount).

---

## 8. Risks & mitigations

| Risk | Mitigation |
|---|---|
| **Reconciling two streams** (realtime voice vs. agent text) — double‑speak/desync | Phase 1: model speaks only filler + final summary; agent text goes to the *chat pane*, not TTS. Don't pipe `message.delta` to voice in v1. |
| **shuvagent tool dispatch blocks** the loop | Only relevant for Options B/C: thread the handler + rely on native async function calling (§6.1). |
| **API key leakage** | Never in renderer; ephemeral token minted server‑side; works in remote‑backend mode. |
| **Over/under‑delegation** by the junior model | Explicit allow‑list in instructions + mandatory filler before delegate (Chat‑Supervisor); tune. |
| **Breaking existing voice** (dictation + gateway per‑chat voice toggle) | Add realtime **alongside** `/api/audio/*`; don't touch `transcribe_audio`/`tts_tool` or `gateway` `_voice_mode` (covered by `tests/gateway/test_voice_command.py`, `test_voice_mode_platform_isolation.py`). |
| **Config validation** rejects unknown keys | Add a `realtime.*` block to the `web_server` config allowlist (`:370‑382`) and `cli-config.yaml.example`. |
| **Long‑session cost/quality drift** | Session caps + periodic text‑model summarization + pruning (§7). |
| **WebRTC ephemeral + sideband is newer ground** | That's why Phase 1 avoids sideband; prove the pieces first. |
| **`reasoning_effort` inert in shuvagent** | If porting shuvagent, actually add it to the `session.update` payload. |

---

## 9. Phased plan

**Phase 0 — Spike (1–2 days). ✅ DONE (code) — live latency measurement PENDING key.** Stand up `POST /api/realtime/session` (ephemeral token) + a throwaway renderer page that opens WebRTC to `gpt-realtime-2` and does a plain voice chat with one trivial tool. Measure real time‑to‑first‑voice on a Hermes dev box. Confirm the ephemeral/WebRTC/tool‑call cycle end‑to‑end.

> **Status 2026‑06‑04:** `POST /api/realtime/session` mints an ephemeral `client_secret` server‑side from `VOICE_TOOLS_OPENAI_KEY` and returns `{client_secret, model, voice, expires_at, turn_detection, max_session_sec, idle_timeout_ms}` — the raw key never crosses the wire (unit‑tested in `tests/hermes_cli/test_realtime_session.py`, incl. no‑leak + missing‑key 503 + upstream‑error 502 + non‑dict‑body 502). A `realtime.*` config block is in `DEFAULT_CONFIG` + the web_server schema overlay + `.env.example` + `cli-config.yaml.example`. The throwaway WebRTC spike lives at `apps/desktop/src/app/dev/realtime-spike.tsx`, reachable at `#/realtime-spike` in dev builds; it runs `get_browser_time` through the full function‑call cycle and renders time‑to‑first‑voice.
>
> **Live verification 2026‑06‑04 (real OpenAI key):** ✅ The token mint was confirmed end‑to‑end against the live API — `POST /api/realtime/session` returns a real `ek_…` `gpt-realtime-2` ephemeral token + `expires_at`, with the raw key kept server‑side (no leak). ✅ The renderer's `session.update` shape (nested `audio.input.turn_detection` server_vad + `audio.output.voice` + `output_modalities:["audio"]` + the three tool definitions + `tool_choice`) was confirmed accepted (`session.updated`). ⚠️ Finding: the Realtime API rejects a session‑level `reasoning_effort` ("unknown_parameter") on BOTH the mint and `session.update`, so it is no longer sent on the wire (the `realtime.reasoning_effort` config key is advisory; gpt-realtime-2 already defaults to low). **Still browser‑manual:** the WebRTC SDP handshake, live audio in/out, the spoken function‑call round‑trip, and the actual time‑to‑first‑voice number — these need a real `RTCPeerConnection` + microphone. To measure: set `VOICE_TOOLS_OPENAI_KEY`, `npm run dev` in `apps/desktop`, open `#/realtime-spike` in the Electron window, click Start, speak, and read the TTFV readout.

**Phase 1 — MVP voice mode (the deliverable). ✅ DONE (code + unit tests) — live end‑to‑end verification PENDING key.**
1. ✅ Token endpoint + `realtime.*` config (§5 #1‑2).
2. ✅ `useRealtimeConversation` hook (`apps/desktop/src/app/chat/composer/hooks/use-realtime-conversation.ts`) as a drop‑in — identical surface `{start,end,status,level,muted,toggleMute,stopTurn}`; mode toggle in the composer + a "Voice Mode" setting (Appearance); mic level meter mirrors `use-mic-recorder` (`use-audio-level.ts`, no double mic acquisition); reuses the existing mic‑permission plumbing (§5 #3‑5).
3. ✅ `run_hermes_agent` tool → `requestGateway('prompt.submit', {session_id, text})` on the active session, consuming `message.delta`→`message.complete` → `function_call_output` + `response.create`; `scope:"new"` opens a fresh session via `session.create` (§4.2, §5 #6).
4. ✅ Chat‑Supervisor instructions + mandatory pre‑delegation filler + minimal §6.6 allow‑list (`realtime-session.ts` `REALTIME_INSTRUCTIONS`; §5 #7, §6.2).
5. ✅ Barge‑in (`turn_detection.interrupt_response` + `response.cancel` on `stopTurn`) + `cancel_running_work()` → `session.interrupt` (§6.3).
6. ✅ Session caps (`max_session_sec` timer; `idle_timeout_ms` via `turn_detection`) + usage monitor on `response.done` (§5 #8, §7).
- Coexist behind a setting: realtime is default; the classic STT→LLM→TTS loop stays intact and is selected when the toggle is off **or** the token mint fails (no key → auto‑fallback). Pure helpers unit‑tested in `realtime-session.test.ts` (17 cases).
**Exit:** spoken question → instant filler → Hermes agent runs (visible in chat) → spoken answer; barge‑in works; old voice mode still available as fallback. **Live walkthrough pending `VOICE_TOOLS_OPENAI_KEY`** (see Phase 0 status for how to run).

**Phase 2 — Server‑owned tools (north star).** Move tool handling to an OpenAI **sideband** server connection; replace `prompt.submit` with in‑process `AIAgent.run_conversation()` (model child setup on `delegate_task`); port shuvagent's `tools/` gate + telemetry for audited, risk‑tiered execution and confirmation UI. Add out‑of‑band spoken progress for long runs (§6.2). Add long‑session context summarization (§7).

**Phase 3 — Polish.** Semantic VAD tuning, double‑talk detection, multi‑agent parallel delegation (`delegate_task` batch), per‑task model routing (cheap vs. heavy backend), voice selection UI, telemetry dashboards (reuse shuvagent's first‑audio‑latency + usage events).

---

## 10. Decisions — LOCKED 2026‑06‑04

All seven resolved (Kyle). These are now the spec's assumptions, not open questions.

1. **Topology — Renderer WebRTC → sideband (A → C).** Phase 1: audio via WebRTC in the renderer + tool calls over `/api/ws prompt.submit`. Phase 2: move tool handling server‑side via an OpenAI sideband connection. The Python sidecar (Option B) is **not** the path. (§3)
2. **Session model — active chat session.** Voice turns delegate into the user's visible active session (work shows in the chat, agent has context). A `scope:"new"` arg on `run_hermes_agent` opens a scratch session on request. (§6.5)
3. **Delegation line — minimal; delegate almost everything.** The realtime model answers only greetings, clarifications, and state it was explicitly handed; everything substantive → Hermes. Allow‑list in §6.6.
4. **Sub‑agent model — same as the desktop chat agent.** Delegated runs use whatever model the user configured for chat; no separate realtime‑brain model. (Per‑task routing via `delegate_task` stays available later.) Satisfied automatically by Phase 1, since `prompt.submit` runs the configured chat agent.
5. **Barge‑in — speech‑only.** Interrupting stops the talking (`interrupt_response` + `response.cancel`); the in‑flight Hermes agent keeps running. An explicit "stop that" → `cancel_running_work()` → `session.interrupt` / `interrupt_subagent`. (§6.3)
6. **Rollout — coexist behind a setting.** Realtime is the default voice experience; the old STT→LLM→TTS loop stays as a fallback (offline / no OpenAI key). `/api/audio/*` stays (dictation + gateway need it). (§8, §9)
7. **Model — pin `gpt-realtime-2`** (flagship, released 2026‑05‑07), `reasoning_effort=low`.

---

## Appendix A — Verified OpenAI Realtime facts (2026‑06)
- **Model:** `gpt-realtime-2` is the current flagship realtime speech‑to‑speech model, **released 2026‑05‑07**, with configurable `reasoning_effort` (`minimal|low|medium|high|xhigh`, default `low`), parallel tool calls, and **spoken preambles** while calling tools. Lineage: `gpt-realtime` (GA 2025‑08‑28) → `gpt-realtime-1.5` (2026‑02‑23) → `gpt-realtime-2`. (developers.openai.com models/changelog.)
- **Transport:** WebRTC recommended for client/desktop; WebSocket for server‑to‑server. WebRTC carries native media (Opus/SDP) — no manual PCM framing. WebSocket uses PCM16 @ 24 kHz (`{type:"audio/pcm",rate:24000}`; output `audio/pcm` or `audio/pcmu` for telephony).
- **Ephemeral auth:** client mints a short‑lived `client_secret` server‑side for WebRTC; key never reaches the client.
- **Tool cycle:** model emits `function_call` in `response.done` (`call_id`+`arguments`); reply `conversation.item.create {type:"function_call_output", call_id, output}` then `response.create`; tools declared in `session.update.tools`.
- **Async/long‑running tools:** native and non‑blocking in `gpt-realtime`+; placeholder responses auto‑injected; no code change required.
- **Turn detection:** `session.audio.input.turn_detection` = `server_vad` (default; threshold/prefix_padding_ms/silence_duration_ms) | `semantic_vad` (eagerness) | `null`; `create_response`/`interrupt_response` toggle auto‑response and barge‑in; `idle_timeout_ms` auto‑prompts after silence.
- **Sideband:** WebRTC/SIP sessions support a 2nd server connection to the same session that can monitor, update instructions, and respond to tool calls.
- **First‑party pattern:** Chat‑Supervisor (`github.com/openai/openai-realtime-agents`) — fast realtime agent + filler + delegate to a smarter model via a tool. Agents‑SDK handoffs keep the same session model; to use a different/slower model you **delegate through tools** (realtime model as router).
- **Pricing (gpt‑realtime‑2):** ~$32/1M audio‑in, $64/1M audio‑out, $4/$24 text‑in/out, $0.40 cached‑in; ≈$0.18–0.46/min uncached (~10× cascade/min).

## Appendix B — In‑repo prior art
- `plugins/google_meet/realtime/openai_client.py` — an existing Hermes `RealtimeSession` (WebSocket to `wss://api.openai.com/v1/realtime?model=gpt-realtime`, PCM16, `response.cancel` barge‑in) — **text‑in → audio‑out only** (a Meet TTS speaker), not a full mic→tools loop, but proves the dependency/pattern already exist in‑tree.
- `gateway/stream_consumer.py:79‑92` — canonical sync‑callback → async‑stream bridge for `AIAgent`.
- `../shuvagent/shuvagent/realtime/openai_session.py` — full bidirectional Realtime WebSocket implementation to mine.
