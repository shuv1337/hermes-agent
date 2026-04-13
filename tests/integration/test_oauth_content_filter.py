"""Live OAuth content-filter regression test for Anthropic Claude Code auth.

Anthropic's Claude Code OAuth edge has a content blocklist of specific
n-grams. When the system prompt contains one, the request is rejected at the
edge BEFORE reaching the model with a misleading 400:

  Error code: 400 - {'type': 'error', 'error': {'type': 'invalid_request_error',
    'message': "You're out of extra usage. Add more at claude.ai/settings/usage
    and keep going."}}

The error message lies — the account is NOT usage-capped. A sub-200ms failure
latency is the giveaway. Known trigger patterns were identified in April 2026
(see AGENTS.md → Known Pitfalls → 'DO NOT write literal tool-call syntax in
system-prompt prose').

This test sends the REAL constructed Hermes system prompt through the same
build_anthropic_client + build_anthropic_kwargs(is_oauth=True) pipeline used
in production and asserts it does not get rejected. The static guard in
tests/agent/test_prompt_builder.py::TestAnthropicOAuthBlocklistGuard catches
known literals at source-edit time; this test is the live counterpart that
catches NEW patterns Anthropic adds to their blocklist over time.

Marked `integration` so it does not run in the default `addopts = -m 'not
integration'` suite. Run explicitly with:

    pytest -m integration tests/integration/test_oauth_content_filter.py -v

Skips automatically when no Anthropic OAuth token is resolvable, so it is
safe to run on machines without Claude Code credentials.
"""

import uuid

import pytest

pytestmark = pytest.mark.integration

USAGE_BLOCK_SIGNAL = "out of extra usage"
EDGE_REJECT_LATENCY_S = 0.25


@pytest.fixture(scope="module")
def oauth_token():
    """Resolve an Anthropic OAuth token; skip the module if none is available."""
    from agent.anthropic_adapter import _is_oauth_token, resolve_anthropic_token

    token = resolve_anthropic_token()
    if not token:
        pytest.skip("No Anthropic token available — skipping OAuth content filter tests")
    if not _is_oauth_token(token):
        pytest.skip(
            "Resolved Anthropic token is a regular API key, not OAuth — "
            "the edge content filter only applies to OAuth/setup-token auth"
        )
    return token


@pytest.fixture(scope="module")
def oauth_client(oauth_token):
    """A real Anthropic SDK client wired for OAuth."""
    from agent.anthropic_adapter import build_anthropic_client

    return build_anthropic_client(oauth_token)


@pytest.fixture(scope="module")
def real_hermes_system_prompt():
    """Build the actual constructed Hermes system prompt for an Anthropic call."""
    from run_agent import AIAgent

    agent = AIAgent(
        model="anthropic/claude-opus-4.6",
        provider="anthropic",
        platform="cli",
        skip_context_files=False,
        skip_memory=True,
        quiet_mode=True,
        save_trajectories=False,
        persist_session=False,
    )
    prompt = agent._build_system_prompt()
    assert prompt and len(prompt) > 1000, (
        f"Real Hermes system prompt looks empty/truncated ({len(prompt)} chars) — "
        f"AIAgent setup may be broken"
    )
    return prompt


def _send_oauth_probe(client, system_prompt: str, model: str) -> tuple[str, float, str]:
    """Send a minimal OAuth request and classify the response."""
    import time

    from agent.anthropic_adapter import build_anthropic_kwargs

    nonce = uuid.uuid4().hex[:8]
    api_messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": f"Reply with exactly: pong ({nonce})"},
    ]
    kwargs = build_anthropic_kwargs(
        model=model,
        messages=api_messages,
        tools=None,
        max_tokens=32,
        reasoning_config=None,
        is_oauth=True,
    )

    t0 = time.monotonic()
    try:
        resp = client.messages.create(**kwargs)
        latency = time.monotonic() - t0
        text_parts = [b.text for b in resp.content if getattr(b, "type", "") == "text"]
        detail = "".join(text_parts)[:120]
        return "OK", latency, detail
    except Exception as e:
        latency = time.monotonic() - t0
        msg = str(e)
        if USAGE_BLOCK_SIGNAL in msg:
            return "USAGE_BLOCK", latency, msg[:300]
        return f"ERROR:{type(e).__name__}", latency, msg[:300]


class TestOAuthContentFilter:
    def test_real_hermes_prompt_not_blocked_on_haiku(
        self, oauth_client, real_hermes_system_prompt
    ):
        status, latency, detail = _send_oauth_probe(
            oauth_client, real_hermes_system_prompt, "claude-haiku-4-5"
        )

        if status == "USAGE_BLOCK":
            pytest.fail(
                f"Anthropic OAuth edge rejected the real Hermes system prompt "
                f"with the 'out of extra usage' content-filter signal "
                f"(latency {latency:.2f}s). Raw error: {detail}"
            )

        assert status == "OK", (
            f"OAuth probe failed with unexpected status {status!r} "
            f"(latency {latency:.2f}s): {detail}"
        )
        assert latency > EDGE_REJECT_LATENCY_S, (
            f"Suspiciously fast OK response ({latency:.2f}s). The edge filter "
            f"normally rejects in <200ms while real inference takes >250ms."
        )

    def test_minimal_oauth_control_succeeds(self, oauth_client):
        status, latency, detail = _send_oauth_probe(
            oauth_client,
            "You are a helpful assistant. Answer concisely.",
            "claude-haiku-4-5",
        )
        assert status == "OK", (
            f"Minimal control prompt failed with {status!r} ({latency:.2f}s): "
            f"{detail}"
        )
