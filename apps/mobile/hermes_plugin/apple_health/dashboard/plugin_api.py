"""Authenticated Hermes Go ingestion routes."""

from __future__ import annotations

import importlib.util
from pathlib import Path
from typing import Any

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

_storage_path = Path(__file__).resolve().parents[1] / "storage.py"
_spec = importlib.util.spec_from_file_location("hermes_go_apple_health_storage", _storage_path)
if _spec is None or _spec.loader is None:
    raise RuntimeError("Unable to load Apple Health storage")
storage = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(storage)

router = APIRouter()


class SyncBody(BaseModel):
    schema_version: int = 1
    device_id: str = Field(min_length=1, max_length=200)
    batch_id: str = Field(min_length=1, max_length=200)
    app_version: str | None = Field(default=None, max_length=80)
    samples: list[dict[str, Any]] = Field(max_length=5000)


@router.get("/status")
def health_status():
    return storage.status()


@router.post("/sync")
def health_sync(body: SyncBody):
    if body.schema_version != 1:
        raise HTTPException(status_code=400, detail="Unsupported schema version")
    return storage.ingest(device_id=body.device_id, batch_id=body.batch_id,
                          app_version=body.app_version, samples=body.samples)


@router.get("/summary")
def health_summary(start: str, end: str, metrics: str | None = None):
    selected = [m.strip() for m in metrics.split(",")] if metrics else None
    return storage.summary(start, end, selected)


@router.delete("/data")
def health_clear():
    return {"ok": True, "deleted": storage.clear()}

