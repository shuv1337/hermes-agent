# Merge Plan: upstream/main into local main

## Current State

- Local branch: `main`
- Tracking branch: `origin/main`
- Upstream target: `upstream/main`
- Current upstream tip: `40420a619 fix(desktop): attachments on Enter, IME composition, scroll, fetchJson resets (salvage #38502) (#38677)`
- Current divergence after `git fetch upstream`: `78` commits ahead, `135` commits behind `upstream/main`
- Merge base: `205ed71ba0e55d1b34083e9db52fee732aa7038e`
- Dry merge command used:
  ```bash
  git merge-tree --name-only --merge-base "$(git merge-base HEAD upstream/main)" HEAD upstream/main
  ```

## Upstream Commits to Merge

```text
40420a619 (upstream/main, upstream/HEAD) fix(desktop): attachments on Enter, IME composition, scroll, fetchJson resets (salvage #38502) (#38677)
2e628ae97 fix(docker): add libolm-dev so matrix lazy-install can build python-olm (#33685)
30c7b787d fix(memory): fall back to pip when uv is unavailable (salvage #5954) (#38668)
03ba06ebf fix(docker): chown gateway install tree on UID remap (salvage #37928) (#38655)
e45dd2b0e refactor(web): unify main-slot model assignment base_url/context handling (#38593)
e2ea648a0 test(docker): make tty-passthrough probe robust to container boot-log noise (#38665)
7402706c5 fix(docker): accept Unraid uid mappings (#38098)
2059707fc fix(gateway-windows): anchor detached/startup cwd at HERMES_HOME
40fbb0f3c fix(constants): use windows native default hermes home
e3313c50a feat(dashboard): add Debug Share to the System page (#38600)
f66a929a6 fix(desktop): render approval/sudo/secret prompts so tools stop silently timing out (#38578)
04d620d91 fix(docker): run config migrations during container boot (salvage #35508) (#36627)
92be98929 Merge pull request #38564 from NousResearch/bb/tui-sgr-mouse-fragment-leak
343c54e35 fix(docker): reject unsupported --user <arbitrary-uid> start with clear guidance (#38579)
b0a52d74a fix(mcp): resolve ${ENV} in discovery probe so header auth works (#38571)
5a22cd427 fix(desktop): configure local/custom endpoint without an API key or UI changes
ca0671572 feat(web): wire local/custom endpoints into model assignment
d50741af9 fix(onboarding): clarify Anthropic API vs OAuth provider entries and reorder (#38577)
725290db6 test(hermes-ink): fuzz the tokenizer flush valve against fragment leaks
e7bc6189c feat(cli): resume relaunches in the directory the session was started from (#38562)
6efc7eda5 refactor(hermes-ink): delete now-dead SGR mouse fragment recovery
de124800a test(hermes-ink): drop input-event SGR guard test
f35432354 fix(hermes-ink): reassemble split mouse sequences at the tokenizer; drop the regex sink
5446153c9 fix(docker): chown build trees on UID remap independently of $HERMES_HOME (#35027 regression) (#38556)
01c010e23 fix(hermes-ink): collapse SGR mouse fragment guards into one flush-aware rule
f99665f99 feat(prompt): broaden Hermes self-knowledge pointer to docs + skill (#38538)
a6e47314f fix(dashboard): sanction plugin WS/upload auth via SDK helpers (gated mode)
1c88360fe Merge pull request #38546 from NousResearch/bb/disable-provider-key-validation
475ecea3d fix(install): cap requires-python at <3.14 and pin UV_PYTHON to the venv (#38535)
e8c3ac2f5 fix: strip extra_content from tool_calls for strict APIs (Fireworks, Mistral)
ec69c767f docs(desktop): point Chat section to remote-backend + dashboard doc (#38545)
2f523a469 fix(tui): cgroup-aware V8 heap cap so memory-limited containers stop dying silently (#38541)
8a19884bf fix(update): stop stash/restore from clobbering desktop source on managed clones (#38542)
7ea37cd08 fix(desktop): stop validating provider keys in launch setup
1927ff217 Merge pull request #38517 from NousResearch/bb/desktop-yolo-statusbar-toggle
63727f32b docs(dashboard): document connecting Hermes Desktop to a remote backend (#38534)
5c0a1fec0 fix(desktop): surface skill & quick-command slash commands in the palette (#38531)
96f0ddc6a fix(docker): bake hindsight-client into the image (#38128) (#38530)
51a2c0701 fix(skills): document xurl X Article ingestion
e223503b0 fix(packaging): modernize project.license to PEP 639 SPDX string (#38353)
6fff74415 Merge pull request #38465 from kshitijk4poor/portal-quick-setup-model
26a57467a fix(cli): harden `hermes portal` SystemExit handling + finish model-pick doc sweep
cd188b814 feat(cli): make `hermes portal` run the full quick-setup Nous flow (model picker)
d4787d3e2 Merge pull request #38449 from kshitijk4poor/portal-login-alias
0caa23788 fix(desktop): prevent IME Enter from splitting messages and viewport resize from disarming scroll anchor (#38333)
9ba7e5b1b fix(setup): point Portal login-failure retry hints at `hermes portal`
da4f407e5 feat(cli): make `hermes portal` the human-readable Portal onboarding alias
39fee4f3b test(installer): cover the post-update relaunch/install target derivation
d3b1e4300 fix(installer): never brick the install when a self-update swap fails
c349eca82 fix(packaging): ship locales/ i18n catalogs in wheel, sdist, and Nix (#38383)
b91c38203 Merge pull request #38393 from NousResearch/bb/desktop-session-fixes
1b89715e1 fix(desktop): guard reconnect sockets and keep branch search precise
93228d529 fix(desktop): persist pins, reconnect after sleep, dedupe session search
b4b9a9384 Merge pull request #38384 from NousResearch/bb/fix-installer-emit-log-logstream
1971b1052 fix(installer): pass LogStream to emit_log calls from #38296
84710995e Merge pull request #38312 from NousResearch/bb/installer-stderr-log-label
963260944 Merge pull request #38296 from NousResearch/bb/fix-dmg-update-relaunch
2d9ea0997 Potential fix for pull request finding
ee8aeea4c Potential fix for pull request finding
3c73d1852 docs: remote desktop connect needs --tui on the backend (#38350)
df848bd2d test(gateway): cover schtasks locale-safe decoding on Windows
973decc05 fix(gateway): decode schtasks output with locale encoding on Windows
966630563 fix(dashboard): clamp PTY resize dimensions for WSL2 winsize garbage (#38200)
810e5864d fix(installer): stop mislabeling stdout-style progress as stderr
ecac659d7 Merge pull request #38306 from NousResearch/bb/desktop-clipboard-image-double-paste
c711146ad fix(desktop): dedupe clipboard image paste
a1cda2410 fix(desktop): self-update rebuilds and relaunches cleanly on macOS
e02a6038a fix(tui): save TUI /save snapshots under Hermes home with system prompt (#38251)
12ea7fc7e Merge pull request #38255 from NousResearch/bb/installer-desktop-build-logging
7fb8a6b5c feat(dashboard): enrich profiles dashboard and de-dupe channel env vars (#37872)
1dca7c620 fix(install): require Node >=20.19/22.12 for the desktop build
214b7e070 fix(install.ps1): handle dirty worktree on Windows update (#38239)
6ee046a72 fix(doctor): detect + repair stale HERMES_MAX_ITERATIONS .env ghost shadowing config.yaml (#38222)
de26b1785 test: stub has_hook in transform_tool_result hook tests
827f25142 perf(observability): gate tool-hook emit on has_hook; slim per-tool footprint
432325933 test: restore unrelated trailing newlines in cwd/tool-search tests
0d9b7132f feat(observability): observer-grade telemetry hooks + NeMo-Relay plugin
a78c73f3a Merge pull request #38224 from NousResearch/hermes/hermes-79601e59
4c544b633 fix(kanban): don't permanently block tasks that hit a provider rate limit (#38223)
60b6352fe Merge pull request #38221 from NousResearch/hermes/hermes-45accc84
e76d8bf5a fix(tui): stop persisting full tool output in trail lines (silent OOM death)
c5d199ead feat(dashboard): check-before-update flow on the System page (#38205)
c930a49ce fix(desktop): honor upward wheel scroll in long threads
3aa24e261 fix(desktop): stop chat scroll backward-jump from content-growth interim scrolls (#37997)
ba57ebec3 fix(nix): bump npmDepsHash for refreshed lockfile
b98b645f8 chore: regenerate lockfile + map vladkvlchk for salvaged #36978
f45d7dee7 fix(desktop): add @testing-library/dom as explicit dev dependency
1b302a047 feat(debug): include desktop.log in hermes debug share / /debug / hermes logs (#38203)
1d90b2398 fix(mcp): banner shows 'disabled' not 'failed' for enabled:false servers (#38204)
ef6529810 docs: make the Desktop App remote-backend section self-contained (#38194)
50ba36dca chore: add bbednarski9 to AUTHOR_MAP for #29722 salvage (#38189)
5fca754ee fix(desktop): pass live backend PID to in-app update so its own dashboard is spared
192020992 fix(cli): exclude desktop-managed backend from stale-dashboard kill
d833b1eff docs: add remote-backend section to the Desktop App page (#38180)
a1264e996 fix(matrix): make bang-command resolution robust + fix dead skill-command branch
0022e94d7 feat(matrix): support bang command aliases
6038bfb66 docs: explain remote-gateway session token for Hermes Desktop (#38144)
047e7cf36 fix(docs): remove remaining stale submodule references missed by #38089 (#38105)
43fd63b4b fix(windows): rip out unused submodule support in installer & docker & docs
64202200a chore: remove committed RELEASE_v*.md changelogs from repo root (#37855)
f019a9c49 Merge pull request #37975 from kshitijk4poor/fix/desktop-session-view-bleed
46ea0a184 Merge pull request #37999 from kshitijk4poor/desktop-slash-nav-dom-regression-test
49f1b9e4b fix(desktop): stop Esc reopening the slash/@ menu; harden keyup guard
c77c470d2 test(desktop): real-DOM regression for slash/@ menu keyboard nav
e114b31ed test(dashboard): direct unit coverage for internal WS credential + docstring fix
fd1ec8033 fix(dashboard): authenticate server-spawned PTY child WS with a process-internal credential
28f1590b7 fix(desktop): stop background session messages bleeding into the active transcript
ada04573a Merge pull request #37948 from kshitijk4poor/fix/desktop-stop-button-interrupt
a23728dfc fix(desktop): make Stop button actually interrupt when a turn is queued
9b43ab8de Merge pull request #37937 from kshitijk4poor/fix/desktop-slash-menu-keyup-nav
188e52db9 fix(desktop): keep slash/@ completion menu navigable and Esc-dismissable
5005b79bc Merge pull request #37932 from NousResearch/bb/desktop-remote-flicker
d0ea4caf7 fix(desktop): don't treat WSLg as a remote display
6a2909fe5 fix(desktop): disable GPU acceleration on remote displays to stop flicker
9272e4019 fix(docker): point TUI launcher at prebuilt bundle via HERMES_TUI_DIR (#37923)
feb50eee7 Merge pull request #37908 from NousResearch/bb/desktop-concurrent-session-loss
e0a999aa8 fix(desktop): label in-flight new chats with the first message
55a76ec66 fix(desktop): keep in-flight new chats from vanishing on refresh
d9f7e7ac8 fix(docker): seed gateway_state.json from HERMES_GATEWAY_BOOTSTRAP_STATE on first boot (#37896)
e618cbee4 feat(desktop): custom zoom shortcuts at half default step
2f0ee6646 Merge pull request #37877 from NousResearch/bb/desktop-sticky-msg-clamp
cbc1d901b chore: uptick
84eb5f1f8 fix(desktop): restore sticky human clamp transition at 0.75s
e5472da58 fix(desktop): drop sticky human clamp max-height transition
3ab783a7b chore: uptick
06aa140fa fix(desktop): inset sticky human messages with --sticky-human-top
dd28f2ac9 fix(dashboard): trust non-web WS origins on OAuth-gated binds after ticket auth (#37870)
9bdf01852 feat(desktop): clamp sticky human messages to ~2 lines until hover/focus
a92cbcac4 Merge pull request #37866 from NousResearch/bb/desktop-scroll-anchor
e67ab2e04 fix(desktop): stop chat scroll jumping by disabling native scroll anchoring
b6da66c5b Merge pull request #37786 from NousResearch/bb/tui-rightclick-and-boundaries
dfba3f3e5 fix(tui): clear selection on right-click copy + group transcript blocks
b28dd3417 fix(setup): default browser/TTS picker to free local backend, not paid Nous (#37800)
918aef267 Merge pull request #37782 from NousResearch/bb/configurable-default-interface
d6b0c23f8 feat(cli): configurable default interface (cli vs tui)
```

