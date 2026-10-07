# Design

How GChat is built and why, for developers and reviewers. What it does is in
behavior.md. How to build it is in development.md.


## Shape

GChat is a SwiftUI app with one Swift package and no third-party
dependencies.

    GChat.xcodeproj    the Xcode project. It includes the files in GChat/
                       automatically.
    GChat/             the app: views, sign-in sheet, notifications
    GChatKit/          a Swift package with all code that has no user
                       interface: OAuth, the Keychain, the Chat and People
                       API clients, polling, read markers, Chat markup
    Config/            build configuration. Local.xcconfig, which is not in
                       git, holds an organization's client ID.
    scripts/           release.sh, and the generator for the development
                       icon
    docs/              the documents

GChatKit has unit tests that run without a network. The views have no
tests.


## Sign-in

- GChat uses an OAuth client of type iOS. That type has no client secret,
  and Google redirects to a URL scheme made from the client ID. The sign-in
  runs in ASWebAuthenticationSession with PKCE. PKCE makes sure that only
  the copy of the app that started a sign-in can finish it.
- The client ID is not a secret. Every app that ships a client ID contains
  it in a readable form. The audience of the consent screen is Internal, so
  only accounts in the organization can sign in.
- GChat keeps the refresh token in the login Keychain and gets a new access
  token when the old one is about to expire, or after a 401 answer.
- An organization's build gets the client ID from Config/Local.xcconfig
  through Config/Info.plist. The file is not in git, so the repository
  carries no organization's settings. A client ID that the person signing in
  types replaces the built-in one.

Rejected: keeping the token in a file in the app's container. That stops
Keychain prompts, but other programs that run as the same user can read the
file. The owner chose the Keychain (October 2, 2026).


## Getting messages

The Chat API cannot push messages to a client app, so GChat polls:

- The open conversation every 3 seconds, or every 10 seconds when GChat is
  in the background. GChat asks only for messages created after the newest
  one it has.
- The conversation list every 15 seconds, or every 30 seconds in the
  background. Each conversation in the list has the time of its last
  activity, so one request shows which conversations changed. GChat then
  gets the new messages of those conversations only.
- No polling while the Mac is offline.

Messages stay in memory. A launch loads the newest 50 messages of a
conversation when it opens.

Consequences: a notification can come up to 15 seconds after the message,
or 30 seconds in the background. A message that someone edits or deletes
elsewhere does not change in GChat until the next launch, because polling
asks only for new messages.

Push delivery through a relay replaces most of this polling. It is in
progress; see "Push delivery" below.


## Push delivery

Status, October 7, 2026: push delivery works from end to end for the Zia
Consulting build. A message sent in Google Chat reached GChat as a notice
through the relay, and GChat had the message 0.4 seconds after the notice.
Builds without a relay address, and sign-ins to another organization, poll
as before.

Google can announce new messages through the Workspace Events API. GChat
makes one Workspace Events subscription for the person signed in, with the
target //chat.googleapis.com/spaces/-, which means all spaces of that person.
Google publishes the events to a Pub/Sub topic in the organization's Cloud
project. A push subscription on that topic sends each event to a relay on
the owner's Hetzner host, as an HTTPS request. The relay passes the event to
the copy of GChat that made the Workspace Events subscription. GChat then fetches
the new messages from the Chat API with the person's own sign-in, as it does
after a poll.

    Google Chat --> Workspace Events --> Pub/Sub topic --push--> relay --> GChat
                                                                       |
    GChat <-- message text, with the person's own sign-in <-- Chat API +

The relay is in src/python/relay. Its interface is in api-contract.md. In
GChat, PushController (GChatKit/Sources/GChatKit/Push) makes and renews the
subscription and reads the stream, and ChatStore.handlePush acts on each
notice.

What GChat does:

- It makes the subscription with the Chat permissions that it already has.
  No new scope is needed. Google allows one subscription for each person
  and target, so a second Mac of the same person adopts the first Mac's
  subscription, and both Macs get every notice.
- A subscription without resource data lasts 7 days. GChat renews it at
  each connection when less than 2 days are left, and when Google sends an
  expiration reminder. Sign Out deletes it.
- On a notice for a new message, GChat fetches the message that the notice
  names. It does not list the conversation, because the list can lag behind
  the notice.
- On a notice for a changed or deleted message, GChat updates or removes
  the message in a loaded transcript.
