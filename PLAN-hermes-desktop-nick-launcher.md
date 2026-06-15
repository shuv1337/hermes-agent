# Plan: Add a second Walker launcher for Hermes Desktop connected to `nick`

## Context

Hermes Desktop uses Electron's single-instance lock to prevent accidental duplicate launches of the same desktop profile. Electron scopes that lock by `app.getPath('userData')`, and Hermes Desktop supports overriding that path with `HERMES_DESKTOP_USER_DATA_DIR`.

That gives us the intended multi-instance model:

- [x] Default local launcher: normal `~/.config/Hermes` user-data profile, local backend.
- [x] New `nick` launcher: separate user-data profile, remote backend on host `nick`.

Important implementation detail: when `HERMES_DESKTOP_USER_DATA_DIR` is set and `HERMES_HOME` is not set, `apps/desktop/electron/main.cjs::resolveHermesHome()` moves `HERMES_HOME` under the alternate user-data dir. The `nick` launcher must explicitly set `HERMES_HOME=/home/shuv/.hermes` so it reuses the existing Hermes install instead of bootstrapping a new one.

## Goals

- [x] Keep the existing Walker entry, `Hermes Agent`, launching the local desktop instance.
- [x] Add a second Walker-visible desktop entry, `Hermes Agent (nick)`.
- [x] Make the second entry run concurrently with the local Hermes Desktop instance.
- [x] Make the second entry connect to a remote Hermes dashboard backend running on host `nick`.
- [x] Avoid storing the remote session token directly in the `.desktop` file.
- [x] Keep local user-data and remote connection config separated; Desktop logs remain shared at `~/.hermes/logs/desktop.log` because `HERMES_HOME` is intentionally shared.

## Relevant Files and Surfaces

| Path / Surface | Role |
| --- | --- |
| `apps/desktop/electron/main.cjs` | Hermes Desktop boot, single-instance lock, remote backend config, env overrides. |
| `~/.local/share/applications/hermes-agent.desktop` | Existing Walker-visible local launcher. |
| `~/.local/share/applications/hermes-agent-nick.desktop` | New Walker-visible remote launcher to create. |
| `~/.local/bin/hermes-desktop-nick` | New wrapper script to keep env setup and secrets out of the desktop file. |
| `~/.config/hermes-desktop-nick/env` | Local private env file containing remote URL/token for the wrapper. |
| `~/.config/Hermes-nick/` | Separate Electron `userData` dir for the `nick` desktop profile. |
| remote `nick`: `~/.config/systemd/user/hermes-desktop-remote.service` | Persistent remote dashboard backend service. |
| remote `nick`: `~/.config/hermes-desktop-remote/env` | Remote service env with `HERMES_DASHBOARD_SESSION_TOKEN`. |

## Architecture

### Remote Backend on `nick`

Run a long-lived Hermes dashboard backend on `nick` bound to a Tailscale/trusted-network-reachable interface. Non-loopback remote Desktop session-token mode requires `--insecure`; otherwise the OAuth gate engages and rejects the legacy session-token path.

```bash
HERMES_DASHBOARD_SESSION_TOKEN=<shared-secret> \
hermes dashboard --host 0.0.0.0 --port 9120 --no-open --tui --insecure
```

The desktop app connects with:

```bash
HERMES_DESKTOP_REMOTE_URL=http://nick:9120
HERMES_DESKTOP_REMOTE_TOKEN=<same-shared-secret>
```

### Local `nick` Desktop Instance

Launch the same packaged Hermes binary, but with a distinct Electron user-data dir:

```bash
HERMES_HOME=/home/shuv/.hermes \
HERMES_DESKTOP_USER_DATA_DIR=/home/shuv/.config/Hermes-nick \
HERMES_DESKTOP_REMOTE_URL=http://nick:9120 \
HERMES_DESKTOP_REMOTE_TOKEN=<shared-secret> \
/home/shuv/repos/hermes-agent/apps/desktop/release/linux-unpacked/Hermes
```

This allows concurrent local + `nick` windows because the single-instance locks are scoped to different user-data dirs.

## Implementation Tasks

### 1. Confirm Remote Addressing for `nick`

- [x] Check whether `nick` resolves locally:

```bash
getent hosts nick || true
```

- [x] If `nick` does not resolve, get the Tailscale IP:

```bash
tailscale status | rg '\bnick\b'
ssh nick 'tailscale ip -4'
```

- [x] Choose the remote URL:
  - Prefer `http://nick:9120` if hostname resolution works.
  - Otherwise use `http://<nick-tailnet-ip>:9120`.

### 2. Set Up the Remote Backend on `nick`

- [x] Generate a session token without printing it to chat or shell history.
- [x] On `nick`, create `~/.config/hermes-desktop-remote/env` with mode `0600`.
- [x] Create `~/.config/systemd/user/hermes-desktop-remote.service` on `nick`:

