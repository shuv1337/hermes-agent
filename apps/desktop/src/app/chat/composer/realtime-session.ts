/**
 * Pure helpers for the realtime voice mode (Phase 1) — kept free of React and
 * WebRTC so they can be unit-tested in isolation. The stateful WebRTC/gateway
 * wiring lives in `hooks/use-realtime-conversation.ts`.
 *
 * Wire protocol references: PLAN-realtime-voice-mode.md Appendix A and the
 * shuvagent `openai_session.py` gpt-realtime-2 session shape.
 */

/** GA WebRTC SDP-exchange endpoint. The model is bound to the ephemeral key. */
export const REALTIME_CALLS_URL = 'https://api.openai.com/v1/realtime/calls'

/** Data-channel name OpenAI expects for realtime control events. */
export const OAI_EVENTS_CHANNEL = 'oai-events'

export type RealtimeScope = 'current_session' | 'new'

export interface RealtimeRuntimeConfig {
  clientSecret: string
  /** Per-turn model override for run_hermes_agent (empty = desktop chat model). */
  delegationModel: string
  /** Optional explicit provider for the delegation model. */
  delegationProvider: string
  expiresAt: null | number
  idleTimeoutMs: number
  maxSessionSec: number
  model: string
  /** Semantic VAD eagerness (low|medium|high|auto), used only for semantic_vad. */
  semanticVadEagerness: string
  turnDetection: string
  voice: string
}

export interface RealtimeFunctionCall {
  argumentsJson: string
  callId: string
  name: string
}

/**
 * Chat-Supervisor instructions (PLAN §6.6, §6.2). The realtime model is a thin,
 * fast router: it may handle only social glue / clarifications / state it was
 * just handed, and MUST delegate anything substantive to `run_hermes_agent`,
 * always speaking a short filler first so the ~2s round-trip never feels dead.
 */
export const REALTIME_INSTRUCTIONS = [
  'You are the voice front-end of Hermes, a capable AI agent. You are a fast,',
  'friendly router — NOT the brain. A full Hermes agent does the real work.',
  '',
  'You may answer DIRECTLY, without any tool, ONLY for:',
  '- Greetings, acknowledgements, and social glue ("hi", "thanks", "one sec").',
  '- Clarifying questions back to the user ("which repo do you mean?").',
  '- Reading back state you were explicitly handed THIS turn (a summary the',
  '  agent just produced, or the result of a fast context tool).',
  '- Meta about the conversation itself ("what did you just say?").',
  '',
  'For ANYTHING ELSE — facts, files, code, the web, memory, math, tools, or any',
  'multi-step reasoning — you MUST call run_hermes_agent. When unsure, delegate.',
  'NEVER answer a factual or task question from your own knowledge: a confident',
  'wrong answer in the user\'s own voice is the worst outcome.',
  '',
  'CRITICAL: before EVERY run_hermes_agent call, first SAY a brief, natural',
  'filler out loud so the user is not left in silence — e.g. "Let me look into',
  'that.", "One moment, checking now.", "Sure, pulling that up." Then call the',
  'tool. While it runs you may add a short "still working on it" if it is slow.',
  '',
  'When the tool returns, speak a concise, conversational summary of the result.',
  'Do NOT read raw agent output verbatim unless the user asks. Keep spoken',
  'replies short. Use cancel_running_work only when the user clearly asks you to',
  'stop the work in progress.'
].join('\n')

/** OpenAI function-tool definitions advertised in session.update. */
export function buildToolDefinitions(): Array<Record<string, unknown>> {
  return [
    {
      type: 'function',
      name: 'run_hermes_agent',
      description:
        'Delegate real work to a full Hermes agent in the current chat session: ' +
        'answering factual/task questions, reading or editing files, running code or ' +
        'tools, searching the web, recalling memory, or any multi-step reasoning. ' +
        'The agent has full tools and context. Always speak a short filler before calling.',
      parameters: {
        type: 'object',
        properties: {
          task: {
            type: 'string',
            description: 'The task or question to hand to the agent, in clear natural language.'
          },
          scope: {
            type: 'string',
            enum: ['current_session', 'new'],
            description:
              'Where to run. "current_session" (default) uses the visible chat so work ' +
              'appears in history; "new" opens a fresh scratch session for unrelated work.'
          },
          toolsets: {
            type: 'array',
            items: { type: 'string' },
            description: 'Optional hint of toolset names the task needs (usually omit).'
          }
        },
        required: ['task']
      }
    },
    {
      type: 'function',
      name: 'get_active_session_summary',
      description:
        'Instantly read back the gist of the current chat (last assistant message / title) ' +
        'without delegating. Use only to recap state you were just handed.',
      parameters: { type: 'object', properties: {}, required: [] }
    },
    {
      type: 'function',
      name: 'cancel_running_work',
      description:
        'Stop the Hermes agent work currently in progress. Use when the user explicitly ' +
        'says to stop, cancel, or never mind the running task.',
      parameters: { type: 'object', properties: {}, required: [] }
    }
  ]
}

