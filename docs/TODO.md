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

## Display images inline (mostly done)

Images uploaded to Chat are downloaded through the Chat API with the user's
sign-in, cached in Caches/attachments (300 MB, least recently used first),
and shown in the transcript at up to 360 by 270 points; click opens Quick
Look, right-click offers Save As. See GChat/Views/MessageContent.swift.

Left to do:

- The row shows a fixed-size placeholder until the image loads, then
  resizes, which can make the transcript jump. Google's attachment data
  does not seem to include dimensions; remember them per attachment after
  the first load.
- Images shared from Google Drive stay as chips; showing them needs a Drive
  read scope. Decide whether that is acceptable.
- Animated GIFs show their first frame inline (Quick Look plays them).
- "Open with Preview" from the Quick Look window appears to leave a copy in
  Documents, because Preview cannot read the app's sandbox. Not confirmed.
- Sending images from the app (upload) is not part of this.

## Give the app a proper icon

The current icon is a placeholder drawn by a script: a green rounded square
with a white speech bubble and three dots. The PNGs are in
GChat/Assets.xcassets/AppIcon.appiconset.

To do: design a real icon and replace those files. Keep the sizes listed in
that folder's Contents.json (16 to 1024 pixels). Check how it looks in the
Dock, in the app switcher, in notifications and at 16 pixels in Finder lists,
in both light and dark appearance. Consider whether to supply the newer
layered icon format that recent macOS versions use for tinted and clear
icon styles.

## Research what makes an app "Mac-assed" and refactor to match

The app is native SwiftUI, but it has not been checked against what long-time
Mac users expect from a good Mac app. Research first, then refactor.

Known example: the Settings window shows a scroll bar even though its content
fits. See GChat/Views/SettingsView.swift (a grouped Form with a fixed width).

Research:

- Apple's Human Interface Guidelines for macOS: windows, sidebars, toolbars,
  menus, settings, keyboard, notifications.
- Writing on the subject by Mac developers and critics (the term comes from
  Brent Simmons; John Gruber and others have written about what separates a
  real Mac app from a port).
- Reference apps to compare against side by side: Messages, Mail, Notes, and
  well-regarded third-party apps.

Things to check in this app, to be confirmed or replaced by the research:

- Settings: no stray scroll bar, standard pane layout, toolbar tabs if it
  grows, changes apply immediately.
- Menus: every action reachable from the menu bar with a standard shortcut;
  Edit, View and Window menus complete; items disabled when they do not
  apply; contextual menus on sidebar rows and messages.
- Keyboard: full keyboard navigation of sidebar and transcript, focus moving
  predictably between sidebar, transcript and composer, Escape and Return
  behaving as in system apps.
- Windows: size, position and sidebar width restored on relaunch; sensible
  minimum sizes; behaviour when the window is closed and the Dock icon is
  clicked; whether more than one window should be possible.
- Text: system text services in the composer (spelling, substitutions,
  dictation, emoji picker, undo), selection and copy across messages,
  Look Up and Services on message text, drag and drop of text.
- Toolbar and sidebar: standard toolbar items, sidebar toggle, section
  collapse state remembered, unread badges in the system style.
- System integration: notification actions such as reply, Dock menu, Handoff
  or Spotlight if they make sense, respecting Reduce Motion, Increase
  Contrast and accent colour, VoiceOver labels.
- Feel: no layout jumps, no spinners where cached content could show, scroll
  position preserved, native materials, nothing that looks like a web page.

Most of the UI has only been compiled and unit tested, not reviewed on
screen, so expect to find more than is listed here.

## Load the whole conversation history, or back to a chosen date

Today opening a conversation loads the newest 50 messages. Older ones load 50
at a time when you scroll to the top or click Load Earlier Messages. Nothing
is kept between launches. See open() and loadOlder() in
GChatKit/Sources/GChatKit/Sync/ChatStore.swift.

Goal: have the full history of a conversation available, or everything back
to a period the user picks (for example 30 days, 1 year, everything), without
paging by hand.

Decisions to make first:

- Per conversation on demand ("Load Entire History" command), or
  automatically for every conversation in the background.
- The period choices and the default, as a setting.
- Whether history is kept on disk. Without that, a full load is repeated
  on every launch, which is slow for long conversations and uses API quota.

What it would take:

- A loop over messages.list pages until the start of the conversation or the
  cutoff date, with progress shown and a way to cancel.
- Rate limiting, so loading many conversations does not hit the Chat API
  per-user quota, and backing off when it does.
- A local store for messages (SQLite is the likely fit), keyed by message
  name, with the newest and oldest loaded time per conversation so that only
  the gaps are fetched later.
- Transcript performance with thousands of messages: check that the lazy
  list stays smooth and that row grouping is not recomputed for the whole
  conversation on every change.
- Storing messages on disk changes the privacy note in the README, which
  says messages are kept in memory only. Decide where the file lives and
  that Sign Out deletes it.

This would also make searching message text possible, which the app cannot do
today.

Not verified yet: the Chat API quota numbers and the largest page size
messages.list accepts.

## Notifications

The app posts a system notification for new messages from other people in
any conversation that is not in front, and shows the count of unread
conversations on the Dock icon. Settings can turn notifications off and hide
the message text. See notify() in GChat/AppModel.swift and
GChat/Notifier.swift. None of this has been checked with real incoming
messages yet.

To do first: verify the basics on a real account. A banner appears, clicking
it opens the right conversation, the Dock badge counts correctly and clears,
nothing is posted for your own messages or for the conversation in front,
and macOS asks for notification permission once.

