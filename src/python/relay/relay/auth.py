"""Checks the Google ID token that each client sends."""

from dataclasses import dataclass
from typing import Protocol

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


class GoogleVerifier:
    """Checks the signature, issuer, expiry and audience of a Google ID token.

    Blocking: it can fetch Google's public keys. Call it from a worker thread.
    """

    def __init__(self, client_ids: frozenset[str], domains: frozenset[str]):
        self._client_ids = client_ids
        self._domains = domains
        self._request = google_requests.Request()

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
