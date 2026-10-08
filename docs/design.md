# Design

How GChat is built and why, for developers and reviewers. What it does is in
behavior.md. How to build it is in development.md.


## Shape

GChat is a SwiftUI app with one Swift package of its own and one
third-party dependency: Sparkle, for updates.

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
    scripts/support/   the parts that release.sh runs:
                       write-release-notes.sh with its prompt, publish.sh,
                       and bucket.sh, which both read
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

The Chat API cannot push messages to a client app. Without push delivery
through the relay (below), GChat polls.

One check covers every conversation. GChat gets the conversation list, in
which each conversation has the time of its last activity. One request
therefore shows which conversations changed. GChat then gets the new
messages of those conversations only, including the open one.

The wait between checks follows chat activity, which is a message sent or
received in any conversation:

- After activity, the wait is 2 seconds.
- After each check that finds nothing, the wait grows by a tenth.
- The longest wait is 10 minutes. Without a message, the wait is 30 seconds
  after about 5 minutes, 1 minute after about 10 minutes, and 10 minutes
  after about 100 minutes.
- Check Now in the sidebar line, and Refresh (Command-R), check at once and
  start the waits again from 2 seconds.
- No polling while the Mac is offline.

The wait does not depend on whether GChat is in front. The person can be
working with a colleague and switching between GChat and other apps.

The limits: 2 seconds is the shortest wait, because all copies of GChat
share the quota of one Cloud project (to-do.md, "Quota"). The growth is a
tenth and not a doubling, because a pause in a conversation is not a
failure. With doubling, the wait is at 30 seconds within a minute, while
the person is still typing a reply.

The longest wait decides how late the first message after a quiet time
shows: up to 10 minutes. The owner chose 10 minutes on October 7, 2026, with
Check Now as the way to look sooner. A first version stopped at 30 seconds.
For a sign-in with push delivery, the long wait matters only while the
relay is down. A sign-in without a relay always polls, so there the first
message after a quiet hour or two can be up to 10 minutes late, and the
sidebar shows no line and no Check Now button. Refresh (Command-R) does the
same there. The owner accepted this: the app is for the organization with
the relay, and the sign-in without one was only a test during the first
build.

Earlier versions and why they changed (October 7, 2026):

- A slower rate in the background. The owner rejected it.
- Two checks at two rates: the open conversation, and the list. The list
  check already covers the open conversation, so one check is simpler, and
  every conversation updates at the same speed. The cost: each check
  returns the whole list, about 60 KB for 200 conversations. Not verified
  yet: how soon Google updates the time of the last activity. If it lags,
  the direct check of the open conversation can come back.
- Three fixed rates by time since the last activity. The growing wait
  replaced them with one rule.

Messages stay in memory. A launch loads the newest 50 messages of a
conversation when it opens.

Consequences of polling: a notification can come up to 30 seconds after the
message. A message that someone edits or deletes elsewhere does not change
in GChat until the next launch, because polling asks only for new messages.

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
  When the stream closes, it polls at the normal rate and connects again.
  The wait between attempts doubles from 1 second up to 15 minutes, and
  there is no limit on the number of attempts. After a long failure, GChat
  can therefore take up to 15 minutes to find that the relay is back.
  Polling covers that time.
- When a message is sent or received while GChat waits to try again, it
  tries at once, and the waits start again from 1 second. The person is
  chatting, so prompt delivery matters, and Google can be reached. This
  happens at most once a minute.
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

The conversation list of Google calls some group chats direct messages.
Seen in October 2026 in one account: 3 of 74 listed direct messages, all
group chats with their last activity between 2019 and 2021. For these, the
list says DIRECT_MESSAGE, and a request for the one conversation
(spaces.get) says GROUP_CHAT. chat.google.com also shows them with the
direct messages. Where the other members of such a group were deleted, the
member list has one other person, so the row had the same title as the real
direct message with that person.

GChat finds them with two signs from the list, and makes sure with one
request for each candidate:

- The conversation has no threading (UNTHREADED_MESSAGES). All 71 real
  direct messages were threaded, and all 3 of the others were not.
- The conversation has the same other member as another direct message. A
  person has only one direct message with the signed-in person.

