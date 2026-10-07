# To do

Work that was left out of GChat or deferred, with the reasons, for the
developer. It is not a prioritized backlog. What GChat does today is in
behavior.md.


## Push delivery: what is left

The design and the relay are done (design.md, api-contract.md,
deployment.md). Left:

- In GChat: get an ID token at sign-in and at each refresh, make and renew
  the Workspace Events subscription with includeResource false, keep the
  stream to the relay open and reconnect, fetch on each notice, and slow
  polling to about once a minute while the stream works.
- A new scope for Workspace Events, if the Chat scopes are not enough. Not
  verified yet.
- Look at a real event without resource data, and make sure that it holds
  only identifiers (design.md, security rule 1).
- Whether a subscription to all spaces covers spaces that the person joins
  later. Not verified yet. If not, GChat renews it when the conversation
  list grows.
- One relay serves one Cloud project. Serving a second organization needs a
  second relay, or a relay that accepts pushes from several Pub/Sub
  subscriptions.

## End the Google Cloud free trial when push delivery works

The billing account of the Zia Consulting Cloud project started as a Google
Cloud free trial in October 2026. The trial normally lasts 90 days, so it
ends about January 2027. Billing > Overview shows the exact date. Until then,
Google charges nothing, and paid services stop when the trial ends or its
credit runs out.

The owner wants to end the trial as soon as push delivery works from end to
end, not at the end of the trial period. If the trial ends first, Pub/Sub
stops for the project, push delivery stops, and GChat falls back to
polling. Steps:

1. Click "Activate full account" in Billing. After that, charges go to the
   owner's card.
2. Set the quota limit (deployment.md, step 4): select all rows of
   "Regional publisher throughput, kB per minute per region" in APIs &
   Services > Cloud Pub/Sub API > Quotas & System Limits, and set them to
   1000. Google does not allow quota changes during the free trial.
3. Make sure that the budget alert of 20 US dollars a month still exists.


## Images in the transcript: what is left

Images uploaded to Chat show in the transcript (behavior.md). Left
out:

- The row shows a placeholder of a fixed size until the image loads, then
  changes size. The transcript can jump. The attachment data from Google
  seems to have no dimensions. Store the dimensions after the first load.
- Images from Google Drive stay as chips. Showing them needs a Drive read
  scope. Decide whether that scope is acceptable.
- Animated GIFs show only their first frame. Quick Look plays them.
- "Open with Preview" in Quick Look appears to put a copy in the Documents
  folder. Not verified yet.
- Sending images (upload).


## Consider a different name

Not decided. The owner is not sure that the problem is large enough for the
work (October 7, 2026).

The name GChat is close to "Google Chat". Two problems follow:

- Confusion. During the Cloud setup, Google's own account
  chat-api-push@system.gserviceaccount.com looked like a part of this
  project.
- If the app becomes public, the name suggests a Google product. Google can
  object to that.

A rename is not a rewrite, but it changes many names at once:

- The bundle ID org.themullers.gchat. The OAuth client is registered for
  it, and macOS ties the Keychain item, the preferences, the cache and the
  notification permission to it. With a new bundle ID, each person signs in
  again and allows notifications again. The OAuth client of each
  organization needs the new bundle ID.
- The app name, the Xcode project and its targets, the GChatKit package,
  the Keychain item "GChat Google sign-in", and the text in the app.
- The relay: the address gchat-relay.themullers.org, the Compose project
  name gchat, the port registry, the Caddy block and the DNS record.
- The Cloud resources gchat-events and gchat-relay. These names are
  internal, so they can stay.
- The repository on GitHub and the link in the About window.
- All documents.

A rename is cheapest before colleagues install the app. After that, each
installed copy loses its sign-in at the update.

A smaller step, if the name stays: say in the app and in install.md that
GChat is not a Google product. install.md and the README already say so.


## A designed icon

The icon is a placeholder that a script drew: a green rounded square with a
white speech bubble. The files are in
GChat/Assets.xcassets/AppIcon.appiconset.

Replace them with a designed icon, in the sizes listed in Contents.json in
that folder. Look at it in the Dock, the app switcher, notifications, and at
16 pixels in Finder lists, in light and dark appearance. Decide whether to
supply the layered icon format that recent macOS versions use for tinted and
clear icons. Then run scripts/make-dev-icon.swift again (development.md).


## Mac conventions

GChat is a native SwiftUI app, but nobody compared it with the behavior that
experienced Mac users expect. Research first, then change the app.

A known problem: the Settings window shows a scroll bar when its content
fits. See GChat/Views/SettingsView.swift.

Sources:

- The Human Interface Guidelines of Apple for macOS.
- Writing by Mac developers and critics on what makes a real Mac app. Brent
  Simmons used the term "Mac-assed". John Gruber and others wrote about it.
- Messages, Mail, Notes and well-regarded third-party apps, side by side.

Areas to look at, to keep or replace after the research:

