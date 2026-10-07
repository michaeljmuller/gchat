"""Configuration from the environment. Missing required values stop startup."""

import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Config:
    # OAuth client IDs whose ID tokens GChat clients may send (the aud claim).
    client_ids: frozenset[str]
    # Workspace domains whose users are accepted (the hd claim).
    domains: frozenset[str]
    # The service account that Pub/Sub signs its pushes as. Empty turns the
    # push endpoint off, for local development and tests.
    push_service_account: str
    # The audience that the push subscription puts in its tokens: by default
    # the push endpoint URL.
    push_audience: str
    # projects/<project>/subscriptions/<name>. When set, pushes from any other
    # Pub/Sub subscription are refused.
    pubsub_subscription: str
    version: str


def _set(name: str) -> frozenset[str]:
    return frozenset(v.strip() for v in os.environ.get(name, "").split(",") if v.strip())


def load() -> Config:
    client_ids = _set("ALLOWED_CLIENT_IDS")
    domains = _set("ALLOWED_DOMAINS")
    # Empty lists are a startup error, not an open door.
    if not client_ids:
        raise SystemExit("set ALLOWED_CLIENT_IDS")
    if not domains:
        raise SystemExit("set ALLOWED_DOMAINS")
    push_service_account = os.environ.get("PUSH_SERVICE_ACCOUNT", "").strip()
    push_audience = os.environ.get("PUSH_AUDIENCE", "").strip()
    if push_service_account and not push_audience:
        raise SystemExit("PUSH_SERVICE_ACCOUNT is set: set PUSH_AUDIENCE too")
    version_file = Path("/app/VERSION")
    version = " ".join(version_file.read_text().split()) if version_file.exists() else "dev"
    return Config(
        client_ids=client_ids,
        domains=domains,
        push_service_account=push_service_account,
        push_audience=push_audience,
        pubsub_subscription=os.environ.get("PUBSUB_SUBSCRIPTION", "").strip(),
        version=version or "dev",
    )
