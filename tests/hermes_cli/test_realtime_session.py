"""Tests for the realtime voice ephemeral-token endpoint.

`POST /api/realtime/session` mints a short-lived OpenAI Realtime
``client_secret`` server-side. The full OpenAI key (``VOICE_TOOLS_OPENAI_KEY``)
must stay on the backend and never appear in the response — these tests pin
that contract and the local-vs-OpenAI request shape.
"""

import json

import pytest


# A recognisable sentinel so we can assert the raw key is never leaked back to
# the renderer in any response body.
SENTINEL_KEY = "sk-voice-tools-SENTINEL-DO-NOT-LEAK-0123456789"


class _FakeRealtimeResponse:
    """Stand-in for an ``httpx.Response`` from the client_secrets endpoint."""

    def __init__(self, status_code=200, payload=None, text=None):
        self.status_code = status_code
        self._payload = payload if payload is not None else {}
        self.text = text if text is not None else json.dumps(self._payload)

    def json(self):
        return self._payload


class _CapturingAsyncClient:
    """Fake ``httpx.AsyncClient`` that records the outgoing request and returns
    a scripted response. Configured per-test via class attributes."""

    captured: list = []
    response = _FakeRealtimeResponse(200, {"value": "ek_test_EPHEMERAL", "expires_at": 1999999999})

    def __init__(self, *args, **kwargs):
        pass

    async def __aenter__(self):
        return self

    async def __aexit__(self, *args):
        return False

    async def post(self, url, headers=None, json=None, **kwargs):  # noqa: A002 - mirror httpx kwarg
        type(self).captured.append({"url": url, "headers": headers or {}, "json": json or {}})
        return type(self).response


