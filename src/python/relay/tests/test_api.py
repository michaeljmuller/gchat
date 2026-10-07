import asyncio
import base64
import json

import httpx

from relay.hub import Hub, Notice
from relay.main import create_app

from .conftest import FakePushVerifier, FakeVerifier

URL = "/v1/events?subscription=subscriptions/chat-spaces-abc"


def make_client(config, hub=None, push_verifier=FakePushVerifier()):
    app = create_app(
        verifier=FakeVerifier(), push_verifier=push_verifier, hub=hub or Hub(), config=config,
        keepalive_seconds=0.05)
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
    assert body.startswith(": connected\n\n")
    assert ": ping" in body
    assert body.endswith("event: reauth\ndata: {}\n\n")
    # The client is gone, and the owner keeps the subscription.
    assert hub.listener_count() == 0
    assert not hub.claim("subscriptions/chat-spaces-abc", "mallory")


def push_body(subscription="projects/p/subscriptions/gchat-relay", source="subscriptions/chat-spaces-abc"):
    data = base64.b64encode(json.dumps({"message": {"name": "spaces/AAAA/messages/BBBB"}}).encode()).decode()
    return {
        "subscription": subscription,
        "message": {
            "attributes": {
                "ce-source": f"//workspaceevents.googleapis.com/{source}",
                "ce-type": "google.workspace.chat.message.v1.created",
                "ce-subject": "//chat.googleapis.com/spaces/AAAA",
                "ce-time": "2026-10-06T12:00:00Z",
            },
            "data": data,
            "messageId": "1",
        },
    }


PUSH = {"Authorization": "Bearer good-push"}


async def test_push_delivers_to_listeners_of_the_subscription(config):
    hub = Hub()
    queue = hub.listen("subscriptions/chat-spaces-abc")
    other = hub.listen("subscriptions/other")
    _, client = make_client(config, hub)
    async with client:
        response = await client.post("/v1/pubsub/push", json=push_body(), headers=PUSH)
    assert response.status_code == 204
    notice = queue.get_nowait()
    assert notice.resource == "spaces/AAAA/messages/BBBB"
    assert notice.type == "google.workspace.chat.message.v1.created"
    assert other.empty()


async def test_push_acknowledges_events_nobody_listens_to(config):
    _, client = make_client(config)
    async with client:
        unknown = await client.post("/v1/pubsub/push", json=push_body(), headers=PUSH)
        not_workspace = await client.post(
            "/v1/pubsub/push", headers=PUSH,
            json={"subscription": "projects/p/subscriptions/gchat-relay", "message": {"data": None}})
    assert unknown.status_code == 204
    assert not_workspace.status_code == 204


async def test_push_refuses_unsigned_or_foreign_requests(config):
    hub = Hub()
    queue = hub.listen("subscriptions/chat-spaces-abc")
    _, client = make_client(config, hub)
    async with client:
        no_token = await client.post("/v1/pubsub/push", json=push_body())
        bad_token = await client.post(
            "/v1/pubsub/push", json=push_body(), headers={"Authorization": "Bearer forged"})
        other_subscription = await client.post(
            "/v1/pubsub/push", json=push_body(subscription="projects/x/subscriptions/y"), headers=PUSH)
        not_json = await client.post("/v1/pubsub/push", content=b"nonsense", headers=PUSH)
    assert no_token.status_code == 401
    assert bad_token.status_code == 401
    assert other_subscription.status_code == 403
    assert not_json.status_code == 400
    assert queue.empty()


async def test_push_is_off_without_a_service_account(config):
    app = create_app(verifier=FakeVerifier(), push_verifier=None, hub=Hub(), config=config.__class__(
        **{**config.__dict__, "push_service_account": "", "push_audience": ""}))
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://relay") as off:
        response = await off.post("/v1/pubsub/push", json=push_body(), headers=PUSH)
    assert response.status_code == 503


async def test_refused_requests_are_logged_with_their_user_agent(config, caplog):
    caplog.set_level("INFO", logger="relay")
    _, client = make_client(config)
    async with client:
        await client.get("/", headers={"User-Agent": "SomeScanner/1.0", "X-Forwarded-For": "203.0.113.9"})
        await client.get("/healthz", headers={"User-Agent": "curl/8"})
        await client.post("/v1/pubsub/push", json=push_body(), headers={"User-Agent": "Forger"})
    messages = [record.getMessage() for record in caplog.records]
    assert any(
        "refused GET / -> 404" in m and "SomeScanner/1.0" in m and "203.0.113.9" in m for m in messages)
    assert any("refused POST /v1/pubsub/push -> 401" in m and "Forger" in m for m in messages)
    assert not any("/healthz" in m for m in messages)
