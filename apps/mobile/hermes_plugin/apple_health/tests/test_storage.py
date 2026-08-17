from __future__ import annotations

import importlib.util
import json
from pathlib import Path


def _load():
    path = Path(__file__).resolve().parents[1] / "storage.py"
    spec = importlib.util.spec_from_file_location("apple_health_storage_test", path)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


def test_ingest_is_idempotent_and_queryable(tmp_path):
    storage = _load()
    storage.DEFAULT_DB = tmp_path / "health.sqlite3"
    sample = {
        "uuid": "sample-1", "type": "STEPS",
        "dateFrom": "2026-08-16T10:00:00Z", "dateTo": "2026-08-16T11:00:00Z",
        "value": {"numericValue": 1234}, "unit": "count",
    }
    first = storage.ingest(device_id="phone", batch_id="batch-1", app_version="20", samples=[sample])
    again = storage.ingest(device_id="phone", batch_id="batch-1", app_version="20", samples=[sample])
    assert first["accepted"] == 1
    assert again["duplicate"] is True
    result = storage.summary("2026-08-16T00:00:00Z", "2026-08-17T00:00:00Z", ["steps"])
    assert result["sample_count"] == 1
    assert result["metrics"]["STEPS"][0]["value"]["numericValue"] == 1234


def test_ingest_accepts_expanded_health_categories(tmp_path):
    storage = _load()
    storage.DEFAULT_DB = tmp_path / "health.sqlite3"
    samples = [
        {
            "uuid": f"sample-{kind}", "type": kind,
            "dateFrom": "2026-08-16T10:00:00Z",
            "dateTo": "2026-08-16T10:01:00Z",
            "value": {"numericValue": 1},
        }
        for kind in (
            "BLOOD_OXYGEN", "RESPIRATORY_RATE", "LEAN_BODY_MASS",
            "SLEEP_WRIST_TEMPERATURE", "DIETARY_ENERGY_CONSUMED",
        )
    ]

    result = storage.ingest(
        device_id="phone", batch_id="expanded", app_version="29",
        samples=samples,
    )

    assert result["accepted"] == len(samples)
