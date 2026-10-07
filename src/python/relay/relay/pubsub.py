"""Reads the Pub/Sub subscription and hands each event to the hub."""

import asyncio
import logging

import httpx
from google.auth.transport import requests as google_requests
from google.oauth2 import service_account

from . import events
from .hub import Hub

log = logging.getLogger("relay.pubsub")

SCOPE = "https://www.googleapis.com/auth/pubsub"
API = "https://pubsub.googleapis.com/v1"


class PubSubReader:
    """Pulls from one Pub/Sub subscription and acknowledges every message.

    The relay keeps no queue: an event for a client that is not connected is
    acknowledged and lost. Clients refresh when they connect, so they catch up.
    """

    def __init__(self, subscription: str, credentials_file: str, hub: Hub):
        self._subscription = subscription
        self._hub = hub
        self._credentials = service_account.Credentials.from_service_account_file(
            credentials_file, scopes=[SCOPE])
        self._request = google_requests.Request()

    async def _token(self) -> str:
        if not self._credentials.valid:
            await asyncio.to_thread(self._credentials.refresh, self._request)
        return self._credentials.token

    async def run(self) -> None:
        delay = 1.0
        async with httpx.AsyncClient(timeout=90) as client:
            while True:
                try:
                    await self._pull_once(client)
                    delay = 1.0
                except asyncio.CancelledError:
                    raise
                except Exception:
                    log.exception("Pub/Sub pull failed; retrying in %.0f s", delay)
                    await asyncio.sleep(delay)
                    delay = min(delay * 2, 60)

    async def _pull_once(self, client: httpx.AsyncClient) -> None:
        headers = {"Authorization": f"Bearer {await self._token()}"}
        response = await client.post(
            f"{API}/{self._subscription}:pull", headers=headers, json={"maxMessages": 100})
        response.raise_for_status()
        received = response.json().get("receivedMessages", [])
        if not received:
            return
        ack_ids = []
        for item in received:
            ack_ids.append(item["ackId"])
            parsed = events.parse(item.get("message", {}))
            if parsed is None:
                continue
            subscription, notice = parsed
            delivered = self._hub.publish(subscription, notice)
            log.info("%s for %s: %d client(s)", notice.type, subscription, delivered)
        response = await client.post(
            f"{API}/{self._subscription}:acknowledge", headers=headers, json={"ackIds": ack_ids})
        response.raise_for_status()