class TestRealtimeSessionEndpoint:
    """Exercise ``POST /api/realtime/session`` with the OpenAI mint mocked."""

    @pytest.fixture(autouse=True)
    def _setup_test_client(self, monkeypatch):
        from starlette.testclient import TestClient
        from hermes_cli.web_server import app, _SESSION_HEADER_NAME, _SESSION_TOKEN

        self.client = TestClient(app)
        self.client.headers[_SESSION_HEADER_NAME] = _SESSION_TOKEN

        # Reset the fake client between tests (class-level state).
        _CapturingAsyncClient.captured = []
        _CapturingAsyncClient.response = _FakeRealtimeResponse(
            200, {"value": "ek_test_EPHEMERAL", "expires_at": 1999999999}
        )

    def test_default_config_has_realtime_block(self):
        """The pinned realtime defaults live in DEFAULT_CONFIG."""
        from hermes_cli.config import DEFAULT_CONFIG

        rt = DEFAULT_CONFIG["realtime"]
        assert rt["model"] == "gpt-realtime-2"
        assert rt["reasoning_effort"] == "low"
        assert rt["turn_detection"] == "server_vad"
        assert "voice" in rt
        assert isinstance(rt["max_session_sec"], int)
        assert isinstance(rt["idle_timeout_ms"], int)

    def test_missing_key_returns_503(self, monkeypatch):
        """With no VOICE_TOOLS_OPENAI_KEY the endpoint is unavailable (fallback)."""
        monkeypatch.delenv("VOICE_TOOLS_OPENAI_KEY", raising=False)
        # load_env() reads the (empty, tmp) hermes home, so this is the only key source.
        resp = self.client.post("/api/realtime/session")
        assert resp.status_code == 503
        assert SENTINEL_KEY not in resp.text

    def test_mints_token_without_leaking_key(self, monkeypatch):
        """Happy path: returns the ephemeral token + metadata, never the key."""
        import httpx

        monkeypatch.setenv("VOICE_TOOLS_OPENAI_KEY", SENTINEL_KEY)
        monkeypatch.setattr(
            "hermes_cli.web_server.load_config",
            lambda: {
                "realtime": {
                    "model": "gpt-realtime-2",
                    "voice": "cedar",
                    "reasoning_effort": "low",
                    "turn_detection": "server_vad",
                    "max_session_sec": 240,
                    "idle_timeout_ms": 15000,
                    "delegation_model": "google/gemini-3.1-flash-lite",
                    "delegation_provider": "",
                }
            },
        )
        monkeypatch.setattr(httpx, "AsyncClient", _CapturingAsyncClient)

        resp = self.client.post("/api/realtime/session")
        assert resp.status_code == 200

        body = resp.json()
        assert body["client_secret"] == "ek_test_EPHEMERAL"
        assert body["model"] == "gpt-realtime-2"
        assert body["voice"] == "cedar"
        assert body["expires_at"] == 1999999999
        # Non-secret guard knobs are passed through for the renderer to enforce.
        assert body["turn_detection"] == "server_vad"
        assert body["max_session_sec"] == 240
        assert body["idle_timeout_ms"] == 15000
        # Per-turn delegation model override is surfaced to the renderer.
        assert body["delegation_model"] == "google/gemini-3.1-flash-lite"
        assert body["delegation_provider"] == ""

        # The raw key must NEVER cross back to the renderer.
        assert SENTINEL_KEY not in resp.text

        # ...but it IS used server-side to authenticate the mint, and the
        # session config we send upstream reflects the realtime.* config block.
        cap = _CapturingAsyncClient.captured
        assert len(cap) == 1
        assert cap[0]["url"].endswith("/v1/realtime/client_secrets")
        assert cap[0]["headers"]["Authorization"] == f"Bearer {SENTINEL_KEY}"
        session = cap[0]["json"]["session"]
        assert session["type"] == "realtime"
        assert session["model"] == "gpt-realtime-2"
        assert session["audio"]["output"]["voice"] == "cedar"
        # The live client_secrets endpoint rejects session.reasoning_effort, so
        # it must NOT be forwarded even when configured (gpt-realtime-2 defaults
        # to low effort regardless).
        assert "reasoning_effort" not in session

    def test_reasoning_effort_never_sent_to_mint(self, monkeypatch):
        """reasoning_effort is never forwarded to client_secrets (it 400s there)."""
        import httpx

        monkeypatch.setenv("VOICE_TOOLS_OPENAI_KEY", SENTINEL_KEY)
        monkeypatch.setattr(
            "hermes_cli.web_server.load_config",
            lambda: {"realtime": {"model": "gpt-realtime-2", "voice": "marin", "reasoning_effort": "high"}},
        )
        monkeypatch.setattr(httpx, "AsyncClient", _CapturingAsyncClient)

        resp = self.client.post("/api/realtime/session")
        assert resp.status_code == 200
        session = _CapturingAsyncClient.captured[0]["json"]["session"]
        assert "reasoning_effort" not in session

    def test_upstream_error_returns_502_without_echoing_body(self, monkeypatch):
        """A 4xx/5xx from OpenAI becomes a generic 502 — no upstream body leak."""
        import httpx

        monkeypatch.setenv("VOICE_TOOLS_OPENAI_KEY", SENTINEL_KEY)
        _CapturingAsyncClient.response = _FakeRealtimeResponse(
            401, {"error": {"message": "invalid api key"}}, text='{"error":{"message":"invalid api key"}}'
        )
        monkeypatch.setattr(httpx, "AsyncClient", _CapturingAsyncClient)

        resp = self.client.post("/api/realtime/session")
        assert resp.status_code == 502
        assert "invalid api key" not in resp.text
        assert SENTINEL_KEY not in resp.text

    def test_malformed_mint_response_returns_502(self, monkeypatch):
        """A 200 with no usable client_secret is reported as malformed."""
        import httpx

        monkeypatch.setenv("VOICE_TOOLS_OPENAI_KEY", SENTINEL_KEY)
        _CapturingAsyncClient.response = _FakeRealtimeResponse(200, {"unexpected": "shape"})
        monkeypatch.setattr(httpx, "AsyncClient", _CapturingAsyncClient)

        resp = self.client.post("/api/realtime/session")
        assert resp.status_code == 502

    def test_non_dict_mint_response_returns_502(self, monkeypatch):
        """A valid-JSON but non-object 200 body must be a clean 502, not a 500."""
        import httpx

        monkeypatch.setenv("VOICE_TOOLS_OPENAI_KEY", SENTINEL_KEY)
        # e.g. a proxy/CDN returning a JSON array or string with HTTP 200.
        _CapturingAsyncClient.response = _FakeRealtimeResponse(200, ["ek_not_an_object"])
        monkeypatch.setattr(httpx, "AsyncClient", _CapturingAsyncClient)

        resp = self.client.post("/api/realtime/session")
        assert resp.status_code == 502
