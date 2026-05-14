# Plan: Resolve Remaining `computer_use` Test Sweep Issues

## Source Context

This plan is based on the test sweep in `~/.hermes/plans/computer-use-test-sweep-2026-05-12.md` and the current Hermes implementation in `tools/computer_use/`.

Remaining issues from the sweep:

| Issue | Current status | User-visible problem |
|---|---:|---|
| `click` | FAIL | `AXPress failed with code -25206`; can drift to the wrong app/window |
| `right_click` | FAIL | `AXShowMenu failed with code -25206`; same app/window drift |
| `focus_app(raise_window=true)` | PARTIAL | Routes input, but reports “without raising window” and does not raise the target window |
| `middle_click` | UNSUPPORTED | Advertised by Hermes schema, but cua-driver backend cannot perform it |
| `drag` by element | UNSUPPORTED | Hermes cannot resolve element centers/bounds because cua-driver output parsed by Hermes does not expose bounds |

## Goals

- Make `computer_use` honest: do not advertise or return successful results for actions the backend cannot actually perform.
- Make window/app targeting deterministic across `capture`, `focus_app`, `click`, `right_click`, `drag`, `scroll`, `type`, `key`, and `set_value`.
- Make element-indexed pointer actions reliable when cua-driver can perform them.
- Add coordinate fallback paths when semantic AX actions fail and element bounds are available.
- Preserve the working actions from the sweep: `list_apps`, `capture`, `type`, `key`, `scroll`, `double_click`, `set_value`, `wait`, and coordinate `drag`.
- Include enough telemetry/logging to debug future backend failures without re-running an ad-hoc manual sweep.

## Non-goals

- Do not reintroduce the direct `cua-driver mcp` over SSH path. The working route remains `HERMES_CUA_DRIVER_CMD=/usr/local/bin/cua-remote`.
- Do not make all actions frontmost by default. Background operation remains the default. Raising windows is allowed only when the caller explicitly passes `raise_window=true`.
- Do not depend on model-specific Anthropic `computer_20251124` APIs. The tool remains a generic OpenAI-style function schema.

## Relevant Code References

### Hermes repo: `/home/shuv/repos/hermes-agent`

- `tools/computer_use/tool.py`
  - `handle_computer_use()` dispatch entry point.
  - `_dispatch()` maps public actions to backend methods.
  - `_capture_response()` formats SOM/vision/AX responses.
  - `_format_elements()` currently shows `bounds`, but the cua backend often fills them as `(0, 0, 0, 0)`.
  - `check_computer_use_requirements()` contains the Linux remote-shim escape hatch.
- `tools/computer_use/cua_backend.py`
  - `CuaDriverBackend.capture()` selects `pid/window_id`, calls `list_windows`, `get_window_state`, and `screenshot`.
  - `CuaDriverBackend.click()` maps `click`, `double_click`, `right_click`, and `middle_click` to cua-driver calls.
  - `CuaDriverBackend.drag()` explicitly rejects element-indexed drag.
  - `CuaDriverBackend.focus_app()` currently ignores `raise_window=true` by design.
  - `_parse_elements_from_tree()` currently parses only index/role/label, not actions or bounds.
- `tools/computer_use/backend.py`
  - `UIElement`, `CaptureResult`, and `ActionResult` data contracts.
- `tools/computer_use/schema.py`
  - Public tool schema currently advertises `middle_click`, element `drag`, and `raise_window=true` behavior that the backend does not fully satisfy.
- `tests/tools/test_computer_use.py`
  - Existing schema/dispatch/multimodal tests.
  - Add targeted unit tests for deterministic window targeting, unsupported action behavior, AX fallback behavior, and element metadata parsing.
- `tests/hermes_cli/test_install_cua_driver.py`
  - Existing install/upgrade tests; likely unchanged unless version-pinning behavior changes.
- `agent/prompt_builder.py`
  - `COMPUTER_USE_GUIDANCE` should be updated if the recommended workflow changes away from “click by element index” as universally preferred.
