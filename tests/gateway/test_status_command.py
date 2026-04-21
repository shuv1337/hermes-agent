"""Tests for gateway /status behavior and token persistence."""

from datetime import datetime
import time
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest

from gateway.config import GatewayConfig, Platform, PlatformConfig
from gateway.platforms.base import MessageEvent
from gateway.session import SessionEntry, SessionSource, build_session_key


def _make_source() -> SessionSource:
    return SessionSource(
        platform=Platform.TELEGRAM,
        user_id="u1",
        chat_id="c1",
        user_name="tester",
        chat_type="dm",
    )


def _make_event(text: str) -> MessageEvent:
    return MessageEvent(
        text=text,
        source=_make_source(),
        message_id="m1",
    )


def _make_runner(session_entry: SessionEntry):
    from gateway.run import GatewayRunner

    runner = object.__new__(GatewayRunner)
    runner.config = GatewayConfig(
        platforms={Platform.TELEGRAM: PlatformConfig(enabled=True, token="***")}
    )
    adapter = MagicMock()
    adapter.send = AsyncMock()
    runner.adapters = {Platform.TELEGRAM: adapter}
    runner._voice_mode = {}
    runner.hooks = SimpleNamespace(emit=AsyncMock(), loaded_hooks=False)
    runner.session_store = MagicMock()
    runner.session_store.get_or_create_session.return_value = session_entry
    runner.session_store.load_transcript.return_value = []
    runner.session_store.has_any_sessions.return_value = True
    runner.session_store.append_to_transcript = MagicMock()
    runner.session_store.rewrite_transcript = MagicMock()
    runner.session_store.update_session = MagicMock()
    runner._running_agents = {}
    runner._session_run_generation = {}
    runner._pending_messages = {}
    runner._pending_approvals = {}
    runner._session_db = MagicMock()
    runner._session_db.get_session_title.return_value = None
    runner._reasoning_config = None
    runner._provider_routing = {}
    runner._fallback_model = None
    runner._show_reasoning = False
    runner._is_user_authorized = lambda _source: True
    runner._set_session_env = lambda _context: None
    runner._should_send_voice_reply = lambda *_args, **_kwargs: False
    runner._send_voice_reply = AsyncMock()
    runner._capture_gateway_honcho_if_configured = lambda *args, **kwargs: None
    runner._emit_gateway_run_progress = AsyncMock()
    return runner


@pytest.mark.asyncio
async def test_status_command_reports_running_agent_without_interrupt(monkeypatch):
    session_entry = SessionEntry(
        session_key=build_session_key(_make_source()),
        session_id="sess-1",
        created_at=datetime.now(),
        updated_at=datetime.now(),
        platform=Platform.TELEGRAM,
        chat_type="dm",
        total_tokens=321,
    )
    runner = _make_runner(session_entry)
    running_agent = MagicMock()
    runner._running_agents[build_session_key(_make_source())] = running_agent

    result = await runner._handle_message(_make_event("/status"))

    assert "**Session ID:** `sess-1`" in result
    assert "**Tokens:** 321" in result
    assert "**Agent Running:** Yes ⚡" in result
    assert "**Title:**" not in result
    running_agent.interrupt.assert_not_called()
    assert runner._pending_messages == {}


@pytest.mark.asyncio
async def test_status_command_includes_session_title_when_present():
    session_entry = SessionEntry(
        session_key=build_session_key(_make_source()),
        session_id="sess-1",
        created_at=datetime.now(),
        updated_at=datetime.now(),
        platform=Platform.TELEGRAM,
        chat_type="dm",
        total_tokens=321,
    )
    runner = _make_runner(session_entry)
    runner._session_db.get_session_title.return_value = "My titled session"

    result = await runner._handle_message(_make_event("/status"))

    assert "**Session ID:** `sess-1`" in result
    assert "**Title:** My titled session" in result


