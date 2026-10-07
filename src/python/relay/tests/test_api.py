import asyncio
import json

import httpx

from relay.hub import Hub, Notice
from relay.main import create_app

from .conftest import FakeVerifier

URL = "/v1/events?subscription=subscriptions/chat-spaces-abc"


def make_client(config, hub=None):
    app = create_app(verifier=FakeVerifier(), hub=hub or Hub(), config=config, keepalive_seconds=0.05)
    return app, httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://relay")


async def test_healthz_reports_version(config):
    _, client = make_client(config)
    async with client:
        response = await client.get("/healthz")
    assert response.json() == {"status": "ok", "version": "abc1234 2026-10-06"}


async def test_rejects_bad_requests(config):
    hub = Hub()
    hub.claim("subscriptions/chat-spaces-abc", "alice")
    _, client = make_client(config, hub)
    async with client:
        bad_name = await client.get("/v1/events?subscription=spaces/x", headers=auth("bob"))
        no_token = await client.get(URL)
        bad_token = await client.get(URL, headers={"Authorization": "Bearer nonsense"})
        wrong_domain = await client.get(URL, headers={"Authorization": "Bearer bob:other.com:60"})
        not_owner = await client.get(URL, headers=auth("bob"))
    assert bad_name.status_code == 400
    assert no_token.status_code == 401
    assert bad_token.status_code == 401
    assert wrong_domain.status_code == 403
    assert not_owner.status_code == 403
    assert not_owner.json()["detail"] == "another user owns this subscription"


def auth(user: str, seconds: float = 60) -> dict:
    return {"Authorization": f"Bearer {user}:example.com:{seconds}"}


async def test_streams_notices_until_the_token_expires(config):
    hub = Hub()
    app, client = make_client(config, hub)
    async with client:
        # ASGITransport returns the body when the stream ends, which happens
        # when the 0.5 second token expires.
        request = asyncio.create_task(client.get(URL, headers=auth("alice", 0.5)))
        while hub.listener_count() == 0:
            await asyncio.sleep(0.01)
        notice = Notice(
            type="google.workspace.chat.message.v1.created",
            subject="//chat.googleapis.com/spaces/AAAA",
            resource="spaces/AAAA/messages/BBBB",
            time="2026-10-06T12:00:00Z",
        )
        assert hub.publish("subscriptions/chat-spaces-abc", notice) == 1
        response = await request

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/event-stream")
    body = response.text
    data_line = next(line for line in body.splitlines() if line.startswith("data: {\"type\""))
    assert json.loads(data_line[6:]) == notice.as_dict()
    assert ": ping" in body
    assert body.endswith("event: reauth\ndata: {}\n\n")
    # The client is gone, and the owner keeps the subscription.
    assert hub.listener_count() == 0
    assert not hub.claim("subscriptions/chat-spaces-abc", "mallory")
