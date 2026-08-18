"""Contract tests for the Hermes Go Apple Health gateway plugin."""

from __future__ import annotations

import importlib
import json
import sys
from pathlib import Path

import pytest


@pytest.fixture
def apple_health(monkeypatch):
    plugin_root = Path(__file__).parents[2] / "apps" / "mobile" / "hermes_plugin"
    monkeypatch.syspath_prepend(str(plugin_root))
    for name in [key for key in sys.modules if key == "apple_health" or key.startswith("apple_health.")]:
        sys.modules.pop(name, None)
    return importlib.import_module("apple_health")


def test_summary_schema_exposes_required_bounded_arguments(apple_health):
    schema = apple_health._SUMMARY_SCHEMA

    assert schema["name"] == "apple_health_summary"
    assert set(schema["parameters"]["required"]) == {"start", "end", "metrics"}
    assert schema["parameters"]["properties"]["metrics"]["minItems"] == 1
    assert "SLEEP_*" in schema["description"]


def test_summary_handler_refuses_an_unbounded_all_metrics_dump(apple_health):
    result = json.loads(apple_health._summary_handler({}))

    assert "required" in result["error"]
    assert isinstance(result["available_metrics"], list)


def test_summary_handler_passes_explicit_sleep_bounds(apple_health, monkeypatch):
    captured = {}

    def fake_summary(start, end, metrics):
        captured.update(start=start, end=end, metrics=metrics)
        return {"sample_count": 30}

    monkeypatch.setattr(apple_health, "summary", fake_summary)
    result = json.loads(apple_health._summary_handler({
        "start": "2026-08-16T18:00:00-05:00",
        "end": "2026-08-17T12:00:00-05:00",
        "metrics": ["SLEEP_DEEP", "SLEEP_REM"],
    }))

    assert result == {"sample_count": 30}
    assert captured == {
        "start": "2026-08-16T18:00:00-05:00",
        "end": "2026-08-17T12:00:00-05:00",
        "metrics": ["SLEEP_DEEP", "SLEEP_REM"],
    }
