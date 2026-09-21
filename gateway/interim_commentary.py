"""Low-frequency commentary delivery, separate from the turn's final-response target."""

import asyncio
from typing import Any, Callable

from agent.interrupt_compat import _accepts_keyword
from gateway.platforms.base import next_edit_target_message_id


class InterimCommentaryDelivery:
    """Serialize one editable commentary bubble; a broken chain leaves the final unaffected."""

    def __init__(self, adapter: Any, chat_id: str, *, edit_enabled: bool = False,
                 run_still_current: Callable[[], bool] | None = None):
        self.adapter = adapter
        self.chat_id = chat_id
        self.edit_enabled = edit_enabled
        self.message_id: str | None = None
        self._failed_closed = False
        self._run_still_current = run_still_current or (lambda: True)
        self._lock = asyncio.Lock()

    async def deliver(self, text: str, *, metadata: dict | None = None,
                      reply_to: str | None = None) -> tuple[bool, bool]:
        """Return (delivered, created_message); edits do not reset the tool-progress bubble."""
        async with self._lock:
            if self._failed_closed or not self._run_still_current():
                return False, False
            if self.edit_enabled and self.message_id is not None:
                kwargs = dict(chat_id=self.chat_id, message_id=self.message_id, content=text)
                if _accepts_keyword(self.adapter.edit_message, "finalize"):
                    kwargs["finalize"] = False
                if metadata and _accepts_keyword(self.adapter.edit_message, "metadata"):
                    kwargs["metadata"] = metadata
                # An exception may follow remote acceptance. Reusing an uncertain timestamp
                # can corrupt the chain, so later commentary remains quiet.
                try:
                    result = await self.adapter.edit_message(**kwargs)
                except Exception:
                    self._failed_closed = True
                    raise
                if not getattr(result, "success", False):
                    self._failed_closed = True
                    return False, False
                next_id = next_edit_target_message_id(self.adapter, self.message_id, result)
                if (getattr(self.adapter, "EDIT_RESULT_ID_IS_NEXT_TARGET", False) is True
                        and next_id == self.message_id):
                    self._failed_closed = True
                    return False, False
                self.message_id = next_id
                return True, False
            result = await self.adapter.send(
                chat_id=self.chat_id, content=text, reply_to=reply_to, metadata=metadata,
            )
            if not getattr(result, "success", False):
                return False, False
            if self.edit_enabled:
                message_id = getattr(result, "message_id", None)
                if message_id:
                    self.message_id = str(message_id)
                # A split send cannot later be replaced by editing only its final chunk.
                if not message_id or getattr(result, "continuation_message_ids", ()):
                    self._failed_closed = True
            return True, True