If the request says GROUP_CHAT, GChat treats the conversation as a group
chat from then on. It keeps the answer for each candidate, so each costs
one request, once. See checkListedTypes() in ChatStore.swift.

Rejected (October 8, 2026):

- The number of members in the list (membershipCount). It is 2 for a real
  direct message, and also 2 for a group chat with one member left.
- A request for each listed direct message. It costs one request for each
  at every first launch.
- No threading as proof, without the request. It held in one account, and
  Google does not document it.

Deleted accounts in messages: Google gives the sender the name "Deleted
User" and no email, and the People API answers "not found". The text of a
mention keeps the name as it was typed ("@Name"), and the mention still
holds the user ID. GChat does not use this yet (to-do.md).

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


## Scrolling in the transcript

The transcript follows new content while the person is at its end. It
counts as at the end until the person scrolls up: the view moves up, and
the end is more than 40 points out of view. Growth of the content and the
app's own scrolls do not count, because they also change the distance to
the end. A first version measured only the distance, and showed the "New
messages" button when a conversation opened. The second version still did.
A log of the measurements showed the cause: the distance came from the
scroll offset and the container size, which include the 52 points under the
title bar, so the view never measured as at the end. The distance now comes
from the visible rectangle that SwiftUI reports. Movement of the view
within half a second after the app loads or scrolls the transcript does not
count as a scroll by the person, because rows that are still being laid out
can shift the view. While the
person is at the end, a new message, or an image that finishes loading,
scrolls the end back into view. If the person scrolled up, the
transcript stays in place and shows a "New messages" button, because a jump
interrupts reading. Mac chat apps commonly do the same. The owner asked
for the scroll, and for a "mac-assed" app. The behavior in the scrolled-up
case follows from the second request (requirements.md).

The space between the last message and the composer is a 12 point marker at
the end of the content, and scrolls go to that marker. When that space was
padding around the content, scrolls stopped 12 points short.


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

Nothing goes anywhere except to Google, with one exception: a copy with an
updater reads the appcast and downloads new versions from the bucket (see
Updates). Sparkle keeps the time of its last check and the two update
settings in the app's preferences.


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

- Every build records the commit that it was built from: the short ID, the
  number of commits, and the time of the commit. A build phase in the Xcode
  project, "Record commit", reads them from git and writes BuildInfo.plist
  into the app. The About window reads that file. The phase needs git, so
  the script sandbox of Xcode is off for the app target.
- The phase also records the build configuration and the time of the
  build. A Debug build is usually made from code that is not committed, so
  a commit ID on it misleads. The About window shows "development" and the
  time of the build for it.
- A first version passed the commit from scripts/release.sh as a build
  setting. Development builds then showed "Version development (1)".
- The version fields that macOS reads (CFBundleShortVersionString and
  CFBundleVersion) hold the number of commits, set by scripts/release.sh.
  macOS uses these fields to decide which of two copies is newer. Commit
  IDs do not sort, so they are not in these fields.
- Debug builds have a separate icon with an orange hammer badge. The badge
  stays inside the rounded square of the icon. If part of an icon is outside
  that shape, macOS shows the whole icon small, on a gray plate.


## Updates

Sparkle 2, the usual updater for Mac apps outside the App Store, updates
GChat. It is a Swift package, pinned in Package.resolved inside the Xcode
project. GChat/Updater.swift owns it.

How an update reaches a copy:

- scripts/support/publish.sh uploads three files to one folder of a public
  bucket: the disk image, appcast.xml and release-notes.html. The appcast is
  the file that lists the releases. Sparkle reads it.
- The app reads the appcast at the address in SUFeedURL in its Info.plist.
  The value comes from GCHAT_APPCAST_URL in Config/Local.xcconfig. Each
  organization's build has its own client ID, so each has its own folder
  and its own appcast.
- Sparkle compares sparkle:version in the appcast with CFBundleVersion of
  the copy. Both are the number of commits (see Versions).
- Sparkle accepts a download only if two signatures are valid: the EdDSA
  signature in the appcast, made with the Sparkle key of GChat, and the
  Developer ID signature of the new app, from the same team as the old one.
  The public half of the Sparkle key is SUPublicEDKey in Info.plist.