- `agent/context_compressor.py`, `agent/model_metadata.py`, `agent/anthropic_adapter.py`, `run_agent.py`
  - Multimodal image handling paths are already tested; only touch if response shape changes.

### Operational files outside the repo

- `/usr/local/bin/cua-remote`
  - Remote stdio MCP shim. If new backend-only pseudo-tools are needed temporarily, this is the operational insertion point, but prefer upstream cua-driver support when possible.
- `~/.hermes/plans/remote-macos-computer-use.md`
  - Current architecture and operational runbook.
- `~/.hermes/plans/computer-use-test-sweep-2026-05-12.md`
  - Source sweep and expected before/after comparison.

### External references

- Cua upstream repository: `https://github.com/trycua/cua`
- Cua-driver installer referenced by Hermes: `https://raw.githubusercontent.com/trycua/cua/main/libs/cua-driver/scripts/install.sh`
- Local cua-driver MCP docs source of truth during validation:
  ```bash
  ssh shuvbot '/Applications/CuaDriver.app/Contents/MacOS/cua-driver dump-docs'
  ```

## Current Technical Findings

### cua-driver action semantics

The installed cua-driver docs describe these important constraints:

- `get_window_state(pid, window_id)` must run before element-indexed actions for the same `(pid, window_id)`.
- Element-indexed `click` defaults to AX `press`; unsupported AX actions fail with errors such as `AXPress failed with code -25206`.
- Element-indexed `right_click` uses `AXShowMenu`; unsupported elements fail similarly.
- Pixel `click`, `double_click`, `right_click`, and coordinate `drag` operate in **window-local screenshot pixels**, not global screen coordinates.
- `drag` is pixel-only in cua-driver. Element drag requires the caller to know element bounds and convert to coordinates.
- `list_windows` returns `bounds`, `pid`, `window_id`, `app_name`, `title`, `z_index`, `is_on_screen`, and current-space metadata in `structuredContent.windows`.
- Current `get_window_state` output observed on shuvbot includes `structuredContent.tree_markdown`, screenshot dimensions, screenshot scale factor, app metadata, and text content, but does **not** currently expose a structured `elements[]` list with bounds.

### Likely root causes

1. **Silent app fallback in `capture(app=...)`**
   - Current behavior filters windows by app, but if no match is found it silently falls back to the frontmost window.
   - This can make actions hit the wrong app while appearing to satisfy the app filter.

2. **Insufficient target diagnostics**
   - Action responses do not consistently include the selected `app`, `pid`, `window_id`, targeting mode, or original cua-driver error code.
   - Failures are hard to distinguish: stale cache, unsupported AX action, app mismatch, wrong coordinate space, or no active capture.

3. **Element metadata is under-modeled**
   - `UIElement` has `bounds` and `attributes`, but `_parse_elements_from_tree()` only populates index/role/label.
   - It does not parse `actions=[...]`, `DISABLED`, element ids, or ancestor context.
   - Without bounds, Hermes cannot implement element drag or pixel fallback from failed AX actions.

4. **Schema over-promises backend support**
   - `middle_click` is in the public action enum, but the cua backend explicitly returns unsupported.
   - `raise_window=true` says it brings a window forward, but `focus_app()` intentionally ignores it.
   - `from_element`/`to_element` are advertised for `drag`, but element bounds are not available.

5. **AX action choice is too generic**
   - Single `click(element=N)` always goes through cua-driver `click` default action (`press`).
   - Many elements expose `AXOpen`, `AXShowDefaultUI`, or `AXShowMenu`, not `AXPress`.
   - `right_click(element=N)` always expects `AXShowMenu`, which is not valid on many rows/cells/buttons.

## Desired End State

After implementation and validation:

