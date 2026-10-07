"""Who owns which Workspace Events subscription, and who is listening to it."""

import asyncio
from dataclasses import dataclass, asdict

# Notices waiting for one slow client before the oldest are dropped.
QUEUE_LIMIT = 100


@dataclass(frozen=True)
class Notice:
    type: str
    subject: str
    resource: str | None
    time: str

    def as_dict(self) -> dict:
        return asdict(self)


# Put in a client's queue when notices were dropped; the client refreshes.
RESYNC = object()


class Hub:
    def __init__(self) -> None:
        # Workspace Events subscription name -> Google user ID that owns it.
        self._owners: dict[str, str] = {}
        self._listeners: dict[str, set[asyncio.Queue]] = {}

    def claim(self, subscription: str, user: str) -> bool:
        """Binds a subscription to the first user who connects with it."""
        owner = self._owners.setdefault(subscription, user)
        return owner == user

    def listen(self, subscription: str) -> asyncio.Queue:
        queue: asyncio.Queue = asyncio.Queue(maxsize=QUEUE_LIMIT)
        self._listeners.setdefault(subscription, set()).add(queue)
        return queue

    def unlisten(self, subscription: str, queue: asyncio.Queue) -> None:
        listeners = self._listeners.get(subscription)
        if listeners is None:
            return
        listeners.discard(queue)
        if not listeners:
            del self._listeners[subscription]

    def listener_count(self) -> int:
        return sum(len(q) for q in self._listeners.values())

    def publish(self, subscription: str, notice: Notice) -> int:
        """Gives the notice to every client of the subscription. Returns how many."""
        listeners = self._listeners.get(subscription, set())
        for queue in listeners:
            if queue.full():
                # Drop the backlog and tell the client to refresh instead.
                while not queue.empty():
                    queue.get_nowait()
                queue.put_nowait(RESYNC)
            queue.put_nowait(notice)
        return len(listeners)
