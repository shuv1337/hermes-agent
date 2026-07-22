# PLAN: Merge upstream → Hermes Desktop on Linux

**Goal:** Absorb 298 upstream commits (through `b34ee8074`, ~v0.15.2+468), enabling `hermes desktop` on Linux.

**State as of:** 2026-06-02  
**Fork:** `shuv1337/hermes-agent` at `~/repos/hermes-agent`  
**Behind:** 298 commits. **Ahead:** 56 commits.

---

## What we're unlocking

Upstream shipped `apps/desktop/` as a full Electron app with a `hermes desktop` CLI subcommand. On Linux the path is build-from-source (no AppImage in the current public release yet — those were pre-release smoke tests). Once merged, the workflow is:

```bash
hermes desktop          # builds + launches against existing install
# or on fresh install:
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash -s -- --include-desktop
```

Node 26 is installed (above the Node 22 minimum). No other new prereqs.

---

## Risk map

### High-risk overlap files (fork AND upstream both touched)

| File | Fork patches | Upstream changes | Risk |
|------|-------------|-----------------|------|
| `agent/anthropic_adapter.py` + `agent/transports/anthropic.py` | Retired uppercase OAuth encoding (`ab6eb9783`) | Upstream `mcp__` producer/consumer contract supersedes it | 🔴 CRITICAL — take upstream in both files; never mix schemes |
| `tools/skill_manager_tool.py` | Symlink fix: `os.walk(followlinks=True)` (`992a147f3`) | Replaced with `rglob("SKILL.md")` which silently breaks symlinked skill dirs | 🔴 CRITICAL — re-apply immediately |
| `gateway/platforms/signal.py` | `require_mention` gating + self-@mention strip (`e8034a962`, `38aa74095`) | New message handling; duplicate-block risk from previous merge patterns | 🟠 HIGH |
| `agent/prompt_builder.py` | OAuth-safe MEDIA: literal rewordings (`88c103b07`, `03f8a5e8f`) | CUA driver element bounds additions | 🟠 HIGH |
| `run_agent.py` | Maple OTEL wiring, delegation patch, preserved across merges | 258 lines changed upstream; the big refactor already landed (3,821 lines vs old 16k) | 🟡 MEDIUM — mostly additive |
| `gateway/run.py` | Gateway patches | Stream-event protocol, gateway restart handling | 🟡 MEDIUM |
| `gateway/session.py` | — | Session list, compression changes | 🟡 MEDIUM |
| `gateway/platforms/telegram.py` | HTML parse mode fix (`84f200e26`) | Draft formatting parity | 🟡 MEDIUM |
| `hermes_cli/web_server.py` | — | Dashboard auth, loopback fixes | 🟡 LOW |
| `tools/transcription_tools.py` | CUDA version fallback (patch file) | — | 🟡 LOW |
| `AGENTS.md` | Computer use notes, OAuth pitfalls | Desktop docs added | 🟢 LOW |
| `locales/en.yaml` | — | New string keys | 🟢 LOW (auto-merge) |

### Fork-only files (additions — should survive cleanly)

Our additions that upstream doesn't have and will need to be preserved:

- `agent/error_classifier.py`, `agent/telemetry.py` — Maple OTEL
- `agent/transports/anthropic.py` — transport abstraction layer
- `gateway/channel_directory.py` + tests
- `tools/computer_use/` (backend, schema, tool) + tests
- `tools/delegate_tool.py`, `tools/mcp_oauth_manager.py`, `tools/mcp_oauth.py`
- `tools/memory_tool.py`, `tools/skill_manager_tool.py` (with symlink fix)
- Signal/OAuth integration tests

These are additions on our side with no upstream counterpart — they should auto-merge cleanly. Verify they're still present after merge.

---

## Pre-merge checklist

```bash
cd ~/repos/hermes-agent

# 1. Confirm clean working tree
git status -sb

# 2. Confirm upstream remote is current
git fetch upstream --quiet
git rev-list --count main..upstream/main   # should be 298

# 3. Stash any untracked files if needed
git stash list
```

---

## Phase 1 — Staging branch + dry-run

