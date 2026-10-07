"""Checks the Google-signed tokens that GChat clients and Pub/Sub send."""

from dataclasses import dataclass
from typing import Protocol

import cachecontrol
import requests
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token


@dataclass(frozen=True)
class Identity:
    user: str        # the sub claim: the Google user ID
    domain: str      # the hd claim: the Workspace domain
    expires: float   # the exp claim, seconds since 1970


class AuthError(Exception):
    def __init__(self, status: int, reason: str):
        super().__init__(reason)
        self.status = status
        self.reason = reason


class Verifier(Protocol):
    def __call__(self, token: str) -> Identity: ...


class PushVerifier(Protocol):
    def __call__(self, token: str) -> None: ...


def _google_request() -> google_requests.Request:
    # Google's public keys change rarely; caching them per their Cache-Control
    # header avoids a fetch for every token.
    return google_requests.Request(session=cachecontrol.CacheControl(requests.Session()))


class GoogleVerifier:
    """Checks a GChat client's ID token: signature, issuer, expiry, audience,
    and Workspace domain. Blocking; call it from a worker thread."""

    def __init__(self, client_ids: frozenset[str], domains: frozenset[str]):
        self._client_ids = client_ids
        self._domains = domains
        self._request = _google_request()

    def __call__(self, token: str) -> Identity:
        try:
            # audience=None: the aud claim is checked against the list below.
            claims = id_token.verify_oauth2_token(token, self._request, audience=None)
        except ValueError as error:
            raise AuthError(401, f"invalid ID token: {error}") from error
        if claims.get("aud") not in self._client_ids:
            raise AuthError(401, "ID token is for another client")
        domain = claims.get("hd", "")
        if domain not in self._domains:
            raise AuthError(403, "this Workspace domain is not accepted")
        return Identity(user=str(claims["sub"]), domain=domain, expires=float(claims["exp"]))


class GooglePushVerifier:
    """Checks the token that Pub/Sub puts on each push: signed by Google, for
    this audience, for the expected service account. Blocking."""

    def __init__(self, service_account: str, audience: str):
        self._service_account = service_account
        self._audience = audience
        self._request = _google_request()

    def __call__(self, token: str) -> None:
        try:
            claims = id_token.verify_oauth2_token(token, self._request, audience=self._audience)
        except ValueError as error:
            raise AuthError(401, f"invalid push token: {error}") from error
        if claims.get("email") != self._service_account or not claims.get("email_verified"):
            raise AuthError(403, "push token is for another service account")
