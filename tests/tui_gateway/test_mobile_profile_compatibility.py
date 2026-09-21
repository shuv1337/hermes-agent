"""Hermes Go restores sessions and capabilities from their owning profile."""

import pytest
import yaml

from hermes_constants import get_hermes_home, set_hermes_home_override, reset_hermes_home_override
from hermes_state import SessionDB
from tui_gateway import server


@pytest.fixture
def profile_stores(monkeypatch):
    root = get_hermes_home()
    launch = SessionDB(root / 'state.db')
    monkeypatch.setattr(server, '_get_db', lambda: launch)
    homes = {}
    for name in ('coach', 'other'):
        home = root / 'profiles' / name
        home.mkdir(parents=True)
        homes[name] = home
        SessionDB(home / 'state.db').close()
    yield root, launch, homes
    launch.close()


def _store(home, session_id):
    db = SessionDB(home / 'state.db')
    try:
        db.create_session(session_id=session_id, source='mobile')
    finally:
        db.close()


def test_resume_recovers_unique_owner_using_real_profile_stores(profile_stores):
    root, launch, homes = profile_stores
    _store(homes['coach'], 'mobile-bot')
    before = (homes['coach'] / 'state.db').read_bytes()
    ctx = server._Resume('test', {'session_id': 'mobile-bot'}, 'mobile-bot')
    assert (ctx.profile, ctx.profile_home) == ('coach', homes['coach'])
    assert launch.get_session('mobile-bot') is None
    assert (homes['coach'] / 'state.db').read_bytes() == before


def test_resume_owner_inference_refuses_ambiguous_id(profile_stores):
    _, _, homes = profile_stores
    for home in homes.values():
        _store(home, 'same-id')
    ctx = server._Resume('test', {'session_id': 'same-id'}, 'same-id')
    assert ctx.profile is None
    assert ctx.profile_home is None


def test_resume_owner_inference_keeps_launch_owner(profile_stores):
    _, launch, homes = profile_stores
    launch.create_session(session_id='same-id', source='mobile')
    _store(homes['coach'], 'same-id')
    assert server._infer_profile_for_session_id('same-id') is None


def test_resume_owner_inference_respects_explicit_profile(profile_stores, monkeypatch):
    _, _, homes = profile_stores
    _store(homes['coach'], 'mobile-bot')
    def refuse_inference(_target):
        pytest.fail('Explicit profile must not infer a different owner')
    monkeypatch.setattr(server, '_infer_profile_for_session_id', refuse_inference)
    ctx = server._Resume('test', {'profile': 'other'}, 'mobile-bot')
    assert (ctx.profile, ctx.profile_home) == ('other', homes['other'])


def test_resume_owner_inference_refuses_unreadable_store(profile_stores):
    _, _, homes = profile_stores
    _store(homes['coach'], 'mobile-bot')
    (homes['other'] / 'state.db').write_bytes(b'not a sqlite database')
    assert server._infer_profile_for_session_id('mobile-bot') is None


def test_profile_capability_pin_wins_over_coding_posture(profile_stores, monkeypatch):
    _, _, homes = profile_stores
    import agent.coding_context as coding
    monkeypatch.delenv('HERMES_TUI_TOOLSETS', raising=False)
    (homes['coach'] / 'config.yaml').write_text(yaml.safe_dump({
        'tools': {'enabled_toolsets': ['web', 'apple_health']},
        'mcp_servers': {'example': {'command': 'unused-fixture', 'enabled': True}},
    }))
    monkeypatch.setattr(coding, 'coding_selection', lambda **kwargs: ['coding'])
    token = set_hermes_home_override(homes['coach'])
    try:
        selected = server._load_enabled_toolsets('mobile')
    finally:
        reset_hermes_home_override(token)
    assert set(selected) == {'web', 'apple_health', 'example', 'project'}


def test_profile_capability_pin_survives_plugin_discovery_failure(profile_stores, monkeypatch):
    _, _, homes = profile_stores
    import agent.coding_context as coding
    import hermes_cli.plugins as plugins
    monkeypatch.delenv('HERMES_TUI_TOOLSETS', raising=False)
    (homes['coach'] / 'config.yaml').write_text(yaml.safe_dump({
        'tools': {'enabled_toolsets': ['apple_health']},
    }))
    def broken_discovery():
        raise PermissionError('unreadable plugin directory')
    monkeypatch.setattr(plugins, 'discover_plugins', broken_discovery)
    monkeypatch.setattr(coding, 'coding_selection', lambda **kwargs: ['coding'])
    token = set_hermes_home_override(homes['coach'])
    try:
        assert server._load_enabled_toolsets('mobile') == ['apple_health', 'project']
    finally:
        reset_hermes_home_override(token)
