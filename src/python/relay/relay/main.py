"""The relay's HTTP interface. See docs/api-contract.md."""

import asyncio
import contextlib
import json
import logging
import re
import time
from collections.abc import AsyncIterator

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import StreamingResponse

from . import config as config_module
from .auth import AuthError, GoogleVerifier, Verifier
from .hub import RESYNC, Hub, Notice

log = logging.getLogger("relay")

SUBSCRIPTION_NAME = re.compile(r"^subscriptions/[A-Za-z0-9_-]+$")
KEEPALIVE_SECONDS = 20


def create_app(
    verifier: Verifier | None = None,
    hub: Hub | None = None,
    config: config_module.Config | None = None,
    keepalive_seconds: float = KEEPALIVE_SECONDS,
) -> FastAPI:
    """Builds the app. Tests pass a fake verifier and no Pub/Sub subscription."""
    config = config or config_module.load()
    verifier = verifier or GoogleVerifier(config.client_ids, config.domains)
    hub = hub or Hub()

    @contextlib.asynccontextmanager
    async def lifespan(app: FastAPI):
        reader_task = None
        if config.pubsub_subscription:
            from .pubsub import PubSubReader
            reader = PubSubReader(config.pubsub_subscription, config.credentials_file, hub)
            reader_task = asyncio.create_task(reader.run())
        else:
            log.warning("PUBSUB_SUBSCRIPTION is not set: no events will be relayed")
        yield
        if reader_task:
            reader_task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await reader_task

    app = FastAPI(title="gchat-relay", docs_url=None, redoc_url=None, lifespan=lifespan)
    app.state.hub = hub

    @app.get("/healthz")
    async def healthz() -> dict:
        return {"status": "ok", "version": config.version}

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
