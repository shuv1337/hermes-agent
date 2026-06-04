import { describe, expect, it } from 'vitest'

import {
  asString,
  buildFunctionCallOutput,
  buildSessionUpdate,
  buildToolDefinitions,
  buildTurnDetection,
  extractFunctionCall,
  isFirstVoiceEvent,
  parseToolArguments,
  type RealtimeRuntimeConfig,
  resolveScope
} from './realtime-session'

const config: RealtimeRuntimeConfig = {
  clientSecret: 'ek_test',
  delegationModel: '',
  delegationProvider: '',
  expiresAt: null,
  idleTimeoutMs: 15000,
  maxSessionSec: 300,
  model: 'gpt-realtime-2',
  turnDetection: 'server_vad',
  voice: 'marin'
}

describe('buildToolDefinitions', () => {
  it('exposes exactly the Phase 1 tool surface', () => {
    const names = buildToolDefinitions().map(tool => tool.name)

    expect(names).toEqual(['run_hermes_agent', 'get_active_session_summary', 'cancel_running_work'])
  })

  it('declares run_hermes_agent with a required task and a scope enum', () => {
    const run = buildToolDefinitions().find(tool => tool.name === 'run_hermes_agent')

    const params = run?.parameters as {
      properties: { scope: { enum: string[] } }
      required: string[]
    }

    expect(params.required).toContain('task')
    expect(params.properties.scope.enum).toEqual(['current_session', 'new'])
  })
})

describe('buildTurnDetection', () => {
  it('configures server_vad with barge-in and idle timeout', () => {
    const detection = buildTurnDetection('server_vad', 15000)

    expect(detection).toEqual({
      type: 'server_vad',
      create_response: true,
      interrupt_response: true,
      idle_timeout_ms: 15000
    })
  })

  it('omits idle_timeout_ms for semantic_vad', () => {
    const detection = buildTurnDetection('semantic_vad', 15000) as Record<string, unknown>

    expect(detection.type).toBe('semantic_vad')
    expect(detection).not.toHaveProperty('idle_timeout_ms')
  })

  it('omits idle_timeout_ms when zero', () => {
    expect(buildTurnDetection('server_vad', 0)).not.toHaveProperty('idle_timeout_ms')
  })

  it('returns null when detection is disabled', () => {
    expect(buildTurnDetection('none', 15000)).toBeNull()
  })
})

describe('buildSessionUpdate', () => {
  it('assembles the gpt-realtime-2 session shape', () => {
    const update = buildSessionUpdate(config) as {
      session: {
        audio: { input: { turn_detection: unknown }; output: { voice: string } }
        instructions: string
        output_modalities: string[]
        tool_choice: string
        tools: unknown[]
        type: string
      }
      type: string
    }

    expect(update.type).toBe('session.update')
    expect(update.session.type).toBe('realtime')
    expect(update.session.output_modalities).toEqual(['audio'])
    expect(update.session.audio.output.voice).toBe('marin')
    expect(update.session.audio.input.turn_detection).toMatchObject({ type: 'server_vad' })
    expect(update.session.tools).toHaveLength(3)
    expect(update.session.tool_choice).toBe('auto')
    expect(update.session.instructions).toContain('run_hermes_agent')
  })
})

describe('extractFunctionCall', () => {
  it('parses response.function_call_arguments.done', () => {
    const call = extractFunctionCall({
      type: 'response.function_call_arguments.done',
      call_id: 'call_1',
      name: 'run_hermes_agent',
      arguments: '{"task":"hi"}'
    })

    expect(call).toEqual({ argumentsJson: '{"task":"hi"}', callId: 'call_1', name: 'run_hermes_agent' })
  })

  it('parses response.output_item.done with a function_call item', () => {
    const call = extractFunctionCall({
      type: 'response.output_item.done',
      item: { type: 'function_call', call_id: 'call_2', name: 'cancel_running_work', arguments: '{}' }
    })

    expect(call).toEqual({ argumentsJson: '{}', callId: 'call_2', name: 'cancel_running_work' })
  })

  it('returns null for non-function-call events', () => {
    expect(extractFunctionCall({ type: 'response.audio.delta' })).toBeNull()
    expect(extractFunctionCall({ type: 'response.output_item.done', item: { type: 'message' } })).toBeNull()
  })

  it('defaults missing arguments to an empty object literal', () => {
    const call = extractFunctionCall({
      type: 'response.function_call_arguments.done',
      call_id: 'c',
      name: 'get_active_session_summary'
    })

    expect(call?.argumentsJson).toBe('{}')
  })
})

describe('parseToolArguments', () => {
  it('parses a JSON object', () => {
    expect(parseToolArguments('{"task":"x","scope":"new"}')).toEqual({ task: 'x', scope: 'new' })
  })

  it('falls back to {} for invalid or non-object JSON', () => {
    expect(parseToolArguments('not json')).toEqual({})
    expect(parseToolArguments('[1,2]')).toEqual({})
    expect(parseToolArguments('')).toEqual({})
  })
})

describe('resolveScope', () => {
  it('returns "new" only when explicitly requested', () => {
    expect(resolveScope({ scope: 'new' })).toBe('new')
    expect(resolveScope({ scope: 'current_session' })).toBe('current_session')
    expect(resolveScope({})).toBe('current_session')
    expect(resolveScope({ scope: 'garbage' })).toBe('current_session')
  })
})

describe('buildFunctionCallOutput', () => {
  it('wraps the result in a conversation.item.create envelope', () => {
    expect(buildFunctionCallOutput('call_9', '{"result":"ok"}')).toEqual({
      type: 'conversation.item.create',
      item: { type: 'function_call_output', call_id: 'call_9', output: '{"result":"ok"}' }
    })
  })
})

describe('isFirstVoiceEvent', () => {
  it('recognizes both audio-delta event names', () => {
    expect(isFirstVoiceEvent('response.output_audio.delta')).toBe(true)
    expect(isFirstVoiceEvent('response.audio.delta')).toBe(true)
    expect(isFirstVoiceEvent('response.created')).toBe(false)
  })
})

describe('asString', () => {
  it('coerces without throwing', () => {
    expect(asString('a')).toBe('a')
    expect(asString(null)).toBe('')
    expect(asString(undefined)).toBe('')
    expect(asString(42)).toBe('42')
  })
})
