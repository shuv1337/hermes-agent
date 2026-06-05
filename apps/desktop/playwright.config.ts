import { defineConfig } from '@playwright/test'

// Electron end-to-end smokes. These launch the real desktop app (which spawns
// the Python backend), so they run serially and are kept out of the jsdom unit
// suite: vitest only matches *.test/*.spec, these are named *.e2e.ts.
export default defineConfig({
  testDir: './tests/e2e',
  testMatch: '**/*.e2e.ts',
  // One Electron instance at a time; the app binds a backend port.
  workers: 1,
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: 0,
  // Booting the backend (venv/import) can take a while on a cold cache.
  timeout: 180_000,
  expect: { timeout: 15_000 },
  reporter: process.env.CI ? 'line' : 'list',
  use: { trace: 'retain-on-failure' }
})