| Action | Expected result |
|---|---|
| `click` by valid element with supported AX action | PASS, uses semantic AX action |
| `click` by element without `AXPress` but with usable bounds | PASS, falls back to pixel click at element center |
| `click` by coordinate | PASS, uses window-local screenshot coordinates and the active target window |
| `right_click` by valid menu-capable element | PASS, uses `AXShowMenu` |
| `right_click` by element without `AXShowMenu` but with usable bounds | PASS or clear backend-limited failure depending on target surface |
| `focus_app(raise_window=false)` | PASS, targets app/window without raising |
| `focus_app(raise_window=true)` | PASS if raise support is implemented; otherwise explicit unsupported error and schema/docs updated |
| `middle_click` | Either PASS via real backend support or removed from schema and reported as unsupported before approval |
| `drag` by element | PASS if bounds become available; otherwise removed/de-emphasized from schema and guidance |
| `capture(app=missing)` | FAIL clearly; never silently falls back to another app |

## Implementation Plan

### Milestone 1 — Add deterministic target state and diagnostics

- [x] Add a small internal target-state object in `tools/computer_use/cua_backend.py`, for example:
  ```python
  @dataclass
  class ActiveWindowTarget:
      app_name: str
      bundle_id: str
      pid: int
      window_id: int
      title: str = ""
      bounds: tuple[int, int, int, int] = (0, 0, 0, 0)
      screenshot_width: int = 0
      screenshot_height: int = 0
      screenshot_scale_factor: float = 1.0
      selected_by: str = ""
  ```
- [x] Replace separate `_active_pid` / `_active_window_id` state with `_active_target`, while keeping compatibility properties or helper accessors if needed.
- [x] Add helper methods in `CuaDriverBackend`:
  - [x] `_list_windows(on_screen_only: bool = True, pid: int | None = None) -> list[dict]`
  - [x] `_select_window(app: str | None, *, require_match: bool, on_screen_only: bool = True) -> ActiveWindowTarget | None`
  - [x] `_target_meta(extra: dict | None = None) -> dict`
- [x] Ensure `capture(app=...)` with an unmatched `app` returns a clear failure/empty capture with message, rather than silently selecting the frontmost window.
- [x] Ensure `focus_app(app=...)` also requires a real match when `app` is provided.
- [x] Verify cua-driver `z_index` sort semantics against observed output and docs before changing sort order.
  - Current code sorts ascending with a comment saying lowest is frontmost.
  - Installed docs say higher `z_index` is closer to front.
  - [x] Add a unit test that locks in the chosen behavior with sample windows.
- [x] Add structured debug logging around every backend action:
  - action name
  - target app/title/pid/window_id
  - addressing mode: `element`, `coordinate`, `element_to_coordinate_fallback`, `keyboard`, etc.
  - cua-driver tool name
  - raw args excluding secrets
  - result ok/error and parsed error code if available
- [x] Populate `ActionResult.meta` for all pointer/focus/value actions with target metadata and raw backend result metadata.

Validation:

```bash
cd /home/shuv/repos/hermes-agent
source .venv/bin/activate 2>/dev/null || source venv/bin/activate
python -m pytest tests/tools/test_computer_use.py -q
```

Manual check:

```bash
hermes -z "Use computer_use to capture app='DefinitelyMissingApp'. Report the exact error." -t computer_use --yolo
```

Expected: clear no-match error; no fallback to Finder/Safari/etc.

### Milestone 2 — Parse richer element metadata from `get_window_state`

- [x] Extend `UIElement.attributes` usage in `tools/computer_use/backend.py` without changing the public dataclass fields unless necessary.
- [x] Replace `_ELEMENT_LINE_RE` / `_parse_elements_from_tree()` with a parser that captures:
  - [x] index
  - [x] role
  - [x] quoted label/title/value snippet
  - [x] disabled state
  - [x] `id=...`
  - [x] `actions=[AXPress, AXShowMenu, AXOpen, AXRaise, ...]`
  - [x] ancestor label/path where cheap to compute
- [x] Store parsed actions in `UIElement.attributes["actions"]` as a list of strings.
- [x] Store disabled state in `UIElement.attributes["disabled"]`.
- [x] Add `CuaDriverBackend._last_elements_by_index: dict[int, UIElement]`, scoped to the current active `(pid, window_id)`.
- [x] In `capture(mode="som"|"ax")`, populate `_last_elements_by_index` from the parsed tree.
- [x] In `capture(mode="vision")`, clear or mark the element cache unavailable because installed cua-driver skips AX tree walking in vision mode.
- [x] Preserve screenshot metadata from `structuredContent`:
  - [x] `screenshot_width`
  - [x] `screenshot_height`
  - [x] `screenshot_original_width`
  - [x] `screenshot_original_height`
  - [x] `screenshot_scale_factor`
  - [x] `screenshot_file_path` if used