- Settings: no scroll bar, the standard layout, tabs if it grows.
- Menus: every action in the menu bar with a standard shortcut, complete
  Edit, View and Window menus, items disabled when they do not apply,
  context menus on conversations and messages.
- Keyboard: full keyboard control of the sidebar and the transcript, and
  predictable focus between the sidebar, the transcript and the composer.
- Windows: size, position and sidebar width restored after a launch,
  minimum sizes, behavior when the window is closed, more than one window.
- Text: text services in the composer (spelling, substitutions, dictation,
  emoji, undo), selection across messages, drag and drop.
- System: actions in notifications such as Reply, a Dock menu, Reduce
  Motion, Increase Contrast, the accent color, VoiceOver labels.
- Feel: no jumps in the layout, cached content in place of spinners, scroll
  position kept.

Most of the user interface was compiled and unit tested, but not reviewed
on screen. Expect more problems than this list.


## All of a conversation's history

Opening a conversation loads its newest 50 messages. Older messages load 50
at a time when the transcript is scrolled to the top. Nothing is kept after
GChat quits. See open() and loadOlder() in
GChatKit/Sources/GChatKit/Sync/ChatStore.swift.

Goal: the whole history of a conversation, with no manual paging. A setting
can limit it to a period, for example 30 days, 1 year or all.

Decide first:

- One conversation on request ("Load Entire History"), or all
  conversations in the background.
- The periods and the default.
- Whether to keep history on disk. Without that, each launch loads the
  whole history again, which is slow and uses quota.

Work:

- A loop over the pages of messages.list until the start of the
  conversation or the cutoff date, with progress and Cancel.
- A limit on the rate, and backoff on 429.
- A local store for messages, probably SQLite, with the newest and oldest
  loaded time of each conversation, so that later loads fetch only the gaps.
- Speed of the transcript with thousands of messages.
- Messages on disk change "What is stored on the Mac" in design.md. Decide
  where the file is, and make Sign Out delete it.

This also makes a search of message text possible.

Not verified yet: the largest page size of messages.list.


## Scroll to new messages

When a message arrives in the open conversation, the transcript must scroll
down to show it. Today it scrolls only after the person sends a message. A
message from someone else can arrive below the visible area, with no sign of
it. See TranscriptView in GChat/Views/ConversationView.swift. The transcript
uses defaultScrollAnchor(.bottom), which does not reliably follow new
content.

Decide first: what happens when the person has scrolled up to read older
messages. The usual behavior in Mac chat apps:

- If the transcript is at the bottom, scroll to the new message.
- If the person scrolled up, stay in place and show a "New messages" button
  at the bottom. A click on it scrolls down.

Work:

- Track whether the transcript is at the bottom.
- Scroll on each new message from the server, not only on a sent message.
- The "New messages" button, if chosen.
- Images that load after the scroll change the height of the transcript.
  Make sure that the last message stays visible when an image above it
  loads.

A fault in the scroll that exists today (reported October 7, 2026): after
the person sends a message, the transcript does not scroll all the way down.
The space below the last message stays hidden, so the new message sits too
close to the composer. The transcript has 12 points of padding at the bottom
and a 1 point marker that the scroll goes to. The scroll must end at the
bottom of the content, padding included. Use the same scroll for new
messages from the server.


## Notifications

GChat posts a notification for each new message from another person in a
conversation that is not on screen. The Dock icon shows the number of unread
conversations (behavior.md). See notify() in
GChat/AppModel.swift and GChat/Notifier.swift.

First, make sure that these basics work with a real account:

- The banner shows.
- A click on the banner opens the right conversation.
- The Dock shows the correct count.
- No notification comes for the person's own messages, or for the
  conversation on screen.
- macOS asks for permission once.

Then decide and build:

- Which conversations notify. Today all of them do, including busy spaces
  and meeting chats. Probably: direct messages and group chats always,
  spaces only for mentions, and a mute for each conversation.
- Whether to follow the notification configuration of Google Chat, if the
  API gives it.
- Reply and Mark as Read actions in the notification.
- Grouping, and summary text for several messages.
- Whether hidden conversations (deleted users, apps) notify.
- A more visible permission request. The macOS request is a small banner
  that is easy to miss, and GChat cannot ask again.
- Whether GChat starts at login. Notifications come only while GChat runs.


## Distribution to colleagues: what is left

Done: the Developer ID certificate, the built-in client ID, backoff on 429,
the release script, and install.md. A first disk image was notarized on
October 2, 2026.

Left:

- Where colleagues download releases, and how they learn about a new one.
  release.md has the current suggestion.
- A period of real use before the first distribution (release.md).
- A discussion with the owners of IT and security at Zia Consulting.
- Neutral versions of install.md and directory-sharing-request.md, if the
  repository is public and Zia Consulting must not appear in it.


## Quota

Google's limits, read in October 2026 at
https://developers.google.com/workspace/chat/limits:

    For each Cloud project, each minute:
      message reads         3000
      space reads           3000
      membership reads      3000
      message writes        3000
      space writes            60   (new conversations)
    For each space, each second, shared by all apps:
      reads                   15
      writes                   1