Then decide and build:

- Which conversations notify. Today all of them do, including busy spaces
  and meeting chats. Likely wanted: direct messages and group chats always,
  spaces only when you are mentioned, with a per-conversation mute.
- Whether to follow the notification settings you have in Google Chat, if
  the API exposes them, so the app and the phone agree.
- Reply from the notification, and a Mark as Read action.
- Grouping and summary text when several messages arrive together.
- Whether hidden conversations (deleted users, apps) should ever notify.
- Sound choice, and respecting Focus modes (the system handles Focus, but
  check that time-sensitive delivery is not needed).
- Delay. With polling, a notification can lag up to 15 seconds, or 30 when
  the app is in the background. Push delivery (first item in this file)
  would fix that.
- Notifications only arrive while the app is running. Decide whether it
  should keep running without a window, or start at login.

## Package the app for other employees in the organization (mostly done)

Done: Developer ID certificate (docs/signing-certificate.md), built-in client
ID (Config/Local.xcconfig), backoff on 429, release script
(scripts/release.sh VERSION) that builds, signs, notarizes and makes a disk
image, and an install page for colleagues (docs/install.md). Version 0.1 was
built and notarized on October 2, 2026.

Left to do:

- Decide where colleagues download it from, and how they hear about new
  versions. There is no updater; consider Sparkle if releases are frequent.
- A round of real use before handing it out: notifications, sending,
  scrolling, group chats and sign-out have not been reviewed on screen.
- Clear the plan with whoever owns IT or security at work.

## Quota when many people use one client

Google's limits (https://developers.google.com/workspace/chat/limits, read
October 2026). Per Cloud project, per minute: 3000 message reads, 3000 space
reads, 3000 membership reads, 3000 message writes, 60 space writes (creating
conversations). Per space, per second, shared by all apps: 15 reads, 1
write. Over the limit, Google answers 429 and recommends exponential
backoff. A per-project increase can be requested but is not guaranteed.

What one running copy of the app uses:

- Frontmost with a conversation open: about 20 message reads and 4 space
  reads per minute.
- In the background with a conversation selected: about 6 message reads and
  2 space reads per minute.
- At first launch, or after the cache is cleared: one membership read per
  direct message and group chat, in a burst. About 200 for an account with
  200 conversations.

What that allows on one shared client:

- Message reads are the first limit: about 150 people with the app
  frontmost at the same moment, or about 500 with it in the background.
- First launches: about 15 people with 200 conversations each launching for
  the first time in the same minute use up the membership reads.
- One space open in about 45 copies at once reaches the per-space read
  limit of 15 per second.

So a few dozen colleagues are well within the limits. A few hundred need
changes first.

The organization has about 30 active employees. All 30 with the app
frontmost use about 600 of the 3000 message reads per minute, so the items
below are good practice, not blockers. The one case to avoid is everyone
installing in the same few minutes: 30 first launches at once would exceed
the membership reads. Stagger the rollout, or add the backoff first.

To do:

- The app does not back off when it gets 429; it keeps polling at the same
  rate. Add exponential backoff and show a "slowed down" state. Do this
  before sharing the client with anyone.
- Throttle the first-launch load. See "Throttle the initial conversation
  load" below.
- Poll less often: slow the open conversation to 5 to 10 seconds, stop
  polling after some minutes without user activity, and stop when the
  window is closed or the screen is locked.
- Push delivery (first item in this file) removes most reads.
- Not found in Google's table: which quota the read-marker calls count
  against. Check in the Cloud console's quota page under real use.


## Throttle the initial conversation load

On a first launch, after signing in to a different account, or when names
are missing, the app reads the member list of every direct message and group
chat to build titles, and the read marker of every conversation active in
the last 90 days. It runs four requests at a time with no delay between
them, so an account with 200 conversations sends a few hundred requests in
the first seconds. See resolveTitles(), loadReadStates() and
forEachLimited() in GChatKit/Sources/GChatKit/Sync/ChatStore.swift.

Membership reads are limited to 3000 per minute for the whole Cloud project,
so many people doing this in the same minute would exceed it.

To do:

- Rate-limit the startup requests to a fixed budget, for example 2 to 5 per
  second per copy of the app, instead of as fast as four connections allow.
- Order the work so what is on screen comes first: the selected tab's
  conversations, most recently active first, then the rest in the
  background.
- Load lazily where possible: resolve a conversation's members when its row
  first becomes visible, not for the whole list up front.
- On a 429 answer, pause the whole queue with exponential backoff and
  resume; do not drop the item. Today a failed lookup is not retried until
  the next launch.
- Do not repeat the work on later launches. Group chats with more than
  eight members are currently looked up again at every launch when the
  People API gives no names.
- Show that titles are still loading, so rows that read "Direct Message" or
  "Group Chat" for a while do not look like a bug.
- Add a test with a fake service that counts requests per second.

Batching, looked into October 2026:

- Member lists cannot be batched. The Chat API lists members one
  conversation at a time (spaces.members.list); there is no call that
  returns members for several conversations, and the conversation list does
  not include members. No batch endpoint for the Chat API was found in
  Google's documentation. Where Google APIs do offer HTTP batching, each
  inner request still counts against the quota, so it would save
  connections, not quota.
- People lookups can be batched. people.getBatchGet takes up to 200 people
  per request. Replace the one-request-per-person lookups with it. This
  helps most where the People API returns names (the family Workspace); at
  work it returns none.
- The bigger saving is to make fewer member-list calls at all: only for
  conversations on screen, and never again once the members are cached.
