# Relay API contract

The interfaces of the relay: the stream that GChat reads, and the endpoint
that Pub/Sub pushes events to. For developers of GChat and of the relay.
Why the relay exists, and its security rules, are in design.md. Deploying it
is in deployment.md.

The relay serves plain HTTP. Caddy on the host adds TLS. The public address
is https://gchat-relay.themullers.org.

This is version 1 of the interface. A change that breaks old copies of
GChat gets a new path prefix (/v2/...), and the relay keeps /v1 until no
copy uses it.


## GET /healthz

No authentication.

Answer: 200 with a JSON object:

    {"status": "ok", "version": "<commit> <commit date>"}

The version is "dev" for a build without git history.


## GET /v1/events

Opens a stream of notices for one Workspace Events subscription.

Request:

    GET /v1/events?subscription=subscriptions/<id>
    Authorization: Bearer <Google ID token>
    Accept: text/event-stream

- subscription: the name of a Workspace Events subscription that the
  person made, exactly as Google returned it. Letters, digits, "-" and "_"
  after "subscriptions/".
- The ID token comes from the person's Google sign-in with the openid
  scope. Its audience must be one of the OAuth client IDs that the relay
  accepts. Its hd claim (the Workspace domain) must be one of the domains
  that the relay accepts.

Errors, each with a JSON body {"detail": "<reason>"}:

    400   the subscription name is missing or has the wrong form
    401   no ID token, or the token is not valid or has expired
    403   the domain is not accepted, or another user owns the subscription

Answer: 200 with Content-Type text/event-stream. The stream is open until
the ID token expires, the client closes it, or the relay restarts. It has
three kinds of item:

A notice, for each event of the subscription:

    event: notice
    data: {"type": "...", "subject": "...", "resource": "...", "time": "..."}

- type: the event type, for example
  google.workspace.chat.message.v1.created, or a lifecycle type such as
  google.workspace.events.subscription.v1.expirationReminder.
- subject: the resource where the event happened, for example
  //chat.googleapis.com/spaces/AAAA.
- resource: the name of the changed resource, for example
  spaces/AAAA/messages/BBBB, or null if the event has none.
- time: when the event happened, RFC 3339.

A keepalive, every 20 seconds:

    : ping

The end of the stream when the ID token expires:

    event: reauth
    data: {}

On reauth, or when the stream ends for another reason, the client gets a new
ID token and connects again. After each connection, the client refreshes its
conversation list, because the relay keeps no events for clients that are
not connected.

If a client reads too slowly and more than 100 notices wait for it, the
relay drops the oldest and sends:

    event: resync
    data: {}

The client then refreshes its conversation list.


## POST /v1/pubsub/push

For the Pub/Sub push subscription only. GChat does not call it.

Request: the Pub/Sub push format, with the token that Pub/Sub adds when the
subscription has authentication on:

    POST /v1/pubsub/push
    Authorization: Bearer <token signed by Google>
    Content-Type: application/json

    {"subscription": "projects/<project>/subscriptions/<name>",
     "message": {"attributes": {"ce-source": "...", "ce-type": "...",
                                "ce-subject": "...", "ce-time": "..."},
                 "data": "<base64>", "messageId": "..."}}

The relay accepts the request only if all of these are true:

- The token has a valid Google signature, has not expired, and its audience
  is the configured PUSH_AUDIENCE.
- The email claim of the token is the configured PUSH_SERVICE_ACCOUNT, and
  it is verified.
- The subscription field is the configured PUBSUB_SUBSCRIPTION, if that is
  set.

Answers:

    204   accepted. Pub/Sub treats the message as acknowledged. The relay
          also answers 204 for events that no client listens to, and for
          messages that are not Workspace events.
    400   the body is not JSON
    401   no token, or the token is not valid
    403   the token is for another service account, or the push came from
          another Pub/Sub subscription
    503   PUSH_SERVICE_ACCOUNT is not set, so push is off

Pub/Sub sends a refused message again later. A message that keeps failing
goes away when the retention period of the subscription ends.
