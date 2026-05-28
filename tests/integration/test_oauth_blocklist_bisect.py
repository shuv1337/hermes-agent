"""Comprehensive Anthropic OAuth content-filter bisect probe.

The existing `test_oauth_content_filter.py` only probes the default CLI
system prompt. When Anthropic silently updates their blocklist, new
triggers slip through that narrow probe because they live in guidance
constants, platform hints, skills prompts, or memory blocks that aren't
in the CLI baseline.

This probe fires a minimal OAuth request against every individual
prompt fragment that `_build_system_prompt()` can emit, so we can pin
down exactly which n-gram Anthropic is targeting this round.

Run:
    pytest -m integration tests/integration/test_oauth_blocklist_bisect.py -v -s
"""

from __future__ import annotations

import time
import uuid
from dataclasses import dataclass
from typing import Callable

import pytest

pytestmark = pytest.mark.integration

USAGE_BLOCK_SIGNAL = "out of extra usage"
PROBE_MODEL = "claude-haiku-4-5"


# --------------------------------------------------------------------------- #
# Shared probe plumbing
# --------------------------------------------------------------------------- #


@dataclass
class ProbeResult:
    label: str
    status: str       # "OK" | "USAGE_BLOCK" | "ERROR:<ExcName>"
    latency: float
    detail: str
    length: int


@pytest.fixture(scope="module")
def oauth_client():
    from agent.anthropic_adapter import (
        _is_oauth_token,
        build_anthropic_client,
        resolve_anthropic_token,
    )

    token = resolve_anthropic_token()
    if not token:
        pytest.skip("No Anthropic token available.")
    if not _is_oauth_token(token):
        pytest.skip("Resolved token is a regular API key, not OAuth.")
    return build_anthropic_client(token)


@pytest.fixture(scope="module")
def real_hermes_home():
    """Path to the user's real ~/.hermes for skills-index probing.

    The autouse ``_hermetic_environment`` fixture redirects ``HERMES_HOME``
    to a temp dir so production code can't read the real one. For live
    blocklist bisects we deliberately opt back in via ``monkeypatch.setenv``
    inside each test.
    """
    import os
    from pathlib import Path
    return Path(os.path.expanduser("~")) / ".hermes"


def _probe(client, system_prompt: str, label: str) -> ProbeResult:
    from agent.anthropic_adapter import build_anthropic_kwargs

    nonce = uuid.uuid4().hex[:8]
    api_messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": f"Reply exactly: pong ({nonce})"},
    ]
    kwargs = build_anthropic_kwargs(
        model=PROBE_MODEL,
        messages=api_messages,
        tools=None,
        max_tokens=32,
        reasoning_config=None,
        is_oauth=True,
    )
    t0 = time.monotonic()
    try:
        client.messages.create(**kwargs)
        latency = time.monotonic() - t0
        return ProbeResult(label, "OK", latency, "", len(system_prompt))
    except Exception as exc:
        latency = time.monotonic() - t0
        msg = str(exc)
        status = "USAGE_BLOCK" if USAGE_BLOCK_SIGNAL in msg else f"ERROR:{type(exc).__name__}"
        return ProbeResult(label, status, latency, msg[:400], len(system_prompt))


def _run_suite(client, cases: list[tuple[str, str]]) -> list[ProbeResult]:
    """Serial execution — concurrent OAuth calls trip 429 noise."""
    results: list[ProbeResult] = []
    for label, prompt in cases:
        res = _probe(client, prompt, label)
        print(
            f"  [{res.status:<22}] {res.latency:5.2f}s  "
            f"len={res.length:>5}  {res.label}"
        )
        if res.status == "USAGE_BLOCK":
            # Short tail so we can see which literal/phrase is at fault
            print(f"        detail: {res.detail[:240]}")
        results.append(res)
        # Modest throttle — avoid 429 while still keeping runtime reasonable
        time.sleep(0.25)
    return results


