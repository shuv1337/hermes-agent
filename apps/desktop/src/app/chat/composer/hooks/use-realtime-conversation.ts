import { useCallback, useEffect, useRef, useState } from 'react'

import { createRealtimeSession } from '@/hermes'
import { chatMessageText } from '@/lib/chat-messages'
import { notify, notifyError } from '@/store/notifications'
import { $activeSessionId, $gateway, $messages } from '@/store/session'
import type { SessionCreateResponse } from '@/types/hermes'

import {
  asString,
  buildFunctionCallOutput,
  buildSessionUpdate,
  extractFunctionCall,
  isFirstVoiceEvent,
  OAI_EVENTS_CHANNEL,
  parseToolArguments,
  REALTIME_CALLS_URL,
  type RealtimeRuntimeConfig,
  type RealtimeScope,
  resolveScope
} from '../realtime-session'

import { useAudioLevel } from './use-audio-level'
import type { ConversationStatus } from './use-voice-conversation'

// Cap a single delegated run, and periodically reassure the user out loud so a
// slow or wedged agent turn never leaves dead air / an endless silent spinner.
// 15s first-fire so typical (≤~10s) turns finish before any nudge interrupts.
const MAX_DELEGATION_MS = 60_000
const NUDGE_INTERVAL_MS = 15_000

interface RealtimeConversationOptions {
  busy: boolean
  /** Desktop's current workspace cwd; delegated turns run here. */
  cwd?: null | string
  enabled: boolean
  /** Called on an unrecoverable error (e.g. no key) so the caller can fall back. */
  onFatalError?: (reason: string) => void
}

interface ActiveDelegation {
  cancel: () => void
  sessionId: string
}

