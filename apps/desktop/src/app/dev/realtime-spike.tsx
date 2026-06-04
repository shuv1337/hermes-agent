/**
 * Phase 0 throwaway spike — NOT shipped in production.
 *
 * Opens a WebRTC connection to OpenAI GPT-Realtime using a backend-minted
 * ephemeral token, runs one trivial tool through the full function-call cycle,
 * and records time-to-first-voice. Mounted only in dev mode via the
 * `#/realtime-spike` hash (see main.tsx). Delete once Phase 1 lands.
 *
 * Requires VOICE_TOOLS_OPENAI_KEY on the backend; with no key the mint returns
 * 503 and the spike reports it (it does not crash).
 */
import { useCallback, useEffect, useRef, useState } from 'react'

import { createRealtimeSession } from '@/hermes'

const REALTIME_CALLS_URL = 'https://api.openai.com/v1/realtime/calls'

interface LogLine {
  at: number
  kind: 'error' | 'event' | 'info' | 'metric'
  text: string
}

// One trivial, instant local tool to exercise the function-call round-trip.
const SPIKE_TOOLS = [
  {
    type: 'function',
    name: 'get_browser_time',
    description: "Return the user's current local date and time. Use when asked what time it is.",
    parameters: { type: 'object', properties: {}, required: [] }
  }
]

const SPIKE_INSTRUCTIONS =
  'You are a realtime voice test harness. Keep replies to one short sentence. ' +
  'When the user asks for the time, call get_browser_time and read the result back conversationally.'

