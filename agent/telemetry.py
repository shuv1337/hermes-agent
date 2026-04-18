"""Maple OTEL telemetry wiring for hermes-agent.

Zero-config: reads MAPLE_INGEST_URL + MAPLE_INGEST_KEY from the environment.
If either is missing, init_telemetry() becomes a silent no-op so the gateway
boots fine on machines without a local Maple stack.

What it instruments out of the box:
    • HTTP via httpx, requests, aiohttp (catches every LLM call + web tool)
    • AIAgent.run_conversation → one trace per user turn
    • handle_function_call   → child span per tool call

Design:
    • Singleton init — safe to call multiple times
    • Exporter errors throttled so a down Maple doesn't spam journalctl
    • Service name defaults to "hermes-gateway" but caller can override
"""

from __future__ import annotations

import logging
import os
import threading
from typing import Optional

_initialized = False
_init_lock = threading.Lock()
_tracer = None
_logger = logging.getLogger(__name__)


def _getenv(name: str, default: Optional[str] = None) -> Optional[str]:
    value = os.environ.get(name)
    return value.strip() if value and value.strip() else default


def _silence_otel_export_warnings() -> None:
    """Throttle OTEL exporter error logs so a down Maple doesn't spam journalctl."""
    noisy = [
        "opentelemetry.exporter.otlp.proto.http.trace_exporter",
        "opentelemetry.exporter.otlp.proto.http._log_exporter",
        "opentelemetry.sdk.trace.export",
    ]
    for name in noisy:
        logging.getLogger(name).setLevel(logging.ERROR)


def init_telemetry(
    service_name: str = "hermes-gateway",
    extra_resource_attrs: Optional[dict] = None,
) -> bool:
    """Bootstrap OTEL SDK + auto-instrumentations pointing at local Maple.

    Returns True if telemetry was wired, False if env vars missing or init failed.

    Env overrides (for multi-instance deployments — shuvdev, shuvbot, nick, etc.):
        HERMES_SERVICE_NAME  — override service.name without code changes
        HERMES_INSTANCE      — deployment.instance (default: hostname)
        HERMES_OWNER         — agent.owner (e.g. "shuv", "nick")
        HERMES_ENV           — deployment.environment (default: "local")
    """
    global _initialized, _tracer

    with _init_lock:
        if _initialized:
            return _tracer is not None

        ingest_url = _getenv("MAPLE_INGEST_URL", "http://127.0.0.1:3474")
        ingest_key = _getenv("MAPLE_INGEST_KEY")

        if not ingest_key:
            _logger.debug("Maple telemetry disabled (no MAPLE_INGEST_KEY set)")
            _initialized = True
            return False

        # Env override for per-instance naming. Default caller-supplied name.
        service_name = _getenv("HERMES_SERVICE_NAME", service_name)

        try:
            import socket as _socket
            from opentelemetry import trace
            from opentelemetry.exporter.otlp.proto.http.trace_exporter import (
                OTLPSpanExporter,
            )
            from opentelemetry.sdk.resources import Resource
            from opentelemetry.sdk.trace import TracerProvider
            from opentelemetry.sdk.trace.export import BatchSpanProcessor

            hostname = _socket.gethostname()
            instance = _getenv("HERMES_INSTANCE", hostname)
            owner = _getenv("HERMES_OWNER")

            resource_attrs = {
                "service.name": service_name,
                "service.namespace": "hermes",
                "deployment.environment": _getenv("HERMES_ENV", "local"),
                "deployment.instance": instance,
                "host.name": hostname,
            }
            if owner:
                resource_attrs["agent.owner"] = owner
            if extra_resource_attrs:
                resource_attrs.update(extra_resource_attrs)

            resource = Resource.create(resource_attrs)
            headers = {"Authorization": f"Bearer {ingest_key}"}

            provider = TracerProvider(resource=resource)
            provider.add_span_processor(
                BatchSpanProcessor(
                    OTLPSpanExporter(
                        endpoint=f"{ingest_url}/v1/traces",
                        headers=headers,
                    ),
                    max_export_batch_size=256,
                    schedule_delay_millis=2_000,
                )
            )
            trace.set_tracer_provider(provider)
            _tracer = trace.get_tracer("hermes")

            _install_auto_instrumentations()
            _patch_agent_loop()

            _silence_otel_export_warnings()
            _logger.info(
                "Maple telemetry active (service=%s → %s)", service_name, ingest_url
            )
            _initialized = True
            return True

        except Exception as exc:
            _logger.warning("Maple telemetry init failed: %s", exc)
            _initialized = True
            _tracer = None
            return False


