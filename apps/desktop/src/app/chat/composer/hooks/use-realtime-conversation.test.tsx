import { act, renderHook } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { setGateway } from '@/store/session'

import { useRealtimeConversation } from './use-realtime-conversation'

// notify/notifyError are spied so we can assert the benign-error filter.
vi.mock('@/store/notifications', async orig => ({
  ...(await orig<Record<string, unknown>>()),
  notify: vi.fn(),
  notifyError: vi.fn()
}))

import { notifyError } from '@/store/notifications'
import { $activeSessionId, $messages } from '@/store/session'

// ── Test doubles for the WebRTC + gateway surface the hook touches ──────────

interface MockDc {
  close: ReturnType<typeof vi.fn>
  onmessage: ((event: { data: string }) => void) | null
  onopen: (() => void) | null
  readyState: string
  send: ReturnType<typeof vi.fn>
}

let lastDc: MockDc | null = null

class MockDataChannel implements MockDc {
  close = vi.fn()
  onmessage: ((event: { data: string }) => void) | null = null
  onopen: (() => void) | null = null
  readyState = 'open'
  send = vi.fn()
}

class MockPeerConnection {
  addTrack = vi.fn(() => ({}))
  close = vi.fn()
  createDataChannel = vi.fn(() => {
    lastDc = new MockDataChannel()

    return lastDc
  })
  createOffer = vi.fn(async () => ({ sdp: 'offer-sdp', type: 'offer' }))
  getSenders = vi.fn(() => [])
  ontrack: ((event: unknown) => void) | null = null
  setLocalDescription = vi.fn(async () => undefined)
  setRemoteDescription = vi.fn(async () => undefined)
}

const MINTED_TOKEN = {
  client_secret: 'ek_test',
  delegation_model: 'google/gemini-3.1-flash-lite',
  delegation_provider: '',
  expires_at: null,
  idle_timeout_ms: 0,
  max_session_sec: 0,
  model: 'gpt-realtime-2',
  semantic_vad_eagerness: 'auto',
  turn_detection: 'server_vad',
  voice: 'marin'
}

interface MockGateway {
  emit: (name: string, event: Record<string, unknown>) => void
  on: ReturnType<typeof vi.fn>
  request: ReturnType<typeof vi.fn>
}

function makeGateway(): MockGateway {
  const handlers = new Map<string, Array<(event: Record<string, unknown>) => void>>()

  return {
    emit: (name, event) => (handlers.get(name) ?? []).slice().forEach(handler => handler(event)),
    on: vi.fn((name: string, handler: (event: Record<string, unknown>) => void) => {
      const arr = handlers.get(name) ?? []
      arr.push(handler)
      handlers.set(name, arr)

      return () => handlers.set(name, (handlers.get(name) ?? []).filter(h => h !== handler))
    }),
    request: vi.fn(async (method: string) => (method === 'session.create' ? { session_id: 'new-sess' } : undefined))
  }
}

let gateway: MockGateway
let apiMock: ReturnType<typeof vi.fn>

beforeEach(() => {
  lastDc = null
  vi.useFakeTimers()
  gateway = makeGateway()
  setGateway(gateway as never)
  $activeSessionId.set('sess-1')
  $messages.set([])

  apiMock = vi.fn(async (req: { path: string }) => {
    if (req.path === '/api/realtime/session') {
      return MINTED_TOKEN
    }

    return undefined
  })

  Object.defineProperty(window, 'hermesDesktop', { configurable: true, value: { api: apiMock } })
  Object.defineProperty(navigator, 'mediaDevices', {
    configurable: true,
    value: {
      getUserMedia: vi.fn(async () => ({
        getAudioTracks: () => [{ enabled: true, stop: vi.fn() }],
        getTracks: () => [{ stop: vi.fn() }]
      }))
    }
  })
  vi.stubGlobal('RTCPeerConnection', MockPeerConnection as never)
  vi.stubGlobal(
    'fetch',
    vi.fn(async () => ({ ok: true, status: 200, text: async () => 'answer-sdp' }))
  )
})

afterEach(() => {
  vi.runOnlyPendingTimers()
  vi.useRealTimers()
  vi.restoreAllMocks()
  vi.unstubAllGlobals()
  setGateway(null as never)
})

function render(cwd = '/repo') {
  return renderHook(() => useRealtimeConversation({ busy: false, cwd, enabled: false, onFatalError: vi.fn() }))
}

