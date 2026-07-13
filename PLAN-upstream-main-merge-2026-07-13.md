# Fresh upstream merge plan — 2026-07-13

**Status:** executed and landed on 2026-07-13.

**Final result:** upstream was refreshed to `b03c94dbed5ee72e97eace2376e02092cc854f6a`,
merged as two-parent commit `a5130bf6291f9ab48dbe713e659699a78443e660`, and
the desktop CWD return-contract integration repair was committed as
`7c8e24dede0cf5d57d8c43b59993923d7d448832`. Both commits are pushed to
`origin/main`. The clean desktop package is stamped to `7c8e24dede0c`.

**Execution notes:** the focused Python merge suite passed (834 tests), the
desktop typecheck and focused CWD test pass after the integration repair, and
the packaged Linux app contains its native `node-pty` binding. The broad UI and
lint commands exposed additional merged-tree test-runner, test, and lint
failures that were not addressed or folded into this merge. The installed
delegate patch now reports a textual conflict because its behavior is already
present in the merged source; its semantic tests passed, so it was not
reapplied blindly.

**Reviewed target:** `upstream/main` at `2bd721cebc857bdd1b052d4246f977f624ea0fff`
(`test(kanban): remove duplicate final-results footer`, 2026-07-12 23:44 PDT).

**Fork base:** `origin/main` at `0c5fb99a8` (`Merge upstream/main into fork`).

## Review result

The merge is ready to execute in a disposable worktree. The dry run produced
four textual conflicts, all of which are additive unions rather than design
forks. The larger review burden is the 47 silently auto-merged paths that both
the fork and upstream changed.

- Merge base: `8e3f9537db21b49ebe796f7b5a6ff489028fe1fb`
- Divergence from the merge base: 130 fork-side commits, 284 upstream-side commits
- Upstream delta: 400 files, 23,044 insertions, 2,159 deletions
- Fork delta: 245 files
- Both sides changed: 47 files
- Textual conflicts in a real `--no-commit` merge: 4 files
- Open PRs against `shuv1337/hermes-agent:main`: none
- `stack status`: unavailable because the local `stack` executable is not on `PATH`; no fork PR stack was found through GitHub
- Current release remains `0.18.2` / `v2026.7.7.2`; the reviewed tip is 423 commits past that tag

The main checkout has unrelated uncommitted removal/catalog work for
`gitnexus-explorer`. None of those paths changes in the reviewed upstream
delta. Do not stash, discard, stage, or fold those edits into this merge.

## Guardrails

- [ ] Re-fetch `origin` and `upstream` immediately before execution.
- [ ] Require `origin/main == 0c5fb99a8` and either:
  - `upstream/main == 2bd721ceb`, or
  - repeat the divergence, overlap, and dry-merge review for the new tip.
- [ ] Preserve the current main-checkout diff and its exact path list for a
  post-landing comparison; do not use `git stash` in the installed checkout.
- [ ] Perform all merge work on a new branch in a separate worktree based on
  `origin/main`.
- [ ] Create a true two-parent merge commit; do not rebase or squash the fork's
  history.
- [ ] Do not mix dependency refreshes, generated output, or unrelated catalog
  changes into the merge commit unless upstream requires the generated file.

## Phase 1 — freeze the reviewed inputs

- [ ] Capture the current state:

  ```bash
  cd /home/shuv/repos/hermes-agent
  git fetch --prune origin
  git fetch --prune upstream --tags
  git status --short --branch
  git rev-parse origin/main upstream/main
  git merge-base origin/main upstream/main
  git rev-list --left-right --count origin/main...upstream/main
  ```

- [ ] Save a read-only checksum and patch for the existing uncommitted catalog
  work so it can be proven unchanged after landing:

  ```bash
  git diff --binary -- \
    optional-skills/research/gitnexus-explorer \
    website/docs/reference/optional-skills-catalog.md \
    website/docs/user-guide/skills/optional/research/research-gitnexus-explorer.md \
    website/i18n/zh-Hans/docusaurus-plugin-content-docs/current/reference/optional-skills-catalog.md \
    website/i18n/zh-Hans/docusaurus-plugin-content-docs/current/user-guide/skills/optional/research/research-gitnexus-explorer.md \
    website/sidebars.ts > /tmp/hermes-premerge-local-catalog.patch
  sha256sum /tmp/hermes-premerge-local-catalog.patch
  ```