- GChat handles each message once. Pub/Sub can deliver a notice twice.
- While the stream is open, GChat polls only once a minute, as a safety net.
  When the stream closes, it polls at the normal rate and connects again,
  with waits from 1 to 60 seconds.
- The ID token lasts an hour. The relay ends the stream then, and GChat
  connects again with a new token.

### Security rules

1. Events carry no content. GChat makes each subscription with
   includeResource set to false. Events then hold identifiers and times
   only: which conversation, which message, when.
2. The relay only receives events. It has no Google credentials and no
   Google permissions. It accepts a push only with a token that Google
   signed for one service account and one audience, from one Pub/Sub
   subscription.
3. GChat sends the relay only a Google ID token. An ID token proves who the
   person is, expires within an hour, and cannot call Google APIs.

If the host is compromised, the attacker sees which conversations get
messages and when, as opaque identifiers. The attacker cannot read messages
or change subscriptions. A false notice only makes GChat fetch and find
nothing new.

Google gives a subscription without resource data the 7 day lifetime, which
it reserves for such subscriptions. Not verified yet: the bytes of a real
event. To look at one, make a second, pull subscription on the topic in the
Cloud console, send a chat message, and click Pull.

Not verified yet: whether a subscription to all spaces covers a
conversation that starts later.

### Routing

Events carry the name of the Workspace Events subscription that produced
them (the CloudEvents attribute ce-source). Google makes the name, and only
the person who made the subscription, the relay and Google know it. GChat
connects to the relay with the subscription name and an ID token. The relay
binds the name to the user ID in the token at the first connection, and
refuses the name to any other user afterwards. A bound name stays bound
until the relay restarts. Then the next connection binds it again.

Each Mac makes its own Workspace Events subscription, so two Macs of one
person each get every event. Debug builds and releases on one Mac share
their saved state, so they share one subscription.

The relay keeps no queue. Its answer to each push acknowledges the Pub/Sub
message. Events for a copy of GChat that is not connected are
lost. GChat refreshes the conversation list when it connects, so it catches
up, and it keeps a slow poll as a safety net.

### Options considered

- One shared topic, read by each Mac. Rejected: anybody allowed to read the
  topic gets the events of every colleague. Each person also needs a broad
  Pub/Sub permission at sign-in.
- One topic for each colleague, made by the owner with a script. Full
  isolation and no server, but a setup step for each new colleague, and the
  same broad Pub/Sub permission at sign-in.
- The relay (chosen). Colleagues only sign in, and the permission screen
  does not change. The cost is a service to build, secure and run.
- A relay that pulls from Pub/Sub. Rejected (October 6, 2026) for push: a
  pulling relay needs a service account key on the host, which is a secret
  to protect, and new organizations block key creation by default. With
  push, Google sends the events and signs each request. The cost of push:
  the relay must be reachable from Google, so a full test needs a deployed
  relay, not one on a development Mac.
- Faster polling, every 5 seconds. Considered as an interim step. The owner
  preferred push.


## Read markers

GChat loads the read marker of each conversation that had activity in the
last 90 days. A conversation is unread when its last activity is later than
its read marker. Opening a conversation sets the marker in Google Chat, so
other devices agree. Every fourth refresh of the conversation list reloads
the markers of unread conversations, to find conversations that were read
on another device.


## Names, titles and members

The Chat API gives user IDs, and sometimes names. GChat uses two sources:

- The member lists of the Chat API. These include names in some
  organizations.
- The People API, for names and photos. Some organizations do not let apps
  read profiles of other users. At Zia Consulting, the People API returns no
  names and no photos, so names come from the Chat API only.

Direct messages and group chats have no name in the API. GChat reads the
member list of each one and builds the title from the members' current
names, each time it shows the title. The names that it last saw are kept as
a fallback.

GChat records the other person of each direct message, and the members of
each group chat, by user ID. Starting a conversation compares user IDs, so a
changed display name does not cause a duplicate.

When the People API answers "not found" for a user, GChat treats the account
as deleted. A direct message whose member list has only the signed-in user
is also treated as a conversation with a deleted account.

All of this is cached in the app's preferences for one account. When a
different account signs in, GChat discards the cache, so that nothing from
the previous account shows.


## Meeting chats