async function startAndOpen(cwd = '/repo') {
  const view = render(cwd)

  await act(async () => {
    await view.result.current.start()
  })
  act(() => lastDc?.onopen?.())

  return view
}

/** Push a realtime data-channel event through the hook's onmessage handler. */
function emit(event: Record<string, unknown>) {
  act(() => lastDc?.onmessage?.({ data: JSON.stringify(event) }))
}

/** All JSON payloads the hook has sent over the data channel. */
function sent(): Array<Record<string, unknown>> {
  return (lastDc?.send.mock.calls ?? []).map(call => JSON.parse(call[0] as string))
}

function sentTypes(): string[] {
  return sent().map(payload => String(payload.type))
}

async function flush() {
  await act(async () => {
    await Promise.resolve()
    await Promise.resolve()
  })
}

const RUN_CALL = (callId = 'call-1', args: Record<string, unknown> = { scope: 'current_session', task: 'do it' }) => ({
  arguments: JSON.stringify(args),
  call_id: callId,
  name: 'run_hermes_agent',
  type: 'response.function_call_arguments.done'
})

describe('useRealtimeConversation — startup', () => {
  it('opens WebRTC and sends session.update on data-channel open', async () => {
    const view = await startAndOpen()

    expect(apiMock).toHaveBeenCalledWith({ method: 'POST', path: '/api/realtime/session' })
    expect(sentTypes()).toContain('session.update')
    expect(view.result.current.status).toBe('listening')
  })

  it('falls back via onFatalError when the token mint fails', async () => {
    apiMock.mockRejectedValueOnce(new Error('no key'))
    const onFatalError = vi.fn()

    const view = renderHook(() =>
      useRealtimeConversation({ busy: false, cwd: '/repo', enabled: false, onFatalError })
    )

    await act(async () => {
      await view.result.current.start()
    })

    expect(onFatalError).toHaveBeenCalledWith('no key')
    expect(view.result.current.status).toBe('idle')
  })
})

describe('useRealtimeConversation — response.cancel gating (hardening)', () => {
  it('does not send response.cancel when no response is active', async () => {
    const view = await startAndOpen()
    act(() => view.result.current.stopTurn())

    expect(sentTypes()).not.toContain('response.cancel')
  })

  it('sends response.cancel only while a response is active', async () => {
    const view = await startAndOpen()
    emit({ type: 'response.created' })
    act(() => view.result.current.stopTurn())
    expect(sentTypes()).toContain('response.cancel')

    lastDc?.send.mockClear()
    emit({ response: {}, type: 'response.done' })
    act(() => view.result.current.stopTurn())
    expect(sentTypes()).not.toContain('response.cancel')
  })
})

describe('useRealtimeConversation — error filtering (hardening)', () => {
  it('suppresses benign control-flow errors', async () => {
    await startAndOpen()
    emit({ error: { message: 'Cancellation failed: no active response' }, type: 'error' })

    expect(notifyError).not.toHaveBeenCalled()
  })

  it('surfaces real errors', async () => {
    await startAndOpen()
    emit({ error: { message: 'Invalid API key' }, type: 'error' })

    expect(notifyError).toHaveBeenCalled()
  })

  it('clears the active-response flag on error so a later stop is a no-op', async () => {
    const view = await startAndOpen()
    emit({ type: 'response.created' })
    emit({ error: { message: 'Invalid API key' }, type: 'error' })
    act(() => view.result.current.stopTurn())

    expect(sentTypes()).not.toContain('response.cancel')
  })
})