## Expected Conflict Set

The dry merge reports two content conflicts:

- `agent/conversation_loop.py`
- `tests/test_hermes_constants.py`

Several important files auto-merge but still need review because both local and upstream histories touched adjacent behavior:

- `AGENTS.md`
- `agent/chat_completion_helpers.py`
- `agent/prompt_builder.py`
- `agent/transports/chat_completions.py`
- `apps/desktop/electron/main.cjs`
- `gateway/run.py`
- `hermes_cli/config.py`
- `hermes_cli/web_server.py`
- `hermes_constants.py`
- `run_agent.py`
- `tests/agent/transports/test_chat_completions.py`
- `tools/delegate_tool.py`
- `tools/skills_tool.py`
- `web/src/pages/SystemPage.tsx`
- `website/docs/reference/environment-variables.md`

## Local Changes to Preserve

Local-only commits include behavior that should not be lost during the merge:

- Signal group mention gating and inline-reply bypass:
  - `gateway/platforms/signal.py`
  - `gateway/config.py`
  - `hermes_cli/config.py`
  - `tests/gateway/test_signal.py`
  - `tests/gateway/test_config.py`
- Gateway status/version reporting:
  - `gateway/run.py`
  - `tests/gateway/test_status_command.py`
- Discord channel report:
  - `plugins/platforms/discord/adapter.py`
  - `tests/gateway/test_discord_channel_report.py`
