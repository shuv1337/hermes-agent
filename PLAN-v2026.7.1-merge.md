# Merge Plan: upstream v2026.7.1 (v0.18.0) into fork `main`

**Created:** 2026-07-01  
**Status:** prep / not started  
**Skills:** `fork-upstream-merge`, `hermes-agent-local-patches`  
**Release:** [v2026.7.1 — The Judgment Release](https://github.com/NousResearch/hermes-agent/releases/tag/v2026.7.1)

## Current state (snapshot 2026-07-01)

| Item | Value |
|------|--------|
| Fork branch | `main` @ `cb6d5c8b7` — feat(anthropic): Claude Sonnet 5 |
| Running (`hermes --version`) | v0.17.0 (2026.6.19) · Project: `~/repos/hermes-agent` |
| Upstream target | `upstream/main` @ `676236bb1` (tip) |
| Release tag | `v2026.7.1` → `7c1a02955` chore: release v0.18.0 |
| Merge-base | `2bd1977d8` — v0.17.0 (2026.6.19) release |
| Divergence | **109** fork-only commits · **1,961** behind upstream |
| `origin/main` | Fork `main` was **1 commit ahead** of `origin/main` at prep time — push or reconcile before merge |
| `git config rerere.enabled` | `true` (repeat conflict auto-resolution) |

**Do not use `hermes update` alone.** It skips upstream sync when the fork is ahead and can report “Already up to date” while ~2k commits behind. Always:

```bash
cd ~/repos/hermes-agent
git fetch upstream --tags
git rev-list --count HEAD..upstream/main
```

## Why this merge matters (upstream themes)

High-signal areas in v0.18.0 that will land on the fork:

- **Mixture-of-Agents (MoA)** — first-class `moa` provider presets, streaming aggregator
- **Verification / goals** — coding evidence ledger, `/goal` completion contracts
- **`/learn`**, **`/journey`**, **`/prompt`** — skill distillation, learning timeline, `$EDITOR` compose
- **Background `delegate_task` fan-out**
- **Desktop coding Projects** — worktrees, review pane
- **Gateway** — scale-to-zero, drain on restart
- **Vertex AI** — Gemini with auto-refreshed OAuth tokens
- **Security** — MCP hardening, cron `base_url` exfil block, aiohttp CVE floor, etc.
- **P0/P1 sweep** — upstream claims zero open P0/P1 at release

## Dry-run: merge conflicts (no branch, no working-tree change)

Command used:

```bash
cd ~/repos/hermes-agent
git fetch upstream --tags
git merge-tree --write-tree HEAD upstream/main > /tmp/mt-v071.out
grep -i CONFLICT /tmp/mt-v071.out
```

**Result: 21 conflict markers** (exit 1 from merge-tree)

| # | File | Notes |
|---|------|--------|
| 1 | `.github/workflows/tests.yml` | CI — align fork workflows (PyPI guard, realtime e2e) with upstream |
| 2 | `agent/prompt_builder.py` | Both sides touched; fork has merge history + realtime/self-knowledge paths |
| 3 | `agent/transports/chat_completions.py` | Overlap with fork Sonnet/metadata work |
| 4 | `apps/desktop/electron/main.cjs` | Desktop + realtime fork |
| 5 | `apps/desktop/src/app/chat/composer/index.tsx` | Realtime voice composer |
| 6 | `apps/desktop/src/app/right-sidebar/index.tsx` | |
| 7 | **`apps/desktop/src/app/session/hooks/use-prompt-actions.ts`** | **modify/delete** — upstream **deleted** monolithic file; replaced with `use-prompt-actions/{index,slash,submit,utils}.ts` |
| 8 | `apps/desktop/src/app/settings/appearance-settings.tsx` | |
| 9 | `apps/desktop/src/app/settings/constants.ts` | |
| 10 | `apps/desktop/src/lib/desktop-slash-commands.ts` | Fork `/cwd`, desktop slash catalog |
| 11 | `apps/desktop/src/main.tsx` | |
| 12 | `hermes_cli/config.py` | |
| 13 | `hermes_cli/models.py` | Sonnet 5 / catalog |
| 14 | `tests/gateway/test_signal.py` | |
| 15 | `tests/tools/test_computer_use.py` | Fork keeps `computer_use` disabled on Linux — expect test alignment |
| 16 | `tools/computer_use/schema.py` | |
| 17 | `tools/computer_use/tool.py` | |
| 18 | **`tools/skill_manager_tool.py`** | **Critical:** upstream `rglob("SKILL.md")` vs fork `os.walk(..., followlinks=True)` (`992a147f3`) |
| 19 | `tools/skills_hub.py` | |
| 20 | `tui_gateway/server.py` | |
| 21 | `website/static/api/model-catalog.json` | Sonnet 5 + upstream catalog |

**Anthropic OAuth files** (`anthropic_adapter.py`, `transports/anthropic.py`) are in the **88-file overlap set** but were **not** listed as merge-tree conflicts for this batch — unlike the v0.17 merge. Still review after merge if OAuth/MCP tool naming regresses.

### High-risk overlap (88 files)

Files changed on **both** fork and upstream since merge-base. Full list from:

```bash
BASE=$(git merge-base HEAD upstream/main)
comm -12 \
  <(git diff --name-only upstream/main...HEAD | sort -u) \
  <(git diff --name-only $BASE..upstream/main | sort -u)
```

Notable fork-owned behavior in overlap (preserve during resolution):

- Realtime voice desktop (`use-voice-conversation`, settings, Playwright smoke)
- Desktop `/cwd` + “new chat in folder” + `desktop-slash-commands` tests
- Telegram rich-message edit path (fork merge lineage)
- Pairing approval fix (`0775545d5`)
- Claude Sonnet 5 metadata (`cb6d5c8b7`)
- Symlinked skills repo (`992a147f3`) — **must survive** (`~/repos/shuvbot-skills` → `~/.hermes/skills/`)
- `HERMES_DASHBOARD_ALLOWED_HOSTS` in `hermes_cli/web_server.py` (fork commit + patch)
- STT `stt.local.device` / `compute_type` in `tools/transcription_tools.py` (patch)

## Priority conflict: `use-prompt-actions`

**Do not keep** `use-prompt-actions.ts` as a single file.

Upstream layout:

```text
apps/desktop/src/app/session/hooks/use-prompt-actions/
  index.ts
  slash.ts
  submit.ts
  utils.ts
  (+ tests)
```

**Action:** Read fork `HEAD:use-prompt-actions.ts` for desktop-only behavior (slash dispatch, `/cwd`, transcribe, catalog filters). Port deltas into upstream’s split modules; delete the obsolete path; fix imports in composer/session code.

## Priority conflict: `skill_manager_tool.py`

Upstream discovery uses `skills_dir.rglob("SKILL.md")` (no symlink follow).

Fork fix `992a147f3`: `os.walk(skills_dir, followlinks=True)` so symlinked skill trees resolve.

**Action:** After taking upstream structure, reintroduce `followlinks=True` discovery (or equivalent) everywhere `_find_skill` / profile skill scans run. Verify:

```bash
skill_view name=hermes-agent   # skill lives under symlinked shuvbot-skills
```

There is **no** `~/.hermes/patches/skill-manager-symlink-followlinks/` — fix lives in **git history**; merge resolution must retain it.

## Out-of-tree patches (`~/.hermes/patches/`)

Run full audit after merge. Pre-merge dry-run against detached `upstream/main` worktree:

| Patch / dir | Dry-run on upstream | Post-merge action |
|-------------|---------------------|-------------------|
| `dashboard-allowed-hosts.patch` | applies clean | Keep; may duplicate fork commit in `web_server.py` — apply.sh should skip if already applied |
| `transcription-cuda-version-fallback.patch` | applies clean | **Keep** — upstream still lacks `stt.local.device` / `compute_type` |
| `delegate-tool-config-model-counts.patch` | conflict | **Retire** → `_retired/` (code path removed upstream) |
| `mcp_oauth-anyurl-serialization` | in `_retired/` | **Done** — upstream uses `model_dump(mode="json")` |
| `hermes-agent-review-fork-skip-memory/` | N/A | **No-op** — `skip_memory=True` in `agent/background_review.py` |
| `hermes-agent-honcho-peer-naming/` | old `.patch` conflicts | **Config-only** — set `honcho.runtimePeerPrefix` in `~/.hermes/config.yaml` |
| `kanban-inline-create-select-onvaluechange/` | re-verify | Likely upstream absorbed; retire if `selectChangeHandler` present |
| `dashboard-night-owl-theme/` | N/A | Run dir `apply.sh` (not in master glob) |
| `shuvoncho-ws-shuvslop-model-override/` | shuvdev only | Skip on nick |
| `orcaslicer-cli-inheritance/`, `omarchy-hyprpicker-safe/` | wrong repo | Ignore master-glob `✗` |

Master apply + per-directory scripts:

```bash
~/.hermes/patches/apply.sh
for d in ~/.hermes/patches/*/; do
  [ -f "$d/apply.sh" ] && bash "$d/apply.sh"
done
```

## Dependency manifest (expect diff after merge)

Preview vs upstream (non-exhaustive):

- `version` → `0.18.0`
- `cryptography==46.0.7` (explicit pin)
- `aiohttp==3.14.1` across messaging/slack/matrix/homeassistant/sms/teams
- New extras: `vertex`, `supermemory`, `mem0`
- Dev/test plugins may add pytest options — install via **venv interpreter**:

```bash
cd ~/repos/hermes-agent
./venv/bin/python -m pip install -e .
# NOT bare `pip` on PEP 668 host
```

## Execution procedure

### 0. Preconditions

- [ ] Clean or stashed working tree: `git status -sb`
- [ ] `git fetch upstream --tags`
- [ ] Optional: `git push origin main` if local-only commits should be on origin first
- [ ] Backup branch: `git branch backup/main-pre-v2026.7.1-$(date +%Y%m%d) main`

### 1. Merge on a branch (never first on `main`)

```bash
cd ~/repos/hermes-agent
git checkout -b try-merge-v2026.7.1-$(date +%Y%m%d)
git merge upstream/main --no-edit
# resolve conflicts → git add -A && git commit --no-edit
```

Conflict hygiene:

```bash
grep -rn '^<<<<<<< \|^>>>>>>> ' --include='*.py' --include='*.ts' --include='*.tsx' --include='*.yml' .
```

### 2. Re-apply patches

See table above.

### 3. Install + scoped tests

Overlap-focused suite (tune file list from overlap comm output):

```bash
./venv/bin/python -m pytest tests/agent/test_prompt_builder.py \
  tests/tools/test_computer_use.py tests/gateway/test_signal.py \
  tests/hermes_cli/ -q --tb=short -x -p no:cacheprovider
```

**Set-difference method** (merge-caused vs pre-existing):

```bash
# On backup branch vs merge branch, same SUITE; comm -13 = regressions you introduced
```

Do **not** block on full 25k+ test run; background if needed.

### 4. Land

```bash
git checkout main
git merge try-merge-v2026.7.1-YYYYMMDD --ff-only
git push origin main
git branch -d try-merge-v2026.7.1-YYYYMMDD
```

### 5. Post-merge runtime refresh (mandatory)

Source tree ≠ running gateway ≠ packaged desktop.

```bash
cd ~/repos/hermes-agent
~/.hermes/patches/apply.sh
./venv/bin/python -m pip install -e .

# From a shell OUTSIDE the gateway process (Telegram-origin merges cannot):
hermes gateway restart
hermes gateway status

hermes desktop --force-build
stat -c '%y' apps/desktop/release/linux-unpacked/resources/app.asar
```

**Smoke checklist**

- [ ] `skill_view` on a skill only reachable via symlink under `~/.hermes/skills/`
- [ ] Voice memo STT (`stt.local.device: cpu` if CUDA 12 libs missing)
- [ ] Dashboard: `curl -H 'Host: shuvdev:9119' …` → 200
- [ ] MoA preset visible in model picker (new in 0.18)
- [ ] Desktop realtime voice settings still present
- [ ] `computer_use` still disabled in config (shuvdev policy)

### 6. Secondary hosts (nick / shuvbot) — after `main` is green

```bash
ssh nick 'cd ~/repos/hermes-agent && git pull origin main'
ssh nick '/home/shuv/repos/hermes-agent/venv/bin/pip3 install -e /home/shuv/repos/hermes-agent -q'
rsync -av ~/.hermes/patches/ nick:~/.hermes/patches/
ssh nick 'bash ~/.hermes/patches/apply.sh'
# Skip shuvoncho-ws-shuvslop-model-override on non-shuvdev hosts
```

## Fork-only commits (top of `upstream/main..HEAD`)

```text
cb6d5c8b7 feat(anthropic): add Claude Sonnet 5 support
0775545d5 fix(pairing): stop the Ref/code footgun in approval flow
2c0ff030d Merge upstream/main (v0.17.0 "The Reach", 335 commits) into fork
… realtime voice, desktop cwd/folder, telegram rich, CI/PyPI guards, merge commits …
992a147f3 fix(skill_manager): follow symlinks in _find_skill using os.walk
```

Full list: `git log --oneline upstream/main..HEAD`

## Risk / effort estimate

| Risk | Mitigation |
|------|------------|
| ~2× size of v0.17 merge | Branch + rerere; budget ~4–8h for conflicts + scoped tests |
| Silent feature drop in desktop refactor | Explicit port of `use-prompt-actions` behavior |
| Skills invisible after merge | Verify `followlinks` in `skill_manager_tool.py` |
| False “patch broken” in journal | Compare `systemctl --user status` Active time vs error timestamp |
| Gateway restart from Telegram session | User runs `hermes gateway restart` locally |

## References

- `PLAN-upstream-main-merge.md` — older merge plan format (stale counts)
- `AGENTS.md` — post-merge runtime refresh (fork)
- `~/.hermes/wiki/reference/patches-ledger.md` — patch inventory (update after merge)
- `~/repos/shuvbot-skills/skills/devops/hermes-agent-local-patches/` — authoritative patch procedures
- `~/repos/shuvbot-skills/skills/software-development/fork-upstream-merge/` — merge discipline

## Completion log

| Step | Date | Result |
|------|------|--------|
| Dry-run merge-tree | 2026-07-01 | 21 conflicts |
| Patch dry-run on upstream | 2026-07-01 | STT + dashboard clean; delegate retire |
| Merge branch created | | |
| Conflicts resolved | | |
| `main` ff-merged | | |
| Gateway + desktop refreshed | | |