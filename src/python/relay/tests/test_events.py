import base64
import json

from relay import events


def message(attributes: dict, payload=None) -> dict:
    data = base64.b64encode(json.dumps(payload).encode()).decode() if payload is not None else None
    return {"attributes": attributes, "data": data}


ATTRIBUTES = {
    "ce-source": "//workspaceevents.googleapis.com/subscriptions/chat-spaces-abc",
    "ce-type": "google.workspace.chat.message.v1.created",
    "ce-subject": "//chat.googleapis.com/spaces/AAAA",
    "ce-time": "2026-10-06T12:00:00.123Z",
}


def test_parses_a_message_event():
    subscription, notice = events.parse(message(ATTRIBUTES, {"message": {"name": "spaces/AAAA/messages/BBBB"}}))
    assert subscription == "subscriptions/chat-spaces-abc"
    assert notice.type == "google.workspace.chat.message.v1.created"
    assert notice.subject == "//chat.googleapis.com/spaces/AAAA"
    assert notice.resource == "spaces/AAAA/messages/BBBB"
    assert notice.time == "2026-10-06T12:00:00.123Z"


def test_unknown_payload_gives_no_resource():
    _, notice = events.parse(message(ATTRIBUTES, ["unexpected"]))
    assert notice.resource is None
    _, notice = events.parse({"attributes": ATTRIBUTES, "data": "not base64!"})
    assert notice.resource is None
    _, notice = events.parse(message(ATTRIBUTES))
    assert notice.resource is None


def test_ignores_messages_that_are_not_workspace_events():
    assert events.parse(message({"ce-source": "//other.googleapis.com/x"})) is None
    assert events.parse({"data": None}) is None
