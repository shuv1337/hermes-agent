import { execSync } from 'node:child_process'
import fs from 'node:fs'
import { createRequire } from 'node:module'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

import { _electron as electron, type ElectronApplication, expect, type Page, test } from '@playwright/test'

// ── Paths ───────────────────────────────────────────────────────────────────
const HERE = path.dirname(fileURLToPath(import.meta.url))
const APP_DIR = path.resolve(HERE, '..', '..')
const REPO_ROOT = path.resolve(APP_DIR, '..', '..')
const DIST_DIR = path.join(APP_DIR, 'dist')
const VENV_PYTHON = path.join(REPO_ROOT, 'venv', 'bin', 'python')
const require = createRequire(import.meta.url)
const ELECTRON_EXECUTABLE = require('electron') as string

// The realtime voice settings section. We flip the voice and assert it sticks.
const VOICES = ['marin', 'cedar', 'alloy', 'ash', 'ballad', 'coral', 'echo', 'sage', 'shimmer', 'verse'] as const

type HermesApi = <T>(req: { body?: unknown; method?: string; path: string }) => Promise<T>

let app: ElectronApplication
let page: Page
let tempHome: string

/** Poll a thunk until it returns truthy or the deadline passes. */
async function waitFor<T>(fn: () => Promise<T>, { timeout = 120_000, interval = 1_000 } = {}): Promise<T> {
  const deadline = Date.now() + timeout
  let lastErr: unknown

  while (Date.now() < deadline) {
    try {
      const value = await fn()

      if (value) {
        return value
      }
    } catch (err) {
      lastErr = err
    }

    await new Promise(resolve => setTimeout(resolve, interval))
  }

  throw new Error(`waitFor timed out after ${timeout}ms${lastErr ? `: ${String(lastErr)}` : ''}`)
}

/** Read realtime.voice straight from the backend (proves persistence, no UI). */
function readVoiceFromBackend(): Promise<string> {
  return page.evaluate(async () => {
    const api = (window as unknown as { hermesDesktop: { api: HermesApi } }).hermesDesktop.api
    const config = await api<{ realtime?: { voice?: string } }>({ path: '/api/config' })

    return config?.realtime?.voice ?? ''
  }) as Promise<string>
}

test.beforeAll(async () => {
  // Build the renderer so the app loads from dist (no vite dev server needed).
  if (!fs.existsSync(path.join(DIST_DIR, 'index.html'))) {
    execSync('npm run build', { cwd: APP_DIR, stdio: 'inherit' })
  }

  tempHome = fs.mkdtempSync(path.join(os.tmpdir(), 'hermes-e2e-'))

  // Seed a configured runtime so the first-run onboarding overlay does not gate
  // the Settings UI. setup.runtime_check only needs a resolvable model and a
  // credential that is *present* (it checks presence, never makes a network
  // call), so a concrete model + a dummy key is enough to look configured.
  fs.writeFileSync(path.join(tempHome, 'config.yaml'), 'model: openai/gpt-4o-mini\n')

  app = await electron.launch({
    args: ['.'],
    cwd: APP_DIR,
    executablePath: ELECTRON_EXECUTABLE,
    env: {
      ...process.env,
      // Redirect ALL Hermes state to a throwaway dir — never touch ~/.hermes.
      HERMES_HOME: tempHome,
      HERMES_DESKTOP_USER_DATA_DIR: path.join(tempHome, 'user-data'),
      // Drive the local repo backend with the repo venv (skips bootstrap).
      HERMES_DESKTOP_HERMES_ROOT: REPO_ROOT,
      ...(fs.existsSync(VENV_PYTHON) ? { HERMES_DESKTOP_PYTHON: VENV_PYTHON } : {}),
      HERMES_DESKTOP_WEB_DIST: DIST_DIR,
      // Dummy, non-network credential so the runtime resolves as "configured".
      OPENAI_API_KEY: 'sk-e2e-playwright-dummy-credential'
    }
  })

  page = await app.firstWindow()

  // Ready when the backend answers /api/config over the IPC bridge. This both
  // confirms the gateway is up and is exactly what the settings UI needs.
  await waitFor(async () =>
    page.evaluate(async () => {
      try {
        const api = (window as unknown as { hermesDesktop?: { api?: HermesApi } }).hermesDesktop?.api

        if (!api) {
          return false
        }

        const config = await api<Record<string, unknown>>({ path: '/api/config' })

        return Boolean(config && typeof config === 'object')
      } catch {
        return false
      }
    })
  )
})

test.afterAll(async () => {
  await app?.close()

  if (tempHome) {
    fs.rmSync(tempHome, { force: true, recursive: true })
  }
})

test('Settings → Realtime Voice persists a changed voice', async () => {
  // Open the Realtime Voice settings section directly (HashRouter route).
  await page.evaluate(() => {
    window.location.hash = '#/settings?tab=config:realtime'
  })

  // The section header proves the new config section rendered.
  await expect(page.getByText('Realtime Voice', { exact: false }).first()).toBeVisible()

  const before = await readVoiceFromBackend()
  // The select renders the backend default (marin) when unset, so pick a target
  // that differs from both the persisted value and that default — a real change.
  const current = before || 'marin'
  const target = VOICES.find(voice => voice !== current) ?? 'cedar'

  // The "Realtime Voice" row's Select trigger is the first combobox; open it and
  // pick the target option (rendered Title-cased via prettyName, so match
  // case-insensitively).
  const trigger = page.getByRole('combobox').first()
  await trigger.click()
  await page.getByRole('option', { name: new RegExp(`^${target}$`, 'i') }).click()

  // Autosave debounces ~550ms then PUTs /api/config; poll the backend until the
  // new value is persisted (decoupled from UI timing).
  const persisted = await waitFor(
    async () => {
      const voice = await readVoiceFromBackend()

      return voice === target ? voice : ''
    },
    { interval: 250, timeout: 15_000 }
  )

  expect(persisted).toBe(target)
  expect(persisted).not.toBe(current)
})