describe('useRealtimeConversation — delegation', () => {
  it('threads cwd and the minted delegation model into prompt.submit', async () => {
    await startAndOpen('/repo')
    emit(RUN_CALL())
    await flush()

    const submit = gateway.request.mock.calls.find(call => call[0] === 'prompt.submit')
    expect(submit?.[1]).toMatchObject({
      cwd: '/repo',
      model: 'google/gemini-3.1-flash-lite',
      session_id: 'sess-1',
      text: 'do it'
    })
  })

  it('returns the agent result as a function_call_output then asks the model to speak', async () => {
    await startAndOpen()
    emit(RUN_CALL())
    await flush()

    gateway.emit('message.start', { session_id: 'sess-1' })
    gateway.emit('message.delta', { payload: { text: 'partial' }, session_id: 'sess-1' })
    await act(async () => {
      gateway.emit('message.complete', { payload: { text: 'final answer' }, session_id: 'sess-1' })
      await Promise.resolve()
    })

    const output = sent().find(payload => payload.type === 'conversation.item.create')
    expect((output?.item as { output: string }).output).toContain('final answer')
    expect(sentTypes()).toContain('response.create')
  })

  it('ignores turn events that arrive before the prompt.submit ack', async () => {
    let resolveAck: () => void = () => undefined
    gateway.request.mockImplementationOnce(
      () => new Promise<undefined>(resolve => (resolveAck = () => resolve(undefined)))
    )
    await startAndOpen()
    emit(RUN_CALL())

    // Pre-ack stream for the session must not latch as our delegation result.
    gateway.emit('message.start', { session_id: 'sess-1' })
    gateway.emit('message.complete', { payload: { text: 'wrong turn' }, session_id: 'sess-1' })

    expect(sent().some(p => JSON.stringify(p).includes('wrong turn'))).toBe(false)

    await act(async () => {
      resolveAck()
      await Promise.resolve()
    })
  })

  it('handles a tool call once even when it arrives as both event shapes', async () => {
    await startAndOpen()
    emit(RUN_CALL('dup-call'))
    emit({
      item: {
        arguments: JSON.stringify({ task: 'do it' }),
        call_id: 'dup-call',
        name: 'run_hermes_agent',
        type: 'function_call'
      },
      type: 'response.output_item.done'
    })
    await flush()

    const submits = gateway.request.mock.calls.filter(call => call[0] === 'prompt.submit')
    expect(submits).toHaveLength(1)
  })

  it('opens a fresh session for scope:"new"', async () => {
    await startAndOpen()
    emit(RUN_CALL('c2', { scope: 'new', task: 'unrelated' }))
    await flush()

    expect(gateway.request).toHaveBeenCalledWith('session.create', { cols: 96 })
    const submit = gateway.request.mock.calls.find(call => call[0] === 'prompt.submit')
    expect(submit?.[1]).toMatchObject({ session_id: 'new-sess' })
  })

  it('answers get_active_session_summary locally without delegating', async () => {
    $messages.set([{ hidden: false, id: 'a1', parts: [{ text: 'the last answer', type: 'text' }], role: 'assistant' }] as never)
    await startAndOpen()
    emit({ call_id: 'c3', name: 'get_active_session_summary', type: 'response.function_call_arguments.done' })

    const output = sent().find(payload => payload.type === 'conversation.item.create')
    expect((output?.item as { output: string }).output).toContain('the last answer')
    expect(gateway.request).not.toHaveBeenCalledWith('prompt.submit', expect.anything())
  })

  it('cancel_running_work interrupts the active delegation', async () => {
    await startAndOpen()
    emit(RUN_CALL())
    await flush()

    emit({ call_id: 'c4', name: 'cancel_running_work', type: 'response.function_call_arguments.done' })

    expect(gateway.request).toHaveBeenCalledWith('session.interrupt', { session_id: 'sess-1' })
  })
})

describe('useRealtimeConversation — nudge backpressure (hardening)', () => {
  it('speaks an out-of-band reassurance while a delegation is pending', async () => {
    await startAndOpen()
    emit(RUN_CALL())
    await flush()
    lastDc?.send.mockClear()

    await act(async () => {
      await vi.advanceTimersByTimeAsync(15_000)
    })

    const nudge = sent().find(
      payload => payload.type === 'response.create' && (payload.response as { conversation?: string })?.conversation === 'none'
    )

    expect(nudge).toBeTruthy()
  })

  it('skips the nudge while a response is already in flight', async () => {
    await startAndOpen()
    emit(RUN_CALL())
    await flush()
    emit({ type: 'response.created' })
    lastDc?.send.mockClear()

    await act(async () => {
      await vi.advanceTimersByTimeAsync(15_000)
    })

    expect(sentTypes()).not.toContain('response.create')
  })
})

describe('useRealtimeConversation — teardown', () => {
  it('interrupts the in-flight agent turn on unmount', async () => {
    const view = await startAndOpen()
    emit(RUN_CALL())
    await flush()
    gateway.request.mockClear()

    act(() => view.unmount())

    expect(gateway.request).toHaveBeenCalledWith('session.interrupt', { session_id: 'sess-1' })
  })
})
