"""Tests for Anthropic OAuth mcp tool-name round-tripping.

Anthropic's OAuth edge rejects tool names matching ``^mcp_[a-z0-9_]+$`` with a
misleading quota error. Current requests avoid that blocklist by capitalizing the
first character after ``mcp_`` while keeping names reversible. The response-side
suite also preserves compatibility with the older ``mcp__`` wire encoding.
"""

from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import patch


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_tool_use_block(name: str, block_id: str = "tc_1", input_data: dict | None = None):
    """Create a fake Anthropic tool_use content block."""
    return SimpleNamespace(
        type="tool_use",
        id=block_id,
        name=name,
        input=input_data or {"query": "test"},
    )


def _make_response(*blocks, stop_reason="end_turn"):
    """Create a fake Anthropic Messages response."""
    return SimpleNamespace(
        content=list(blocks),
        stop_reason=stop_reason,
        model="claude-sonnet-4",
        usage=SimpleNamespace(input_tokens=100, output_tokens=50),
    )


class _FakeRegistry:
    """Minimal fake tool registry for testing prefix round-trip logic."""

    def __init__(self, registered_names: set[str]):
        self._names = registered_names

    def get_entry(self, name: str):
        if name in self._names:
            return SimpleNamespace(name=name)  # truthy = tool exists
        return None

    def get_all_tool_names(self):
        # Used by the transport's OAuth tool-name decoder to disambiguate
        # canonical Hermes vs MCP-style names.
        return list(self._names)


# ---------------------------------------------------------------------------
# Response side: mcp__ wire name -> registry name
# ---------------------------------------------------------------------------

class TestAnthropicMcpPrefixStrip:
    """Verify strip_tool_prefix reverses the ``mcp__`` wire prefix correctly."""

    def _get_transport(self):
        from agent.transports.anthropic import AnthropicTransport
        return AnthropicTransport()

    def test_strips_prefix_for_oauth_injected_native_tool(self):
        """``mcp__read_file`` -> ``read_file`` (bare native tool)."""
        transport = self._get_transport()
        block = _make_tool_use_block("mcp__read_file")
        response = _make_response(block)

        registry = _FakeRegistry({"read_file", "terminal", "web_search"})
        with patch("tools.registry.registry", registry):
            result = transport.normalize_response(response, strip_tool_prefix=True)

        assert len(result.tool_calls) == 1
        assert result.tool_calls[0].name == "read_file"

    def test_restores_single_underscore_mcp_server_tool(self):
        """``mcp__linear_get_issue`` -> ``mcp_linear_get_issue`` (MCP server tool).

        MCP server tools are registered under their full single-underscore
        ``mcp_<server>_<tool>`` name, but they MUST go on the OAuth wire as
        double-underscore to dodge the classifier.  The response side restores
        the single-underscore registry name so dispatch still resolves.
        """
        transport = self._get_transport()
        block = _make_tool_use_block("mcp__linear_get_issue")
        response = _make_response(block)

        registry = _FakeRegistry({"mcp_linear_get_issue", "read_file"})
        with patch("tools.registry.registry", registry):
            result = transport.normalize_response(response, strip_tool_prefix=True)

        assert len(result.tool_calls) == 1
        assert result.tool_calls[0].name == "mcp_linear_get_issue"

    def test_no_strip_when_flag_false(self):
        """When strip_tool_prefix=False, names are never modified."""
        transport = self._get_transport()
        block = _make_tool_use_block("mcp__read_file")
        response = _make_response(block)

        registry = _FakeRegistry({"read_file"})
        with patch("tools.registry.registry", registry):
            result = transport.normalize_response(response, strip_tool_prefix=False)

        assert len(result.tool_calls) == 1
        assert result.tool_calls[0].name == "mcp__read_file"

    def test_no_strip_when_not_mcp_prefixed(self):
        """Non-``mcp__`` names are untouched regardless of strip flag."""
        transport = self._get_transport()
        block = _make_tool_use_block("web_search")
        response = _make_response(block)

        registry = _FakeRegistry({"web_search"})
        with patch("tools.registry.registry", registry):
            result = transport.normalize_response(response, strip_tool_prefix=True)

        assert len(result.tool_calls) == 1
        assert result.tool_calls[0].name == "web_search"

    def test_preserves_name_when_no_original_in_registry(self):
        """Neither the single-underscore nor bare original is registered.

        Safety fallback: keep the full ``mcp__`` name the LLM was told about.
        """
        transport = self._get_transport()
        block = _make_tool_use_block("mcp__unknown_tool")
        response = _make_response(block)

        registry = _FakeRegistry({"read_file"})  # no matching original
        with patch("tools.registry.registry", registry):
            result = transport.normalize_response(response, strip_tool_prefix=True)

        assert len(result.tool_calls) == 1
        assert result.tool_calls[0].name == "mcp__unknown_tool"

    def test_mixed_native_and_mcp_server_tools_same_response(self):
        """A bare native tool and an MCP server tool, both wired as ``mcp__``."""
        transport = self._get_transport()
        block1 = _make_tool_use_block("mcp__read_file", block_id="tc_1")
        block2 = _make_tool_use_block("mcp__linear_get_issue", block_id="tc_2")
        response = _make_response(block1, block2)

        registry = _FakeRegistry({"read_file", "mcp_linear_get_issue"})
        with patch("tools.registry.registry", registry):
            result = transport.normalize_response(response, strip_tool_prefix=True)

        assert len(result.tool_calls) == 2
        assert result.tool_calls[0].name == "read_file"
        assert result.tool_calls[1].name == "mcp_linear_get_issue"

    def test_prefers_full_wire_name_when_it_resolves_directly(self):
        """If the ``mcp__`` wire name itself is registered, keep it as-is.

        Defensive: never rewrite a name that already resolves natively.
        """
        transport = self._get_transport()
        block = _make_tool_use_block("mcp__foo")
        response = _make_response(block)

        registry = _FakeRegistry({"foo", "mcp__foo"})
        with patch("tools.registry.registry", registry):
            result = transport.normalize_response(response, strip_tool_prefix=True)

        assert len(result.tool_calls) == 1
        assert result.tool_calls[0].name == "mcp__foo"