```bash
git checkout -b try-merge-upstream-$(date +%Y%m%d)

# Preview conflicts before committing
git merge upstream/main --no-commit --no-ff
```

Expected conflict sites based on overlap analysis:
- `agent/anthropic_adapter.py` — OAuth blocklist removal conflict
- `tools/skill_manager_tool.py` — rglob vs os.walk
- `gateway/platforms/signal.py` — likely clean auto-merge but inspect
- `agent/prompt_builder.py` — MEDIA literal rewording vs upstream additions

If conflict volume is overwhelming, abort and come back: `git merge --abort`

---

## Phase 2 — Conflict resolution guide

Run actual merge:

```bash
git merge upstream/main --no-edit
```

### `tools/skill_manager_tool.py` 🔴

**Shape:** Upstream replaced `os.walk(followlinks=True)` with `rglob("SKILL.md")`. Our commit `992a147f3` reverted this. May auto-merge with upstream's rglob if our commit was the LAST thing to touch it.

**Resolution:** Regardless of which side wins textually, the final state MUST use `os.walk(followlinks=True)`. Check after merge:

```bash
grep -n "followlinks\|rglob" tools/skill_manager_tool.py
```

If `rglob` is present without `followlinks`, re-apply manually:

```python
# In _find_skill() — replace:
for skill_md in skills_dir.rglob("SKILL.md"):
# With:
for root, _dirs, files in os.walk(skills_dir, followlinks=True):
    if "SKILL.md" not in files:
        continue
    skill_md = Path(root) / "SKILL.md"
```

Do the same in `_find_skill_in_other_profiles()`. Verify: `python -c "from tools.skill_manager_tool import _find_skill; print(_find_skill('shuvgeist'))"` (should find symlinked skill).

### `agent/anthropic_adapter.py` + `agent/transports/anthropic.py` 🔴

> **Superseded guidance (corrected after the v0.17.0 merge):** Do **not**
> restore the fork-only `_encode_oauth_tool_name` / `_decode_oauth_tool_name`
> uppercase scheme from `ab6eb9783`. Upstream's `mcp__` double-underscore
> implementation supersedes it and also handles native MCP server tools.

**Required invariant:** `build_anthropic_kwargs()` and
`AnthropicTransport.normalize_response()` must use the same wire-name contract.
Outgoing OAuth tools become `mcp__...`; the response transport reverses that
form via registry lookup. A partial merge that takes upstream's adapter (which
removed `_decode_oauth_tool_name`) while retaining the fork transport import
causes every Anthropic response to fail locally after a successful API call.

**Check after merge:**

```bash
! grep -R "_decode_oauth_tool_name\|_encode_oauth_tool_name" \
    agent/anthropic_adapter.py agent/transports/anthropic.py
scripts/run_tests.sh tests/agent/test_anthropic_mcp_prefix_strip.py \
    tests/agent/transports/test_transport.py -q
```

The request- and response-side tests must both pass. Also run the Opus 4.8
thinking replay tests because merge conflicts in `anthropic_adapter.py` can
silently revert the byte-exact latest-assistant contract.

### `agent/prompt_builder.py` 🟠

**Shape:** We rewrote blocked MEDIA literal strings. Upstream added new strings. Risk of new strings reintroducing blocked literals.

**Check after merge:**

```bash
grep -n "MEDIA:/\|/absolute/path\|file path" agent/prompt_builder.py | head -20
```

Any literal `MEDIA:/path/to/file` or `MEDIA:/absolute/path` in model-visible text will get rejected by Anthropic's content filter on the OAuth path. Re-apply rewordings if needed (git show `88c103b07`).

### `gateway/platforms/signal.py` 🟠

**Check after merge that both invariants hold:**
1. Self-@mention stripping so slash commands route correctly (`e8034a962`)
2. `require_mention` group gating (`38aa74095`)
3. No duplicate text/mention rendering block (`2d682eb34` — the classic merge artifact)

```bash
grep -n "require_mention\|strip.*mention\|_render_mentions\|text.*=.*data_message" gateway/platforms/signal.py
```

If `_render_mentions` appears twice in the same function, the duplicate-block is back — delete the second occurrence.

### Conflict marker sweep (always before committing)

```bash
grep -rn "<<<<<<< \|>>>>>>> " --include="*.py" .
```

