import { atom } from 'nanostores'

import { persistBoolean, storedBoolean } from '@/lib/storage'

// Desktop UI preference: when on, the composer's voice button opens the
// low-latency realtime (GPT-Realtime speech-to-speech) conversation; when off
// (or when the backend can't mint a token — no VOICE_TOOLS_OPENAI_KEY), it
// falls back to the classic STT -> LLM -> TTS loop. Realtime is the default
// experience per the locked spec.
const REALTIME_VOICE_STORAGE_KEY = 'hermes.desktop.voice.realtime'

export const $realtimeVoiceEnabled = atom<boolean>(storedBoolean(REALTIME_VOICE_STORAGE_KEY, true))

$realtimeVoiceEnabled.subscribe(enabled => persistBoolean(REALTIME_VOICE_STORAGE_KEY, enabled))

export function setRealtimeVoiceEnabled(enabled: boolean) {
  $realtimeVoiceEnabled.set(enabled)
}