- [x] If upstream cua-driver exposes structured elements with bounds in a newer version, prefer that over markdown parsing.

Validation:

- [x] Add tests in `tests/tools/test_computer_use.py` using a representative tree line such as:
  ```text
  - [2] AXOutline (sidebar) id=_NS:8 actions=[AXShowMenu]
  - [4] AXCell actions=[AXOpen]
  - [14] AXButton DISABLED
  ```
- [x] Assert parsed attributes include actions, id, and disabled state.
- [x] Assert capture stores last elements by index for the active target.

### Milestone 3 — Make click/right-click action-aware and prevent wrong-window actions

- [x] Add a helper in `CuaDriverBackend`:
  ```python
  def _resolve_element(self, index: int) -> UIElement | None:
      ...
  ```
  It should only return an element when the active target is still the same `(pid, window_id)` that produced the element cache.
- [x] For element `click`:
  - [x] If the element is disabled, return `ok=false` with a clear message.
  - [x] If `AXPress` is available, call cua-driver `click` with `action="press"`.
  - [x] If `AXOpen` is available and the caller used `double_click`, prefer cua-driver `double_click` or `click(action="open")` according to installed-driver behavior.
  - [x] If only `AXShowDefaultUI` / `AXShowAlternateUI` is available, test whether cua-driver `click(action="open")`, `click(action="confirm")`, or `double_click` is the correct mapping; document the selected mapping in code.
  - [x] If no semantic AX action is appropriate and bounds are available, fall back to coordinate click at the element center.
  - [x] If no semantic action and no bounds, return a clear error telling the caller to use coordinates or recapture.
- [x] For element `right_click`:
  - [x] If `AXShowMenu` is available, call cua-driver `right_click` by element.
  - [x] If `AXShowMenu` is unavailable but bounds are available, call cua-driver `right_click` by center coordinate.
  - [x] If neither is possible, return a clear unsupported message.
- [x] For coordinate `click` / `right_click`:
  - [x] Treat `coordinate` as window-local screenshot pixels, matching cua-driver docs.
  - [x] Include active target metadata in responses so users can detect stale captures.
  - [x] Do not mutate `_active_target` based on frontmost app after the user has already selected a target.
- [x] Parse common cua-driver errors into helpful messages:
  - [x] `AXPress failed with code -25206` → “element does not support AXPress; try double_click/open or coordinate click.”
  - [x] `AXShowMenu failed with code -25206` → “element does not expose AXShowMenu; coordinate right-click fallback may be needed.”
  - [x] stale/missing element cache → “call capture(mode='som' or 'ax') before element-indexed action.”
- [x] Add regression tests using a fake session:
  - [x] `click(element=N)` with `AXPress` passes `action="press"`.
  - [x] `click(element=N)` with no usable action and no bounds returns a clear error.
  - [x] `right_click(element=N)` with `AXShowMenu` calls the `right_click` tool.
  - [x] `right_click(element=N)` without `AXShowMenu` does not call AX if no fallback coordinates exist.
  - [x] `capture(app=missing)` does not allow subsequent element click against a stale prior target.

Manual validation:

```bash
hermes -z "Use computer_use: capture Finder in som mode, click a safe sidebar element, then capture_after=true. Report target app/pid/window." -t computer_use --yolo
hermes -z "Use computer_use: capture Finder in som mode, right_click a safe element that exposes AXShowMenu. Report whether a menu appeared." -t computer_use --yolo
```

### Milestone 4 — Resolve `focus_app(raise_window=true)` honestly

Choose one of the following approaches after checking installed cua-driver capabilities and upstream feasibility.

#### Preferred approach: add/use upstream cua-driver raise support

