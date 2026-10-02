# To do

## Replace polling with push delivery

Today the app polls: the open conversation every 3 seconds and the
conversation list every 15 seconds (10 and 30 seconds when the app is not
frontmost). See run() in GChatKit/Sources/GChatKit/Sync/ChatStore.swift. A
message in another conversation can take up to 15 seconds to produce a
notification, or 30 in the background.

The Chat API cannot push to a client app directly. Google's push mechanism is
the Workspace Events API, which delivers events to a Google Cloud Pub/Sub
topic. The app would hold a connection open to Pub/Sub and pull events from
its own subscription.

Benefits: near-instant delivery, fewer requests, and edits and deletions made
elsewhere would arrive as events (polling only sees newly created messages).

What it would take:

- Cloud setup per organization: enable the Workspace Events API and Pub/Sub,
  create a topic, grant Google Chat permission to publish to it, create a
  pull subscription. Add these steps to the README walkthrough.
- More OAuth scopes: one for Pub/Sub so the app can pull as the user, plus
  whatever the Workspace Events API requires for Chat message events.
  Existing users would have to sign in again.
- A Workspace Events subscription per conversation, or one for all of the
  user's conversations if the API supports that. Check this first, since it
  decides how much bookkeeping is needed.
- Subscriptions expire, so they need renewing on a timer and recreating when
  renewal fails.
- A Pub/Sub pull client in GChatKit (REST pull or streaming pull), with
  acknowledgement and reconnect handling.
- With one shared topic, each signed-in Mac needs its own Pub/Sub
  subscription, or two Macs would each receive only some of the events.
- Keep polling as the fallback at a much longer interval, for when the push
  connection is down or the Cloud setup has not been done.

Not verified yet: the exact scopes, subscription lifetime and renewal rules,
whether events carry the full message or only its name, and Pub/Sub cost at
this volume (expected to be within the free tier).
