import { useCallback, useEffect, useRef, useState } from 'react'

type BrowserAudioContext = typeof AudioContext

/**
 * Drive a 0..1 mic level meter from an existing MediaStream. This mirrors the
 * RMS metering in `use-mic-recorder.ts` (same fftSize / normalization) but
 * attaches to a stream the caller already owns — the realtime hook feeds it the
 * WebRTC mic stream so we never acquire the microphone twice.
 */
export function useAudioLevel(): {
  level: number
  start: (stream: MediaStream) => void
  stop: () => void
} {
  const [level, setLevel] = useState(0)
  const audioContextRef = useRef<AudioContext | null>(null)
  const animationRef = useRef<null | number>(null)

  const stop = useCallback(() => {
    if (animationRef.current) {
      window.cancelAnimationFrame(animationRef.current)
      animationRef.current = null
    }

    void audioContextRef.current?.close()
    audioContextRef.current = null
    setLevel(0)
  }, [])

  const start = useCallback(
    (stream: MediaStream) => {
      stop()

      const audioWindow = window as Window & { webkitAudioContext?: BrowserAudioContext }
      const AudioContextCtor = window.AudioContext || audioWindow.webkitAudioContext

      if (!AudioContextCtor) {
        return
      }

      try {
        const audioContext = new AudioContextCtor()
        const analyser = audioContext.createAnalyser()
        const source = audioContext.createMediaStreamSource(stream)

        analyser.fftSize = 256
        const data = new Uint8Array(analyser.fftSize)
        source.connect(analyser)
        audioContextRef.current = audioContext

        const tick = () => {
          analyser.getByteTimeDomainData(data)

          let sum = 0

          for (const value of data) {
            const centered = value - 128

            sum += centered * centered
          }

          const rms = Math.sqrt(sum / data.length)

          setLevel(Math.min(1, rms / 42))
          animationRef.current = window.requestAnimationFrame(tick)
        }

        tick()
      } catch {
        setLevel(0)
      }
    },
    [stop]
  )

  useEffect(() => () => stop(), [stop])

  return { level, start, stop }
}
