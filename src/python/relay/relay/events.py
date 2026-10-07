"""Turns a Pub/Sub message from the Workspace Events API into a Notice."""

import base64
import json

from .hub import Notice


def parse(message: dict) -> tuple[str, Notice] | None:
    """Returns (Workspace Events subscription name, notice), or None if the
    message is not a Workspace event.

    Pub/Sub carries the CloudEvents attributes as ce-* attributes. ce-source is
    //workspaceevents.googleapis.com/subscriptions/<id>.
    """
    attributes = message.get("attributes") or {}
    source = attributes.get("ce-source", "")
    prefix = "//workspaceevents.googleapis.com/"
    if not source.startswith(prefix):
        return None
    subscription = source[len(prefix):]
    notice = Notice(
        type=attributes.get("ce-type", ""),
        subject=attributes.get("ce-subject", ""),
        resource=_resource_name(message.get("data")),
        time=attributes.get("ce-time", ""),
    )
    return subscription, notice


def _resource_name(data: str | None) -> str | None:
    """The name of the changed resource, if the payload has one.

    Without resource data the payload is expected to be like
    {"message": {"name": "spaces/A/messages/B"}}. Not verified against a real
    event yet, so anything else gives None.
    """
    if not data:
        return None
    try:
        payload = json.loads(base64.b64decode(data))
    except (ValueError, TypeError):
        return None
    if not isinstance(payload, dict):
        return None
    for value in payload.values():
        if isinstance(value, dict) and isinstance(value.get("name"), str):
            return value["name"]
    return None