# ---------------------------------------------------------------------------
# Request side: registry name -> capitalized mcp_ wire name (blocklist-safe)
# ---------------------------------------------------------------------------

class TestAnthropicOAuthOutgoingPrefix:
    """build_anthropic_kwargs must emit names outside Anthropic's OAuth
    ``^mcp_[a-z0-9_]+$`` blocklist while preserving reversible names."""

    def _build(self, tools, is_oauth=True):
        from agent.anthropic_adapter import build_anthropic_kwargs
        return build_anthropic_kwargs(
            model="claude-sonnet-4-6",
            messages=[{"role": "user", "content": "Hi"}],
            tools=tools,
            max_tokens=4096,
            reasoning_config=None,
            is_oauth=is_oauth,
        )

    def test_oauth_capitalizes_bare_tool_name(self):
        """OAuth + bare name -> ``mcp_`` prefix with capitalized suffix."""
        kwargs = self._build([{
            "type": "function",
            "function": {"name": "read_file", "description": "x", "parameters": {}},
        }])
        assert [t["name"] for t in kwargs["tools"]] == ["mcp_Read_file"]

    def test_oauth_capitalizes_single_underscore_mcp_server_tool(self):
        """OAuth + ``mcp_<server>_<tool>`` -> capitalized after prefix.

        MCP server tools must not be skipped and left as all-lowercase
        ``mcp_...`` names that match Anthropic's OAuth blocklist.
        """
        kwargs = self._build([{
            "type": "function",
            "function": {
                "name": "mcp_linear_get_issue",
                "description": "x",
                "parameters": {},
            },
        }])
        names = [t["name"] for t in kwargs["tools"]]
        assert names == ["mcp_Linear_get_issue"]

    def test_oauth_already_double_prefixed_left_alone(self):
        """OAuth + already-``mcp__`` name -> unchanged (no triple underscore)."""
        kwargs = self._build([{
            "type": "function",
            "function": {"name": "mcp__already", "description": "x", "parameters": {}},
        }])
        assert [t["name"] for t in kwargs["tools"]] == ["mcp__already"]

    def test_oauth_no_blocklisted_mcp_name_on_wire(self):
        """Mixed set: every wire name avoids the OAuth mcp_ blocklist."""
        from agent.anthropic_adapter import _OAUTH_BLOCKED_TOOL_NAME_RE

        kwargs = self._build([
            {"type": "function", "function": {"name": "read_file",
                                              "description": "x", "parameters": {}}},
            {"type": "function", "function": {"name": "mcp_linear_get_issue",
                                              "description": "y", "parameters": {}}},
            {"type": "function", "function": {"name": "terminal",
                                              "description": "z", "parameters": {}}},
        ])
        names = sorted(t["name"] for t in kwargs["tools"])
        assert names == ["mcp_Linear_get_issue", "mcp_Read_file", "mcp_Terminal"]
        for n in names:
            assert not _OAUTH_BLOCKED_TOOL_NAME_RE.match(n)

    def test_non_oauth_path_untouched(self):
        """Non-OAuth requests never get the prefix — schemas pass through as-is."""
        kwargs = self._build([
            {"type": "function", "function": {"name": "read_file",
                                              "description": "x", "parameters": {}}},
            {"type": "function", "function": {"name": "mcp_linear_get_issue",
                                              "description": "y", "parameters": {}}},
        ], is_oauth=False)
        names = sorted(t["name"] for t in kwargs["tools"])
        assert names == ["mcp_linear_get_issue", "read_file"]