Zero results required.

### AST check on modified files

```bash
python -c "
import ast, glob
for f in ['run_agent.py', 'agent/anthropic_adapter.py', 'tools/skill_manager_tool.py',
          'agent/prompt_builder.py', 'gateway/platforms/signal.py',
          'gateway/run.py', 'gateway/session.py']:
    try:
        ast.parse(open(f).read())
        print(f'OK: {f}')
    except SyntaxError as e:
        print(f'FAIL: {f}: {e}')
"
```

---

## Phase 3 — Post-merge patches

After resolving and committing the merge, re-run the patches. **Both env vars required** — the master `apply.sh` uses `HERMES_AGENT_DIR`, but subdirectory patch scripts use `HERMES_AGENT_REPO`.

```bash
export HERMES_AGENT_DIR=~/repos/hermes-agent
export HERMES_AGENT_REPO=~/repos/hermes-agent

# Top-level .patch files
bash ~/.hermes/patches/apply.sh

# Subdirectory patches (each has its own apply.sh)
for d in ~/.hermes/patches/*/; do
  [ -f "$d/apply.sh" ] && bash "$d/apply.sh"
done
```

### Patch inventory and expected outcome

**hermes-agent patches (HERMES_AGENT_DIR / HERMES_AGENT_REPO):**
- `dashboard-allowed-hosts.patch` — dashboard loopback auth
- `delegate-tool-config-model-counts.patch` — delegation model counting
- `transcription-cuda-version-fallback.patch` — CUDA STT fallback
- `orca-cli-inheritance-fix.patch` — OrcaSlicer profile inheritance
- `hermes-agent-honcho-peer-naming/` — injects `runtimePeerPrefix` into `~/.hermes/config.yaml` (updated 2026-05-28 from git-patch to config mutation; should apply cleanly regardless)
- `hermes-agent-review-fork-skip-memory/` — `skip_memory=True` in background review; updated 2026-05-28 to check for upstream absorption first, should exit 0 if already present

**Host-infra patches (not hermes-agent; will silently skip or handle their own targets):**
- `dashboard-night-owl-theme/` — mutates `~/.hermes/config.yaml` theme setting, targets `$HERMES_HOME`
- `kanban-inline-create-select-onvaluechange/` — patches kanban `dist/index.js` via `HERMES_AGENT_DIR`
- `omarchy-hyprpicker-safe/` — Linux/Hyprland hyprpicker; no-op on wrong host
- `shuvoncho-ws-shuvslop-model-override/` — targets shuvoncho instance, not hermes-agent

Patches that may be **absorbed upstream** (check before applying):
- Any patch that fails with "already applied" or "context mismatch" — check if upstream shipped the same fix. If so, move to `_retired/`.

---

## Phase 4 — Test isolation

```bash
source venv/bin/activate
python -m pytest tests/ -x --tb=short -q \
  --ignore=tests/integration \
  --ignore=tests/gateway/test_whatsapp.py \
  2>&1 | tail -40
```

**Before assuming a failure is merge-caused**, check it against pure upstream:

```bash
git stash -u
git checkout upstream/main -- <failing_test.py>
python -m pytest <failing_test.py> --tb=no -q
git checkout HEAD -- <failing_test.py>
git stash pop
```

If it fails on upstream too, skip it — not our regression.

Critical fork tests to verify pass:

```bash
python -m pytest \
  tests/integration/test_oauth_blocklist_bisect.py \
  tests/integration/test_oauth_content_filter.py \
  tests/agent/test_anthropic_adapter.py \
  tests/agent/test_anthropic_mcp_prefix_strip.py \
  tests/gateway/test_channel_directory.py \
  tests/tools/test_computer_use.py \
  --tb=short -q
```

---

## Phase 5 — Land on main

```bash
# Stash the post-merge patch mutations (apply.sh rewrote run_agent.py etc.)
git stash push -u -m "post-merge local patches"

git checkout main
git merge try-merge-upstream-YYYYMMDD --ff-only
git push origin main

# Re-apply patches on main — export BOTH vars
export HERMES_AGENT_DIR=~/repos/hermes-agent
export HERMES_AGENT_REPO=~/repos/hermes-agent
bash ~/.hermes/patches/apply.sh
for d in ~/.hermes/patches/*/; do
  [ -f "$d/apply.sh" ] && bash "$d/apply.sh"
done

git stash drop  # patches re-applied; stash is now redundant

# Clean up staging branch
git branch -d try-merge-upstream-YYYYMMDD
```