@pytest.mark.asyncio
async def test_agents_command_reports_active_agents_and_processes(monkeypatch):
    session_key = build_session_key(_make_source())
    session_entry = SessionEntry(
        session_key=session_key,
        session_id="sess-1",
        created_at=datetime.now(),
        updated_at=datetime.now(),
        platform=Platform.TELEGRAM,
        chat_type="dm",
        total_tokens=0,
    )
    runner = _make_runner(session_entry)
    running_agent = SimpleNamespace(
        session_id="sess-running",
        model="openrouter/test-model",
        interrupt=MagicMock(),
        get_activity_summary=lambda: {"seconds_since_activity": 0},
    )
    runner._running_agents[session_key] = running_agent
    runner._running_agents_ts = {session_key: time.time() - 8}
    runner._background_tasks = set()

    class _FakeRegistry:
        def list_sessions(self):
            return [
                {
                    "session_id": "proc-1",
                    "status": "running",
                    "uptime_seconds": 17,
                    "command": "sleep 30",
                }
            ]

    monkeypatch.setattr("tools.process_registry.process_registry", _FakeRegistry())

    result = await runner._handle_message(_make_event("/agents"))

    assert "**Active agents:** 1" in result
    assert "**Running background processes:** 1" in result
    assert "proc-1" in result
    running_agent.interrupt.assert_not_called()


@pytest.mark.asyncio
async def test_tasks_alias_routes_to_agents_command(monkeypatch):
    session_entry = SessionEntry(
        session_key=build_session_key(_make_source()),
        session_id="sess-1",
        created_at=datetime.now(),
        updated_at=datetime.now(),
        platform=Platform.TELEGRAM,
        chat_type="dm",
        total_tokens=0,
    )
    runner = _make_runner(session_entry)
    runner._background_tasks = set()

    class _FakeRegistry:
        def list_sessions(self):
            return []

    monkeypatch.setattr("tools.process_registry.process_registry", _FakeRegistry())

    result = await runner._handle_message(_make_event("/tasks"))

    assert "Active Agents & Tasks" in result


@pytest.mark.asyncio
async def test_handle_message_persists_agent_token_counts(monkeypatch):
    import gateway.run as gateway_run

    session_entry = SessionEntry(
        session_key=build_session_key(_make_source()),
        session_id="sess-1",
        created_at=datetime.now(),
        updated_at=datetime.now(),
        platform=Platform.TELEGRAM,
        chat_type="dm",
    )
    runner = _make_runner(session_entry)
    runner.session_store.load_transcript.return_value = [{"role": "user", "content": "earlier"}]
    runner._run_agent = AsyncMock(
        return_value={
            "final_response": "ok",
            "messages": [],
            "tools": [],
            "history_offset": 0,
            "last_prompt_tokens": 80,
            "input_tokens": 120,
            "output_tokens": 45,
            "model": "openai/test-model",
        }
    )

    monkeypatch.setattr(gateway_run, "_resolve_runtime_agent_kwargs", lambda: {"api_key": "***"})
    monkeypatch.setattr(
        "agent.model_metadata.get_model_context_length",
        lambda *_args, **_kwargs: 100000,
    )

    result = await runner._handle_message(_make_event("hello"))

    assert result == "ok"
    runner.session_store.update_session.assert_called_once_with(
        session_entry.session_key,
        last_prompt_tokens=80,
    )