def _report_blocks(results: list[ProbeResult], where: str) -> None:
    blocked = [r for r in results if r.status == "USAGE_BLOCK"]
    errored = [r for r in results if r.status.startswith("ERROR:")]
    if blocked:
        lines = [
            f"\nAnthropic OAuth blocklist rejected {len(blocked)} prompt(s) "
            f"in {where}:"
        ]
        for r in blocked:
            lines.append(f"  - {r.label} (len={r.length}, {r.latency:.2f}s)")
        pytest.fail("\n".join(lines))
    if errored:
        # Flag non-block errors but don't fail — rate-limits etc. shouldn't
        # mask blocklist results.
        print(f"[warn] {len(errored)} non-block errors in {where}:")
        for r in errored:
            print(f"  - {r.label}: {r.status} — {r.detail[:160]}")


# --------------------------------------------------------------------------- #
# Guidance constants — one fragment at a time
# --------------------------------------------------------------------------- #


def _base_identity() -> str:
    from agent.prompt_builder import DEFAULT_AGENT_IDENTITY
    return DEFAULT_AGENT_IDENTITY


def _wrap(fragment: str) -> str:
    """Minimal valid system prompt that includes the fragment under test."""
    return f"{_base_identity()}\n\n{fragment}"


class TestGuidanceConstants:
    def test_guidance_fragments(self, oauth_client):
        from agent import prompt_builder as pb

        cases: list[tuple[str, str]] = [
            ("DEFAULT_AGENT_IDENTITY",         _base_identity()),
            ("MEMORY_GUIDANCE",                _wrap(pb.MEMORY_GUIDANCE)),
            ("SESSION_SEARCH_GUIDANCE",        _wrap(pb.SESSION_SEARCH_GUIDANCE)),
            ("SKILLS_GUIDANCE",                _wrap(pb.SKILLS_GUIDANCE)),
            ("TOOL_USE_ENFORCEMENT_GUIDANCE",  _wrap(pb.TOOL_USE_ENFORCEMENT_GUIDANCE)),
            ("OPENAI_MODEL_EXECUTION_GUIDANCE",_wrap(pb.OPENAI_MODEL_EXECUTION_GUIDANCE)),
            ("GOOGLE_MODEL_OPERATIONAL_GUIDANCE",
                                               _wrap(pb.GOOGLE_MODEL_OPERATIONAL_GUIDANCE)),
            ("WSL_ENVIRONMENT_HINT",           _wrap(pb.WSL_ENVIRONMENT_HINT)),
        ]
        print("\n── Guidance constants ──")
        results = _run_suite(oauth_client, cases)
        _report_blocks(results, "guidance constants")


# --------------------------------------------------------------------------- #
# Platform hints — one at a time
# --------------------------------------------------------------------------- #


class TestPlatformHints:
    def test_each_platform_hint(self, oauth_client):
        from agent.prompt_builder import PLATFORM_HINTS

        cases = [
            (f"PLATFORM_HINTS[{key!r}]", _wrap(hint))
            for key, hint in sorted(PLATFORM_HINTS.items())
        ]
        print("\n── Platform hints ──")
        results = _run_suite(oauth_client, cases)
        _report_blocks(results, "platform hints")


# --------------------------------------------------------------------------- #
# Full constructed prompt, varied by platform and toolset
# --------------------------------------------------------------------------- #


def _build_full_prompt(
    platform: str,
    *,
    skip_memory: bool = True,
    skip_context_files: bool = True,
) -> str:
    from run_agent import AIAgent

    agent = AIAgent(
        model="anthropic/claude-opus-4.6",
        provider="anthropic",
        platform=platform,
        skip_context_files=skip_context_files,
        skip_memory=skip_memory,
        quiet_mode=True,
        save_trajectories=False,
    )
    prompt = agent._build_system_prompt()
    assert prompt, f"Empty prompt for platform={platform!r}"
    return prompt