---

## Phase 6 — Multi-host propagation (shuvbot)

Resolve the merge once on shuvdev, push, fast-forward on shuvbot. Do **not** re-resolve conflicts on the secondary host.

```bash
ssh shuvbot '
  REPO=$HOME/.hermes/hermes-agent
  cd "$REPO" || { echo "repo not found at $REPO"; exit 1; }

  # Safety branch
  git branch backup/main-pre-update-$(date +%Y%m%d) HEAD 2>&1 | tail -1

  # Stash any active patches before the ff-merge
  git stash push -u -m "post-merge local patches" 2>&1 | tail -2

  # Fast-forward to already-merged origin/main
  git fetch origin --quiet
  git merge --ff-only origin/main 2>&1 | tail -3

  echo "--- NEW HEAD ---"
  git rev-parse HEAD

  # Re-apply patches (shuvbot uses ~/.hermes/hermes-agent, not ~/repos/hermes-agent)
  export HERMES_AGENT_DIR=$HOME/.hermes/hermes-agent
  export HERMES_AGENT_REPO=$HOME/.hermes/hermes-agent
  bash ~/.hermes/patches/apply.sh 2>&1 | tail -8
  for d in ~/.hermes/patches/*/; do
    [ -f "$d/apply.sh" ] && bash "$d/apply.sh" 2>&1 | tail -3
  done

  git stash drop 2>&1 | tail -1
'
```

**Verify the HEAD matches what you pushed from shuvdev.** If `git rev-parse HEAD` still shows the old SHA, the merge ran in a stale shell context — open a fresh SSH session and re-run.

Note: `omarchy-hyprpicker-safe` and `shuvoncho-ws-shuvslop-model-override` patches are Linux/Hyprland or shuvoncho-specific and silently skip on shuvbot (no matching target file).

---

## Phase 7 — Desktop build + config migration

```bash
# Migrate config if version bumped (check first — value may already be current)
hermes config migrate

# Reload hermes (picks up new code)
hermes update   # or: pip install -e . from repo root

# Build + launch desktop
hermes desktop
```

On first launch: Hermes walks you through provider selection. Since the install already exists at `~/.hermes`, it should connect automatically (confirmed in the tweet: "It connects your existing agent if there is one").

If `hermes desktop` subcommand is missing after update:

```bash
# Install desktop deps and build manually
cd apps/desktop
npm install
npm run build
npm run start
```

Remote gateway mode is also available if needed: point it at `http://127.0.0.1:8642` (the dashboard gateway port) with a session token.

---

## Known issues to watch for

1. **Ollama local model connection** — upstream tweeted it's broken, fix incoming. Workaround: `hermes model` in CLI to set provider.
2. **Config version drift** — verify the exact migration version with `hermes config migrate --dry-run` or inspect the upstream changelog before running; the v22→v24 figure is based on reading the tweet thread, not confirmed from the code.
3. **Patch anchor rot** — `transcription-cuda-version-fallback.patch` and `orca-cli-inheritance-fix.patch` may have stale anchors if upstream touched those files. Check `apply.sh` output carefully for `✗ conflict` lines.
4. **`apps/desktop/` npm install** — first build downloads Electron (~150MB). Make sure disk space is fine.
5. **`HERMES_AGENT_DIR` vs `HERMES_AGENT_REPO` split** — the master `apply.sh` uses `HERMES_AGENT_DIR`; subdirectory scripts (`hermes-agent-review-fork-skip-memory`, `kanban-inline-create-select-onvaluechange`) use `HERMES_AGENT_REPO`. Always export both before running the patch loop.

---

## Quick verification after landing

```bash
hermes --version                          # should show v0.15.2+
hermes doctor                             # no regressions
hermes skill_manage list | grep shuvgeist # symlinked skills still visible
hermes desktop                            # launches GUI
```
