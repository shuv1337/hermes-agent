"""Tests for /channel-report slash command."""

import sys
from collections import namedtuple
from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock
import pytest


def _ensure_discord_mock():
    if "discord" in sys.modules and hasattr(sys.modules["discord"], "__file__"):
        return

    if sys.modules.get("discord") is None:
        discord_mod = MagicMock()
        discord_mod.Intents.default.return_value = MagicMock()
        discord_mod.DMChannel = type("DMChannel", (), {})
        discord_mod.Thread = type("Thread", (), {})
        discord_mod.ForumChannel = type("ForumChannel", (), {})
        discord_mod.Interaction = object
        discord_mod.Forbidden = Exception
        # utils.utcnow must return a real datetime for timedelta math
        discord_mod.utils = SimpleNamespace(
            utcnow=lambda: datetime(2024, 1, 1, 12, 0, 0, tzinfo=timezone.utc)
        )
        discord_mod.MessageType = SimpleNamespace(default=0, reply=1)

        class _FakeGroup:
            def __init__(self, *, name, description, parent=None):
                self.name = name
                self.description = description
                self.parent = parent
                self._children = {}
                if parent is not None:
                    parent.add_command(self)

            def add_command(self, cmd):
                self._children[cmd.name] = cmd

        class _FakeCommand:
            def __init__(self, *, name, description, callback, parent=None):
                self.name = name
                self.description = description
                self.callback = callback
                self.parent = parent

        discord_mod.app_commands = SimpleNamespace(
            describe=lambda **kwargs: (lambda fn: fn),
            choices=lambda **kwargs: (lambda fn: fn),
            autocomplete=lambda **kwargs: (lambda fn: fn),
            Choice=lambda **kwargs: SimpleNamespace(**kwargs),
            Group=_FakeGroup,
            Command=_FakeCommand,
        )

        ext_mod = MagicMock()
        commands_mod = MagicMock()
        commands_mod.Bot = MagicMock
        ext_mod.commands = commands_mod

        sys.modules["discord"] = discord_mod
        sys.modules.setdefault("discord.ext", ext_mod)
        sys.modules.setdefault("discord.ext.commands", commands_mod)


_ensure_discord_mock()

from gateway.config import PlatformConfig
from plugins.platforms.discord.adapter import DiscordAdapter


def _make_adapter():
    config = PlatformConfig(enabled=True, token="***")
    adapter = DiscordAdapter(config)
    adapter._client = SimpleNamespace(
        tree=_FakeTree(),
        get_channel=lambda _id: None,
        fetch_channel=AsyncMock(),
        user=SimpleNamespace(id=99999, name="HermesBot"),
    )
    adapter._text_batch_delay_seconds = 0
    adapter._check_slash_authorization = AsyncMock(return_value=True)
    return adapter


class _FakeTree:
    def __init__(self):
        self.commands = {}

    def command(self, *, name, description):
        def decorator(fn):
            self.commands[name] = fn
            return fn
        return decorator

    def add_command(self, cmd):
        self.commands[cmd.name] = cmd

    def get_commands(self):
        return [SimpleNamespace(name=n) for n in self.commands]


def _make_interaction(channel=None, channel_id=123):
    return SimpleNamespace(
        channel=channel,
        channel_id=channel_id,
        user=SimpleNamespace(display_name="TestUser", id=42, name="testuser"),
        guild=SimpleNamespace(name="TestGuild"),
        response=SimpleNamespace(defer=AsyncMock()),
        followup=SimpleNamespace(send=AsyncMock()),
    )


def _make_message(author_name, content, is_bot=False, msg_type=0):
    return SimpleNamespace(
        author=SimpleNamespace(display_name=author_name, bot=is_bot, id=1),
        content=content,
        clean_content=content,
        type=msg_type,
        attachments=[],
    )


class _FakeChannel:
    def __init__(self, messages, name="general"):
        self.id = 123
        self.name = name
        self._messages = messages

    async def history(self, *, limit=None, after=None, oldest_first=True):
        for msg in self._messages:
            yield msg


# ------------------------------------------------------------------
# Registration
# ------------------------------------------------------------------


def test_channel_report_command_registered():
    adapter = _make_adapter()
    adapter._register_slash_commands()
    assert "channel-report" in adapter._client.tree.commands


# ------------------------------------------------------------------
# Basic report generation
# ------------------------------------------------------------------


@pytest.mark.asyncio
async def test_basic_report_counts_messages():
    adapter = _make_adapter()
    messages = [
        _make_message("Alice", "hello"),
        _make_message("Alice", "world"),
        _make_message("Bob", "hi there"),
    ]
    channel = _FakeChannel(messages)
    interaction = _make_interaction(channel=channel)

    await adapter._handle_channel_report_slash(interaction, hours=24.0)

    interaction.response.defer.assert_awaited_once()
    interaction.followup.send.assert_awaited_once()
    report = interaction.followup.send.call_args[0][0]
    assert "Alice" in report
    assert "2 msgs" in report
    assert "67%" in report or "66%" in report  # 2/3 ≈ 67%
    assert "Bob" in report
    assert "1 msg" in report
    assert "33%" in report  # 1/3 ≈ 33%
    assert "Total" in report
    assert "3 messages" in report