class TestFullPromptPerPlatform:
    """Live full-prompt probe for every platform the gateway supports."""

    @pytest.mark.parametrize(
        "platform",
        [
            "cli",
            "telegram",
            "whatsapp",
            "discord",
            "slack",
            "signal",
            "email",
            "sms",
            "cron",
            "bluebubbles",
            "weixin",
            "wecom",
            "qqbot",
        ],
    )
    def test_full_prompt_for_platform(self, oauth_client, platform):
        prompt = _build_full_prompt(platform)
        result = _probe(oauth_client, prompt, f"full_prompt[{platform}]")
        print(
            f"  [{result.status:<22}] {result.latency:5.2f}s  "
            f"len={result.length:>5}  {result.label}"
        )
        if result.status == "USAGE_BLOCK":
            print(f"        detail: {result.detail[:240]}")
            pytest.fail(
                f"Anthropic OAuth edge rejected the full {platform!r} system "
                f"prompt (len={result.length}, {result.latency:.2f}s). "
                f"Detail: {result.detail[:300]}"
            )


# --------------------------------------------------------------------------- #
# Skills system prompt — common trigger surface because it's dynamically built
# --------------------------------------------------------------------------- #


class TestSkillsPrompt:
    def test_skills_prompt_alone(self, oauth_client, tmp_path, monkeypatch):
        from agent.prompt_builder import (
            build_skills_system_prompt,
            clear_skills_system_prompt_cache,
        )

        # Use a minimal synthetic skill dir so the test doesn't depend on the
        # user's real ~/.hermes/skills inventory.
        skills_dir = tmp_path / "skills" / "general" / "demo"
        skills_dir.mkdir(parents=True)
        (skills_dir / "SKILL.md").write_text(
            "---\nname: demo\ndescription: Example skill for probe.\n---\n# Demo\n",
            encoding="utf-8",
        )
        monkeypatch.setenv("HERMES_HOME", str(tmp_path))
        clear_skills_system_prompt_cache(clear_snapshot=True)

        prompt = build_skills_system_prompt(
            available_tools={"skills_list", "skill_view", "skill_manage"},
            available_toolsets={"skills"},
        )
        assert prompt, "build_skills_system_prompt returned empty"

        wrapped = _wrap(prompt)
        result = _probe(oauth_client, wrapped, "build_skills_system_prompt")
        print(
            f"  [{result.status:<22}] {result.latency:5.2f}s  "
            f"len={result.length:>5}  {result.label}"
        )
        if result.status == "USAGE_BLOCK":
            print(f"        detail: {result.detail[:240]}")
            pytest.fail(
                f"Anthropic OAuth edge rejected the skills system prompt "
                f"(len={result.length}). Detail: {result.detail[:300]}"
            )


# --------------------------------------------------------------------------- #
# Real-user skills — probe with the user's actual installed skills index
# --------------------------------------------------------------------------- #