@pytest.mark.asyncio
async def test_handle_message_discards_stale_result_after_session_invalidation(monkeypatch):
    import gateway.run as gateway_run

    session_entry = SessionEntry(
        session_key=build_session_key(_make_source()),
        session_id="sess-1",
        created_at=datetime.now(),
        updated_at=datetime.now(),
        platform=Platform.TELEGRAM,
        chat_type="dm",
    )
    runner = _make_runner(session_entry)
    runner.session_store.load_transcript.return_value = [{"role": "user", "content": "earlier"}]
    session_key = session_entry.session_key
    runner.adapters[Platform.TELEGRAM]._post_delivery_callbacks = {session_key: object()}

    async def _stale_result(**kwargs):
        runner._invalidate_session_run_generation(kwargs["session_key"], reason="test_stale_result")
        return {
            "final_response": "late reply",
            "messages": [],
            "tools": [],
            "history_offset": 0,
            "last_prompt_tokens": 80,
            "input_tokens": 120,
            "output_tokens": 45,
            "model": "openai/test-model",
        }

    runner._run_agent = AsyncMock(side_effect=_stale_result)

    monkeypatch.setattr(gateway_run, "_resolve_runtime_agent_kwargs", lambda: {"api_key": "***"})
    monkeypatch.setattr(
        "agent.model_metadata.get_model_context_length",
        lambda *_args, **_kwargs: 100000,
    )

    result = await runner._handle_message(_make_event("hello"))

    assert result is None
    runner.session_store.append_to_transcript.assert_not_called()
    runner.session_store.update_session.assert_not_called()
    assert session_key not in runner.adapters[Platform.TELEGRAM]._post_delivery_callbacks


@pytest.mark.asyncio
async def test_handle_message_stale_result_keeps_newer_generation_callback(monkeypatch):
    import gateway.run as gateway_run

    class _Adapter:
        def __init__(self):
            self._post_delivery_callbacks = {}

        async def send(self, *args, **kwargs):
            return None

        def pop_post_delivery_callback(self, session_key, *, generation=None):
            entry = self._post_delivery_callbacks.get(session_key)
            if entry is None:
                return None
            if isinstance(entry, tuple):
                entry_generation, callback = entry
                if generation is not None and entry_generation != generation:
                    return None
                self._post_delivery_callbacks.pop(session_key, None)
                return callback
            if generation is not None:
                return None
            return self._post_delivery_callbacks.pop(session_key, None)

    session_entry = SessionEntry(
        session_key=build_session_key(_make_source()),
        session_id="sess-1",
        created_at=datetime.now(),
        updated_at=datetime.now(),
        platform=Platform.TELEGRAM,
        chat_type="dm",
    )
    runner = _make_runner(session_entry)
    runner.session_store.load_transcript.return_value = [{"role": "user", "content": "earlier"}]
    session_key = session_entry.session_key
    adapter = _Adapter()
    runner.adapters[Platform.TELEGRAM] = adapter

    async def _stale_result(**kwargs):
        # Simulate a newer run claiming the callback slot before the stale run unwinds.
        runner._session_run_generation[session_key] = 2
        adapter._post_delivery_callbacks[session_key] = (2, lambda: None)
        return {
            "final_response": "late reply",
            "messages": [],
            "tools": [],
            "history_offset": 0,
            "last_prompt_tokens": 80,
            "input_tokens": 120,
            "output_tokens": 45,
            "model": "openai/test-model",
        }

    runner._run_agent = AsyncMock(side_effect=_stale_result)

    monkeypatch.setattr(gateway_run, "_resolve_runtime_agent_kwargs", lambda: {"api_key": "***"})
    monkeypatch.setattr(
        "agent.model_metadata.get_model_context_length",
        lambda *_args, **_kwargs: 100000,
    )

    result = await runner._handle_message(_make_event("hello"))

    assert result is None
    assert session_key in adapter._post_delivery_callbacks
    assert adapter._post_delivery_callbacks[session_key][0] == 2



