"""Hermes Go Apple Health tools."""

from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone

from .storage import status, summary


def _available() -> bool:
    return bool(status()["available"])


def _status_handler(args: dict, **_: object) -> str:
    return json.dumps(status())


def _summary_handler(args: dict, **_: object) -> str:
    end = str(args.get("end") or datetime.now(timezone.utc).isoformat())
    start = str(args.get("start") or (datetime.now(timezone.utc) - timedelta(days=7)).isoformat())
    metrics = args.get("metrics")
    return json.dumps(summary(start, end, metrics if isinstance(metrics, list) else None))


def register(ctx) -> None:
    ctx.register_tool(
        name="apple_health_status",
        toolset="apple_health",
        description="Check whether Hermes Go has synced Apple Health data and which metrics are available.",
        schema={"type": "object", "properties": {}, "required": []},
        handler=_status_handler,
        check_fn=_available,
        emoji="❤️",
    )
    ctx.register_tool(
        name="apple_health_summary",
        toolset="apple_health",
        description="Read Apple Health samples for a bounded date range. Use for health coaching and trend analysis; do not diagnose medical conditions.",
        schema={
            "type": "object",
            "properties": {
                "start": {"type": "string", "description": "Inclusive ISO-8601 start; defaults to 7 days ago."},
                "end": {"type": "string", "description": "Exclusive ISO-8601 end; defaults to now."},
                "metrics": {"type": "array", "items": {"type": "string"}, "description": "Optional metric names from apple_health_status."},
            },
            "required": [],
        },
        handler=_summary_handler,
        check_fn=_available,
        emoji="📈",
    )

