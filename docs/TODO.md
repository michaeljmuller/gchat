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

## Display images inline

Today every attachment, images included, is shown as a chip with a paperclip
and the file name that opens in the browser. See AttachmentChip in
GChat/Views/ConversationView.swift.

Goal: show image attachments in the transcript as a thumbnail that fits the
message column, with a click to open full size (Quick Look) and the usual
drag and copy behaviour. Other file types stay as chips.

What it would take:

- Decode attachmentDataRef (and thumbnailUri) on Attachment in
  GChatKit/Sources/GChatKit/API/Models.swift; they are ignored today.
- Download uploaded images through the Chat API media endpoint with the
  user's token. AsyncImage cannot send an Authorization header, so this needs
  a small authenticated image loader in GChatKit.
- Cache downloaded images on disk, bounded in size, so scrolling and
  relaunching do not download them again.
- Reserve the image's space before it loads, so the transcript does not jump
  and the pinned-to-bottom behaviour keeps working.
- Images shared from Google Drive come as a Drive file ID, not as Chat media.
  Showing those needs a Drive read scope, which is a broad permission; decide
  whether that is acceptable or whether Drive images stay as chips.
- Animated GIFs, and images pasted as links with a preview, are separate
  cases; decide whether they are in scope.

Not verified yet: whether the existing chat.messages scope is enough for the
media download, whether thumbnailUri can be fetched with a token or only with
browser cookies, and whether the API reports image dimensions.

Related, not part of this item: sending images from the app (upload).

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
