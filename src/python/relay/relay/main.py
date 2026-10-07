"""The relay's HTTP interface. See docs/api-contract.md."""

import asyncio
import json
import logging
import re
import time
from collections.abc import AsyncIterator

from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.responses import StreamingResponse

from . import config as config_module
from . import events as events_module
from .auth import AuthError, GooglePushVerifier, GoogleVerifier, PushVerifier, Verifier
from .hub import RESYNC, Hub, Notice

log = logging.getLogger("relay")

SUBSCRIPTION_NAME = re.compile(r"^subscriptions/[A-Za-z0-9_-]+$")
KEEPALIVE_SECONDS = 20


def create_app(
    verifier: Verifier | None = None,
    push_verifier: PushVerifier | None = None,
    hub: Hub | None = None,
    config: config_module.Config | None = None,
    keepalive_seconds: float = KEEPALIVE_SECONDS,
) -> FastAPI:
    """Builds the app. Tests pass fake verifiers."""
    config = config or config_module.load()
    verifier = verifier or GoogleVerifier(config.client_ids, config.domains)
    if push_verifier is None and config.push_service_account:
        push_verifier = GooglePushVerifier(config.push_service_account, config.push_audience)
    if push_verifier is None:
        log.warning("PUSH_SERVICE_ACCOUNT is not set: the push endpoint refuses everything")
    hub = hub or Hub()

    app = FastAPI(title="gchat-relay", docs_url=None, redoc_url=None)
    app.state.hub = hub

    @app.get("/healthz")
    async def healthz() -> dict:
        return {"status": "ok", "version": config.version}

    @app.post("/v1/pubsub/push", status_code=204)
    async def pubsub_push(request: Request) -> Response:
        """Receives one event from the Pub/Sub push subscription.

        Any 2xx answer acknowledges the message. Events that are not Workspace
        events, or that no client is listening for, are acknowledged too: the
        relay keeps no queue.
        """
        if push_verifier is None:
            raise HTTPException(503, "push is not configured")
        header = request.headers.get("authorization", "")
        if not header.lower().startswith("bearer "):
            raise HTTPException(401, "push requests must carry a Google-signed token")
        try:
            await asyncio.to_thread(push_verifier, header[7:].strip())
        except AuthError as error:
            raise HTTPException(error.status, error.reason) from error
        try:
            body = await request.json()
        except ValueError as error:
            raise HTTPException(400, "body is not JSON") from error
        if config.pubsub_subscription and body.get("subscription") != config.pubsub_subscription:
            raise HTTPException(403, "push from another Pub/Sub subscription")
        parsed = events_module.parse(body.get("message") or {})
        if parsed is not None:
            subscription, notice = parsed
            delivered = hub.publish(subscription, notice)
            log.info("%s for %s: %d client(s)", notice.type, subscription, delivered)
        return Response(status_code=204)

    @app.get("/v1/events")
    async def events(request: Request, subscription: str = "") -> StreamingResponse:
        if not SUBSCRIPTION_NAME.match(subscription):
            raise HTTPException(400, "subscription must look like subscriptions/<id>")
        header = request.headers.get("authorization", "")
        if not header.lower().startswith("bearer "):
            raise HTTPException(401, "send a Google ID token as a Bearer token")
        try:
            identity = await asyncio.to_thread(verifier, header[7:].strip())
        except AuthError as error:
            raise HTTPException(error.status, error.reason) from error
        if not hub.claim(subscription, identity.user):
            raise HTTPException(403, "another user owns this subscription")

        queue = hub.listen(subscription)

        async def stream() -> AsyncIterator[str]:
            try:
                while True:
                    remaining = identity.expires - time.time()
                    if remaining <= 0:
                        yield "event: reauth\ndata: {}\n\n"
                        return
                    try:
                        item = await asyncio.wait_for(
                            queue.get(), timeout=min(keepalive_seconds, remaining))
                    except TimeoutError:
                        yield ": ping\n\n"
                        continue
                    if item is RESYNC:
                        yield "event: resync\ndata: {}\n\n"
                    elif isinstance(item, Notice):
                        yield f"event: notice\ndata: {json.dumps(item.as_dict())}\n\n"
            finally:
                hub.unlisten(subscription, queue)

        return StreamingResponse(
            stream(),
            media_type="text/event-stream",
            # Tell proxies not to buffer the stream.
            headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
        )

    return app


def app() -> FastAPI:
    """Entry point for uvicorn --factory."""
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(message)s")
    return create_app()