class TestRealInstalledSkills:
    """Probe with the user's real ~/.hermes/skills inventory.

    This is the surface most likely to surface new blocklist entries —
    third-party skill descriptions can contain anything. The autouse
    hermetic fixture points HERMES_HOME at a temp dir; we override it
    here just for this module to hit the real inventory.
    """

    def test_real_skills_prompt(self, oauth_client, real_hermes_home, monkeypatch):
        from agent.prompt_builder import (
            build_skills_system_prompt,
            clear_skills_system_prompt_cache,
        )

        skills_root = real_hermes_home / "skills"
        if not skills_root.exists():
            pytest.skip(f"No skills dir at {skills_root}")

        monkeypatch.setenv("HERMES_HOME", str(real_hermes_home))
        clear_skills_system_prompt_cache(clear_snapshot=True)
        prompt = build_skills_system_prompt(
            available_tools={"skills_list", "skill_view", "skill_manage"},
            available_toolsets={"skills"},
        )
        clear_skills_system_prompt_cache(clear_snapshot=True)  # cleanup

        if not prompt:
            pytest.skip("build_skills_system_prompt returned empty for real HERMES_HOME")

        wrapped = _wrap(prompt)
        result = _probe(oauth_client, wrapped, "real_skills_index")
        print(
            f"  [{result.status:<22}] {result.latency:5.2f}s  "
            f"len={result.length:>5}  {result.label}"
        )
        if result.status == "USAGE_BLOCK":
            print(f"        detail: {result.detail[:240]}")
            pytest.fail(
                f"Real skills index triggered the blocklist "
                f"(len={result.length}). Bisect per-skill via "
                f"TestRealInstalledSkillsBisect. Detail: {result.detail[:300]}"
            )

    def test_real_skills_bisect_per_directory(
        self, oauth_client, real_hermes_home, monkeypatch
    ):
        """If the real index fails, bisect top-level skill directories.

        Builds a fake ``HERMES_HOME/skills`` containing symlinks to each real
        skill dir, one at a time, and probes. Surfaces the offending skill
        directly rather than requiring a manual binary search.
        """
        from agent.prompt_builder import (
            build_skills_system_prompt,
            clear_skills_system_prompt_cache,
        )

        real_skills = real_hermes_home / "skills"
        if not real_skills.exists():
            pytest.skip(f"No real skills dir at {real_skills}")

        # Enumerate every SKILL.md in the real tree.
        skill_paths = sorted(real_skills.rglob("SKILL.md"))
        if not skill_paths:
            pytest.skip("No SKILL.md files found")

        print(f"\n── Per-skill bisect ({len(skill_paths)} skills) ──")

        import tempfile
        from pathlib import Path

        blocked_skills: list[tuple[str, str]] = []
        for skill_md in skill_paths:
            # Mirror this one skill into a temp HERMES_HOME.
            # Real layout: ~/.hermes/skills/<category>/<skill>/SKILL.md
            rel = skill_md.relative_to(real_skills)
            with tempfile.TemporaryDirectory() as tmp:
                tmp_home = Path(tmp)
                (tmp_home / "skills" / rel.parent).mkdir(parents=True, exist_ok=True)
                # Copy SKILL.md (symlinks are fine; text reader follows them)
                (tmp_home / "skills" / rel).symlink_to(skill_md)
                monkeypatch.setenv("HERMES_HOME", str(tmp_home))
                clear_skills_system_prompt_cache(clear_snapshot=True)
                prompt = build_skills_system_prompt(
                    available_tools={"skills_list", "skill_view", "skill_manage"},
                    available_toolsets={"skills"},
                )
                clear_skills_system_prompt_cache(clear_snapshot=True)

            if not prompt:
                continue
            wrapped = _wrap(prompt)
            result = _probe(oauth_client, wrapped, str(rel.parent))
            print(
                f"  [{result.status:<22}] {result.latency:5.2f}s  "
                f"len={result.length:>5}  {result.label}"
            )
            if result.status == "USAGE_BLOCK":
                print(f"        detail: {result.detail[:240]}")
                blocked_skills.append((str(rel.parent), result.detail[:240]))
            time.sleep(0.25)

        if blocked_skills:
            lines = [
                f"{len(blocked_skills)} skill(s) trigger the Anthropic OAuth blocklist:"
            ]
            for name, detail in blocked_skills:
                lines.append(f"  - {name}\n      {detail}")
            pytest.fail("\n".join(lines))


# --------------------------------------------------------------------------- #
# Full prompt + full tool schemas — closest approximation of a real call
# --------------------------------------------------------------------------- #