- Strict provider payload sanitization:
  - `agent/transports/chat_completions.py`
  - `tests/agent/transports/test_chat_completions.py`
- Anthropic OAuth/tool-name safety and prompt media wording:
  - `agent/anthropic_adapter.py`
  - `agent/prompt_builder.py`
  - `tests/agent/test_anthropic_adapter.py`
- Primary skills directory and symlink-aware skill lookup:
  - `tools/skill_manager_tool.py`
  - `tools/skills_tool.py`
  - `hermes_cli/config.py`
- Desktop/dashboard admin work:
  - `hermes_cli/web_server.py`
  - `web/src/pages/SystemPage.tsx`
  - dashboard/session/skills/cron related tests
- Computer-use backend changes:
  - `tools/computer_use/backend.py`
  - `tools/computer_use/schema.py`
  - `tools/computer_use/tool.py`

## Merge Strategy

- [ ] Create a review branch before touching `main`.
  ```bash
  git switch -c merge-upstream-main-20260603
  ```

- [ ] Confirm no uncommitted user work is present.
  ```bash
  git status --short --branch
  ```

- [ ] Refresh upstream and confirm divergence.
  ```bash
  git fetch upstream
  git rev-list --left-right --count HEAD...upstream/main
  ```

- [ ] Start the merge without committing automatically.
  ```bash
  git merge --no-commit --no-ff upstream/main
  ```

