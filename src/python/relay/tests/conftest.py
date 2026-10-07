import time

import pytest

from relay.auth import AuthError, Identity
from relay.config import Config


class FakeVerifier:
    """Accepts tokens of the form "<user>:<domain>:<seconds valid>"."""

    def __call__(self, token: str) -> Identity:
        try:
            user, domain, seconds = token.split(":")
        except ValueError:
            raise AuthError(401, "invalid ID token") from None
        if domain != "example.com":
            raise AuthError(403, "this Workspace domain is not accepted")
        return Identity(user=user, domain=domain, expires=time.time() + float(seconds))


@pytest.fixture
def config() -> Config:
    return Config(
        client_ids=frozenset({"client.apps.googleusercontent.com"}),
        domains=frozenset({"example.com"}),
        pubsub_subscription="",
        credentials_file="",
        version="abc1234 2026-10-06",
    )