- [x] Check whether a newer cua-driver release exposes a window activation/raise tool. *(Inspected `cua-driver dump-docs` on shuvbot; no raise primitive in v0.1.6.)*
- [ ] If not, open or implement an upstream change in `https://github.com/trycua/cua` to expose one of:
  - `raise_window(pid, window_id)` using `AXRaise` on the target `AXWindow`.
  - `activate_app(pid|bundle_id|app_name)` for explicit foreground activation.
- [ ] Update `CuaDriverBackend.focus_app(app, raise_window=True)` to:
  - [ ] select a deterministic target window,
  - [ ] call the raise/activate tool,
  - [ ] verify via `list_windows` that target app/window is now frontmost/on-screen,
  - [ ] return `ok=true` only when verification succeeds.

_Deferred: took the interim approach below for this cycle._

#### Interim approach: explicit unsupported instead of silent ignore

- [x] If upstream support is not available in this implementation cycle, change `focus_app(..., raise_window=True)` to return `ok=false` with a message like:
  ```text
  raise_window=true is not supported by the current cua-driver backend; input was not raised. Use raise_window=false or update cua-driver once raise_window support lands.
  ```
- [x] Update `tools/computer_use/schema.py` to state that `raise_window=true` is backend-dependent and may fail.
- [x] Update `agent/prompt_builder.py::COMPUTER_USE_GUIDANCE` to discourage raise unless explicitly requested.
- [x] Add tests that `raise_window=True` is not reported as success when no backend raise primitive exists.

Validation:

```bash
hermes -z "Use computer_use to focus Finder with raise_window=true, then list windows and say whether Finder was actually raised." -t computer_use --yolo
```

Expected: either a real raised Finder window with verified metadata, or an explicit unsupported error. No “success without raising.”

### Milestone 5 — Resolve `middle_click` by support or de-advertising

- [x] Inspect current cua-driver docs for a middle-button click primitive.
  - Current installed docs show `drag(button='middle')`, but pixel `click` does not expose a `button` field.
- [x] If cua-driver gains middle-button click support:
  - [x] Route `middle_click` through that backend primitive.
  - [x] Add unit tests and manual smoke tests.
- [x] If cua-driver does not support it:
  - [x] Remove `middle_click` from `COMPUTER_USE_SCHEMA["parameters"]["properties"]["action"]["enum"]` for the cua backend, or keep it only if Hermes supports backend-specific schema shaping.
  - [x] Remove `"middle"` from the public `button` enum unless another code path supports it.
  - [x] Keep a defensive handler that returns a clear unsupported error if old prompts/models call it anyway.
  - [x] Update `tests/tools/test_computer_use.py::TestSchema.test_schema_lists_all_expected_actions` to match the new honest schema.
  - [x] Update prompt guidance to avoid middle-click.

Validation:

```bash
python -m pytest tests/tools/test_computer_use.py -q
hermes -z "Call computer_use middle_click defensively and report the exact result." -t computer_use --yolo
```

Expected: either a working middle click or an explicit unsupported error that is no longer advertised as a normal action.

### Milestone 6 — Resolve element-based drag

Element drag has two possible outcomes: implement it if bounds become available, or remove/de-emphasize it if the backend cannot supply bounds.

#### Preferred implementation: structured element bounds

- [x] Determine whether current or newer cua-driver can expose element bounds in `get_window_state` structured content. *(Inspected structuredContent on shuvbot; no per-element bounds in v0.1.6.)*
- [ ] If not available, open or implement an upstream change in `https://github.com/trycua/cua`:
  - Add `structuredContent.elements[]` with at least:
    ```json
    {
      "index": 4,
      "role": "AXCell",
      "label": "Applications",
      "bounds": {"x": 10, "y": 20, "width": 200, "height": 24},
      "actions": ["AXOpen"],
      "disabled": false
    }
    ```
  - Bounds must be in the same window-local screenshot coordinate space expected by cua-driver pixel actions.
- [ ] Update Hermes parsing to populate `UIElement.bounds` from structured content.
- [ ] Implement `drag(from_element=..., to_element=...)` by:
  - [ ] resolving both elements from the active element cache,
  - [ ] validating both have non-zero bounds,
  - [ ] converting each to `UIElement.center()`,
  - [ ] calling cua-driver `drag` with `from_x/from_y/to_x/to_y`, `pid`, and `window_id`,
  - [ ] returning meta showing both source/target elements and computed coordinates.