def _install_auto_instrumentations() -> None:
    """Turn on auto-instrumentation for common HTTP clients.

    Excludes the Maple ingest endpoint so the exporter's own HTTP POSTs
    don't create self-referential spans.
    """
    # httpx + requests both accept a comma-separated URL-suppress list via env.
    # Set this BEFORE instrumenting so the instrumentors pick it up.
    ingest_host = ""
    try:
        import urllib.parse as _u

        ingest_host = _u.urlparse(_getenv("MAPLE_INGEST_URL", "")).netloc
    except Exception:
        pass
    # Noisy polling URLs — each of these fires on a loop regardless of user
    # activity, so they dominate the trace list without carrying signal.
    # The instrumentors accept comma-separated substring matches (not regex),
    # matched against the full URL.
    polling_noise = [
        "api.telegram.org/.*getUpdates",
        "api.telegram.org/.*sendChatAction",
        "api.telegram.org/.*editMessageText",
        "discord.com/api/.*typing",
        # Honcho health/card probes fire on every turn; keep the interesting
        # context/chat/search calls but drop repetitive lookups.
        "/health",
    ]
    pieces = [ingest_host or "maple-ingest-gateway"] + polling_noise
    existing = os.environ.get("OTEL_PYTHON_HTTPX_EXCLUDED_URLS", "")
    merged = ",".join(p for p in ([existing] + pieces) if p)
    os.environ["OTEL_PYTHON_HTTPX_EXCLUDED_URLS"] = merged
    os.environ["OTEL_PYTHON_REQUESTS_EXCLUDED_URLS"] = merged

    try:
        from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
        HTTPXClientInstrumentor().instrument()
    except Exception as exc:
        _logger.debug("httpx instrumentation skipped: %s", exc)

    try:
        from opentelemetry.instrumentation.requests import RequestsInstrumentor
        RequestsInstrumentor().instrument()
    except Exception as exc:
        _logger.debug("requests instrumentation skipped: %s", exc)

    try:
        from opentelemetry.instrumentation.aiohttp_client import (
            AioHttpClientInstrumentor,
        )
        AioHttpClientInstrumentor().instrument()
    except Exception as exc:
        _logger.debug("aiohttp instrumentation skipped: %s", exc)