- [ ] Resolve `agent/conversation_loop.py`.
  - Preserve upstream loop fixes and any new helper factoring.
  - Preserve local strict-provider/Anthropic safety behavior where the conflict overlaps transport or reasoning/tool payload handling.
  - Check call sites in `run_agent.py`, `agent/tool_executor.py`, and `agent/transports/chat_completions.py` after resolution.

- [ ] Resolve `tests/test_hermes_constants.py`.
  - Upstream changed Windows-native Hermes home behavior.
  - Preserve local expectations only if they still match `hermes_constants.py`.
  - Add or adjust assertions for profile-aware paths if local changes still require them.

- [ ] Review high-risk auto-merged files before staging.
  ```bash
  git diff --check
  git diff --name-only --diff-filter=U
  git diff -- gateway/run.py gateway/config.py gateway/platforms/signal.py hermes_cli/config.py hermes_constants.py
  git diff -- agent/transports/chat_completions.py agent/prompt_builder.py run_agent.py agent/conversation_loop.py
  git diff -- hermes_cli/web_server.py web/src/pages/SystemPage.tsx
  ```

- [ ] Decide intentionally on upstream deletions.
  - Upstream removes root `RELEASE_v*.md` files and adds `RELEASE_v*.md` to `.gitignore`; accept upstream deletion unless there is an unpublished local release note requirement.
  - Upstream removes stale submodule references; accept upstream docs/install changes.
  - Upstream may remove or rewrite local gateway/status tests if files were deleted upstream; reintroduce focused tests only for local behaviors still meant to ship.