@pytest.mark.asyncio
async def test_status_command_bypasses_active_session_guard():
    """When an agent is running, /status must be dispatched immediately via
    base.handle_message — not queued or treated as an interrupt (#5046)."""
    import asyncio
    from gateway.platforms.base import BasePlatformAdapter, MessageEvent, MessageType
    from gateway.session import build_session_key
    from gateway.config import Platform, PlatformConfig, GatewayConfig

    source = _make_source()
    session_key = build_session_key(source)

    handler_called_with = []

    async def fake_handler(event):
        handler_called_with.append(event)
        return "📊 **Hermes Gateway Status**\n**Agent Running:** Yes ⚡"

    # Concrete subclass to avoid abstract method errors
    class _ConcreteAdapter(BasePlatformAdapter):
        platform = Platform.TELEGRAM

        async def connect(self): pass
        async def disconnect(self): pass
        async def send(self, chat_id, content, **kwargs): pass
        async def get_chat_info(self, chat_id): return {}

    platform_config = PlatformConfig(enabled=True, token="***")
    adapter = _ConcreteAdapter(platform_config, Platform.TELEGRAM)
    adapter.set_message_handler(fake_handler)

    sent = []

    async def fake_send_with_retry(chat_id, content, reply_to=None, metadata=None):
        sent.append(content)

    adapter._send_with_retry = fake_send_with_retry

    # Simulate an active session
    interrupt_event = asyncio.Event()
    adapter._active_sessions[session_key] = interrupt_event

    event = MessageEvent(
        text="/status",
        source=source,
        message_id="m1",
        message_type=MessageType.COMMAND,
    )
    await adapter.handle_message(event)

    assert handler_called_with, "/status handler was never called (event was queued or dropped)"
    assert sent, "/status response was never sent"
    assert "Agent Running" in sent[0]
    assert not interrupt_event.is_set(), "/status incorrectly triggered an agent interrupt"
    assert session_key not in adapter._pending_messages, "/status was incorrectly queued"


@pytest.mark.asyncio
async def test_status_command_includes_gateway_info_block(monkeypatch):
    """/status shows version, commit hash, uptime, and PID when available."""
    session_entry = SessionEntry(
        session_key=build_session_key(_make_source()),
        session_id="sess-1",
        created_at=datetime.now(),
        updated_at=datetime.now(),
        platform=Platform.TELEGRAM,
        chat_type="dm",
        total_tokens=42,
    )
    runner = _make_runner(session_entry)
    # Simulate a gateway that has been up for ~2 minutes.
    runner._gateway_started_at = time.time() - 125

    monkeypatch.setattr(
        "gateway.run._collect_gateway_info",
        lambda _started: {
            "version": "9.9.9",
            "release_date": "2099.1.1",
            "local_commit": "abc12345",
            "upstream_commit": "def67890",
            "comparison_label": "upstream",
            "commits_ahead": 3,
            "uptime_seconds": 125,
            "uptime_human": "2m 5s",
            "pid": 12345,
        },
    )

    result = await runner._handle_message(_make_event("/status"))

    assert "**Version:** v9.9.9 (2099.1.1)" in result
    assert "**Commit:** `abc12345` · upstream `def67890` (+3 commits ahead)" in result
    assert "**Gateway Uptime:** 2m 5s (pid 12345)" in result
    # Existing session fields must still be present.
    assert "**Session ID:** `sess-1`" in result
    assert "**Agent Running:** No" in result


@pytest.mark.asyncio
async def test_status_command_singular_commit_ahead(monkeypatch):
    """Commits-ahead label uses singular 'commit' when ahead == 1."""
    session_entry = SessionEntry(
        session_key=build_session_key(_make_source()),
        session_id="sess-1",
        created_at=datetime.now(),
        updated_at=datetime.now(),
        platform=Platform.TELEGRAM,
        chat_type="dm",
    )
    runner = _make_runner(session_entry)
    runner._gateway_started_at = time.time()

    monkeypatch.setattr(
        "gateway.run._collect_gateway_info",
        lambda _started: {
            "version": "1.0.0",
            "release_date": "2026.1.1",
            "local_commit": "aaaa1111",
            "upstream_commit": "bbbb2222",
            "comparison_label": "upstream",
            "commits_ahead": 1,
            "uptime_seconds": 5,
            "uptime_human": "5s",
            "pid": 999,
        },
    )

    result = await runner._handle_message(_make_event("/status"))
    assert "(+1 commit ahead)" in result
    assert "(+1 commits ahead)" not in result


