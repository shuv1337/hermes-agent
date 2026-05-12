"""Cua-driver backend (macOS only).

Speaks MCP over stdio to `cua-driver`. The Python `mcp` SDK is async, so we
run a dedicated asyncio event loop on a background thread and marshal sync
calls through it.

Install: `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/trycua/cua/main/libs/cua-driver/scripts/install.sh)"`

After install, `cua-driver` is on $PATH and supports `cua-driver mcp` (stdio
transport) which is what we invoke.

The private SkyLight SPIs cua-driver uses (SLEventPostToPid, SLPSPostEvent-
RecordTo, _AXObserverAddNotificationAndCheckRemote) are not Apple-public and
can break on OS updates. Pin the installed version via `HERMES_CUA_DRIVER_
VERSION` if you want reproducibility across an OS bump.

Targeting model
---------------

Once a capture or focus_app selects a window, that selection is sticky and
recorded in `_active_target`. Subsequent pointer/keyboard/value actions
operate against that exact (pid, window_id). We never silently fall back to
the frontmost window — if the user filters by `app=` and there is no match,
the action fails with a clear error.

Element actions are scoped per (pid, window_id) by cua-driver. We mirror
that scoping locally in `_last_elements_by_index`, populated from the AX
tree returned by `get_window_state`. An element index is only usable if
the active target still matches the (pid, window_id) that produced it.
"""

from __future__ import annotations

import asyncio
import base64
import json
import logging
import os
import platform
import re
import shutil
import sys
import threading
import time
from concurrent.futures import Future
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple

from tools.computer_use.backend import (
    ActionResult,
    CaptureResult,
    ComputerUseBackend,
    UIElement,
)

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Version pinning
# ---------------------------------------------------------------------------

PINNED_CUA_DRIVER_VERSION = os.environ.get("HERMES_CUA_DRIVER_VERSION", "0.5.0")

_CUA_DRIVER_CMD = os.environ.get("HERMES_CUA_DRIVER_CMD", "cua-driver")
_CUA_DRIVER_ARGS = ["mcp"]  # stdio MCP transport

# Regex to parse list_windows text output lines:
#   "- AppName (pid 12345) "Title" [window_id: 67890]"
_WINDOW_LINE_RE = re.compile(
    r'^-\s+(.+?)\s+\(pid\s+(\d+)\)\s+.*\[window_id:\s+(\d+)\]',
    re.MULTILINE,
)


# Lines in the AX tree look like one of:
#   - [4] AXCell actions=[AXOpen]
#   - [14] AXButton DISABLED
#   - [2] AXOutline (sidebar) id=_NS:8 actions=[AXShowMenu]
#   - [29] AXButton "Eject" (eject) DISABLED
#   - [N] AXRole "Quoted Label"
#   - [N] AXRole (parenthetical hint) actions=[AXPress]
#
# We capture the index, role, then opportunistically extract:
#   - first quoted label
#   - first (parenthetical) hint
#   - id=...
#   - actions=[...]
#   - presence of " DISABLED"
_ELEMENT_LINE_RE = re.compile(
    r'^\s*-\s+\[(\d+)\]\s+(\w+)(?P<rest>.*)$',
    re.MULTILINE,
)
_QUOTED_LABEL_RE = re.compile(r'"([^"]+)"')
_PARENTHETICAL_HINT_RE = re.compile(r'\(([^)]+)\)')
_ELEMENT_ID_RE = re.compile(r'\bid=([^\s\]]+)')
_ELEMENT_ACTIONS_RE = re.compile(r'\bactions=\[([^\]]+)\]')
_ELEMENT_DISABLED_RE = re.compile(r'\bDISABLED\b')


# Match `error code: -25206` or `code -25206` style error tails so we can
# expose the raw AX error code to callers when cua-driver bubbles one up.
_AX_ERROR_CODE_RE = re.compile(r'code\s*[:=]?\s*(-?\d+)', re.IGNORECASE)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _is_macos() -> bool:
    return sys.platform == "darwin"


def _is_arm_mac() -> bool:
    return _is_macos() and platform.machine() == "arm64"


def cua_driver_binary_available() -> bool:
    """True if `cua-driver` is on $PATH or HERMES_CUA_DRIVER_CMD resolves."""
    return bool(shutil.which(_CUA_DRIVER_CMD))


def cua_driver_install_hint() -> str:
    return (
        "cua-driver is not installed. Install with one of:\n"
        "  hermes computer-use install\n"
        "Or run the upstream installer directly:\n"
        '  /bin/bash -c "$(curl -fsSL '
        'https://raw.githubusercontent.com/trycua/cua/main/libs/cua-driver/scripts/install.sh)"\n'
        "Or run `hermes tools` and enable the Computer Use toolset to install it automatically."
    )


def _parse_windows_from_text(text: str) -> List[Dict[str, Any]]:
    """Parse window records from list_windows text output (legacy fallback)."""
    windows = []
    for m in _WINDOW_LINE_RE.finditer(text):
        windows.append({
            "app_name": m.group(1).strip(),
            "pid": int(m.group(2)),
            "window_id": int(m.group(3)),
            "off_screen": "[off-screen]" in m.group(0),
            "title": "",
            "bounds": {"x": 0, "y": 0, "width": 0, "height": 0},
            "z_index": 0,
            "on_current_space": True,
        })
    return windows


def _normalize_window_dict(w: Dict[str, Any]) -> Dict[str, Any]:
    """Normalize a structuredContent window record from cua-driver."""
    return {
        "app_name": w.get("app_name", "") or "",
        "pid": int(w.get("pid", 0) or 0),
        "window_id": int(w.get("window_id", 0) or 0),
        "title": w.get("title", "") or "",
        "bounds": w.get("bounds") or {"x": 0, "y": 0, "width": 0, "height": 0},
        "z_index": int(w.get("z_index", 0) or 0),
        "is_on_screen": bool(w.get("is_on_screen", True)),
        "on_current_space": bool(w.get("on_current_space", True)),
        "off_screen": not bool(w.get("is_on_screen", True)),
    }


