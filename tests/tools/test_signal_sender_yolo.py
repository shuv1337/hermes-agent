"""Persistent, sender-scoped Signal YOLO approval behavior."""

from contextlib import contextmanager

import pytest

import hermes_cli.config as config_module
from gateway.config import Platform
from gateway.session import SessionSource, build_session_key
from gateway.session_context import clear_session_vars, set_session_vars
from hermes_cli.config_defaults import DEFAULT_CONFIG
from tools import approval


KYLE_ACI = "34003dfa-1609-4fdd-9716-9f78efce05ea"
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
        f"        - '{KYLE_ACI}'\n",
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
    approval_token = approval.set_current_session_key(session_key)
    try:
        yield session_key
    finally:
        approval.reset_current_session_key(approval_token)
        clear_session_vars(tokens)
        approval.disable_session_yolo(session_key)


def test_default_schema_keeps_sender_yolo_disabled():
    approvals = DEFAULT_CONFIG["approvals"]
    assert approvals["mode"] == "smart"
    assert approvals["platforms"]["signal"]["yolo_senders"] == []


def test_configured_kyle_signal_sender_bypasses_after_session_state_is_cleared(
    configured_home,
):
    source = _source(Platform.SIGNAL, KYLE_ACI)
    with _bound_source(source) as session_key:
        # Simulate a gateway restart: no in-memory /yolo state survives, while
        # the persisted config is re-read and still activates the bypass.
        approval.clear_session(session_key)
        config_module._LOAD_CONFIG_CACHE.clear()

        assert approval.is_session_yolo_enabled(session_key) is False
        assert approval.is_approval_bypass_active_for_session(session_key) is True
        assert (
            approval.check_all_command_guards("rm -rf /tmp/kyle-yolo-test", "local")[
                "approved"
            ]
            is True
        )


@pytest.mark.parametrize(
    ("platform", "sender_id"),
    [
        pytest.param(Platform.SIGNAL, OTHER_ACI, id="other-signal-sender"),
        pytest.param(Platform.TELEGRAM, KYLE_ACI, id="telegram-same-id"),
        pytest.param(Platform.SLACK, KYLE_ACI, id="slack-same-id"),
        pytest.param(Platform.LOCAL, KYLE_ACI, id="cli-same-id"),
    ],
)
def test_configured_signal_aci_does_not_bypass_other_senders_or_platforms(
    configured_home, platform, sender_id
):
    with _bound_source(_source(platform, sender_id)) as session_key:
        assert approval.is_approval_bypass_active_for_session(session_key) is False


def test_hardline_and_user_deny_still_block_configured_kyle(configured_home):
    with _bound_source(_source(Platform.SIGNAL, KYLE_ACI)):
        hardline = approval.check_all_command_guards("rm -rf /", "local")
        denied = approval.check_all_command_guards(
            "git push --force origin main", "local"
        )

    assert hardline["approved"] is False
    assert hardline.get("hardline") is True
    assert denied["approved"] is False
    assert denied.get("user_deny") is True