- [ ] Reconfirm that upstream does not touch those dirty paths. Stop and ask
  for direction if the result becomes non-empty.

- [ ] Create the merge worktree and branch:

  ```bash
  git worktree add -b merge/upstream-2026-07-13 \
    /tmp/hermes-upstream-merge-2026-07-13 origin/main
  cd /tmp/hermes-upstream-merge-2026-07-13
  git merge --no-ff --no-commit 2bd721cebc857bdd1b052d4246f977f624ea0fff
  ```

## Phase 2 — resolve the four textual conflicts

### `agent/transports/chat_completions.py`

- [ ] Preserve both sanitizers in both detection and removal branches:
  `reasoning_details` from the fork and `effect_disposition` from upstream.
- [ ] Retain copy-on-write behavior so the input message list is not mutated.
- [ ] Ensure tests assert that each field is stripped for strict
  Chat Completions relays while the original messages remain intact.

### `apps/desktop/electron/main.ts`

- [ ] Keep the fork's `DEFAULT_DESKTOP_ZOOM_LEVEL` calculation and default
  `0.5` zoom behavior.
- [ ] Take upstream's configurable app name:
  `process.env.HERMES_DESKTOP_APP_NAME || 'Hermes'`.
- [ ] Preserve the existing single-instance lock and `second-instance` focus
  behavior later in this file.
- [ ] Validate that upstream's restore/show zoom changes still reapply the
  configured or persisted zoom only to chat windows.

### `scripts/release.py`

- [ ] Union the `AUTHOR_MAP`: retain fork entries for `shuv@shuv.dev` and
  `DavidMetcalfe@users.noreply.github.com`, plus every upstream attribution.
- [ ] Do not resolve this conflict by taking either whole side.

### `tools/delegate_tool.py`

- [ ] In the no-provider inheritance return, include all three fields:
  `model_explicitly_supplied`, `request_overrides`, and `max_output_tokens`.
- [ ] Preserve the auto-merged configured-provider return containing runtime
  `request_overrides`, `max_output_tokens`, command/args, and the fork's
  `model_explicitly_supplied` flag.
- [ ] Verify the child-agent construction path consumes all of these values;
  do not stop at dictionary-shape tests.

### Conflict hygiene

- [ ] Stage only the four resolved files first and review them with
  `git diff --check`, `git diff --cached`, and a conflict-marker scan.
- [ ] Confirm `git diff --name-only --diff-filter=U` is empty before staging
  the remaining automatic merge result.
- [ ] Do not commit yet.

## Phase 3 — audit the 47 silent overlaps

Review the fork-side intent and the merged result for each category below.
The test named beside each category is part of the acceptance contract.

### Provider and model transport

- [ ] `agent/transports/chat_completions.py`: preserve strict-relay stripping
  of `reasoning_details` while adding upstream `effect_disposition` handling.
- [ ] `agent/model_metadata.py`: retain the fork's provider-aware GPT-5.6
  Codex context handling and upstream's YAML-null guard.
- [ ] `agent/anthropic_adapter.py`: re-run OAuth/tool-schema tests even though
  Git merged it automatically.
- [ ] Confirm `hermes_cli/codex_models.py` still exposes Sol, Terra, Luna, and
  their `-pro` variants; upstream did not touch this file in the reviewed delta.

### Desktop lifecycle, cwd, and realtime voice

- [ ] `apps/desktop/electron/main.ts`: inspect app naming, zoom restoration,
  single-instance locking, second-instance focus, WSL path bridging, and
  backend switching as one lifecycle surface.
- [ ] `apps/desktop/src/app/session/hooks/use-cwd-actions.ts`: preserve the
  fork's `/cwd` and folder-start behavior while accepting upstream's sidebar
  workspace-target persistence.
- [ ] Confirm realtime voice composer/settings files remain present and wired;
  upstream did not directly change the voice modules, but lifecycle changes can
  still break them indirectly.

### Gateway, prompt, and platform behavior

- [ ] `gateway/run.py`, `gateway/session.py`, and `gateway/slash_commands.py`:
  preserve fork status metadata and command behavior while accepting upstream
  context-budget, async SessionStore, readiness, and context-reference fixes.
- [ ] Reconfirm the Anthropic OAuth prompt guard in `agent/prompt_builder.py`;
  the blocked raw media-path literal must not reappear.
