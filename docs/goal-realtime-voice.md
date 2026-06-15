# Codex Goal — Realtime Voice Mode, Phase 0 + Phase 1

**Objective:** Land Phase 0 (spike) and Phase 1 (MVP) of the GPT‑Realtime‑2 voice mode for Hermes Desktop per the locked spec, so a user can hold a low‑latency spoken conversation where the realtime model delegates real work to a Hermes agent in the active chat session — with the old voice mode preserved as a fallback.

## Read first
- `PLAN-realtime-voice-mode.md` — the contract. §5 component checklist, §6 behaviors, §9 phased plan, §10 LOCKED decisions, Appendix A (verified OpenAI Realtime facts).
- `hermes_cli/web_server.py` — REST + `/api/ws`; `/api/audio/transcribe` (~:1320), `/api/audio/speak` (~:1455), server‑side key pattern (ELEVENLABS ~:1412), config allowlist (~:370‑382), `/api/ws` mount (~:7461).
- `apps/desktop/src/hermes.ts` — `transcribeAudio` (~:571), `speakText` (~:582), `HermesGateway` (~:102).
- `apps/desktop/src/app/chat/composer/hooks/use-voice-conversation.ts` — the loop to coexist with; **match its public hook surface**.
- `apps/desktop/src/app/chat/composer/hooks/use-mic-recorder.ts` — reuse for the level‑meter viz.
- `apps/desktop/src/app/chat/composer/controls.tsx` (~:67‑80, the button) and `composer/index.tsx` (~:1134‑1142, where the hook is built).
- `apps/desktop/src/app/session/hooks/use-prompt-actions.ts` (~:332, `prompt.submit`) and `.../use-message-stream.ts` (event→`$messages`).
- `plugins/google_meet/realtime/openai_client.py` — in‑repo Realtime client (prior art); `../shuvagent/shuvagent/realtime/openai_session.py` — wire‑protocol reference.

## Context — locked decisions (from §10)
1. Topology: **renderer WebRTC** for audio + tool calls over **`/api/ws prompt.submit`** (Phase 2 sideband is OUT of this goal). 2. Voice runs in the **active chat session** (+ `scope:"new"`). 3. **Minimal** delegation line (allow‑list §6.6); delegate everything substantive. 4. Sub‑agents use the **same model as the desktop chat agent** (auto via `prompt.submit`). 5. Barge‑in = **speech‑only**; explicit "stop" kills the agent. 6. **Coexist** behind a setting; keep `/api/audio/*`. 7. Pin **`gpt-realtime-2`**, `reasoning_effort=low`. Key from `VOICE_TOOLS_OPENAI_KEY`.

## Scope
**Do — Phase 0:**
- Add a `realtime.*` config block (model, voice, reasoning_effort, turn_detection, max_session_sec, idle_timeout_ms) to the config schema + `web_server` allowlist + `cli-config.yaml.example` + `.env.example`. Defaults: `model=gpt-realtime-2`, `reasoning_effort=low`.
- Add `POST /api/realtime/session` minting an OpenAI Realtime ephemeral `client_secret` **server‑side** (key never returned to the renderer); works in local‑spawn AND remote‑backend modes; returns `{client_secret, model, voice, expires_at}`.
- A throwaway, dev‑only WebRTC spike (scratch route/component) that opens WebRTC to `gpt-realtime-2` with the ephemeral token, does a plain voice exchange with one trivial tool, and **logs/records time‑to‑first‑voice**.