- [ ] Support mixed drag endpoints if useful:
  - [ ] `from_element` + `to_coordinate`
  - [ ] `from_coordinate` + `to_element`

_Deferred: took the interim approach below for this cycle._

#### Interim approach: honest unsupported behavior

- [x] If bounds cannot be obtained now, update schema descriptions to say element drag is unavailable for the cua backend until element bounds are exposed.
- [x] Consider removing `from_element` / `to_element` from the public schema if backend-specific schema shaping is practical.
- [x] Keep defensive errors precise: “element drag requires element bounds; current cua-driver get_window_state did not provide bounds.”

Validation:

```bash
python -m pytest tests/tools/test_computer_use.py -q
hermes -z "Use computer_use to capture Finder in som mode and attempt a safe element-to-element drag only if bounds are available. Report whether bounds were available and what happened." -t computer_use --yolo
```

Expected: working element drag when bounds are available, otherwise an honest unsupported response that is not presented as a backend failure.

### Milestone 7 — Update schema and model guidance

- [x] Reconcile `tools/computer_use/schema.py` with actual backend behavior after Milestones 4–6.
- [x] Make the schema descriptions precise about coordinate spaces:
  - [x] Coordinates are window-local screenshot pixels for cua-driver actions.
  - [x] Element actions require a prior `capture(mode='som'|'ax')` for the same target window.
  - [x] `capture(mode='vision')` does not populate element-index cache.
- [x] Update `agent/prompt_builder.py::COMPUTER_USE_GUIDANCE`:
  - [x] Prefer `capture(app=...)` or `focus_app(app=...)` first.
  - [x] Prefer `type`, `key`, `scroll`, `set_value`, and coordinate `drag` where known reliable.
  - [x] For `click`, advise checking element action support and using coordinates when semantic click fails.
  - [x] State that `raise_window=true` is disruptive and only for explicit foregrounding.
- [x] Update relevant documentation/runbooks:
  - [x] `~/.hermes/plans/remote-macos-computer-use.md`
  - [x] `~/.hermes/plans/computer-use-test-sweep-2026-05-12.md` or a follow-up sweep file with before/after results.

Validation:

- [x] Unit tests for schema enum/description changes.
- [x] Manual prompt-based smoke test with a generic non-Anthropic model to ensure guidance remains model-agnostic.

### Milestone 8 — End-to-end regression sweep

- [x] Re-run the full action sweep against shuvbot Mac Mini.
- [x] Capture results in a new file:
  - `~/.hermes/plans/computer-use-test-sweep-2026-05-12-followup.md`, or dated successor if performed later.
- [x] Include at least these cases:
  - [x] `list_apps`
  - [x] `capture(mode='vision')`
  - [x] `capture(mode='som')`
  - [x] `capture(mode='ax')`
  - [x] `capture(app='Finder')`
  - [x] `capture(app='DefinitelyMissingApp')`
  - [x] `focus_app(raise_window=false)`
  - [x] `focus_app(raise_window=true)`
  - [x] `type`
  - [x] `key`
  - [x] `scroll`
  - [x] `double_click`
  - [x] `set_value`
  - [x] `click(element=...)`
  - [x] `click(coordinate=...)`
  - [x] `right_click(element=...)`
  - [x] `right_click(coordinate=...)`
  - [x] `middle_click` or unsupported defensive call
  - [x] `drag(from_coordinate, to_coordinate)`
  - [x] `drag(from_element, to_element)` or unsupported defensive call
- [x] Every row should be either `PASS` or `EXPECTED_UNSUPPORTED` with schema/guidance aligned. No row should be `FAIL` due to drift, silent fallback, or false success.

## Testing Strategy

### Unit tests

Run targeted tests frequently:

```bash
cd /home/shuv/repos/hermes-agent
source .venv/bin/activate 2>/dev/null || source venv/bin/activate
python -m pytest tests/tools/test_computer_use.py -q
```

