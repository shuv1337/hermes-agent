"""Root-installed mobile plugins are discoverable with profile-local precedence."""

from hermes_constants import get_hermes_home, set_hermes_home_override, reset_hermes_home_override
from hermes_cli.plugins_discovery import collect_directory_manifests


def _plugin(home, name):
    directory = home / 'plugins' / name
    directory.mkdir(parents=True)
    (directory / 'plugin.yaml').write_text(f'name: {name}\nversion: 0.1.0\n')
    (directory / '__init__.py').write_text('def register(ctx):\n    pass\n')
    return directory


def test_profile_discovers_root_install_and_local_override():
    root = get_hermes_home()
    profile = root / 'profiles' / 'coach'
    root_copy = _plugin(root, 'apple-health')
    local_copy = _plugin(profile, 'apple-health')
    _plugin(root, 'root-only-fixture')
    token = set_hermes_home_override(profile)
    try:
        manifests = collect_directory_manifests()
    finally:
        reset_hermes_home_override(token)
    assert any(item.name == 'root-only-fixture' for item in manifests)
    assert [item.path for item in manifests if item.name == 'apple-health'] == [str(root_copy), str(local_copy)]


def test_default_profile_does_not_scan_same_install_twice():
    root_copy = _plugin(get_hermes_home(), 'apple-health')
    manifests = collect_directory_manifests()
    assert [item.path for item in manifests if item.name == 'apple-health'] == [str(root_copy)]