class TestFullPromptWithTools:
    """Probe with system prompt + every tool schema attached.

    Tool-schema descriptions are another common trigger surface: they are
    long-form prose that ships on every request.
    """

    @pytest.mark.parametrize("platform", ["cli", "telegram", "wecom"])
    def test_prompt_plus_tools(self, oauth_client, platform):
        from model_tools import get_tool_definitions
        from agent.anthropic_adapter import build_anthropic_kwargs

        # Build a rich AIAgent so valid_tool_names is populated and guidance
        # constants are injected.
        prompt = _build_full_prompt(
            platform, skip_memory=True, skip_context_files=True
        )
        tools = get_tool_definitions(quiet_mode=True)
        assert tools, "No tools loaded — is the environment missing everything?"

        nonce = uuid.uuid4().hex[:8]
        api_messages = [
            {"role": "system", "content": prompt},
            {"role": "user", "content": f"Reply exactly: pong ({nonce})"},
        ]
        kwargs = build_anthropic_kwargs(
            model=PROBE_MODEL,
            messages=api_messages,
            tools=tools,
            max_tokens=32,
            reasoning_config=None,
            is_oauth=True,
        )
        t0 = time.monotonic()
        try:
            oauth_client.messages.create(**kwargs)
            latency = time.monotonic() - t0
            status = "OK"
            detail = ""
        except Exception as exc:
            latency = time.monotonic() - t0
            msg = str(exc)
            status = (
                "USAGE_BLOCK" if USAGE_BLOCK_SIGNAL in msg
                else f"ERROR:{type(exc).__name__}"
            )
            detail = msg[:400]

        print(
            f"\n  [{status:<22}] {latency:5.2f}s  platform={platform}  "
            f"tools={len(tools)}  prompt_len={len(prompt)}"
        )
        if status == "USAGE_BLOCK":
            print(f"        detail: {detail[:240]}")
            pytest.fail(
                f"Full prompt + tools for platform={platform!r} triggered "
                f"the blocklist. Bisect tool schemas next."
            )


class TestToolSchemasOnly:
    """Strip to per-tool: if the previous test failed, attach one tool at a
    time with a minimal system prompt to find the offender."""

    def test_each_tool_schema_alone(self, oauth_client):
        from model_tools import get_tool_definitions
        from agent.anthropic_adapter import build_anthropic_kwargs

        tools = get_tool_definitions(quiet_mode=True)
        if not tools:
            pytest.skip("No tools loaded")

        print(f"\n── Per-tool schema bisect ({len(tools)} tools) ──")

        sys_prompt = _base_identity()
        blocked: list[tuple[str, str]] = []
        for tool in tools:
            name = tool.get("function", {}).get("name", "?")
            nonce = uuid.uuid4().hex[:8]
            api_messages = [
                {"role": "system", "content": sys_prompt},
                {"role": "user", "content": f"Reply exactly: pong ({nonce})"},
            ]
            kwargs = build_anthropic_kwargs(
                model=PROBE_MODEL,
                messages=api_messages,
                tools=[tool],
                max_tokens=32,
                reasoning_config=None,
                is_oauth=True,
            )
            t0 = time.monotonic()
            try:
                oauth_client.messages.create(**kwargs)
                latency = time.monotonic() - t0
                status = "OK"
                detail = ""
            except Exception as exc:
                latency = time.monotonic() - t0
                msg = str(exc)
                status = (
                    "USAGE_BLOCK" if USAGE_BLOCK_SIGNAL in msg
                    else f"ERROR:{type(exc).__name__}"
                )
                detail = msg[:400]

            print(
                f"  [{status:<22}] {latency:5.2f}s  tool={name}"
            )
            if status == "USAGE_BLOCK":
                print(f"        detail: {detail[:240]}")
                blocked.append((name, detail[:240]))
            time.sleep(0.2)

        if blocked:
            lines = [
                f"{len(blocked)} tool(s) trigger the Anthropic OAuth blocklist:"
            ]
            for name, detail in blocked:
                lines.append(f"  - {name}\n      {detail}")
            pytest.fail("\n".join(lines))