The Chat API has no field that marks a chat as one that Google Meet made for
a calendar event. In the data of October 2026, every named space without
threading was a meeting chat, and every threaded space was one that people
created. GChat uses that rule. A space that people create without threading
shows under Meetings by mistake. The names of meeting chats also end with a
date, which can become a second test.


## Directory

The list of people in the New Conversation sheet comes from the People API
directory. Some organizations do not let apps read it. Google then answers
403 with "The G Suite domain admin has disabled external directory sharing",
and GChat lists the people from existing conversations instead. The setting
that controls it, and its risks, are in directory-sharing-request.md.


## Requests and quotas

Google limits the requests of each Cloud project, so all copies of GChat
with the same client ID share one quota. The numbers are in to-do.md.

- When Google answers 429 (too many requests), GChat stops polling and stops
  the lookups in the background. It waits 2 seconds, doubled after each
  further 429, up to about 64 seconds, with a random part. The sidebar shows
  "Google asked GChat to slow down".
- The lookups after the first launch (member lists and read markers) run
  four at a time, with a pause after each, for about 10 requests a second.


## Message text

Message text is in a read-only NSTextView, not a SwiftUI Text. NSTextView
gives the pointing-hand cursor over links, Look Up and Services, and the
standard text menu. SwiftUI Text can set only one cursor for a whole view.


## Attachments

- GChat downloads files uploaded to Chat through the media endpoint of the
  Chat API, with the signed-in user's token. The download links that Google
  puts in messages need a browser that is signed in to Google, and they fail
  in other browsers with 403.
- Downloads go to the app's Caches folder. GChat removes the least recently
  used files at launch until the folder is below 300 MB, and empties it on
  Sign Out.
- Images in the transcript are thumbnails that GChat decodes away from the
  main thread. A click opens the full file in Quick Look.
- Files from Google Drive need a Drive scope, which GChat does not ask for.
  They open in the browser.

Not verified yet: "Open with Preview" in Quick Look appears to put a copy of
the file in the Documents folder, because Preview cannot read the app's
sandbox.


## Sidebar

The sidebar is a tabbed view. Rejected: section headings that stay at the
top and the bottom of the list while it scrolls. They need tracking of the
scroll position, which is not reliable in a standard SwiftUI list.


## What is stored on the Mac

- The sign-in token, in the login Keychain (next section).
- Names, photos, titles and members, in the app's preferences, for one
  account.
- Downloaded attachments, in the app's Caches folder.
- Messages are only in memory.

Nothing goes anywhere except to Google.


## The Keychain item

GChat saves one item in the login Keychain, named "GChat Google sign-in". It
holds the refresh token, a short-lived access token and the time when the
access token expires. It never holds the Google password, which the person
signing in types into Google's page.

GChat reads the item at launch and writes it about once an hour. Sign Out
deletes it.

The Keychain lets an app read an item only if the app's signature matches
the signature of the app that saved it. Otherwise, macOS asks whether to
allow it. Development and release builds have the same signature identity
(development.md), so switching between them does not ask. An ad hoc signed
build gets a new identity at each build and asks each time.


## Signing and identity

- Release and Debug builds are both signed with the Developer ID Application
  certificate. macOS identifies an app signed this way by its team and
  bundle ID, so the Keychain treats both builds as one app. Debug builds
  also carry get-task-allow, which the Xcode debugger needs.
- Both builds have the bundle ID org.themullers.gchat. Only one can run at a
  time.

Rejected (October 3, 2026):

- Debug builds signed with the Apple Development certificate. Each switch
  between a Debug build and a release asked for Keychain access, and a
  denied prompt signed the other copy out.
- A separate bundle ID for Debug builds. Both builds can then run together,
  but each needs its own sign-in, preferences and notification permission,
  and possibly its own OAuth client.

Costs: Developer ID is meant for distribution, not development. A Debug
build is signed like a release, so only its icon and its About window show
the difference. Debug builds must not go to other people.


## Versions

- The About window shows the commit ID as the version.
- The version fields that macOS reads (CFBundleShortVersionString and
  CFBundleVersion) hold the build number, which is the number of commits.
  macOS uses these fields to decide which of two copies is newer. Commit IDs
  do not sort, so they are not in these fields.
- Debug builds have a separate icon with an orange hammer badge. The badge
  stays inside the rounded square of the icon. If part of an icon is outside
  that shape, macOS shows the whole icon small, on a gray plate.