```ini
[Unit]
Description=Hermes Desktop remote dashboard backend
After=network-online.target

[Service]
Type=simple
EnvironmentFile=%h/.config/hermes-desktop-remote/env
WorkingDirectory=%h
ExecStart=%h/.local/bin/hermes dashboard --host 0.0.0.0 --port 9120 --no-open --tui --insecure
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
```

- [x] Enable and start the service.
- [x] Validate it is listening on `nick`.
- [x] From the local machine, validate protected HTTP reachability:

```bash
curl -i -H "X-Hermes-Session-Token: <generated-token>" http://nick:9120/api/config
```

Expected: `200`. `/api/status` is public and is not sufficient validation.

### 3. Create Local Private Env for the `nick` Launcher

- [x] Create `~/.config/hermes-desktop-nick` with mode `0700`.
- [x] Write `~/.config/hermes-desktop-nick/env` with mode `0600`:

```bash
HERMES_HOME=/home/shuv/.hermes
HERMES_DESKTOP_USER_DATA_DIR=/home/shuv/.config/Hermes-nick
HERMES_DESKTOP_REMOTE_URL=http://nick:9120
HERMES_DESKTOP_REMOTE_TOKEN=<generated-token>
```

### 4. Create the Wrapper Script

- [x] Create `~/.local/bin/hermes-desktop-nick`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="$HOME/.config/hermes-desktop-nick/env"
APP="/home/shuv/repos/hermes-agent/apps/desktop/release/linux-unpacked/Hermes"

if [[ ! -r "$ENV_FILE" ]]; then
  notify-send "Hermes nick" "Missing env file: $ENV_FILE" 2>/dev/null || true
  echo "Missing env file: $ENV_FILE" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

exec "$APP"
```

- [x] Smoke-test wrapper prerequisites without launching a long-running GUI.

### 5. Create the Second Desktop Entry for Walker

- [x] Create `~/.local/share/applications/hermes-agent-nick.desktop`:

```ini
[Desktop Entry]
Name=Hermes Agent (nick)
Comment=Hermes Desktop connected to remote host nick
Exec=/home/shuv/.local/bin/hermes-desktop-nick
Icon=hermes-agent
Type=Application
Categories=Development;Utility;
Terminal=false
StartupNotify=true
```

- [x] Validate the desktop file.
- [x] Refresh desktop application cache.
- [x] Restart Walker if `omarchy-restart-walker` is available.

### 6. Validate Walker Discovery and Runtime

- [x] Confirm Elephant sees the new entry.
- [x] Confirm local and `nick` launchers can run concurrently.
- [x] Confirm the `nick` instance uses remote connection source `env` and does not spawn a local dashboard backend.
- [x] Re-launch each entry once; same-profile launches should focus the existing window, while local and `nick` remain independent.

### 7. Failure-Mode Checks

- [x] If the `nick` launcher opens a bootstrap/install flow, verify `HERMES_HOME=/home/shuv/.hermes` is present in `~/.config/hermes-desktop-nick/env`.
- [x] If it opens but cannot connect, validate `/api/config` with the token from the local env file.
- [x] If the token is rejected, compare local `HERMES_DESKTOP_REMOTE_TOKEN` with remote `HERMES_DASHBOARD_SESSION_TOKEN`.
- [x] If the host is unreachable, test SSH/Tailscale.

## Security Notes

- [x] Do not place `HERMES_DESKTOP_REMOTE_TOKEN` directly in the `.desktop` file.
- [x] Keep both env files chmod `600`.
- [x] Use Tailscale or equivalent trusted network controls. `--insecure` is required for this Desktop remote-token mode but must not be exposed to the open internet.
- [x] Rotate the token if it is pasted into logs, chat, shell history, or a committed file.

## Rollback

- [ ] Stop remote backend:

```bash
ssh nick 'systemctl --user disable --now hermes-desktop-remote.service'
```

- [ ] Remove local launcher files:

```bash
rm -f ~/.local/bin/hermes-desktop-nick
rm -f ~/.local/share/applications/hermes-agent-nick.desktop
rm -rf ~/.config/Hermes-nick
rm -rf ~/.config/hermes-desktop-nick
update-desktop-database ~/.local/share/applications
omarchy-restart-walker
```

- [ ] Remove remote service files if no longer needed:

```bash
ssh nick 'rm -f ~/.config/systemd/user/hermes-desktop-remote.service && rm -rf ~/.config/hermes-desktop-remote && systemctl --user daemon-reload'
```

## Done Criteria

- [x] Walker shows two entries: `Hermes Agent` and `Hermes Agent (nick)`.
- [x] `Hermes Agent` still launches the local desktop profile.
- [x] `Hermes Agent (nick)` launches a separate desktop window/profile.
- [x] The `nick` window connects to the remote backend on `nick` without spawning a local dashboard backend.
- [x] Both windows can run concurrently without port bind errors.
- [x] Remote backend survives reboot/log out if user lingering is enabled on `nick`, or the operational note documents how to start it manually.
