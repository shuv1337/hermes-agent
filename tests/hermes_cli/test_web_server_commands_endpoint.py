"""Authenticated mobile command cheat sheet follows the shared registry."""

from fastapi.testclient import TestClient


def test_commands_endpoint_serializes_registry_and_requires_auth():
    from hermes_cli.commands import COMMAND_REGISTRY
    from hermes_cli.web_server import app, _SESSION_HEADER_NAME, _SESSION_TOKEN

    client = TestClient(app)
    unauthorized = client.get('/api/commands')
    assert unauthorized.status_code in (401, 403)
    response = client.get('/api/commands', headers={_SESSION_HEADER_NAME: _SESSION_TOKEN})
    assert response.status_code == 200
    body = response.json()
    assert body['total'] == len(body['commands']) == len(COMMAND_REGISTRY)
    assert body['commands'] == [
        {
            'name': command.name, 'description': command.description,
            'category': command.category, 'aliases': list(command.aliases),
            'args_hint': command.args_hint, 'cli_only': command.cli_only,
            'gateway_only': command.gateway_only,
            'config_gated': command.gateway_config_gate is not None,
        }
        for command in COMMAND_REGISTRY
    ]