**Do — Phase 1:**
- `useRealtimeConversation` hook = **drop‑in for `useVoiceConversation`** (identical surface: `{start,end,status,level,muted,toggleMute,stopTurn}`). Opens WebRTC (`getUserMedia`→`pc.addTrack`, `pc.ontrack`→`<audio>`, SDP offer w/ ephemeral token); reuse `use-mic-recorder` for the level meter.
- Tools declared in `session.update`: `run_hermes_agent(task, scope?, toolsets?)`, a couple of fast local context tools, and `cancel_running_work()`. On `run_hermes_agent` → `requestGateway('prompt.submit',{session_id:<active>, text})` → consume `message.delta` to `message.complete` → return `conversation.item.create {function_call_output, call_id, output}` + `response.create`. `scope:"new"` opens a scratch session.
- Chat‑Supervisor instructions with the §6.6 minimal allow‑list + **mandatory pre‑delegation filler**.
- Barge‑in: `turn_detection: server_vad` with `interrupt_response`; `cancel_running_work` → `session.interrupt`.
- Session/cost guards: `max_session_sec`, `idle_timeout_ms`, usage monitor on `response.done`.
- Coexist: a setting/toggle in `controls.tsx`/`composer` selects realtime vs. the old loop; old loop stays intact.

**Do NOT:**
- Touch `tools/transcription_tools.py`, `tools/tts_tool.py`, or the gateway `_voice_mode` (telegram/discord) — keep `/api/audio/*` working.
- Build Phase 2 (sideband / in‑process `AIAgent` tool execution).
- Put the OpenAI key anywhere in the renderer; reuse shuvagent's synchronous/blocking tool dispatch; or broadly refactor the desktop chat/session code.

## Checkpoints
1. Read the PLAN + files above; confirm `web_server.py` REST/ws + `/api/audio/*` + server‑key pattern + config allowlist, and the `useVoiceConversation` hook surface. Record exact line anchors.
2. Phase 0 config + `POST /api/realtime/session`; verify token mint with `curl` (assert no key leak in the response); add a focused Python test.
3. Phase 0 WebRTC spike → **measure and record time‑to‑first‑voice**; confirm the full tool‑call cycle. **PAUSE and report the latency before starting Phase 1.**
4. Phase 1 `useRealtimeConversation` (matching surface) + coexist toggle (old loop untouched).
5. Phase 1 `run_hermes_agent`→`prompt.submit` on the active session + `function_call_output` return; Chat‑Supervisor instructions + allow‑list; barge‑in + `cancel_running_work`; session/cost guards.
6. Validation + update §9 phase status in `PLAN-realtime-voice-mode.md` (completed items only).

## Validation loop
- After Python changes: `uv run ruff check .` and focused `uv run pytest tests/ -m 'not integration' -k "realtime or audio or web_server"`.
- After renderer/TS changes (run inside `apps/desktop`): `npm run type-check`, `npm run lint`, `npm run test:ui`.
- Before declaring done: `npm run build` in `apps/desktop` plus the focused pytest + ruff above.
- Live OpenAI checks need `VOICE_TOOLS_OPENAI_KEY`; **gate them** — if the key is absent, skip and report as a manual step, don't fail the run.
- On failure: diagnose, smallest safe fix, rerun that check.

## Progress log
Keep concise notes in the final response (checkpoint reached, files changed, validation run, remaining work) and update the §9 phase status in `PLAN-realtime-voice-mode.md`.

## Pause and ask before
- The checkpoint‑3 latency report (pause before Phase 1).
- Any change to `transcription_tools`/`tts_tool`/gateway voice; any config‑schema change that risks breaking validation; removing the old voice loop; anything requiring the OpenAI key when it's absent; broad refactors.

## Stopping condition
Stop when: `POST /api/realtime/session` mints a token with the key kept server‑side (test passing); the Phase 0 spike has a recorded time‑to‑first‑voice; `useRealtimeConversation` works as a drop‑in behind a setting with the old mode still selectable; `run_hermes_agent` delegates over `prompt.submit` to the active session and the model speaks the result with pre‑delegation filler and working barge‑in; validation passes (`type-check`/`lint`/`test:ui`/`build` + focused `pytest`/`ruff`); the §9 phase status is updated; and the final response summarizes changed files, validation results, the measured latency, and follow‑ups (Phase 2 sideband).