Add tests for:

- [x] app filter no-match behavior
- [x] z-index sorting helper
- [x] element parser actions/id/disabled parsing
- [x] capture target metadata storage
- [x] stale target cache rejection
- [x] click action mapping
- [x] right-click action mapping
- [x] unsupported `raise_window=true` behavior when no backend primitive exists
- [x] honest `middle_click` schema/defensive handler behavior
- [x] element drag with mocked non-zero bounds
- [x] element drag without bounds returns a precise unsupported error

### Integration tests / smoke tests

Use the existing remote path:

```bash
export HERMES_CUA_DRIVER_CMD=/usr/local/bin/cua-remote
hermes tools list | grep computer_use
ssh shuvbot '/Applications/CuaDriver.app/Contents/MacOS/cua-driver status'
ssh shuvbot '/Applications/CuaDriver.app/Contents/MacOS/cua-driver call check_permissions'
```

Smoke prompts:

```bash
hermes -z "Use computer_use to list apps. Report the first 5 app names and count." -t computer_use --yolo
hermes -z "Use computer_use to capture Finder in som mode. Report target app, pid, window_id, and first 5 elements with actions." -t computer_use --yolo
hermes -z "Use computer_use to click a safe Finder sidebar element, with capture_after=true. Report ok/message/meta." -t computer_use --yolo
hermes -z "Use computer_use to right-click a safe Finder element that exposes AXShowMenu. Report ok/message/meta." -t computer_use --yolo
```

### Full regression command

If a scripted harness exists for the original sweep, re-run it. If not, create a small manual checklist runner or documented prompt sequence and save the output in `~/.hermes/plans/`.

## Telemetry / Observability Requirements

Telemetry is part of definition-of-done for this fix.

- [x] Structured logs for each backend operation with:
  - action
  - target app/title/pid/window_id
  - backend tool called
  - addressing mode
  - latency in milliseconds
  - ok/error
  - parsed error class/code when available
- [x] Add action metadata to `ActionResult.meta` so tool responses can be inspected without reading logs.
- [x] Avoid logging typed text in full. For `type`, log only length and a short redacted preview when safe.
- [x] If Hermes observability hooks already wrap tools elsewhere, do not duplicate spans; add computer-use-specific fields where they are useful.
- [x] Validate logs locally by tailing Hermes logs during one action sweep.

## Risk Assessment

| Risk | Mitigation |
|---|---|
| Changing schema can affect existing prompts/models | Keep defensive handlers for removed/deprecated actions and update tests/guidance |
| Pixel fallback may click an unintended target if coordinate space is wrong | Use only window-local screenshot coordinates, include debug metadata, and optionally support cua-driver `debug_image_out` during manual validation |
| Upstream cua-driver may not expose bounds/raise APIs yet | Treat as backend limitation; make Hermes honest rather than pretending support exists |
| Re-sorting `z_index` could alter target selection | Validate against installed docs and live windows; add helper tests with explicit samples |
| Extra capture before click may change element indices on dynamic UIs | Prefer cached target validation; only re-snapshot when required, and fail clearly if element identity changes |
| Raising windows is disruptive | Require explicit `raise_window=true`, never raise on default focus/capture paths |

## Definition of Done

- [x] `python -m pytest tests/tools/test_computer_use.py -q` passes.
- [x] No current working action from the 2026-05-12 sweep regresses.
- [x] `capture(app=missing)` never silently falls back to another app.
- [x] `click` and `right_click` no longer fail due to wrong-app/window drift.
- [x] `AXPress -25206` and `AXShowMenu -25206` produce actionable messages or fallback behavior.
- [x] `raise_window=true` either works and is verified, or returns explicit unsupported and schema/docs no longer promise success.
- [x] `middle_click` either works or is removed/de-emphasized from schema with a defensive unsupported handler.
- [x] Element drag either works using real bounds or is documented/schema-aligned as unavailable until cua-driver exposes bounds.
- [x] A follow-up sweep document shows every action as `PASS` or `EXPECTED_UNSUPPORTED`, with no ambiguous `FAIL` rows.