- [ ] Re-run Signal mention, inline-reply, attachment, and status tests even
  though upstream did not change `gateway/platforms/signal.py` in this batch.

### Local operational deltas

- [ ] `hermes_cli/web_server.py`: retain `HERMES_DASHBOARD_ALLOWED_HOSTS` and
  hostile-Host rejection after upstream's web-server changes.
- [ ] `tools/transcription_tools.py`: retain `stt.local.device` and
  `stt.local.compute_type` while accepting upstream transcription changes.
- [ ] `tools/skill_manager_tool.py`: confirm symlink-following skill discovery
  remains intact; upstream did not touch it in this batch.
- [ ] `plugins/platforms/photon/sidecar/patch-spectrum-mixed-attachments.mjs`:
  retain support for current and stale Spectrum layouts; upstream did not touch
  it in this batch.

## Phase 4 — local patch audit

The current patch inventory must be classified by behavior, not by whether a
raw patch applies to `upstream/main`.

- [ ] Confirm the merged tree reverse-applies
  `dashboard-allowed-hosts.patch`; if not, restore the behavior and regenerate
  the patch only after the merge is landed.
- [ ] Confirm the merged tree reverse-applies
  `transcription-cuda-version-fallback.patch`.
- [ ] Treat `delegate-tool-config-model-counts.patch` as semantically active:
  its raw patch conflicts with upstream, and the merge resolution must preserve
  the `model_explicitly_supplied` behavior alongside new runtime metadata.
- [ ] Keep Honcho peer naming config-based via `honcho.runtimePeerPrefix`; do
  not resurrect `honcho-peer-naming.patch`.
- [ ] Confirm background review still uses `skip_memory=True` and
  `persist_session=False`; leave its patch retired if upstream/fork code already
  contains the behavior.
- [ ] Check the kanban dashboard bundle for `selectChangeHandler`; retire or
  retain its directory patch based on the merged code, not the old prediction.
- [ ] Ignore raw apply failures for OrcaSlicer, Omarchy, and shuvoncho patches;
  they target other repositories or machine-local integrations.

## Phase 5 — establish dependencies and validate

### Baseline already established on `origin/main`

- Focused Python suite: **827 passed**, 7 warnings.
- Desktop `typecheck` and UI tests: blocked before merge by incomplete root
  workspace dependencies (`@tanstack/react-query`, `@assistant-ui/*`, testing
  libraries, and others are missing from the current `node_modules`).

### Merge-worktree validation

- [ ] Install JavaScript dependencies from the repository root so workspace
  packages resolve correctly:

  ```bash
  cd /tmp/hermes-upstream-merge-2026-07-13
  npm ci
  ```

- [ ] Run desktop checks using the merged scripts, including upstream's new
  Electron TypeScript check:

  ```bash
  npm --workspace apps/desktop run typecheck
  npm --workspace apps/desktop run test:ui -- \
    src/app/settings/voice-field-visible.test.ts \
    src/app/session/hooks/use-cwd-actions.test.tsx
  node --test \
    apps/desktop/electron/zoom.test.ts \
    apps/desktop/electron/update-relaunch.test.ts \
    apps/desktop/electron/workspace-cwd.test.ts \
    apps/desktop/electron/wsl-path-bridge.test.ts
  ```

- [ ] Create a worktree-local Python environment and install the merged package
  with the extras exercised by the focused suite. This avoids mutating the live
  installed venv before the merge lands:

  ```bash
  python -m venv .venv
  .venv/bin/python -m pip install -e '.[dev,messaging,feishu,anthropic]'
  .venv/bin/python -m pytest -q --tb=short \
    tests/agent/transports/test_chat_completions.py \
    tests/tools/test_delegate.py \
    tests/hermes_cli/test_gpt56_registration.py \
    tests/hermes_cli/test_codex_models.py \
    tests/plugins/platforms/photon/test_spectrum_patch.py \
    tests/gateway/test_signal.py \
    tests/gateway/test_status_command.py \
    tests/agent/test_anthropic_adapter.py \
    tests/agent/test_prompt_builder.py \
    tests/hermes_cli/test_realtime_session.py
  ```

- [ ] Add or update focused tests for the four conflict unions if upstream did
  not already cover both sides.
- [ ] Run `scripts/run_tests.sh` as the broad Python gate. If it reports a
  failure, reproduce the same test at `origin/main` before declaring it a merge
  regression.