def _sort_windows_frontmost_first(windows: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Return windows sorted so the frontmost is first.

    Per cua-driver docs (list_windows):
        z_index: stacking order on the current Space
                 (higher = closer to front).

    We sort by descending z_index so windows[0] is the frontmost. Older
    callers expected ascending order; that was a bug — see
    PLAN-computer-use-remaining-issues.md M1.
    """
    return sorted(windows, key=lambda w: w.get("z_index", 0), reverse=True)


def _parse_element_actions(raw: str) -> List[str]:
    """Parse 'AXPress, AXShowMenu, AXOpen' → ['AXPress', 'AXShowMenu', 'AXOpen']."""
    return [a.strip() for a in raw.split(",") if a.strip()]


def _parse_elements_from_tree(markdown: str) -> List[UIElement]:
    """Parse UIElement list from get_window_state AX tree markdown.

    Captures index, role, label, parenthetical hint, id, actions, and
    disabled state. Bounds are not present in the tree markdown.
    """
    elements: List[UIElement] = []
    for m in _ELEMENT_LINE_RE.finditer(markdown):
        idx = int(m.group(1))
        role = m.group(2)
        rest = m.group("rest") or ""

        quoted = _QUOTED_LABEL_RE.search(rest)
        label = quoted.group(1) if quoted else ""

        hint_match = _PARENTHETICAL_HINT_RE.search(rest)
        hint = hint_match.group(1) if hint_match else ""

        id_match = _ELEMENT_ID_RE.search(rest)
        elem_id = id_match.group(1) if id_match else ""

        actions_match = _ELEMENT_ACTIONS_RE.search(rest)
        actions = _parse_element_actions(actions_match.group(1)) if actions_match else []

        disabled = bool(_ELEMENT_DISABLED_RE.search(rest))

        attrs: Dict[str, Any] = {}
        if hint:
            attrs["hint"] = hint
        if elem_id:
            attrs["id"] = elem_id
        if actions:
            attrs["actions"] = actions
        if disabled:
            attrs["disabled"] = True

        elements.append(UIElement(
            index=idx,
            role=role,
            label=label,
            bounds=(0, 0, 0, 0),
            attributes=attrs,
        ))
    return elements


def _split_tree_text(full_text: str) -> Tuple[str, str]:
    """Split get_window_state text into (summary_line, tree_markdown)."""
    lines = full_text.split("\n", 1)
    summary = lines[0]
    tree = lines[1] if len(lines) > 1 else ""
    return summary, tree


def _parse_key_combo(keys: str) -> Tuple[Optional[str], List[str]]:
    """Parse a key string like 'cmd+s' into (key, modifiers).

    Returns (key, modifiers) where key is the non-modifier key and modifiers
    is a list of modifier names (cmd, shift, option, ctrl).
    """
    MODIFIER_NAMES = {"cmd", "command", "shift", "option", "alt", "ctrl", "control", "fn"}
    KEY_ALIASES = {"command": "cmd", "alt": "option", "control": "ctrl"}

    parts = [p.strip().lower() for p in re.split(r'[+\-]', keys) if p.strip()]
    modifiers = []
    key = None
    for part in parts:
        normalized = KEY_ALIASES.get(part, part)
        if normalized in MODIFIER_NAMES:
            modifiers.append(normalized)
        else:
            key = part  # last non-modifier wins
    return key, modifiers


def _parse_ax_error_code(message: str) -> Optional[int]:
    """Extract an AX/CG error code (e.g. -25206) from a cua-driver message."""
    if not message:
        return None
    m = _AX_ERROR_CODE_RE.search(message)
    if not m:
        return None
    try:
        return int(m.group(1))
    except ValueError:
        return None


# Selected Carbon / Accessibility error codes that surface from cua-driver.
# Reference: AXError.h, HIServices/AXError.h.
_AX_ERROR_HINTS: Dict[int, str] = {
    -25200: "Generic AX failure.",
    -25201: "Illegal argument passed to the AX action.",
    -25202: "Invalid AXUIElement reference \u2014 element is gone; recapture.",
    -25204: "AX attribute is not supported by this element.",
    -25205: (
        "AX action is not supported by this element. Recapture and use a "
        "different element, or fall back to coordinate click at the "
        "element's screenshot pixel position."
    ),
    -25206: (
        "AX action failed on this element. Common causes: the action is "
        "advertised but not actually performable right now. Try a different "
        "AX action (e.g. double_click for AXOpen), or coordinate click."
    ),
    -25208: "AX notification is unsupported by this element.",
    -25211: "AX API has been disabled \u2014 check Accessibility permissions.",
}


def _explain_ax_error(message: str) -> str:
    """Return an actionable hint for known AX failure modes, or ''."""
    if not message:
        return ""
    code = _parse_ax_error_code(message)
    lower = message.lower()
    if code is not None and code in _AX_ERROR_HINTS:
        hint = _AX_ERROR_HINTS[code]
        # Add action-specific tail if we can tell which AX action failed.
        if "axshowmenu" in lower:
            hint += " (AXShowMenu was the failed action.)"
        elif "axpress" in lower:
            hint += " (AXPress was the failed action.)"
        elif "axopen" in lower:
            hint += " (AXOpen was the failed action.)"
        return hint
    # Legacy substring-based hints for backends that don't surface a code.
    if "axshowmenu failed" in lower:
        return (
            "Element does not expose AXShowMenu reliably. Recapture and use "
            "coordinate right-click, or pick a different element."
        )
    if "axpress failed" in lower:
        return (
            "Element does not support AXPress. Try double_click "
            "(AXOpen targets), set_value (popup/slider), or coordinate "
            "click using the element's screenshot pixel position."
        )
    return ""


# ---------------------------------------------------------------------------
# Active target state
# ---------------------------------------------------------------------------

@dataclass
class ActiveWindowTarget:
    """Sticky target for subsequent actions after capture()/focus_app()."""

    app_name: str = ""
    bundle_id: str = ""
    pid: int = 0
    window_id: int = 0
    title: str = ""
    bounds: Tuple[int, int, int, int] = (0, 0, 0, 0)
    screenshot_width: int = 0
    screenshot_height: int = 0
    screenshot_scale_factor: float = 1.0
    selected_by: str = ""          # "capture(app=...)", "focus_app(app=...)", ...
    captured_mode: str = ""        # "som" | "vision" | "ax" — last capture mode
    elements_turn: int = 0         # cua-driver turn_id for elements cache invalidation

    def as_meta(self) -> Dict[str, Any]:
        return {
            "app": self.app_name,
            "pid": self.pid,
            "window_id": self.window_id,
            "title": self.title,
            "bundle_id": self.bundle_id,
            "selected_by": self.selected_by,
            "captured_mode": self.captured_mode,
            "screenshot_size": [self.screenshot_width, self.screenshot_height],
        }


# ---------------------------------------------------------------------------
# Asyncio bridge — one long-lived loop on a background thread
# ---------------------------------------------------------------------------

class _AsyncBridge:
    """Runs one asyncio loop on a daemon thread; marshals coroutines from the caller."""

    def __init__(self) -> None:
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        self._thread: Optional[threading.Thread] = None
        self._ready = threading.Event()

    def start(self) -> None:
        if self._thread and self._thread.is_alive():
            return
        self._ready.clear()

        def _run() -> None:
            self._loop = asyncio.new_event_loop()
            asyncio.set_event_loop(self._loop)
            self._ready.set()
            try:
                self._loop.run_forever()
            finally:
                try:
                    self._loop.close()
                except Exception:
                    pass

        self._thread = threading.Thread(target=_run, daemon=True, name="cua-driver-loop")
        self._thread.start()
        if not self._ready.wait(timeout=5.0):
            raise RuntimeError("cua-driver asyncio bridge failed to start")

    def run(self, coro, timeout: Optional[float] = 30.0) -> Any:
        if not self._loop or not self._thread or not self._thread.is_alive():
            raise RuntimeError("cua-driver bridge not started")
        fut: Future = asyncio.run_coroutine_threadsafe(coro, self._loop)
        return fut.result(timeout=timeout)

    def stop(self) -> None:
        if self._loop and self._loop.is_running():
            self._loop.call_soon_threadsafe(self._loop.stop)
        if self._thread:
            self._thread.join(timeout=2.0)
        self._thread = None
        self._loop = None


# ---------------------------------------------------------------------------
# MCP session (lazy, shared across tool calls)
# ---------------------------------------------------------------------------

class _CuaDriverSession:
    """Holds the mcp ClientSession. Spawned lazily; re-entered on drop."""

    def __init__(self, bridge: _AsyncBridge) -> None:
        self._bridge = bridge
        self._session = None
        self._exit_stack = None
        self._lock = threading.Lock()
        self._started = False

    def _require_started(self) -> None:
        if not self._started:
            raise RuntimeError("cua-driver session not started")

    async def _aenter(self) -> None:
        from contextlib import AsyncExitStack
        from mcp import ClientSession, StdioServerParameters
        from mcp.client.stdio import stdio_client

        if not cua_driver_binary_available():
            raise RuntimeError(cua_driver_install_hint())

        params = StdioServerParameters(
            command=_CUA_DRIVER_CMD,
            args=_CUA_DRIVER_ARGS,
            env={**os.environ},
        )
        stack = AsyncExitStack()
        read, write = await stack.enter_async_context(stdio_client(params))
        session = await stack.enter_async_context(ClientSession(read, write))
        await session.initialize()
        self._exit_stack = stack
        self._session = session

    async def _aexit(self) -> None:
        if self._exit_stack is not None:
            try:
                await self._exit_stack.aclose()
            except Exception as e:
                logger.warning("cua-driver shutdown error: %s", e)
        self._exit_stack = None
        self._session = None

    def start(self) -> None:
        with self._lock:
            if self._started:
                return
            self._bridge.start()
            self._bridge.run(self._aenter(), timeout=15.0)
            self._started = True

    def stop(self) -> None:
        with self._lock:
            if not self._started:
                return
            try:
                self._bridge.run(self._aexit(), timeout=5.0)
            finally:
                self._started = False

    async def _call_tool_async(self, name: str, args: Dict[str, Any]) -> Dict[str, Any]:
        result = await self._session.call_tool(name, args)
        return _extract_tool_result(result)

    def call_tool(self, name: str, args: Dict[str, Any], timeout: float = 30.0) -> Dict[str, Any]:
        self._require_started()
        return self._bridge.run(self._call_tool_async(name, args), timeout=timeout)

    async def _list_tools_async(self) -> List[str]:
        result = await self._session.list_tools()
        return [getattr(tool, "name", "") for tool in getattr(result, "tools", []) or []]

    def list_tools(self, timeout: float = 10.0) -> List[str]:
        self._require_started()
        return self._bridge.run(self._list_tools_async(), timeout=timeout)


def _extract_tool_result(mcp_result: Any) -> Dict[str, Any]:
    """Convert an mcp CallToolResult into a plain dict.

    cua-driver returns a mix of text parts, image parts, and structuredContent.
    We flatten into:
      {
        "data": <text or parsed json>,
        "images": [b64, ...],
        "structuredContent": <dict|None>,
        "isError": bool,
      }
    structuredContent is populated from the MCP result's structuredContent field
    (MCP spec §2024-11-05+) and takes precedence for structured data like
    list_windows window arrays.
    """
    data: Any = None
    images: List[str] = []
    is_error = bool(getattr(mcp_result, "isError", False))
    structured: Optional[Dict] = getattr(mcp_result, "structuredContent", None) or None
    text_chunks: List[str] = []
    for part in getattr(mcp_result, "content", []) or []:
        ptype = getattr(part, "type", None)
        if ptype == "text":
            text_chunks.append(getattr(part, "text", "") or "")
        elif ptype == "image":
            b64 = getattr(part, "data", None)
            if b64:
                images.append(b64)
    if text_chunks:
        joined = "\n".join(t for t in text_chunks if t)
        try:
            data = json.loads(joined) if joined.strip().startswith(("{", "[")) else joined
        except json.JSONDecodeError:
            data = joined
    return {"data": data, "images": images, "structuredContent": structured, "isError": is_error}


# ---------------------------------------------------------------------------
# Click action mapping
# ---------------------------------------------------------------------------

# Map from cua-driver `click` `action` values to the AX action names that
# satisfy them. We pick the click `action` based on which AX actions the
# element advertises in `get_window_state` markdown.
_CLICK_ACTION_FOR_AX = (
    # (cua-driver click action, list of AX actions that satisfy it)
    ("press", ["AXPress"]),
    ("confirm", ["AXConfirm"]),
    ("cancel", ["AXCancel"]),
    ("open", ["AXOpen"]),
    ("pick", ["AXPick"]),
    ("show_menu", ["AXShowMenu"]),
)


def _click_action_for_element(elem: UIElement) -> Optional[str]:
    """Choose the best cua-driver click `action` for this element.

    Returns None if no semantic AX action looks supported — caller should
    fall back to coordinate click or refuse with a clear error.
    """
    actions = set(elem.attributes.get("actions") or [])
    if not actions:
        return None
    for click_action, ax_names in _CLICK_ACTION_FOR_AX:
        if any(ax in actions for ax in ax_names):
            return click_action
    return None


# ---------------------------------------------------------------------------
# The backend itself
# ---------------------------------------------------------------------------

class CuaDriverBackend(ComputerUseBackend):
    """Default computer-use backend. macOS-only via cua-driver MCP."""

    def __init__(self) -> None:
        self._bridge = _AsyncBridge()
        self._session = _CuaDriverSession(self._bridge)
        # Sticky context — updated by capture()/focus_app(), used by action tools.
        self._active_target: Optional[ActiveWindowTarget] = None
        # Element cache keyed by (pid, window_id). Replaced on each capture.
        self._last_elements_by_index: Dict[int, UIElement] = {}
        self._elements_owner: Tuple[int, int] = (0, 0)
        self._raise_window_supported: Optional[bool] = None

    # ── Backward-compatible accessors (used by tests + older callers) ──
    @property
    def _active_pid(self) -> Optional[int]:  # pragma: no cover - shim
        return self._active_target.pid if self._active_target else None

    @_active_pid.setter
    def _active_pid(self, value: Optional[int]) -> None:  # pragma: no cover - shim
        if self._active_target is None:
            self._active_target = ActiveWindowTarget()
        self._active_target.pid = int(value or 0)

    @property
    def _active_window_id(self) -> Optional[int]:  # pragma: no cover - shim
        return self._active_target.window_id if self._active_target else None

    @_active_window_id.setter
    def _active_window_id(self, value: Optional[int]) -> None:  # pragma: no cover - shim
        if self._active_target is None:
            self._active_target = ActiveWindowTarget()
        self._active_target.window_id = int(value or 0)

    # ── Lifecycle ──────────────────────────────────────────────────
    def start(self) -> None:
        self._session.start()
        self._probe_raise_window()

    def stop(self) -> None:
        try:
            self._session.stop()
        finally:
            self._bridge.stop()

    def is_available(self) -> bool:
        # Allow non-darwin only when HERMES_CUA_DRIVER_CMD points at a remote
        # MCP shim (see ~/.hermes/plans/remote-macos-computer-use.md).
        if not _is_macos() and not os.environ.get("HERMES_CUA_DRIVER_CMD"):
            return False
        return cua_driver_binary_available()

    def _probe_raise_window(self) -> bool:
        if self._raise_window_supported is not None:
            return self._raise_window_supported
        list_tools = getattr(self._session, "list_tools", None)
        if not callable(list_tools):
            self._raise_window_supported = False
            return False
        try:
            self._raise_window_supported = "raise_window" in set(list_tools())
        except Exception:
            logger.debug("could not probe cua-driver tools/list", exc_info=True)
            self._raise_window_supported = False
        return self._raise_window_supported

    # ── Window discovery helpers ───────────────────────────────────
    def _list_windows(
        self,
        on_screen_only: bool = True,
        pid: Optional[int] = None,
    ) -> List[Dict[str, Any]]:
        """Enumerate windows from cua-driver, normalized + frontmost-first."""
        args: Dict[str, Any] = {"on_screen_only": on_screen_only}
        if pid is not None:
            args["pid"] = pid
        lw_out = self._session.call_tool("list_windows", args)
        sc = lw_out.get("structuredContent") or {}
        raw_windows = sc.get("windows") if sc else None
        if raw_windows:
            windows = [_normalize_window_dict(w) for w in raw_windows]
        else:
            raw_text = lw_out["data"] if isinstance(lw_out["data"], str) else ""
            windows = _parse_windows_from_text(raw_text)
        return _sort_windows_frontmost_first(windows)

    def _select_window(
        self,
        app: Optional[str],
        *,
        require_match: bool,
        on_screen_only: bool = True,
        selected_by: str = "",
    ) -> Optional[ActiveWindowTarget]:
        """Pick a target window.

        - If `app` is provided and `require_match` is True, returns None when
          no on-screen window matches (caller surfaces a clean error).
        - If `app` is None, picks the frontmost on-screen window.
        """
        windows = self._list_windows(on_screen_only=on_screen_only)
        if not windows:
            return None

        if app:
            app_lower = app.lower()
            matched = [
                w for w in windows
                if app_lower in (w["app_name"] or "").lower()
                or app_lower == (w["app_name"] or "").lower()
            ]
            if not matched:
                if require_match:
                    return None
                matched = windows  # fall back only when caller allows it
            windows = matched

        target_w = next(
            (w for w in windows if w.get("is_on_screen", True)),
            windows[0],
        )
        bounds = target_w.get("bounds") or {}
        target = ActiveWindowTarget(
            app_name=target_w.get("app_name", "") or "",
            pid=int(target_w.get("pid", 0) or 0),
            window_id=int(target_w.get("window_id", 0) or 0),
            title=target_w.get("title", "") or "",
            bounds=(
                int(bounds.get("x", 0)) if isinstance(bounds, dict) else 0,
                int(bounds.get("y", 0)) if isinstance(bounds, dict) else 0,
                int(bounds.get("width", 0)) if isinstance(bounds, dict) else 0,
                int(bounds.get("height", 0)) if isinstance(bounds, dict) else 0,
            ),
            selected_by=selected_by,
        )
        return target

    def _target_meta(self, extra: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        meta: Dict[str, Any] = {}
        if self._active_target is not None:
            meta["target"] = self._active_target.as_meta()
        if extra:
            meta.update(extra)
        return meta

    # ── Capture ────────────────────────────────────────────────────
    def capture(self, mode: str = "som", app: Optional[str] = None) -> CaptureResult:
        """Capture the current target window (optionally selected by app name)."""
        require_match = bool(app)
        target = self._select_window(
            app=app, require_match=require_match,
            selected_by=f"capture(app={app!r})" if app else "capture(frontmost)",
        )
        if target is None:
            if app:
                logger.info("capture: no window matched app=%r", app)
                return CaptureResult(
                    mode=mode, width=0, height=0, png_b64=None,
                    elements=[],
                    app=app,
                    window_title=f"<no window matched app={app!r}>",
                    png_bytes_len=0,
                )
            return CaptureResult(mode=mode, width=0, height=0, png_b64=None,
                                 elements=[], app="", window_title="",
                                 png_bytes_len=0)

        self._active_target = target

        # Step 2: capture.
        png_b64: Optional[str] = None
        elements: List[UIElement] = []
        width = height = 0
        window_title = target.title

        t0 = time.monotonic()
        if mode == "vision":
            # cua-driver's get_window_state in 'vision' mode walks no AX tree
            # but still scopes the screenshot to the window. Use it so the
            # screenshot dimensions remain in window-local screenshot pixels.
            sc_out = self._session.call_tool(
                "screenshot",
                {"window_id": target.window_id, "format": "jpeg", "quality": 85},
            )
            if sc_out["images"]:
                png_b64 = sc_out["images"][0]
            target.captured_mode = "vision"
            target.elements_turn = 0
            # Vision skips the AX cache — clear it so element-indexed
            # actions force the caller to recapture in som/ax mode.
            self._last_elements_by_index = {}
            self._elements_owner = (0, 0)
        else:
            # get_window_state: AX tree + optional screenshot.
            gws_out = self._session.call_tool(
                "get_window_state",
                {"pid": target.pid, "window_id": target.window_id},
            )
            sc = gws_out.get("structuredContent") or {}
            tree = sc.get("tree_markdown")
            if not isinstance(tree, str):
                # Legacy/text path: split first line as summary, rest as tree.
                text = gws_out["data"] if isinstance(gws_out["data"], str) else ""
                _summary, tree = _split_tree_text(text)
            if gws_out["images"]:
                png_b64 = gws_out["images"][0]

            # Capture screenshot dimensions and turn id for cache scoping.
            try:
                width = int(sc.get("screenshot_width", 0) or 0)
                height = int(sc.get("screenshot_height", 0) or 0)
                target.screenshot_width = width
                target.screenshot_height = height
                target.screenshot_scale_factor = float(
                    sc.get("screenshot_scale_factor", 1.0) or 1.0
                )
                target.elements_turn = int(sc.get("turn_id", 0) or 0)
                target.bundle_id = sc.get("bundle_id") or target.bundle_id
                target.captured_mode = mode
            except Exception:  # pragma: no cover - defensive
                pass

            # Extract window title from the AX tree first AXWindow line.
            wt = re.search(r'AXWindow\s+"([^"]+)"', tree or "")
            if wt:
                window_title = wt.group(1)
                target.title = window_title

            structured_elements = sc.get("elements")
            if isinstance(structured_elements, list):
                elements = [
                    _parse_element(
                        e,
                        screenshot_scale_factor=target.screenshot_scale_factor,
                        has_screenshot=bool(png_b64 or width or height),
                    )
                    for e in structured_elements
                    if isinstance(e, dict)
                ]
            else:
                elements = _parse_elements_from_tree(tree or "")

            # Stamp pid/window_id onto each element so consumers can detect
            # mis-targeting later.
            for e in elements:
                e.pid = target.pid
                e.window_id = target.window_id
                e.app = target.app_name

            # Replace the element cache for this (pid, window_id).
            self._last_elements_by_index = {e.index: e for e in elements}
            self._elements_owner = (target.pid, target.window_id)

        latency_ms = int((time.monotonic() - t0) * 1000)
        png_bytes_len = 0
        if png_b64:
            try:
                png_bytes_len = len(base64.b64decode(png_b64, validate=False))
            except Exception:
                png_bytes_len = len(png_b64) * 3 // 4

        logger.info(
            "computer_use capture mode=%s app=%r pid=%d window_id=%d elements=%d "
            "image_bytes=%d latency_ms=%d",
            mode, target.app_name, target.pid, target.window_id,
            len(elements), png_bytes_len, latency_ms,
        )

        return CaptureResult(
            mode=mode,
            width=width,
            height=height,
            png_b64=png_b64,
            elements=elements,
            app=target.app_name,
            window_title=window_title,
            png_bytes_len=png_bytes_len,
        )

    # ── Element resolution ─────────────────────────────────────────
    def _resolve_element(self, index: int) -> Optional[UIElement]:
        """Return the cached element for `index` iff the active target still
        matches the (pid, window_id) that produced the cache."""
        if self._active_target is None:
            return None
        owner = self._elements_owner
        if owner != (self._active_target.pid, self._active_target.window_id):
            return None
        return self._last_elements_by_index.get(int(index))

    # ── Pointer ────────────────────────────────────────────────────
    def click(
        self,
        *,
        element: Optional[int] = None,
        x: Optional[int] = None,
        y: Optional[int] = None,
        button: str = "left",
        click_count: int = 1,
        modifiers: Optional[List[str]] = None,
    ) -> ActionResult:
        if self._active_target is None or not self._active_target.pid:
            return ActionResult(
                ok=False, action="click",
                message="No active window — call capture() or focus_app() first.",
                meta=self._target_meta(),
            )

        public_action = (
            "double_click" if click_count == 2 else
            "right_click" if button == "right" else
            "middle_click" if button == "middle" else
            "click"
        )

        if button == "middle":
            return ActionResult(
                ok=False, action=public_action,
                message=(
                    "middle_click is not supported by the cua-driver backend "
                    "(no middle-button primitive in cua-driver's click). "
                    "Use click or right_click instead."
                ),
                meta=self._target_meta({"addressing": "unsupported_button"}),
            )

        if element is not None:
            return self._element_click(
                element_index=int(element),
                button=button,
                click_count=click_count,
                modifiers=modifiers,
                public_action=public_action,
            )

        if x is not None and y is not None:
            return self._coordinate_click(
                x=int(x),
                y=int(y),
                button=button,
                click_count=click_count,
                modifiers=modifiers,
                public_action=public_action,
            )

        return ActionResult(
            ok=False, action=public_action,
            message=f"{public_action} requires element= or coordinate= [x, y].",
            meta=self._target_meta({"addressing": "missing"}),
        )

    def _element_click(
        self,
        *,
        element_index: int,
        button: str,
        click_count: int,
        modifiers: Optional[List[str]],
        public_action: str,
    ) -> ActionResult:
        target = self._active_target
        assert target is not None  # for type-checkers
        elem = self._resolve_element(element_index)
        if elem is None:
            return ActionResult(
                ok=False, action=public_action,
                message=(
                    f"Element {element_index} is not in the active cache "
                    f"for pid={target.pid} window_id={target.window_id}. "
                    "Call capture(mode='som' or 'ax') for this app first."
                ),
                meta=self._target_meta({
                    "addressing": "element_stale",
                    "element_index": element_index,
                }),
            )
        if elem.attributes.get("disabled"):
            return ActionResult(
                ok=False, action=public_action,
                message=f"Element {element_index} ({elem.role}) is DISABLED.",
                meta=self._target_meta({
                    "addressing": "element_disabled",
                    "element_index": element_index,
                    "role": elem.role,
                }),
            )

        # Resolve cua-driver click `action` based on the public action and
        # the AX actions the element exposes.
        actions = set(elem.attributes.get("actions") or [])

        if button == "right":
            tool = "right_click"
            if actions and "AXShowMenu" not in actions:
                # Right-click via element index would just fail with
                # `AXShowMenu failed`. Be honest about it.
                return ActionResult(
                    ok=False, action=public_action,
                    message=(
                        f"Element {element_index} ({elem.role}) does not "
                        "expose AXShowMenu. Recapture and use coordinate "
                        "right-click instead, or pick a menu-capable element."
                    ),
                    meta=self._target_meta({
                        "addressing": "element_no_show_menu",
                        "element_index": element_index,
                        "actions": sorted(actions),
                    }),
                )
            args: Dict[str, Any] = {
                "pid": target.pid,
                "window_id": target.window_id,
                "element_index": element_index,
            }
            if modifiers:
                args["modifier"] = modifiers
            return self._action(
                tool, args,
                public_action=public_action,
                meta_extra={
                    "addressing": "element",
                    "element_index": element_index,
                    "ax_action": "AXShowMenu",
                },
                fallback_element=elem,
            )

        if click_count == 2:
            tool = "double_click"
            ax_action = "AXOpen" if "AXOpen" in actions else None
            args = {
                "pid": target.pid,
                "window_id": target.window_id,
                "element_index": element_index,
            }
            if modifiers:
                args["modifier"] = modifiers
            return self._action(
                tool, args,
                public_action=public_action,
                meta_extra={
                    "addressing": "element",
                    "element_index": element_index,
                    "ax_action": ax_action or "double_click_fallback",
                },
                fallback_element=elem,
            )

        # Single left click — pick a semantic AX action.
        click_action = _click_action_for_element(elem)
        if click_action is None and actions:
            # Element advertised actions but none are click-compatible —
            # do not attempt a doomed AX call; do not advertise success.
            return ActionResult(
                ok=False, action=public_action,
                message=(
                    f"Element {element_index} ({elem.role}) exposes "
                    f"actions {sorted(actions)} but none map to a click. "
                    "Try double_click for AXOpen, set_value for popups/sliders, "
                    "or recapture and use coordinate click at the element's "
                    "screenshot pixel position."
                ),
                meta=self._target_meta({
                    "addressing": "element_no_clickable_action",
                    "element_index": element_index,
                    "actions": sorted(actions),
                }),
            )

        tool = "click"
        args = {
            "pid": target.pid,
            "window_id": target.window_id,
            "element_index": element_index,
        }
        if click_action and click_action != "press":
            # `press` is the cua-driver default; only send `action` when we
            # need a non-default mapping.
            args["action"] = click_action
        if modifiers:
            args["modifier"] = modifiers
        return self._action(
            tool, args,
            public_action=public_action,
            meta_extra={
                "addressing": "element",
                "element_index": element_index,
                "ax_action": (click_action or "press"),
            },
            fallback_element=elem,
        )

    def _coordinate_click(
        self,
        *,
        x: int, y: int,
        button: str,
        click_count: int,
        modifiers: Optional[List[str]],
        public_action: str,
    ) -> ActionResult:
        target = self._active_target
        assert target is not None
        if button == "right":
            tool = "right_click"
        elif click_count == 2:
            tool = "double_click"
        else:
            tool = "click"
        args: Dict[str, Any] = {
            "pid": target.pid,
            "x": int(x),
            "y": int(y),
        }
        if modifiers:
            args["modifier"] = modifiers
        if tool == "click" and click_count == 2:
            args["count"] = 2
        return self._action(
            tool, args,
            public_action=public_action,
            meta_extra={
                "addressing": "coordinate",
                "coordinate": [int(x), int(y)],
            },
        )

    def drag(
        self,
        *,
        from_element: Optional[int] = None,
        to_element: Optional[int] = None,
        from_xy: Optional[Tuple[int, int]] = None,
        to_xy: Optional[Tuple[int, int]] = None,
        button: str = "left",
        modifiers: Optional[List[str]] = None,
    ) -> ActionResult:
        if self._active_target is None or not self._active_target.pid:
            return ActionResult(
                ok=False, action="drag",
                message="No active window — call capture() or focus_app() first.",
                meta=self._target_meta(),
            )
        from_point = self._resolve_drag_endpoint(
            element=from_element,
            xy=from_xy,
            label="from",
        )
        if isinstance(from_point, ActionResult):
            return from_point
        to_point = self._resolve_drag_endpoint(
            element=to_element,
            xy=to_xy,
            label="to",
        )
        if isinstance(to_point, ActionResult):
            return to_point
        if from_point is None or to_point is None:
            return ActionResult(
                ok=False, action="drag",
                message=(
                    "drag requires from_coordinate/to_coordinate or "
                    "from_element/to_element with available bounds."
                ),
                meta=self._target_meta({
                    "addressing": "missing",
                    "from_element": from_element,
                    "to_element": to_element,
                }),
            )
        target = self._active_target
        args: Dict[str, Any] = {
            "pid": target.pid,
            "window_id": target.window_id,
            "from_x": int(from_point[0]),
            "from_y": int(from_point[1]),
            "to_x": int(to_point[0]),
            "to_y": int(to_point[1]),
            "button": button,
        }
        if modifiers:
            args["modifier"] = modifiers
        return self._action(
            "drag", args,
            meta_extra={
                "addressing": "element" if from_element is not None or to_element is not None else "coordinate",
                "from": list(from_point),
                "to": list(to_point),
                "from_element": from_element,
                "to_element": to_element,
            },
        )

    def _resolve_drag_endpoint(
        self,
        *,
        element: Optional[int],
        xy: Optional[Tuple[int, int]],
        label: str,
    ) -> Optional[Tuple[int, int] | ActionResult]:
        if xy is not None:
            return int(xy[0]), int(xy[1])
        if element is None:
            return None
        elem = self._resolve_element(int(element))
        if elem is None:
            return ActionResult(
                ok=False, action="drag",
                message=f"{label}_element {element} is not in the active capture cache.",
                meta=self._target_meta({
                    "addressing": "element_stale",
                    f"{label}_element": element,
                }),
            )
        if not _has_bounds(elem):
            return ActionResult(
                ok=False, action="drag",
                message=(
                    f"{label}_element {element} has no bounds. Recapture with "
                    "a cua-driver version that returns structured elements, or "
                    "use coordinates."
                ),
                meta=self._target_meta({
                    "addressing": "element_bounds_unavailable",
                    f"{label}_element": element,
                }),
            )
        return elem.center()

    def scroll(
        self,
        *,
        direction: str,
        amount: int = 3,
        element: Optional[int] = None,
        x: Optional[int] = None,
        y: Optional[int] = None,
        modifiers: Optional[List[str]] = None,
    ) -> ActionResult:
        if self._active_target is None or not self._active_target.pid:
            return ActionResult(
                ok=False, action="scroll",
                message="No active window — call capture() or focus_app() first.",
                meta=self._target_meta(),
            )
        target = self._active_target
        args: Dict[str, Any] = {
            "pid": target.pid,
            "direction": direction,
            "amount": max(1, min(50, amount)),
        }
        meta_extra: Dict[str, Any] = {"direction": direction, "amount": amount}
        if element is not None:
            # Allow scroll even without a cached element (it focuses by index
            # and falls back gracefully on the cua-driver side), but if we
            # have a cache and the index is unknown, return a clear error.
            if self._last_elements_by_index and element not in self._last_elements_by_index:
                return ActionResult(
                    ok=False, action="scroll",
                    message=(
                        f"Element {element} not in the active capture cache. "
                        "Call capture(mode='som' or 'ax') first."
                    ),
                    meta=self._target_meta({
                        "addressing": "element_stale",
                        "element_index": element,
                    }),
                )
            args["element_index"] = element
            args["window_id"] = target.window_id
            meta_extra.update({"addressing": "element", "element_index": element})
        elif x is not None and y is not None:
            args["x"] = int(x)
            args["y"] = int(y)
            meta_extra.update({"addressing": "coordinate", "coordinate": [int(x), int(y)]})
        else:
            meta_extra["addressing"] = "focused"
        return self._action("scroll", args, meta_extra=meta_extra)

    # ── Keyboard ───────────────────────────────────────────────────
    def type_text(self, text: str) -> ActionResult:
        if self._active_target is None or not self._active_target.pid:
            return ActionResult(
                ok=False, action="type_text",
                message="No active window — call capture() or focus_app() first.",
                meta=self._target_meta(),
            )
        # cua-driver consolidates type_text into a fast AX write with a
        # CGEvent fallback for non-standard text surfaces.
        # Avoid logging the typed payload.
        logger.info(
            "computer_use type_text pid=%d window=%d chars=%d",
            self._active_target.pid, self._active_target.window_id, len(text),
        )
        return self._action(
            "type_text",
            {"pid": self._active_target.pid, "text": text},
            meta_extra={"text_len": len(text)},
        )

    def key(self, keys: str, modifiers: Optional[List[str]] = None) -> ActionResult:
        if self._active_target is None or not self._active_target.pid:
            return ActionResult(
                ok=False, action="key",
                message="No active window — call capture() or focus_app() first.",
                meta=self._target_meta(),
            )
        pid = self._active_target.pid

        key_name, parsed_modifiers = _parse_key_combo(keys)
        if not key_name:
            return ActionResult(
                ok=False, action="key",
                message=f"Could not parse key from '{keys}'.",
                meta=self._target_meta(),
            )

        all_modifiers = list(dict.fromkeys(parsed_modifiers + (modifiers or [])))
        if all_modifiers:
            return self._action(
                "hotkey",
                {"pid": pid, "keys": all_modifiers + [key_name]},
                meta_extra={"keys": keys, "resolved": all_modifiers + [key_name]},
            )
        return self._action(
            "press_key",
            {"pid": pid, "key": key_name},
            meta_extra={"keys": keys, "resolved": [key_name]},
        )

    # ── Value setter ────────────────────────────────────────────────
    def set_value(self, value: str, element: Optional[int] = None) -> ActionResult:
        if self._active_target is None or not self._active_target.pid:
            return ActionResult(
                ok=False, action="set_value",
                message="No active window — call capture() or focus_app() first.",
                meta=self._target_meta(),
            )
        if element is None:
            return ActionResult(
                ok=False, action="set_value",
                message="set_value requires element= (element index).",
                meta=self._target_meta(),
            )
        target = self._active_target
        elem = self._resolve_element(int(element))
        if elem is None:
            return ActionResult(
                ok=False, action="set_value",
                message=(
                    f"Element {element} is not in the active cache "
                    f"for pid={target.pid} window_id={target.window_id}. "
                    "Call capture(mode='som' or 'ax') first."
                ),
                meta=self._target_meta({
                    "addressing": "element_stale",
                    "element_index": int(element),
                }),
            )
        args: Dict[str, Any] = {
            "pid": target.pid,
            "window_id": target.window_id,
            "element_index": int(element),
            "value": value,
        }
        return self._action(
            "set_value", args,
            meta_extra={
                "addressing": "element",
                "element_index": int(element),
                "role": elem.role,
                "value_len": len(value),
            },
        )

    # ── Introspection ──────────────────────────────────────────────
    def list_apps(self) -> List[Dict[str, Any]]:
        out = self._session.call_tool("list_apps", {})
        data = out["data"]
        if isinstance(data, list):
            return data
        if isinstance(data, dict):
            return data.get("apps", [])
        if isinstance(data, str):
            apps = []
            for line in data.splitlines():
                m = re.search(r'(.+?)\s+\(pid\s+(\d+)\)', line)
                if m:
                    apps.append({"name": m.group(1).strip(), "pid": int(m.group(2))})
            return apps
        return []

    def focus_app(self, app: str, raise_window: bool = False) -> ActionResult:
        """Target an app for subsequent actions.

        Default behaviour: pure window selector. Enumerate on-screen windows,
        match `app` (case-insensitive substring or exact match), pin
        `_active_target`. Subsequent click/type/scroll/key calls hit the
        right process without raising the window.

        `raise_window=True` dispatches cua-driver's explicit `raise_window`
        primitive when the installed driver advertises it. Older drivers keep
        the existing unsupported error.
        """
        target = self._select_window(
            app=app, require_match=True,
            selected_by=f"focus_app(app={app!r}, raise_window={raise_window})",
        )
        if target is None:
            return ActionResult(
                ok=False, action="focus_app",
                message=f"No on-screen window found for app '{app}'.",
                meta=self._target_meta({"requested_app": app}),
            )
        # Pin selection so subsequent actions use this window — even if we
        # are about to return an unsupported error for raise_window=True,
        # callers who try `raise_window=false` next still get the right
        # window without re-discovering it. Element cache from a prior
        # capture against a different (pid, window_id) is invalidated.
        if self._active_target is None or (
            self._active_target.pid != target.pid
            or self._active_target.window_id != target.window_id
        ):
            self._last_elements_by_index = {}
            self._elements_owner = (0, 0)
        self._active_target = target

        if raise_window:
            if not self._probe_raise_window():
                return ActionResult(
                    ok=False, action="focus_app",
                    message=(
                        "raise_window=true requires cua-driver with the "
                        "raise_window tool (minimum v0.1.9 in this fork). "
                        "The target was pinned for input routing but the "
                        "window was NOT raised."
                    ),
                    meta=self._target_meta({"raise_window": True, "raised": False}),
                )
            return self._action(
                "raise_window",
                {"pid": target.pid, "window_id": target.window_id},
                public_action="focus_app",
                meta_extra={"raise_window": True, "raised": True},
            )

        return ActionResult(
            ok=True, action="focus_app",
            message=(
                f"Targeted {target.app_name} (pid {target.pid}, "
                f"window {target.window_id}) without raising window."
            ),
            meta=self._target_meta({"raise_window": False, "raised": False}),
        )

    # ── Internal ───────────────────────────────────────────────────
    def _action(
        self,
        name: str,
        args: Dict[str, Any],
        *,
        public_action: Optional[str] = None,
        meta_extra: Optional[Dict[str, Any]] = None,
        fallback_element: Optional[UIElement] = None,
    ) -> ActionResult:
        """Call cua-driver tool `name` and shape an ActionResult.

        `public_action` controls the action label on the returned
        ActionResult — useful when one cua-driver tool (e.g. `click`)
        backs multiple public actions (`click`, `double_click`,
        `right_click`).

        `meta_extra` is merged into the result `meta` for telemetry. We
        always include the active target, the cua-driver tool name, the
        latency, and the parsed error code (when present).
        """
        public = public_action or name
        # Redact `text` (typed payload) before logging args.
        safe_args = {k: v for k, v in args.items() if k != "text"}
        if "text" in args:
            safe_args["text_len"] = len(str(args["text"]))

        t0 = time.monotonic()
        try:
            out = self._session.call_tool(name, args)
        except Exception as e:
            logger.exception("cua-driver %s call failed args=%s", name, safe_args)
            meta = self._target_meta(meta_extra or {})
            meta.update({"backend_tool": name, "exception": str(e)})
            return ActionResult(ok=False, action=public,
                                message=f"cua-driver error: {e}",
                                meta=meta)
        latency_ms = int((time.monotonic() - t0) * 1000)
        ok = not out["isError"]
        data = out["data"]
        message = ""
        if isinstance(data, dict):
            message = str(data.get("message", "")) or ""
        elif isinstance(data, str):
            message = data

        meta = self._target_meta(meta_extra or {})
        meta.update({
            "backend_tool": name,
            "latency_ms": latency_ms,
        })
        if not ok:
            code = _parse_ax_error_code(message)
            if code is not None:
                meta["error_code"] = code
            if (
                name in {"click", "double_click", "right_click"}
                and fallback_element is not None
                and code in {-25204, -25205, -25206}
                and _has_bounds(fallback_element)
            ):
                retry = self._coordinate_click(
                    x=fallback_element.center()[0],
                    y=fallback_element.center()[1],
                    button="right" if name == "right_click" else "left",
                    click_count=2 if name == "double_click" else 1,
                    modifiers=args.get("modifier"),
                    public_action=public,
                )
                retry.meta.update({
                    "fallback_from": "ax_element",
                    "original_error_code": code,
                    "original_message": message,
                })
                return retry
            hint = _explain_ax_error(message)
            if hint:
                meta["hint"] = hint
                if message and hint not in message:
                    message = f"{message}\nHint: {hint}"
        if isinstance(data, dict):
            # Surface useful structured fields without leaking the full blob.
            for k in ("error", "details", "axRole", "axActions"):
                if k in data and k not in meta:
                    meta[k] = data[k]

        logger.info(
            "computer_use action=%s backend=%s ok=%s pid=%s window=%s "
            "latency_ms=%d addressing=%s",
            public, name, ok,
            args.get("pid"), args.get("window_id"),
            latency_ms,
            (meta_extra or {}).get("addressing", ""),
        )
        return ActionResult(ok=ok, action=public, message=message, meta=meta)


def _has_bounds(elem: UIElement) -> bool:
    x, y, w, h = elem.bounds
    return w > 0 and h > 0


def _parse_element(
    d: Dict[str, Any],
    *,
    screenshot_scale_factor: float = 1.0,
    has_screenshot: bool = False,
) -> UIElement:
    """Convert cua-driver structured element metadata into a UIElement."""
    bounds = d.get("bounds") or (0, 0, 0, 0)
    if isinstance(bounds, dict):
        raw_bounds = (
            float(bounds.get("x", 0) or 0),
            float(bounds.get("y", 0) or 0),
            float(bounds.get("w", bounds.get("width", 0)) or 0),
            float(bounds.get("h", bounds.get("height", 0)) or 0),
        )
    elif isinstance(bounds, (list, tuple)) and len(bounds) == 4:
        raw_bounds = tuple(float(v or 0) for v in bounds)
    else:
        raw_bounds = (0.0, 0.0, 0.0, 0.0)
    bounds_space = str(d.get("bounds_space") or d.get("boundsSpace") or "")
    if bounds_space == "native" and has_screenshot and screenshot_scale_factor:
        scale = screenshot_scale_factor if screenshot_scale_factor > 0 else 1.0
        raw_bounds = tuple(v / scale for v in raw_bounds)
    parsed_bounds = tuple(int(round(v)) for v in raw_bounds)
    attrs = {k: v for k, v in d.items()
             if k not in {
                 "index", "role", "label", "title", "bounds", "app", "pid",
                 "window_id", "windowId",
             }}
    if d.get("identifier") and "id" not in attrs:
        attrs["id"] = d["identifier"]
    if d.get("subrole") and "subrole" not in attrs:
        attrs["subrole"] = d["subrole"]
    if bounds_space:
        attrs["bounds_space"] = bounds_space
    label = d.get("label") or d.get("title") or ""
    return UIElement(
        index=int(d.get("index", 0)),
        role=str(d.get("role", "") or ""),
        label=str(label or ""),
        bounds=parsed_bounds,  # type: ignore[arg-type]
        app=str(d.get("app", "") or ""),
        pid=int(d.get("pid", 0) or 0),
        window_id=int(d.get("window_id", d.get("windowId", 0)) or 0),
        attributes=attrs,
    )
