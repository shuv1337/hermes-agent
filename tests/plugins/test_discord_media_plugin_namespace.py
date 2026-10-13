"""Media delivery must use the SDK state of the loaded platform plugin."""

import asyncio
import builtins
import importlib
import sys
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from gateway.config import PlatformConfig
from hermes_cli.plugins import PluginManager
from hermes_cli.plugins_manifest import PluginManifest


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "method,extension,delivery",
    [(method, extension, delivery)
     for method, extension in [
         ("send_image_file", ".png"), ("send_voice", ".mp3"),
         ("send_document", ".txt"), ("send_video", ".mp4"),
     ] for delivery in ["direct", "cron"]]
    + [("send_image", ".png", "direct"), ("send_animation", ".gif", "direct"),
       ("send_multiple_images", ".png", "direct")],
)
async def test_namespaced_plugin_delivers_media_after_sdk_becomes_available(
    monkeypatch, tmp_path, method, extension, delivery,
):
    pytest.importorskip("discord")
    # The first import predates the optional SDK installation. Real plugin
    # discovery later imports a separate, profile-scoped adapter module.
    for name in list(sys.modules):
        if name == "plugins.platforms.discord" or name.startswith("plugins.platforms.discord."):
            monkeypatch.delitem(sys.modules, name)
    original_import = builtins.__import__

    def without_discord(name, *args, **kwargs):
        if name == "discord" or name.startswith("discord."):
            raise ImportError("SDK not yet installed")
        return original_import(name, *args, **kwargs)

    with monkeypatch.context() as early_import:
        early_import.setattr(builtins, "__import__", without_discord)
        stale = importlib.import_module("plugins.platforms.discord.adapter")
    assert stale.discord is None

    plugin_dir = Path(__file__).resolve().parents[2] / "plugins/platforms/discord"
    manifest = PluginManifest(
        name="discord-platform", key="platforms/discord", kind="platform",
        source="bundled", path=str(plugin_dir),
    )
    manager = PluginManager(scope_key=str(tmp_path))
    plugin = manager._load_directory_module(manifest)
    loaded = sys.modules[f"{plugin.__name__}.adapter"]
    assert loaded.DISCORD_AVAILABLE
    sdk = loaded.discord
    channel = SimpleNamespace(id=555, guild=None)
    files = []

    async def accept_attachment(**kwargs):
        attachment = (kwargs.get("files") or [kwargs.get("file")])[0]
        assert isinstance(attachment, sdk.File)
        assert attachment.fp.read() == b"synthetic attachment"
        files.append(attachment)
        return SimpleNamespace(
            id=123, attachments=[SimpleNamespace(filename=attachment.filename)],
        )

    channel.send = AsyncMock(side_effect=accept_attachment)
    # Force native-voice rejection to exercise its ordinary file fallback too.
    client = SimpleNamespace(http=SimpleNamespace(
        request=AsyncMock(side_effect=RuntimeError("native voice unsupported")),
    ))
    adapter = loaded.DiscordAdapter(PlatformConfig(enabled=True, token="synthetic"))
    adapter._client = client
    adapter._resolve_channel = AsyncMock(return_value=channel)
    media = tmp_path / f"brief{extension}"
    media.write_bytes(b"synthetic attachment")
    monkeypatch.setattr(loaded, "is_safe_url", lambda url: True)
    monkeypatch.setattr(
        loaded, "_read_url_image_with_redirect_guard",
        AsyncMock(return_value=(200, b"synthetic attachment", {"content-type": "image/png"})),
    )
    try:
        if delivery == "cron":
            from cron.scheduler_delivery import _send_media_via_adapter

            # The real scheduler runs in its worker and dispatches onto the
            # gateway loop. No model job or network delivery is triggered.
            errors = await asyncio.to_thread(
                _send_media_via_adapter, adapter, "555", [(str(media), False)],
                None, asyncio.get_running_loop(), {"id": "synthetic-brief"},
            )
            assert not errors, errors
        else:
            argument = ([(f"file://{media}", "")]
                        if method == "send_multiple_images" else
                        "https://example.com/fixture.png"
                        if method in {"send_image", "send_animation"} else str(media))
            result = await getattr(adapter, method)("555", argument)
            assert result.success, result.error
            assert result.message_id == "123" or method == "send_multiple_images"
        assert len(files) == 1
    finally:
        for attachment in files:
            attachment.close()