- [ ] Run desktop lint and the relevant UI/electron suites after typecheck.
- [ ] Review dependency-manifest changes before committing. Expected reviewed
  changes include `lark-oapi` 1.5.3 to 1.6.8 and desktop build/typecheck script
  changes; unexpected dependency churn requires investigation.

## Phase 6 — commit, land, and prove the dirty checkout survived

- [ ] Review the final staged delta by parent and by known fork seam:

  ```bash
  git diff --check
  git diff --cached --stat
  git diff --cached -- \
    agent/transports/chat_completions.py \
    apps/desktop/electron/main.ts \
    scripts/release.py \
    tools/delegate_tool.py
  ```

- [ ] Create one true merge commit:

  ```bash
  git add -A
  git commit -m "Merge upstream/main into fork"
  ```

- [ ] Verify two parents and rerun the focused gates against the committed tree.
- [ ] Push the validated merge commit to fork `main` only after checking the
  remote old SHA:

  ```bash
  git push origin HEAD:main --force-with-lease=main:0c5fb99a8
  ```

  This is a guarded non-rewrite push: the merge commit is a descendant of the
  expected old main. Do not use an unguarded force push.

- [ ] In `/home/shuv/repos/hermes-agent`, fast-forward local `main` to
  `origin/main`. Before doing so, recheck that the dirty catalog paths still do
  not overlap the incoming changes.
- [ ] Recreate `/tmp/hermes-postmerge-local-catalog.patch` from the same paths
  and require its SHA-256 to match the pre-merge patch.
- [ ] Remove the temporary worktree and merge branch after successful landing.

## Phase 7 — refresh the installed runtime

Source merge, editable install, gateway process, and packaged desktop are four
separate states. Completion requires all of them to agree.

- [ ] Run the patch driver from the installed checkout and investigate only
  Hermes-target patch failures:

  ```bash
  cd /home/shuv/repos/hermes-agent
  ~/.hermes/patches/apply.sh
  ```

- [ ] Reinstall through the repo venv interpreter, including the upstream
  Feishu dependency update:

  ```bash
  ./venv/bin/python -m pip install -e .
  ```

- [ ] Restart and verify the gateway from a shell outside the gateway process:

  ```bash
  hermes gateway restart
  hermes gateway status
  ```

- [ ] Require a new PID, `active (running)`, and the expected running commit.
- [ ] Rebuild the packaged desktop and prove no desktop source is newer than
  `app.asar`:

  ```bash
  hermes desktop --force-build
  stat -c '%y  %n' apps/desktop/release/linux-unpacked/resources/app.asar
  find apps/desktop/src apps/desktop/electron -type f \
    -newer apps/desktop/release/linux-unpacked/resources/app.asar | wc -l
  ```

## Final smoke checklist

- [ ] GPT-5.6 Sol/Terra/Luna and `-pro` variants appear under `openai-codex`
  with the correct provider-aware context window.
- [ ] Desktop launches as one instance, focuses on repeat activation, preserves
  default/persisted zoom, and opens workspace folders correctly.
- [ ] Desktop `/cwd` and “new chat in folder” work, including sidebar workspace
  targets.
- [ ] Realtime voice settings remain visible and a voice turn can delegate from
  the active workspace.
- [ ] Gateway `/status` reports model/context and running-vs-disk commit data.
- [ ] Signal inline replies, mention gating, attachments, and rich delivery work.
- [ ] A skill reachable only through the symlinked skills tree resolves.
- [ ] Dashboard accepts the configured `shuvdev` Host and rejects an arbitrary
  Host header.
- [ ] Local STT honors CPU/int8 configuration.
- [ ] Authenticated Photon `POST /healthz` succeeds.
- [ ] The main checkout's pre-existing `gitnexus-explorer` catalog diff is byte
  identical to the pre-merge snapshot.

## Stop conditions

Stop and re-plan instead of improvising if any of these occur:

- `origin/main` moved from `0c5fb99a8` before the guarded push.
- `upstream/main` moved past the reviewed SHA and the new dry run changes the
  conflict or overlap set.
- Upstream begins touching the current dirty catalog paths.
- A conflict requires choosing between mutually exclusive product behavior
  rather than combining compatible fields.
- The merge changes prompt-cache stability, message-role alternation, or model
  tool-schema footprint.
- A focused regression reproduces only on the merged tree and its intended
  behavior is unclear from history or tests.