Over a limit, Google answers 429. A higher limit for a project can be
requested, but Google does not guarantee it.

One running copy of GChat uses about:

- In front with a conversation open: 20 message reads and 4 space reads a
  minute.
- In the background: 6 message reads and 2 space reads a minute.
- At the first launch: one membership read for each direct message and group
  chat, about 200 for an account with 200 conversations, at about 10 a
  second.

The limits allow about 150 copies in front at the same time, or about 500
in the background. A space open in about 45 copies at the same time reaches
the limit for one space. Zia Consulting has about 30 active employees, so
the limits are far away. The risk is many first launches in the same minute.

Done: backoff on 429 and a limit of about 10 requests a second at startup
(design.md).

Left:

- Poll less: the open conversation every 5 to 10 seconds, no polling after
  some minutes without activity, and none when the window is closed or the
  screen is locked.
- Push delivery removes most reads.
- Not verified yet: which quota the calls for read markers use. The quota
  page of the Cloud console shows it under real use.


## Startup load

GChat reads many things at the first launch, after a change of account, and
when names are missing. It reads the member list of each direct message and
group chat. It also reads the read marker of each conversation with activity
in the last 90 days. See
resolveTitles() and loadReadStates() in ChatStore.swift.

Done: about 10 requests a second, and a pause on 429.

Left:

- The conversations on screen first, then the rest.
- Members read only when a conversation first shows, not for the whole list.
- After a 429, retry the skipped items in the same session. Today the next
  refresh of the conversation list picks them up.
- No new reads at each launch. Group chats with more than eight members are
  read again at each launch when the People API gives no names.
- An indication that titles are still loading. Rows that show "Direct
  Message" or "Group Chat" for a while look like a fault.
- A test with a fake service that counts requests each second.

Batching, researched in October 2026:

- Member lists cannot be batched. spaces.members.list covers one
  conversation, and the conversation list has no members. Google's
  documentation shows no batch endpoint for the Chat API. Where other Google
  APIs batch requests, each request inside the batch counts against the
  quota.
- People lookups can be batched: people.getBatchGet takes up to 200 people.
  This helps where the People API gives names. At Zia Consulting it gives
  none.


## Automatic updates on a host for several apps

A colleague gets a new version only by installing it again. Sparkle is the
standard updater for Mac apps outside the App Store. The app reads a feed
(the appcast), shows that a new version is available, downloads it, makes
sure that it is genuine, and installs it.

Sparkle needs these files at fixed HTTPS addresses that work without a
sign-in:

- The appcast, an XML file that lists the releases.
- The update files (disk images or zips).

A Google Drive folder shared with the organization does not work, because
GChat cannot sign in to Google to download.

Make the host generic, so that other Mac apps can use it. One host, one
folder for each app:

    https://<updates host>/<app>/appcast.xml
    https://<updates host>/<app>/<app>-<build>.dmg

Choices:

- A public bucket in Hetzner object storage. No server process. Probably the
  best fit for several apps.
- A static site on the Hetzner host behind Caddy. Needs a deployment change,
  which is the job of the release manager.
- GitHub Releases and GitHub Pages. Free, with versions, but for one
  repository, so less suited to several apps.

Anyone with the address can download from any of these. The Zia build
contains the Zia Consulting client ID and name. The client is Internal, so
only Zia accounts can sign in, and the client ID is not a secret. Decide
whether that is acceptable.

In GChat:

- Sparkle as a Swift package, the first third-party dependency.
- "Check for Updates…" in the app menu, and a setting to look for updates
  automatically.
- The appcast address and the public key of Sparkle in
  Config/Base.xcconfig.
- Sparkle makes sure that the Developer ID signature and its own EdDSA
  signature are valid. Updates keep the bundle ID and the team.

Shared tools for every app:

- One script that signs a notarized disk image with sign_update of Sparkle,
  uploads it to the folder of the app, and makes the appcast again with
  generate_appcast. scripts/release.sh calls it. Keep the script in its own
  repository or as a template.
- One Sparkle key for each app. generate_keys --account <app> keeps the
  private key in the login Keychain. A leaked key then affects one app only.
  Keep a backup of each key. Without it, installed copies of that app accept
  no more updates.
- Upload credentials for the bucket stay outside the repositories.
- Release notes, optional, as HTML for each release.


## A script for certificate renewal

Low priority: the certificate is valid until 2031 (signing-certificate.md).

The App Store Connect API can make certificates. A script can do these steps:

- Make the private key and the request with openssl.
- Send the request with POST /v1/certificates, with an App Store Connect API
  key that has the Admin role.
- Download the certificate, and import it with the key into the login
  Keychain (security import).
- Print the end date.

Not verified yet: that the API has a certificate type for G2 (probably
DEVELOPER_ID_APPLICATION_G2), and that API keys can make Developer ID
certificates.
