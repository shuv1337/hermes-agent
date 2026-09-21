"""Persistent, sender-scoped Signal YOLO approval behavior."""

from contextlib import contextmanager

import pytest

import hermes_cli.config as config_module
from gateway.config import Platform
from gateway.session import SessionSource, build_session_key
from gateway.session_context import clear_session_vars, set_session_vars
from hermes_cli.config_defaults import DEFAULT_CONFIG
from tools import approval
from tools.approval_context import set_current_session_key, reset_current_session_key


ALLOWED_ACI = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
OTHER_ACI = "11111111-2222-4333-8444-555555555555"


@pytest.fixture()
def configured_home(tmp_path, monkeypatch):
    home = tmp_path / ".hermes"
    home.mkdir()
    (home / "config.yaml").write_text(
        "approvals:\n"
        "  mode: manual\n"
        "  deny:\n"
        "    - 'git push --force*'\n"
        "  platforms:\n"
        "    signal:\n"
        "      yolo_senders:\n"
        f"        - '{ALLOWED_ACI}'\n",
        encoding="utf-8",
    )
    monkeypatch.setenv("HERMES_HOME", str(home))
    monkeypatch.setattr(approval, "_YOLO_MODE_FROZEN", False)
    config_module._LOAD_CONFIG_CACHE.clear()
    yield home
    config_module._LOAD_CONFIG_CACHE.clear()


def _source(platform: Platform, sender_id: str) -> SessionSource:
    if platform == Platform.SIGNAL:
        # Real Signal DMs commonly key the chat by phone number while carrying
        # sourceUuid/ACI separately as user_id_alt. This proves the allowlist
        # uses the gateway's sender identity rather than parsing the session key.
        return SessionSource(
            platform=platform,
            chat_id="+15551234567",
            chat_type="dm",
            user_id="+15551234567",
            user_id_alt=sender_id,
        )
    return SessionSource(
        platform=platform,
        chat_id=sender_id,
        chat_type="dm",
        user_id=sender_id,
    )


@contextmanager
def _bound_source(source: SessionSource):
    session_key = build_session_key(source)
    tokens = set_session_vars(
        platform=source.platform.value,
        chat_id=source.chat_id,
        chat_type=source.chat_type,
        user_id=source.user_id or "",
        user_id_alt=source.user_id_alt or "",
        session_key=session_key,
        cron_session="",
    )
    approval_token = set_current_session_key(session_key)
    try:
        yield session_key
    finally:
        reset_current_session_key(approval_token)
        clear_session_vars(tokens)
        approval.disable_session_yolo(session_key)


def test_default_schema_keeps_sender_yolo_disabled():
    approvals = DEFAULT_CONFIG["approvals"]
    assert approvals["platforms"]["signal"]["yolo_senders"] == []


def test_configured_allowed_sender_signal_sender_bypasses_after_session_state_is_cleared(
    configured_home,
):
    source = _source(Platform.SIGNAL, ALLOWED_ACI)
    with _bound_source(source) as session_key:
        # Simulate a gateway restart: no in-memory /yolo state survives, while
        # the persisted config is re-read and still activates the bypass.
        approval.clear_session(session_key)
        config_module._LOAD_CONFIG_CACHE.clear()

        assert approval.is_session_yolo_enabled(session_key) is False
        assert approval.is_approval_bypass_active_for_session(session_key) is True
        assert (
            approval.check_all_command_guards("rm -rf /tmp/allowed_sender-yolo-test", "local")[
                "approved"
            ]
            is True
        )


@pytest.mark.parametrize(
    ("platform", "sender_id"),
    [
        pytest.param(Platform.SIGNAL, OTHER_ACI, id="other-signal-sender"),
        pytest.param(Platform.TELEGRAM, ALLOWED_ACI, id="telegram-same-id"),
        pytest.param(Platform.SLACK, ALLOWED_ACI, id="slack-same-id"),
        pytest.param(Platform.LOCAL, ALLOWED_ACI, id="cli-same-id"),
    ],
)
def test_configured_signal_aci_does_not_bypass_other_senders_or_platforms(
    configured_home, platform, sender_id
):
    with _bound_source(_source(platform, sender_id)) as session_key:
        assert approval.is_approval_bypass_active_for_session(session_key) is False


def test_hardline_and_user_deny_still_block_configured_allowed_sender(configured_home):
    with _bound_source(_source(Platform.SIGNAL, ALLOWED_ACI)):
        hardline = approval.check_all_command_guards("rm -rf /", "local")
        denied = approval.check_all_command_guards(
            "git push --force origin main", "local"
        )

    assert hardline["approved"] is False
    assert hardline.get("hardline") is True
    assert denied["approved"] is False
    assert denied.get("user_deny") is True


def test_sender_bypass_requires_exact_bound_session(configured_home, monkeypatch):
    with _bound_source(_source(Platform.SIGNAL, ALLOWED_ACI)) as session_key:
        assert approval.is_approval_bypass_active_for_session(session_key)
        assert not approval.is_approval_bypass_active_for_session("another-session")
        # Plugin/tool approval gates use the same sender-scoped decision.
        monkeypatch.setattr(approval, "prompt_dangerous_approval", lambda *a, **k: pytest.fail("must not prompt"))
        assert approval.request_tool_approval("plugin_test", "write test")["approved"]


def test_process_environment_cannot_spoof_bound_signal_sender(configured_home, monkeypatch):
    import contextvars

    fresh_context = contextvars.Context()
    monkeypatch.setenv("HERMES_SESSION_PLATFORM", "signal")
    monkeypatch.setenv("HERMES_SESSION_KEY", "spoofed-session")
    monkeypatch.setenv("HERMES_SESSION_USER_ID_ALT", ALLOWED_ACI)
    assert not fresh_context.run(approval.is_approval_bypass_active_for_session, "spoofed-session")