export function RealtimeSpike() {
  const [status, setStatus] = useState<'connected' | 'connecting' | 'error' | 'idle'>('idle')
  const [log, setLog] = useState<LogLine[]>([])

  const [ttfv, setTtfv] = useState<{ fromConnect: null | number; fromTurn: null | number }>({
    fromConnect: null,
    fromTurn: null
  })

  const pcRef = useRef<null | RTCPeerConnection>(null)
  const dcRef = useRef<null | RTCDataChannel>(null)
  const audioRef = useRef<HTMLAudioElement | null>(null)
  const micStreamRef = useRef<MediaStream | null>(null)
  const tConnectStart = useRef<null | number>(null)
  const tDcOpen = useRef<null | number>(null)
  const tSpeechStopped = useRef<null | number>(null)
  const firstVoiceSeen = useRef(false)

  const append = useCallback((kind: LogLine['kind'], text: string) => {
    setLog(prev => [...prev.slice(-200), { at: performance.now(), kind, text }])
    // Also mirror to the console for copy/paste during the spike.
    console.log(`[realtime-spike] ${kind}: ${text}`)
  }, [])

  const send = useCallback((payload: Record<string, unknown>) => {
    const dc = dcRef.current

    if (dc?.readyState === 'open') {
      dc.send(JSON.stringify(payload))
    }
  }, [])

  const markFirstVoice = useCallback(
    (source: string) => {
      if (firstVoiceSeen.current) {
        return
      }

      firstVoiceSeen.current = true
      const at = performance.now()
      const fromConnect = tDcOpen.current != null ? Math.round(at - tDcOpen.current) : null
      const fromTurn = tSpeechStopped.current != null ? Math.round(at - tSpeechStopped.current) : null
      setTtfv({ fromConnect, fromTurn })
      append(
        'metric',
        `TIME-TO-FIRST-VOICE (${source}): ${fromTurn != null ? `${fromTurn}ms from end-of-speech` : `${fromConnect ?? '?'}ms from connect`}`
      )
    },
    [append]
  )

  const runTool = useCallback(
    (name: string, callId: string) => {
      let output: string

      if (name === 'get_browser_time') {
        output = JSON.stringify({ now: new Date().toISOString(), tz: Intl.DateTimeFormat().resolvedOptions().timeZone })
      } else {
        output = JSON.stringify({ error: `unknown tool ${name}` })
      }

      send({ type: 'conversation.item.create', item: { type: 'function_call_output', call_id: callId, output } })
      send({ type: 'response.create' })
      append('info', `tool result sent for ${name}`)
    },
    [append, send]
  )

  const handleEvent = useCallback(
    (evt: Record<string, unknown>) => {
      const type = String(evt.type ?? '')

      switch (type) {
        case 'session.created':

        case 'session.updated':
          append('event', type)

          break

        case 'input_audio_buffer.speech_started':
          append('event', 'user speech started')
          firstVoiceSeen.current = false // arm next-turn measurement

          break

        case 'input_audio_buffer.speech_stopped':
          tSpeechStopped.current = performance.now()
          append('event', 'user speech stopped (turn end)')

          break

        case 'response.created':
          append('event', 'response.created')

          break

        case 'response.output_audio.delta':

        case 'response.audio.delta':
          markFirstVoice('audio.delta')

          break

        case 'response.output_audio_transcript.delta':
          break // noisy; ignore
        case 'response.function_call_arguments.done': {
          const name = String(evt.name ?? '')
          const callId = String(evt.call_id ?? '')

          append('event', `function_call: ${name}(${String(evt.arguments ?? '')})`)
          runTool(name, callId)

          break
        }

        case 'response.output_item.done': {
          const item = (evt.item ?? {}) as Record<string, unknown>

          if (item.type === 'function_call') {
            const name = String(item.name ?? '')
            const callId = String(item.call_id ?? '')

            append('event', `function_call (item): ${name}`)
            runTool(name, callId)
          }

          break
        }

        case 'response.done':
          append('event', 'response.done')

          break

        case 'error':
          append('error', JSON.stringify(evt.error ?? evt))

          break

        default:
          break
      }
    },
    [append, markFirstVoice, runTool]
  )

  const stop = useCallback(() => {
    dcRef.current?.close()
    dcRef.current = null
    pcRef.current?.getSenders().forEach(s => s.track?.stop())
    pcRef.current?.close()
    pcRef.current = null
    micStreamRef.current?.getTracks().forEach(t => t.stop())
    micStreamRef.current = null
    setStatus('idle')
    append('info', 'stopped')
  }, [append])

  const start = useCallback(async () => {
    if (!window.hermesDesktop?.api) {
      append('error', 'window.hermesDesktop.api unavailable — open this in the Electron app, not a plain browser.')
      setStatus('error')

      return
    }

    setStatus('connecting')
    setTtfv({ fromConnect: null, fromTurn: null })
    firstVoiceSeen.current = false
    tConnectStart.current = performance.now()
    tSpeechStopped.current = null

    let token: Awaited<ReturnType<typeof createRealtimeSession>>

    try {
      token = await createRealtimeSession()
      append('info', `minted ephemeral token (model=${token.model}, voice=${token.voice})`)
    } catch (error) {
      append('error', `token mint failed: ${error instanceof Error ? error.message : String(error)}`)
      setStatus('error')

      return
    }

    try {
      const pc = new RTCPeerConnection()
      pcRef.current = pc

      pc.ontrack = event => {
        if (audioRef.current) {
          audioRef.current.srcObject = event.streams[0]
        }

        append('info', 'remote audio track attached')
      }

      pc.onconnectionstatechange = () => append('event', `pc: ${pc.connectionState}`)

      const mic = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true } })
      micStreamRef.current = mic
      mic.getTracks().forEach(track => pc.addTrack(track, mic))

      const dc = pc.createDataChannel('oai-events')
      dcRef.current = dc

      dc.onopen = () => {
        tDcOpen.current = performance.now()
        const connectMs = tConnectStart.current != null ? Math.round(tDcOpen.current - tConnectStart.current) : null
        append('metric', `data channel open (connect: ${connectMs ?? '?'}ms)`)
        setStatus('connected')
        send({
          type: 'session.update',
          session: {
            type: 'realtime',
            instructions: SPIKE_INSTRUCTIONS,
            output_modalities: ['audio'],
            audio: {
              input: { turn_detection: { type: 'server_vad', create_response: true, interrupt_response: true } }
            },
            tools: SPIKE_TOOLS,
            tool_choice: 'auto'
          }
        })
      }

      dc.onmessage = e => {
        try {
          handleEvent(JSON.parse(e.data))
        } catch {
          /* ignore non-JSON frames */
        }
      }

      const offer = await pc.createOffer()
      await pc.setLocalDescription(offer)

      const sdpResponse = await fetch(REALTIME_CALLS_URL, {
        method: 'POST',
        body: offer.sdp,
        headers: { Authorization: `Bearer ${token.client_secret}`, 'Content-Type': 'application/sdp' }
      })

      if (!sdpResponse.ok) {
        throw new Error(`SDP exchange failed: HTTP ${sdpResponse.status}`)
      }

      await pc.setRemoteDescription({ type: 'answer', sdp: await sdpResponse.text() })
      append('info', 'SDP answer applied — speak, or click "Trigger reply"')
    } catch (error) {
      append('error', `WebRTC setup failed: ${error instanceof Error ? error.message : String(error)}`)
      setStatus('error')
      stop()
    }
  }, [append, handleEvent, send, stop])

  useEffect(() => () => stop(), [stop])

  return (
    <div style={{ fontFamily: 'monospace', maxWidth: 760, margin: '0 auto', padding: 24 }}>
      <h1 style={{ fontSize: 18 }}>Realtime voice spike (Phase 0, dev-only)</h1>
      <p style={{ color: '#888' }}>
        Status: <strong>{status}</strong>
      </p>
      <div style={{ display: 'flex', gap: 8, marginBottom: 12 }}>
        <button disabled={status === 'connecting' || status === 'connected'} onClick={() => void start()} type="button">
          Start
        </button>
        <button disabled={status !== 'connected'} onClick={() => send({ type: 'response.create' })} type="button">
          Trigger reply
        </button>
        <button disabled={status === 'idle'} onClick={stop} type="button">
          Stop
        </button>
      </div>
      <div style={{ background: '#111', color: '#0f0', padding: 12, borderRadius: 6, marginBottom: 12 }}>
        <div>time-to-first-voice (from end of speech): {ttfv.fromTurn != null ? `${ttfv.fromTurn} ms` : '—'}</div>
        <div>time-to-first-voice (from connect): {ttfv.fromConnect != null ? `${ttfv.fromConnect} ms` : '—'}</div>
      </div>
      <audio autoPlay ref={audioRef} />
      <pre style={{ background: '#0a0a0a', color: '#ccc', padding: 12, borderRadius: 6, height: 360, overflow: 'auto' }}>
        {log.map((line, i) => (
          <div key={i} style={{ color: line.kind === 'error' ? '#f66' : line.kind === 'metric' ? '#6cf' : '#ccc' }}>
            {`${Math.round(line.at)}  ${line.kind.toUpperCase()}  ${line.text}`}
          </div>
        ))}
      </pre>
    </div>
  )
}

export default RealtimeSpike
