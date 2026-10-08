# To do

Work that was left out of GChat or deferred, with the reasons, for the
developer. It is not a prioritized backlog. What GChat does today is in
behavior.md.


## Push delivery: what is left

Push delivery works for the Zia Consulting build (design.md). Left:

- Deploy the relay again. The commit of October 7, 2026, makes it send a
  line when a stream opens. Without it, each connection waits 20 seconds
  for the first keepalive.
- Look at the bytes of a real event, and make sure that it holds only
  identifiers (design.md, security rule 1).
- A notification for a message from another person has not been seen yet.
  The test message was the owner's own.
- Whether a subscription to all spaces covers a conversation that starts
  later. If not, GChat renews the subscription when the conversation list
  grows.
- One relay serves one Cloud project. Serving a second organization needs a
  second relay, or a relay that accepts pushes from several Pub/Sub
  subscriptions.
- End the Google Cloud free trial (next item).

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


## Quick Look opens empty

Seen by the owner on October 8, 2026, in the release and in a development
build: a click on an image in the transcript opened an empty Quick Look
window. A second click showed the image. Later the same day it did not
happen again. The cause is not known.

The image was on screen, so its file was in the cache before the click.
Two possible causes:

- GChat rebuilds the row of the image while the window opens, for example
  when a message arrives. The window then has no file.
- Quick Look opens before it is connected to the row. macOS finds the file
  to show through the focus of the window, and a click on an image does not
  move the focus.

GChat writes log lines for each click on an image or a file, for each
opened and closed preview, and when a view is rebuilt or removed with its
preview open (PreviewLog in GChat/Views/MessageContent.swift). After the
next empty window, read them with:

    log show --last 1h --predicate 'subsystem == "org.themullers.gchat" AND category == "preview"'

If the file was good at the click, the probable fix is one Quick Look
controller for the window in place of one for each image. Remove the log
lines when the cause is found.


## Problem reports: what is left

Help > Report a Problem makes a report with the log (design.md). Left:

- Make sure that the log shows in a report from a real build. Not verified
  inside the sandbox.
- Look at the window on screen.
- "Send to the developer" through Chat, as a file in the direct message
  with the developer. It needs file upload, which GChat does not have. A
  plain message is too short for a log: Google allows 4096 characters.
- The log covers the current run only.


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

- How colleagues learn about GChat and get the first disk image. Releases
  are in the bucket, and installed copies update themselves (release.md).
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

These numbers are for a copy that polls. A copy with push delivery polls
once a minute. One polling copy of GChat uses about:

- During a conversation: 30 space reads a minute, and one message read for
  each conversation that changed.
- After 5 minutes without a message: 2 space reads a minute, and fewer as
  the wait grows to 10 minutes.
- At the first launch: one membership read for each direct message and group
  chat, about 200 for an account with 200 conversations, at about 10 a
  second.

The limits allow about 100 polling copies in active conversations at the
same time. Zia Consulting has about 30 active employees, and their copies
use push delivery, so the limits are far away. The risks are a relay
failure during a busy time, and many first launches in the same minute.

Done: backoff on 429 and a limit of about 10 requests a second at startup
(design.md).

Done: push delivery, and polling that slows after 10 minutes without a
message (design.md).

Left:

- No polling when the screen is locked.
- Not verified yet: which quota the calls for read markers use. The quota
  page of the Cloud console shows it under real use.


## Group chats with deleted members

Google lists some old group chats as direct messages, and GChat moves them
to Groups (design.md, "Names, titles and members"). Left:

- The title names only the members that Google still lists. A group of four
  with two deleted accounts shows as "Megan". Messages from deleted accounts
  are in the transcript, so GChat can add "Deleted User" to the title after
  it loaded messages there.
- A group chat where only the signed-in person is left has the title "Group
  Chat". Before, it showed as a direct message with "Deleted User", and the
  configuration hid it. Decide whether to hide such group chats.
- Names for deleted accounts. The text of a mention keeps the name
  ("@Name") with the user ID. GChat can remember that name whenever it
  loads messages, at no extra requests, and show for example "Eric Harper
  (deleted)" in place of "Deleted User". This covers only people whom
  somebody mentioned in a conversation of the signed-in person. A scan of
  old conversations finds more, and costs requests.
- The two signs were seen in one account. If a listed direct message with
  neither sign is a group chat, GChat does not find it.


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


## Automatic updates: what is left

GChat updates itself with Sparkle from a bucket (design.md, release.md).
Left:

- The first published release, and the test of an update from end to end
  (release.md).
- Copies that colleagues installed before October 8, 2026 have no updater.
  Each needs one more installation by hand.
- Old disk images stay in the bucket. Nothing deletes them.
- Other Mac apps can use the same layout, one folder for each app.
  scripts/support/publish.sh is written for GChat. A shared script needs its own
  repository or a template, and one Sparkle key for each app, so that a
  leaked key affects one app only.
- The notes page has no styling of its own for a browser. It is a fragment
  for the update window and the Release Notes window.
- Look at the Release Notes window on screen, in light and dark appearance.


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