def _patch_agent_loop() -> None:
    """Wrap handle_function_call + AIAgent.run_conversation for spans.

    Monkey-patch keeps instrumentation self-contained —
    run_agent.py is ~11k lines and we don't want to edit it directly.
    """
    from opentelemetry import trace
    from opentelemetry.trace import Status, StatusCode

    tracer = trace.get_tracer("hermes.agent")

    # --- handle_function_call ---
    try:
        import model_tools

        original_hfc = model_tools.handle_function_call

        def traced_handle_function_call(function_name, function_args, *args, **kwargs):
            with tracer.start_as_current_span(
                f"tool.{function_name}",
                attributes={
                    "tool.name": function_name,
                    "tool.arg_count": len(function_args or {}),
                    "hermes.task_id": kwargs.get("task_id") or "",
                    "hermes.session_id": kwargs.get("session_id") or "",
                },
            ) as span:
                try:
                    result = original_hfc(function_name, function_args, *args, **kwargs)
                    try:
                        if isinstance(result, str) and '"error"' in result[:64]:
                            span.set_status(Status(StatusCode.ERROR))
                            span.set_attribute("tool.error", True)
                    except Exception:
                        pass
                    return result
                except Exception as exc:
                    span.record_exception(exc)
                    span.set_status(Status(StatusCode.ERROR, str(exc)))
                    raise

        model_tools.handle_function_call = traced_handle_function_call  # type: ignore[assignment]
    except Exception as exc:
        _logger.debug("handle_function_call patch skipped: %s", exc)

    # --- AIAgent.run_conversation ---
    try:
        import run_agent

        original_rc = run_agent.AIAgent.run_conversation

        def traced_run_conversation(self, user_message, *args, **kwargs):
            with tracer.start_as_current_span(
                "agent.run_conversation",
                attributes={
                    "agent.model": getattr(self, "model", "unknown"),
                    "agent.provider": getattr(self, "provider", "unknown"),
                    "agent.platform": getattr(self, "platform", "unknown"),
                    "hermes.task_id": kwargs.get("task_id") or "",
                    "user.message.length": len(user_message or ""),
                },
            ) as span:
                try:
                    result = original_rc(self, user_message, *args, **kwargs)
                    try:
                        if isinstance(result, dict):
                            span.set_attribute(
                                "agent.messages.count", len(result.get("messages", []))
                            )
                            span.set_attribute(
                                "agent.final_response.length",
                                len(str(result.get("final_response", ""))),
                            )
                    except Exception:
                        pass
                    return result
                except Exception as exc:
                    span.record_exception(exc)
                    span.set_status(Status(StatusCode.ERROR, str(exc)))
                    raise

        run_agent.AIAgent.run_conversation = traced_run_conversation  # type: ignore[assignment]
    except Exception as exc:
        _logger.debug("run_conversation patch skipped: %s", exc)

    # --- AIAgent._interruptible_api_call (non-streaming LLM) ---
    # Wrap the actual inference call so we get model/provider/token counts
    # as first-class attributes. The auto-httpx span only shows the POST URL.
    try:
        import run_agent

        original_call = run_agent.AIAgent._interruptible_api_call

        def traced_api_call(self, api_kwargs, *args, **kwargs):
            return _run_llm_traced(
                tracer,
                self,
                api_kwargs,
                lambda: original_call(self, api_kwargs, *args, **kwargs),
                streaming=False,
            )

        run_agent.AIAgent._interruptible_api_call = traced_api_call  # type: ignore[assignment]
    except Exception as exc:
        _logger.debug("_interruptible_api_call patch skipped: %s", exc)

    # --- AIAgent._interruptible_streaming_api_call (streaming LLM) ---
    try:
        import run_agent

        if hasattr(run_agent.AIAgent, "_interruptible_streaming_api_call"):
            original_stream = run_agent.AIAgent._interruptible_streaming_api_call

            def traced_stream_call(self, api_kwargs, *args, **kwargs):
                return _run_llm_traced(
                    tracer,
                    self,
                    api_kwargs,
                    lambda: original_stream(self, api_kwargs, *args, **kwargs),
                    streaming=True,
                )

            run_agent.AIAgent._interruptible_streaming_api_call = traced_stream_call  # type: ignore[assignment]
    except Exception as exc:
        _logger.debug("_interruptible_streaming_api_call patch skipped: %s", exc)


def _run_llm_traced(tracer, agent, api_kwargs, call_fn, streaming: bool):
    """Shared wrapper for both streaming and non-streaming LLM calls."""
    from opentelemetry.trace import Status, StatusCode
    import time as _time

    model = None
    try:
        model = api_kwargs.get("model")
    except Exception:
        pass
    provider = getattr(agent, "provider", None)
    api_mode = getattr(agent, "api_mode", None)

    # Rough token estimate from messages for requests that never complete.
    msg_chars = 0
    try:
        for m in api_kwargs.get("messages", []) or []:
            c = m.get("content") if isinstance(m, dict) else None
            if isinstance(c, str):
                msg_chars += len(c)
            elif isinstance(c, list):
                for part in c:
                    if isinstance(part, dict):
                        msg_chars += len(str(part.get("text") or part.get("content") or ""))
    except Exception:
        pass

    attrs = {
        "llm.model": str(model) if model else "unknown",
        "llm.provider": str(provider) if provider else "unknown",
        "llm.api_mode": str(api_mode) if api_mode else "unknown",
        "llm.streaming": streaming,
        "llm.prompt.chars": msg_chars,
    }
    t0 = _time.monotonic()
    with tracer.start_as_current_span("llm.call", attributes=attrs) as span:
        try:
            response = call_fn()
            dur = _time.monotonic() - t0
            span.set_attribute("llm.duration_ms", int(dur * 1000))
            _annotate_llm_response(span, response, agent=agent)
            return response
        except Exception as exc:
            span.record_exception(exc)
            span.set_status(Status(StatusCode.ERROR, str(exc)[:400]))
            raise