@pytest.mark.asyncio
async def test_report_sorted_by_count_descending():
    adapter = _make_adapter()
    messages = [
        _make_message("Alice", "a"),
        _make_message("Bob", "b"),
        _make_message("Bob", "c"),
        _make_message("Bob", "d"),
    ]
    channel = _FakeChannel(messages)
    interaction = _make_interaction(channel=channel)

    await adapter._handle_channel_report_slash(interaction, hours=24.0)

    report = interaction.followup.send.call_args[0][0]
    alice_pos = report.index("Alice")
    bob_pos = report.index("Bob")
    # Bob has more messages → ranks first (lower index)
    assert bob_pos < alice_pos


@pytest.mark.asyncio
async def test_empty_channel_sends_no_messages_reply():
    adapter = _make_adapter()
    channel = _FakeChannel([])
    interaction = _make_interaction(channel=channel)

    await adapter._handle_channel_report_slash(interaction, hours=24.0)

    report = interaction.followup.send.call_args[0][0]
    assert "No messages" in report


# ------------------------------------------------------------------
# Bot filtering
# ------------------------------------------------------------------


@pytest.mark.asyncio
async def test_bots_excluded_by_default():
    adapter = _make_adapter()
    messages = [
        _make_message("Alice", "hello"),
        _make_message("SomeBot", "beep boop", is_bot=True),
    ]
    channel = _FakeChannel(messages)
    interaction = _make_interaction(channel=channel)

    await adapter._handle_channel_report_slash(interaction, hours=24.0, include_bots=False)

    report = interaction.followup.send.call_args[0][0]
    assert "Alice" in report
    assert "SomeBot" not in report


@pytest.mark.asyncio
async def test_bots_included_when_flag_set():
    adapter = _make_adapter()
    messages = [
        _make_message("Alice", "hello"),
        _make_message("SomeBot", "beep boop", is_bot=True),
    ]
    channel = _FakeChannel(messages)
    interaction = _make_interaction(channel=channel)

    await adapter._handle_channel_report_slash(interaction, hours=24.0, include_bots=True)

    report = interaction.followup.send.call_args[0][0]
    assert "Alice" in report
    assert "SomeBot [bot]" in report


# ------------------------------------------------------------------
# Ephemeral / public
# ------------------------------------------------------------------


@pytest.mark.asyncio
async def test_report_is_ephemeral_by_default():
    adapter = _make_adapter()
    channel = _FakeChannel([_make_message("Alice", "hi")])
    interaction = _make_interaction(channel=channel)

    await adapter._handle_channel_report_slash(interaction, hours=24.0, public=False)

    # defer should have been called with ephemeral=True
    interaction.response.defer.assert_awaited_once_with(ephemeral=True)
    _, kwargs = interaction.followup.send.call_args
    assert kwargs.get("ephemeral") is True


@pytest.mark.asyncio
async def test_report_is_public_when_requested():
    adapter = _make_adapter()
    channel = _FakeChannel([_make_message("Alice", "hi")])
    interaction = _make_interaction(channel=channel)

    await adapter._handle_channel_report_slash(interaction, hours=24.0, public=True)

    interaction.response.defer.assert_awaited_once_with(ephemeral=False)
    _, kwargs = interaction.followup.send.call_args
    assert kwargs.get("ephemeral") is False


# ------------------------------------------------------------------
# Auth gate
# ------------------------------------------------------------------


@pytest.mark.asyncio
async def test_auth_gate_rejects_unauthorized():
    adapter = _make_adapter()
    adapter._check_slash_authorization = AsyncMock(return_value=False)
    channel = _FakeChannel([_make_message("Alice", "hi")])
    interaction = _make_interaction(channel=channel)

    await adapter._handle_channel_report_slash(interaction)

    interaction.response.defer.assert_not_awaited()
    interaction.followup.send.assert_not_awaited()


# ------------------------------------------------------------------
# Channel fetch fallback
# ------------------------------------------------------------------


@pytest.mark.asyncio
async def test_fetches_channel_when_interaction_channel_is_none():
    adapter = _make_adapter()
    messages = [_make_message("Alice", "hello")]
    channel = _FakeChannel(messages)
    adapter._client.fetch_channel = AsyncMock(return_value=channel)

    interaction = _make_interaction(channel=None, channel_id=999)

    await adapter._handle_channel_report_slash(interaction)

    adapter._client.fetch_channel.assert_awaited_once_with(999)
    report = interaction.followup.send.call_args[0][0]
    assert "Alice" in report


@pytest.mark.asyncio
async def test_fetch_channel_failure_sends_error():
    adapter = _make_adapter()
    adapter._client.fetch_channel = AsyncMock(side_effect=RuntimeError("not found"))
    interaction = _make_interaction(channel=None, channel_id=999)

    await adapter._handle_channel_report_slash(interaction)

    report = interaction.followup.send.call_args[0][0]
    assert "not found" in report
