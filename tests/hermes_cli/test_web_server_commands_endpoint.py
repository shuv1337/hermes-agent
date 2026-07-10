"""Tests for GET /api/commands -- the slash-command registry cheat sheet.

Serializes hermes_cli.commands.COMMAND_REGISTRY for the mobile app's
command cheat-sheet feature.
"""

import pytest


def _client():
    try:
        from starlette.testclient import TestClient
    except ImportError:
        pytest.skip("fastapi/starlette not installed")
    import hermes_state
    from hermes_constants import get_hermes_home
    from hermes_cli.web_server import app, _SESSION_HEADER_NAME, _SESSION_TOKEN

    client = TestClient(app)
    client.headers[_SESSION_HEADER_NAME] = _SESSION_TOKEN
    hermes_state.DEFAULT_DB_PATH = get_hermes_home() / "state.db"
    return client, _SESSION_HEADER_NAME


class TestCommandsEndpoint:
    @pytest.fixture(autouse=True)
    def _setup(self, _isolate_hermes_home):
        self.client, self.header = _client()

    def test_returns_full_registry(self):
        from hermes_cli.commands import COMMAND_REGISTRY

        r = self.client.get("/api/commands")
        assert r.status_code == 200
        body = r.json()
        assert body["total"] == len(COMMAND_REGISTRY)
        assert len(body["commands"]) == body["total"]

    def test_known_commands_present_with_expected_shape(self):
        r = self.client.get("/api/commands")
        assert r.status_code == 200
        by_name = {c["name"]: c for c in r.json()["commands"]}
        for name in ("new", "model", "usage"):
            assert name in by_name
            cmd = by_name[name]
            assert isinstance(cmd["description"], str) and cmd["description"]
            assert isinstance(cmd["category"], str) and cmd["category"]
            assert isinstance(cmd["aliases"], list)
            assert isinstance(cmd["cli_only"], bool)
            assert isinstance(cmd["gateway_only"], bool)
            assert isinstance(cmd["config_gated"], bool)