def _annotate_llm_response(span, response, *, agent=None) -> None:
    """Pull token counts + cost + finish reason off an LLM response object.

    Uses agent.usage_pricing.normalize_usage() — the same code path the agent
    uses internally — so Anthropic, Codex Responses, and OpenAI Chat
    Completions shapes all produce the same canonical buckets.

    Emits:
        llm.tokens.input, llm.tokens.output, llm.tokens.total
        llm.tokens.cache_read, llm.tokens.cache_write, llm.tokens.reasoning
        llm.cost_usd (when pricing is known for the model)
        llm.response.model, llm.finish_reason
    """
    try:
        usage_obj = getattr(response, "usage", None)
        if usage_obj is None and isinstance(response, dict):
            usage_obj = response.get("usage")

        if usage_obj is not None:
            try:
                from agent.usage_pricing import normalize_usage, estimate_usage_cost

                provider = getattr(agent, "provider", None) if agent else None
                api_mode = getattr(agent, "api_mode", None) if agent else None
                canonical = normalize_usage(
                    usage_obj, provider=provider, api_mode=api_mode
                )

                total = (
                    canonical.input_tokens
                    + canonical.output_tokens
                    + canonical.cache_read_tokens
                    + canonical.cache_write_tokens
                )
                span.set_attribute("llm.tokens.input", canonical.input_tokens)
                span.set_attribute("llm.tokens.output", canonical.output_tokens)
                span.set_attribute("llm.tokens.cache_read", canonical.cache_read_tokens)
                span.set_attribute("llm.tokens.cache_write", canonical.cache_write_tokens)
                span.set_attribute("llm.tokens.reasoning", canonical.reasoning_tokens)
                span.set_attribute("llm.tokens.total", total)

                # Cost estimation — silently skip if model unknown.
                try:
                    model_name = None
                    resp_model = getattr(response, "model", None)
                    if isinstance(resp_model, str):
                        model_name = resp_model
                    elif agent is not None:
                        model_name = getattr(agent, "model", None)
                    if model_name:
                        base_url = None
                        if agent is not None:
                            base_url = getattr(agent, "base_url", None) or getattr(
                                agent, "_anthropic_base_url", None
                            )
                        cost = estimate_usage_cost(
                            model_name,
                            canonical,
                            provider=provider,
                            base_url=base_url,
                        )
                        if cost is not None:
                            span.set_attribute("llm.cost_usd", float(cost))
                except Exception:
                    pass
            except Exception:
                # normalize_usage import failed or raised — fall back to best-effort.
                for src_key, dst_key in (
                    ("prompt_tokens", "llm.tokens.input"),
                    ("input_tokens", "llm.tokens.input"),
                    ("completion_tokens", "llm.tokens.output"),
                    ("output_tokens", "llm.tokens.output"),
                    ("total_tokens", "llm.tokens.total"),
                ):
                    v = getattr(usage_obj, src_key, None)
                    if v is None and isinstance(usage_obj, dict):
                        v = usage_obj.get(src_key)
                    if isinstance(v, (int, float)):
                        span.set_attribute(dst_key, int(v))

        # Response model name (post-rewrite by the provider)
        resp_model = getattr(response, "model", None)
        if isinstance(resp_model, str):
            span.set_attribute("llm.response.model", resp_model)
        # First choice finish reason for OpenAI-compatible responses
        choices = getattr(response, "choices", None)
        if choices and len(choices) > 0:
            fr = getattr(choices[0], "finish_reason", None)
            if isinstance(fr, str):
                span.set_attribute("llm.finish_reason", fr)
        # Anthropic stop_reason
        stop_reason = getattr(response, "stop_reason", None)
        if isinstance(stop_reason, str):
            span.set_attribute("llm.finish_reason", stop_reason)
    except Exception:
        pass


def get_tracer():
    """Return the Hermes tracer (None if telemetry isn't initialized)."""
    return _tracer


def shutdown() -> None:
    """Flush pending spans before exit."""
    try:
        from opentelemetry import trace

        provider = trace.get_tracer_provider()
        if hasattr(provider, "shutdown"):
            provider.shutdown()
    except Exception:
        pass