/** Build the turn_detection block for session.update from the configured mode. */
export function buildTurnDetection(
  mode: string,
  idleTimeoutMs: number,
  semanticVadEagerness?: string
): null | Record<string, unknown> {
  if (mode === 'none') {
    return null
  }

  const isSemantic = mode === 'semantic_vad'

  const detection: Record<string, unknown> = {
    type: isSemantic ? 'semantic_vad' : 'server_vad',
    create_response: true,
    // Barge-in: user speech auto-cancels the model's current audio (speech-only).
    interrupt_response: true
  }

  // idle_timeout_ms auto-prompts after silence; only valid for server_vad.
  if (!isSemantic && idleTimeoutMs > 0) {
    detection.idle_timeout_ms = idleTimeoutMs
  }

  // eagerness (how readily the model takes a turn) only applies to semantic_vad.
  if (isSemantic && semanticVadEagerness) {
    detection.eagerness = semanticVadEagerness
  }

  return detection
}

/** Assemble the session.update payload sent over the data channel on open. */
export function buildSessionUpdate(config: RealtimeRuntimeConfig): Record<string, unknown> {
  return {
    type: 'session.update',
    session: {
      type: 'realtime',
      instructions: REALTIME_INSTRUCTIONS,
      output_modalities: ['audio'],
      audio: {
        input: {
          turn_detection: buildTurnDetection(config.turnDetection, config.idleTimeoutMs, config.semanticVadEagerness)
        },
        output: { voice: config.voice }
      },
      tools: buildToolDefinitions(),
      tool_choice: 'auto'
    }
  }
}

// Realtime control-flow errors that are EXPECTED during normal barge-in /
// cancel / out-of-band-response races — e.g. cancelling when nothing is
// speaking, or a response.create that raced an in-flight response. These are
// not real failures and must not surface as user-facing error toasts.
const BENIGN_REALTIME_ERROR_PATTERNS: readonly RegExp[] = [
  /no active response/i,
  /cancellation failed/i,
  /already has an active response/i,
  /conversation already has an active response/i
]

/**
 * True for benign realtime control-flow errors (see patterns above) that should
 * be logged-and-ignored rather than shown to the user.
 */
export function isBenignRealtimeError(message: string): boolean {
  return BENIGN_REALTIME_ERROR_PATTERNS.some(pattern => pattern.test(message))
}

/** Coerce an unknown event field to a string without throwing. */
export function asString(value: unknown): string {
  if (typeof value === 'string') {
    return value
  }

  if (value == null) {
    return ''
  }

  return String(value)
}

/**
 * Extract a function call from a realtime event, handling both the
 * `response.function_call_arguments.done` shape (call_id/name/arguments at the
 * top level) and the `response.output_item.done` shape (nested under item).
 * Returns null for any non-function-call event.
 */
export function extractFunctionCall(event: Record<string, unknown>): null | RealtimeFunctionCall {
  const type = asString(event.type)

  if (type === 'response.function_call_arguments.done') {
    const callId = asString(event.call_id)
    const name = asString(event.name)

    if (!callId || !name) {
      return null
    }

    return { argumentsJson: asString(event.arguments) || '{}', callId, name }
  }

  if (type === 'response.output_item.done') {
    const item = (event.item ?? {}) as Record<string, unknown>

    if (asString(item.type) === 'function_call') {
      const callId = asString(item.call_id)
      const name = asString(item.name)

      if (!callId || !name) {
        return null
      }

      return { argumentsJson: asString(item.arguments) || '{}', callId, name }
    }
  }

  return null
}

/** Safely parse a tool's JSON arguments string into an object. */
export function parseToolArguments(argumentsJson: string): Record<string, unknown> {
  try {
    const parsed = JSON.parse(argumentsJson || '{}')

    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? (parsed as Record<string, unknown>) : {}
  } catch {
    return {}
  }
}

/** Resolve the scope argument from parsed tool args (defaults to current). */
export function resolveScope(args: Record<string, unknown>): RealtimeScope {
  return args.scope === 'new' ? 'new' : 'current_session'
}

/** Build the conversation.item.create payload that returns a tool result. */
export function buildFunctionCallOutput(callId: string, output: string): Record<string, unknown> {
  return { type: 'conversation.item.create', item: { type: 'function_call_output', call_id: callId, output } }
}

/** True when the event signals the model has started emitting audio. */
export function isFirstVoiceEvent(type: string): boolean {
  return type === 'response.output_audio.delta' || type === 'response.audio.delta'
}