export function useRealtimeConversation({ cwd, enabled, onFatalError }: RealtimeConversationOptions) {
  const { level, start: startMeter, stop: stopMeter } = useAudioLevel()
  const [status, setStatus] = useState<ConversationStatus>('idle')
  const [muted, setMuted] = useState(false)

  const pcRef = useRef<null | RTCPeerConnection>(null)
  const dcRef = useRef<null | RTCDataChannel>(null)
  const micStreamRef = useRef<MediaStream | null>(null)
  const audioElRef = useRef<HTMLAudioElement | null>(null)
  const sessionTimerRef = useRef<null | number>(null)
  const nudgeTimerRef = useRef<null | number>(null)
  const delegationRef = useRef<ActiveDelegation | null>(null)
  const usageRef = useRef<{ input: number; output: number }>({ input: 0, output: 0 })
  // De-dupe tool calls: the model emits BOTH response.function_call_arguments.done
  // and response.output_item.done for one call_id — handle each call_id once.
  const handledCallIdsRef = useRef<Set<string>>(new Set())
  // Per-turn delegation model override (from realtime.delegation_model) passed
  // to prompt.submit so voice runs on a fast model while typed chat is unchanged.
  const delegationModelRef = useRef('')
  const delegationProviderRef = useRef('')
  const cwdRef = useRef(cwd || '')

  useEffect(() => {
    cwdRef.current = cwd || ''
  }, [cwd])

  const enabledRef = useRef(enabled)
  const mutedRef = useRef(muted)
  const statusRef = useRef<ConversationStatus>('idle')
  const wasEnabledRef = useRef(false)

  useEffect(() => {
    enabledRef.current = enabled
  }, [enabled])

  useEffect(() => {
    mutedRef.current = muted
  }, [muted])

  useEffect(() => {
    statusRef.current = status
  }, [status])

  const send = useCallback((payload: Record<string, unknown>) => {
    const dc = dcRef.current

    if (dc?.readyState === 'open') {
      dc.send(JSON.stringify(payload))
    }
  }, [])

  const clearSessionTimer = useCallback(() => {
    if (sessionTimerRef.current) {
      window.clearTimeout(sessionTimerRef.current)
      sessionTimerRef.current = null
    }
  }, [])

  const clearNudge = useCallback(() => {
    if (nudgeTimerRef.current) {
      window.clearInterval(nudgeTimerRef.current)
      nudgeTimerRef.current = null
    }
  }, [])

  const teardown = useCallback(() => {
    clearSessionTimer()
    clearNudge()
    // Ending the session is not barge-in: interrupt the server-side agent turn
    // so a delegated run doesn't keep burning tokens / running tools after exit.
    const delegation = delegationRef.current

    if (delegation) {
      $gateway
        .get()
        ?.request('session.interrupt', { session_id: delegation.sessionId })
        .catch(() => undefined)
      delegation.cancel()
    }

    delegationRef.current = null
    handledCallIdsRef.current.clear()
    stopMeter()

    try {
      dcRef.current?.close()
    } catch {
      /* ignore */
    }

    dcRef.current = null

    try {
      pcRef.current?.getSenders().forEach(sender => sender.track?.stop())
      pcRef.current?.close()
    } catch {
      /* ignore */
    }

    pcRef.current = null
    micStreamRef.current?.getTracks().forEach(track => track.stop())
    micStreamRef.current = null

    if (audioElRef.current) {
      audioElRef.current.srcObject = null
      audioElRef.current.remove()
      audioElRef.current = null
    }
  }, [clearNudge, clearSessionTimer, stopMeter])

  // ── Delegation bridge: run a Hermes agent turn over the existing gateway ──
  // Resolves with the agent's final text plus `respond`: whether the realtime
  // model should speak a follow-up (false when the run was cancelled by the
  // user, so cancel_running_work drives the single spoken acknowledgement).
  const delegateToAgent = useCallback(
    async (task: string, scope: RealtimeScope): Promise<{ respond: boolean; text: string }> => {
      const gateway = $gateway.get()

      if (!gateway) {
        throw new Error('Hermes gateway unavailable')
      }

      let sessionId = $activeSessionId.get()

      if (scope === 'new') {
        const created = await gateway.request<SessionCreateResponse>('session.create', { cols: 96 })

        sessionId = created.session_id
      }

      if (!sessionId) {
        throw new Error('No active chat session to delegate into')
      }

      const targetSession = sessionId

      return await new Promise<{ respond: boolean; text: string }>((resolve, reject) => {
        let accumulated = ''
        let started = false
        // Only accept turn events AFTER our prompt.submit is acknowledged, so a
        // prior/queued/goal-loop turn already streaming on this session can't
        // latch `started` and resolve us with the wrong turn's text.
        let ackReceived = false
        const offs: Array<() => void> = []

        const matchesSession = (event: { session_id?: string }) =>
          (event.session_id || $activeSessionId.get()) === targetSession

        const release = () => {
          offs.forEach(off => off())
          offs.length = 0

          // Only clear the ref if it still points at THIS delegation — a newer
          // delegation may have replaced it.
          if (delegationRef.current === thisDelegation) {
            delegationRef.current = null
          }
        }

        const settle = (value: { respond: boolean; text: string }) => {
          release()
          resolve(value)
        }

        const fail = (error: Error) => {
          release()
          reject(error)
        }

        const thisDelegation: ActiveDelegation = {
          sessionId: targetSession,
          // User-driven cancel: hand back partial text and suppress the model's
          // own follow-up (cancel_running_work speaks the acknowledgement).
          cancel: () => settle({ respond: false, text: accumulated.trim() || 'Stopped.' })
        }

        offs.push(
          gateway.on('message.start', event => {
            if (ackReceived && matchesSession(event)) {
              started = true
              accumulated = ''
            }
          })
        )
        offs.push(
          gateway.on('message.delta', event => {
            if (started && matchesSession(event)) {
              accumulated += asString((event.payload as { text?: unknown } | undefined)?.text)
            }
          })
        )
        offs.push(
          gateway.on('message.complete', event => {
            if (!started || !matchesSession(event)) {
              return
            }

            const payload = event.payload as { rendered?: unknown; text?: unknown } | undefined
            const final = asString(payload?.text) || asString(payload?.rendered) || accumulated

            settle({ respond: true, text: final.trim() || 'Done.' })
          })
        )
        offs.push(
          gateway.on('error', event => {
            if (matchesSession(event)) {
              fail(new Error(asString((event.payload as { error?: unknown } | undefined)?.error) || 'Agent error'))
            }
          })
        )

        const timer = window.setTimeout(() => {
          settle({ respond: true, text: accumulated.trim() || 'Still working on that — it is taking longer than usual.' })
        }, MAX_DELEGATION_MS)

        offs.push(() => window.clearTimeout(timer))

        delegationRef.current = thisDelegation

        const submitParams: Record<string, unknown> = { session_id: targetSession, text: task }

        if (cwdRef.current) {
          submitParams.cwd = cwdRef.current
        }

        if (delegationModelRef.current) {
          submitParams.model = delegationModelRef.current

          if (delegationProviderRef.current) {
            submitParams.provider = delegationProviderRef.current
          }
        }

        gateway
          .request('prompt.submit', submitParams)
          .then(() => {
            ackReceived = true
          })
          .catch(err => fail(err instanceof Error ? err : new Error(String(err))))
      })
    },
    []
  )

  const summarizeActiveSession = useCallback((): string => {
    const last = $messages
      .get()
      .findLast(message => message.role === 'assistant' && !message.hidden)

    const text = last ? chatMessageText(last).trim() : ''

    return JSON.stringify({ last_assistant: text.slice(0, 1200) })
  }, [])

  const cancelRunningWork = useCallback(() => {
    const delegation = delegationRef.current

    if (delegation) {
      $gateway
        .get()
        ?.request('session.interrupt', { session_id: delegation.sessionId })
        .catch(() => undefined)
      delegation.cancel()
    }

    send({ type: 'response.cancel' })
  }, [send])

  const handleFunctionCall = useCallback(
    (name: string, callId: string, argumentsJson: string) => {
      const args = parseToolArguments(argumentsJson)

      const finish = (output: string) => {
        send(buildFunctionCallOutput(callId, output))
        send({ type: 'response.create' })
      }

      if (name === 'run_hermes_agent') {
        const task = asString(args.task).trim()

        if (!task) {
          finish(JSON.stringify({ error: 'empty task' }))

          return
        }

        setStatus('delegating')
        // Mask agent latency: reassure out loud every NUDGE_INTERVAL_MS via an
        // out-of-band response (conversation:"none" — never pollutes history),
        // so a slow/wedged turn isn't silent dead air. Stopped the moment the
        // run settles, before the real summary response.
        clearNudge()
        nudgeTimerRef.current = window.setInterval(() => {
          send({
            type: 'response.create',
            response: {
              conversation: 'none',
              output_modalities: ['audio'],
              instructions:
                'Still waiting on a tool result. Say a very brief reassurance (e.g. "one moment", "still on it") in a few words. Do not answer the question yet.'
            }
          })
        }, NUDGE_INTERVAL_MS)

        delegateToAgent(task, resolveScope(args))
          .then(({ respond, text }) => {
            clearNudge()
            // Always answer the call_id so it isn't left dangling. Only ask the
            // model to speak when this run owns the follow-up (not when the user
            // cancelled it — cancel_running_work speaks the acknowledgement).
            send(buildFunctionCallOutput(callId, JSON.stringify({ result: text })))

            if (respond) {
              send({ type: 'response.create' })

              if (statusRef.current === 'delegating') {
                setStatus('thinking')
              }
            }
          })
          .catch(error => {
            clearNudge()
            finish(JSON.stringify({ error: error instanceof Error ? error.message : String(error) }))

            if (statusRef.current === 'delegating') {
              setStatus('listening')
            }
          })

        return
      }

      if (name === 'get_active_session_summary') {
        finish(summarizeActiveSession())

        return
      }

      if (name === 'cancel_running_work') {
        cancelRunningWork()
        finish(JSON.stringify({ cancelled: true, ok: true }))

        if (statusRef.current === 'delegating') {
          setStatus('thinking')
        }

        return
      }

      finish(JSON.stringify({ error: `unknown tool ${name}` }))
    },
    [cancelRunningWork, clearNudge, delegateToAgent, send, summarizeActiveSession]
  )

  const handleRealtimeEvent = useCallback(
    (event: Record<string, unknown>) => {
      const type = asString(event.type)

      if (type === 'input_audio_buffer.speech_started') {
        if (statusRef.current !== 'delegating') {
          setStatus('listening')
        }
      } else if (isFirstVoiceEvent(type)) {
        setStatus('speaking')
      } else if (type === 'response.created') {
        if (statusRef.current !== 'delegating') {
          setStatus('thinking')
        }
      } else if (type === 'response.done') {
        const usage = ((event.response as { usage?: { input_tokens?: number; output_tokens?: number } } | undefined)
          ?.usage) ?? {}

        usageRef.current.input += Number(usage.input_tokens) || 0
        usageRef.current.output += Number(usage.output_tokens) || 0

        if (statusRef.current === 'speaking' || statusRef.current === 'thinking') {
          setStatus('listening')
        }
      } else if (type === 'error') {
        notifyError(new Error(asString((event.error as { message?: unknown } | undefined)?.message) || 'Realtime error'), 'Voice error')
      }

      const fn = extractFunctionCall(event)

      // A single tool call surfaces as BOTH response.function_call_arguments.done
      // and response.output_item.done — dispatch each call_id exactly once.
      if (fn && !handledCallIdsRef.current.has(fn.callId)) {
        handledCallIdsRef.current.add(fn.callId)
        handleFunctionCall(fn.name, fn.callId, fn.argumentsJson)
      }
    },
    [handleFunctionCall]
  )

  const start = useCallback(async () => {
    if (statusRef.current !== 'idle') {
      return
    }

    setMuted(false)
    setStatus('connecting')
    usageRef.current = { input: 0, output: 0 }
    handledCallIdsRef.current.clear()

    let token: RealtimeRuntimeConfig

    try {
      const minted = await createRealtimeSession()

      token = {
        clientSecret: minted.client_secret,
        model: minted.model,
        voice: minted.voice,
        turnDetection: minted.turn_detection || 'server_vad',
        maxSessionSec: minted.max_session_sec || 0,
        idleTimeoutMs: minted.idle_timeout_ms || 0,
        expiresAt: minted.expires_at ?? null,
        delegationModel: minted.delegation_model || '',
        delegationProvider: minted.delegation_provider || ''
      }
      delegationModelRef.current = token.delegationModel
      delegationProviderRef.current = token.delegationProvider
    } catch (error) {
      setStatus('idle')
      const message = error instanceof Error ? error.message : String(error)
      onFatalError?.(message)

      return
    }

    try {
      const pc = new RTCPeerConnection()
      pcRef.current = pc

      const audio = new Audio()
      audio.autoplay = true
      audio.style.display = 'none'
      document.body.appendChild(audio)
      audioElRef.current = audio

      pc.ontrack = event => {
        audio.srcObject = event.streams[0]
      }

      const mic = await navigator.mediaDevices.getUserMedia({
        audio: { echoCancellation: true, noiseSuppression: true }
      })

      micStreamRef.current = mic
      mic.getTracks().forEach(track => pc.addTrack(track, mic))
      startMeter(mic)

      const dc = pc.createDataChannel(OAI_EVENTS_CHANNEL)
      dcRef.current = dc

      dc.onopen = () => {
        send(buildSessionUpdate(token))
        setStatus('listening')

        if (token.maxSessionSec > 0) {
          sessionTimerRef.current = window.setTimeout(() => {
            notify({ kind: 'info', title: 'Voice session ended', message: 'Reached the maximum session length.' })
            teardown()
            setMuted(false)
            setStatus('idle')
          }, token.maxSessionSec * 1000)
        }
      }

      dc.onmessage = messageEvent => {
        try {
          handleRealtimeEvent(JSON.parse(messageEvent.data))
        } catch {
          /* ignore non-JSON frames */
        }
      }

      const offer = await pc.createOffer()
      await pc.setLocalDescription(offer)

      const sdpResponse = await fetch(REALTIME_CALLS_URL, {
        method: 'POST',
        body: offer.sdp,
        headers: { Authorization: `Bearer ${token.clientSecret}`, 'Content-Type': 'application/sdp' }
      })

      if (!sdpResponse.ok) {
        throw new Error(`Realtime SDP exchange failed (HTTP ${sdpResponse.status})`)
      }

      await pc.setRemoteDescription({ type: 'answer', sdp: await sdpResponse.text() })
    } catch (error) {
      teardown()
      setStatus('idle')
      const message = error instanceof Error ? error.message : String(error)
      notifyError(error, 'Could not start realtime voice')
      onFatalError?.(message)
    }
  }, [handleRealtimeEvent, onFatalError, send, startMeter, teardown])

  const end = useCallback(async () => {
    teardown()
    setMuted(false)
    setStatus('idle')
  }, [teardown])

  const stopTurn = useCallback(() => {
    // Interrupt the model's current speech (speech-only barge-in).
    send({ type: 'response.cancel' })
  }, [send])

  const toggleMute = useCallback(() => {
    setMuted(value => {
      const next = !value

      micStreamRef.current?.getAudioTracks().forEach(track => {
        track.enabled = !next
      })

      return next
    })
  }, [])

  // Mirror the classic hook: enable/disable drives start/end.
  useEffect(() => {
    if (enabled && !wasEnabledRef.current) {
      void start()
    }

    if (!enabled && wasEnabledRef.current) {
      void end()
    }

    wasEnabledRef.current = enabled
  }, [enabled, end, start])

  useEffect(() => () => teardown(), [teardown])

  return { end, level, muted, start, status, stopTurn, toggleMute }
}