## Validation Plan

Run focused tests first, then broader suites only after conflicts and high-risk auto-merges are reviewed.

- [ ] Core merge sanity:
  ```bash
  git status --short
  git diff --check
  ```

- [ ] Constants/profile behavior:
  ```bash
  scripts/run_tests.sh tests/test_hermes_constants.py tests/hermes_cli/test_config.py
  ```

- [ ] Provider payload and prompt safety:
  ```bash
  scripts/run_tests.sh tests/agent/transports/test_chat_completions.py tests/agent/test_anthropic_adapter.py tests/agent/test_anthropic_mcp_prefix_strip.py tests/agent/test_prompt_builder.py
  ```

- [ ] Conversation loop and tool execution:
  ```bash
  scripts/run_tests.sh tests/run_agent/test_run_agent.py tests/test_model_tools.py tests/test_transform_tool_result_hook.py
  ```

- [ ] Gateway behavior that local commits added:
  ```bash
  scripts/run_tests.sh tests/gateway/test_signal.py tests/gateway/test_config.py tests/gateway/test_status_command.py tests/gateway/test_discord_channel_report.py tests/gateway/test_matrix.py
  ```

- [ ] Dashboard/web server areas:
  ```bash
  scripts/run_tests.sh tests/hermes_cli/test_web_server.py tests/hermes_cli/test_dashboard_admin_endpoints.py tests/hermes_cli/test_debug.py
  ```

- [ ] Desktop/TUI impacted upstream areas if Node dependencies are available:
  ```bash
  npm test -- apps/desktop/src
  cd ui-tui && npm test
  ```

- [ ] Full suite smoke once focused tests pass:
  ```bash
  scripts/run_tests.sh
  ```

## Commit and Push

- [ ] Stage the resolved merge.
  ```bash
  git add .
  git status --short
  ```

- [ ] Commit with the default merge message unless a more specific message is needed.
  ```bash
  git commit
  ```

- [ ] Push to the fork branch for review first.
  ```bash
  git push origin merge-upstream-main-20260603
  ```

- [ ] Only fast-forward or merge into local `main` after focused validation is clean.

