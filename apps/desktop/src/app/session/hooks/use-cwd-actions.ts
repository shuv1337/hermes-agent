import { type MutableRefObject, useCallback } from 'react'

import { notify, notifyError } from '@/store/notifications'
import { $currentCwd, setCurrentBranch, setCurrentCwd } from '@/store/session'
import type { SessionRuntimeInfo } from '@/types/hermes'

interface CwdActionsOptions {
  activeSessionId: string | null
  activeSessionIdRef: MutableRefObject<string | null>
  onSessionRuntimeInfo?: (info: Pick<SessionRuntimeInfo, 'branch' | 'cwd'>) => void
  requestGateway: <T = unknown>(method: string, params?: Record<string, unknown>) => Promise<T>
}

export function useCwdActions({
  activeSessionId,
  activeSessionIdRef,
  onSessionRuntimeInfo,
  requestGateway
}: CwdActionsOptions) {
  const refreshProjectBranch = useCallback(
    async (cwd: string) => {
      const target = cwd.trim()

      if (!target || activeSessionIdRef.current) {
        return
      }

      try {
        const info = await requestGateway<{ branch?: string; cwd?: string }>('config.get', {
          key: 'project',
          cwd: target
        })

        if (!activeSessionIdRef.current && ($currentCwd.get() || target) === (info.cwd || target)) {
          setCurrentBranch(info.branch || '')
        }
      } catch {
        setCurrentBranch('')
      }
    },
    [activeSessionIdRef, requestGateway]
  )

  // Returns how the change landed: 'applied' (live), 'staged' (older backend —
  // persisted for the next session but not the active one), or null (rejected /
  // empty). Callers like the /cwd command use this to phrase their feedback.
  const changeSessionCwd = useCallback(
    async (cwd: string): Promise<'applied' | 'staged' | null> => {
      const trimmed = cwd.trim()

      if (!trimmed) {
        return null
      }

      if (!activeSessionId) {
        setCurrentCwd(trimmed)

        try {
          const info = await requestGateway<{ branch?: string; cwd?: string }>('config.get', {
            key: 'project',
            cwd: trimmed
          })

          // Adopt the backend's normalized cwd so the persisted workspace and
          // branch stay consistent with what the agent will use.
          if (info.cwd) {
            setCurrentCwd(info.cwd)
          }

          setCurrentBranch(info.branch || '')
        } catch {
          setCurrentBranch('')
        }

        return 'applied'
      }

      try {
        const info = await requestGateway<SessionRuntimeInfo>('session.cwd.set', {
          session_id: activeSessionId,
          cwd: trimmed
        })

        setCurrentCwd(info.cwd || trimmed)
        setCurrentBranch(info.branch || '')
        onSessionRuntimeInfo?.({ branch: info.branch || '', cwd: info.cwd || trimmed })

        return 'applied'
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err)

        if (!message.includes('unknown method')) {
          notifyError(err, 'Working directory change failed')

          return null
        }

        setCurrentCwd(trimmed)
        setCurrentBranch('')
        notify({
          kind: 'warning',
          title: 'Working directory staged',
          message: 'Restart the desktop backend to apply cwd changes to this active session.'
        })

        return 'staged'
      }
    },
    [activeSessionId, onSessionRuntimeInfo, requestGateway]
  )

  return { changeSessionCwd, refreshProjectBranch }
}
