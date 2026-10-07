"""Configuration from the environment. Missing required values stop startup."""

import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Config:
    # OAuth client IDs whose ID tokens are accepted (the aud claim).
    client_ids: frozenset[str]
    # Workspace domains whose users are accepted (the hd claim).
    domains: frozenset[str]
    # projects/<project>/subscriptions/<name>. Empty means no Pub/Sub reading,
    # for local development and tests.
    pubsub_subscription: str
    # Service account key file with the Pub/Sub Subscriber role on that subscription.
    credentials_file: str
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
    subscription = os.environ.get("PUBSUB_SUBSCRIPTION", "").strip()
    credentials_file = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS", "").strip()
    if subscription and not Path(credentials_file).is_file():
        raise SystemExit(
            f"PUBSUB_SUBSCRIPTION is set but the service account key {credentials_file!r} "
            "is missing; see docs/deployment-relay.md")
    version_file = Path("/app/VERSION")
    version = " ".join(version_file.read_text().split()) if version_file.exists() else "dev"
    return Config(
        client_ids=client_ids,
        domains=domains,
        pubsub_subscription=subscription,
        credentials_file=credentials_file,
        version=version or "dev",
    )