- The disk image is the one that people install by hand. There is no
  second package for updates.
- scripts/release.sh publishes only a commit that is on the remote branch.
  The version is the number of commits, and the About window names the
  commit. A local commit can still be changed or dropped. Then the number
  can go to a different commit, and the commit ID leads nowhere.

No updater in two cases. A build with an empty SUFeedURL or an empty
SUPublicEDKey has none, because it has nowhere to look or cannot make sure
that an update is genuine. A Debug build has none, because its version is 1
and every release looks newer.

The sandbox: GChat is sandboxed, and a sandboxed app cannot replace itself.
Sparkle does it through a helper that runs outside the sandbox. This needs
SUEnableInstallerLauncherService in Info.plist and a mach-lookup exception
for two service names in GChat.entitlements. Sparkle's separate downloader
service is not used, because GChat can already make network requests.

SUEnableAutomaticChecks is on, so Sparkle does not ask at the second launch
whether to look for updates. The setting in the Settings window turns it
off.

What the bucket learns from a copy: its IP address and, in the user agent,
the versions of GChat and macOS. Sparkle can send a system profile, and
GChat leaves that off.

The bucket is public. Anyone with the address can download the Zia
Consulting build, which holds its client ID and organization name. The
client is Internal, so only Zia accounts can sign in, and the client ID is
not a secret.

Release notes:

- scripts/support/write-release-notes.sh asks Claude Code (claude -p) for the
  notes, with the prompt in scripts/support/release-notes-prompt.txt. Claude
  Code can read files and run git log, git show and git diff, and nothing
  else. The rules for the text are in release-notes-style.md, not in the
  prompt.
- The developer can ask for a revision in plain words. The script sends the
  request to Claude Code again, with the notes so far. Each call is
  separate, so the notes so far are the only memory between calls.
- The script finds the last published version in the appcast. The version
  is the number of commits, so commit number N in the history is version N,
  and no tags are needed.
- With no appcast in the bucket, the release is the first one, and the
  notes list core features.
- release-notes.html holds one section for each release, newest first. Each
  section has the attribute data-sparkle-version. Sparkle 2.5 and later
  adds the class sparkle-installed-version to the section of the version
  that runs. A style rule hides that section and all sections after it. The
  update window then shows the releases that the copy does not have.
- One page goes to three places. The "Record commit" build phase copies it
  into the app as ReleaseNotes.html, for the Release Notes window
  (GChat/ReleaseNotesPanel.swift). scripts/support/publish.sh puts it in the
  appcast entry of the new release, for the update window, and uploads it as
  release-notes.html, where the next release reads it as the earlier notes.
- The app contains the notes, so the notes are written before the build.
  scripts/release.sh runs scripts/support/write-release-notes.sh first and
  gives the path of the page to the build in the build setting
  GCHAT_RELEASE_NOTES. A build without that setting has no notes.
- The Release Notes window shows the page as it is. Nothing marks a
  section there, so all sections show, and the top one is the version that
  runs.
- scripts/support/publish.sh stops if the page is not for the version of the
  disk image, or differs from the page in the exported app.
- The styling of the page is in scripts/support/write-release-notes.sh, and
  the script writes it again at each release. So all sections look the same.

Rejected (October 8, 2026):

- A Google Drive folder. Sparkle cannot sign in to Google to download.
- A static site on the Hetzner host behind Caddy. It needs a change to the
  deployment. The bucket needs no server process.
- GitHub Releases. It works only for a public repository, and it serves one
  repository. The bucket layout can serve other apps.
- A Release Notes window that reads the page from the bucket. It needs the
  network, and it must mark the section of the version that runs.
- Release notes kept in a file in the repository. The commit that adds the
  notes changes the number of commits, so the notes describe the version
  before their own.
- Release notes from commit subjects alone. About half of the commits
  change only documents or the relay.
- Uploading with an S3 command line tool. curl signs S3 requests itself
  (--aws-sigv4), so nothing is installed on the Mac.

Not verified yet (October 8, 2026): an update from end to end on an
installed copy, and that the update window hides the sections of the
installed version and older ones. release.md has the test. Nobody looked at
the Release Notes window on screen.