@pytest.mark.asyncio
async def test_status_command_clean_tree_omits_ahead_clause(monkeypatch):
    """When HEAD == origin/main, commit line drops the '+N ahead' suffix."""
    session_entry = SessionEntry(
        session_key=build_session_key(_make_source()),
        session_id="sess-1",
        created_at=datetime.now(),
        updated_at=datetime.now(),
        platform=Platform.TELEGRAM,
        chat_type="dm",
    )
    runner = _make_runner(session_entry)
    runner._gateway_started_at = time.time()

    monkeypatch.setattr(
        "gateway.run._collect_gateway_info",
        lambda _started: {
            "version": "1.0.0",
            "release_date": "2026.1.1",
            "local_commit": "deadbeef",
            "upstream_commit": "deadbeef",
            "comparison_label": "upstream",
            "commits_ahead": 0,
            "uptime_seconds": 10,
            "uptime_human": "10s",
            "pid": 100,
        },
    )

    result = await runner._handle_message(_make_event("/status"))
    assert "**Commit:** `deadbeef`" in result
    assert "ahead" not in result  # no '+N commits ahead' suffix
    assert "upstream" not in result  # no 'upstream' label either


@pytest.mark.asyncio
async def test_status_command_survives_gateway_info_failure(monkeypatch):
    """A broken _collect_gateway_info must not break /status — session block still renders."""
    session_entry = SessionEntry(
        session_key=build_session_key(_make_source()),
        session_id="sess-1",
        created_at=datetime.now(),
        updated_at=datetime.now(),
        platform=Platform.TELEGRAM,
        chat_type="dm",
        total_tokens=7,
    )
    runner = _make_runner(session_entry)

    def _boom(_started):
        raise RuntimeError("simulated git failure")

    monkeypatch.setattr("gateway.run._collect_gateway_info", _boom)

    result = await runner._handle_message(_make_event("/status"))
    # No gateway-info lines, but session section still intact.
    assert "**Session ID:** `sess-1`" in result
    assert "**Tokens:** 7" in result
    assert "**Version:**" not in result
    assert "**Commit:**" not in result
    assert "**Gateway Uptime:**" not in result


def test_format_gateway_uptime_boundaries():
    """_format_gateway_uptime covers s/m/h/d ranges."""
    from gateway.run import _format_gateway_uptime

    assert _format_gateway_uptime(0) == "0s"
    assert _format_gateway_uptime(59) == "59s"
    assert _format_gateway_uptime(60) == "1m 0s"
    assert _format_gateway_uptime(125) == "2m 5s"
    assert _format_gateway_uptime(3599) == "59m 59s"
    assert _format_gateway_uptime(3600) == "1h 0m"
    assert _format_gateway_uptime(3661) == "1h 1m"
    assert _format_gateway_uptime(86400) == "1d 0h 0m"
    assert _format_gateway_uptime(90061) == "1d 1h 1m"
    assert _format_gateway_uptime(-5) == "0s"  # clamp to zero


def test_collect_gateway_info_handles_missing_started_at():
    """_collect_gateway_info returns best-effort dict when no start time is given."""
    from gateway.run import _collect_gateway_info

    info = _collect_gateway_info(None)
    # Version/pid are always resolvable; uptime requires started_at.
    assert "uptime_seconds" not in info
    assert "uptime_human" not in info
    assert info.get("pid")
    assert info.get("version")


@pytest.mark.asyncio
async def test_profile_command_reports_custom_root_profile(monkeypatch, tmp_path):
    """Gateway /profile detects custom-root profiles (not under ~/.hermes)."""
    from pathlib import Path

    session_entry = SessionEntry(
        session_key=build_session_key(_make_source()),
        session_id="sess-1",
        created_at=datetime.now(),
        updated_at=datetime.now(),
        platform=Platform.TELEGRAM,
        chat_type="dm",
    )
    runner = _make_runner(session_entry)
    profile_home = tmp_path / "profiles" / "coder"

    monkeypatch.setenv("HERMES_HOME", str(profile_home))
    monkeypatch.setattr(Path, "home", lambda: tmp_path / "unrelated-home")

    result = await runner._handle_profile_command(_make_event("/profile"))

    assert "**Profile:** `coder`" in result
    assert f"**Home:** `{profile_home}`" in result
