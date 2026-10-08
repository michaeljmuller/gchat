# Requirements

What the owner of the project asked for, in the owner's terms, with the date
of the request. What the app does is in behavior.md. Every feature
there must trace to an item here.

The quotes are from the conversation in which the app was built.


## The app

- A native Mac client for Google Chat, for the time when Google Chat had no
  Mac app. "I don't want to replicate all the features, just basic chat
  functionality." (October 2, 2026)
- A "mac-assed" Mac app, "not a wrapper around a web app or a electron bs."
  (October 2, 2026)
- One account for now. Tested on the owner's personal Workspace, used mostly
  for work. (October 2, 2026)
- Instructions for the Google Cloud console setup in the documentation.
  (October 2, 2026)


## Approved in the initial plan

The owner approved a plan on October 2, 2026, that added these features to
"basic chat":

- A sidebar with direct messages and spaces, unread markers and a search
  field.
- A transcript with sender names, avatars, times and day separators, and
  older messages on scroll.
- A composer: Return sends, Shift-Return adds a line break. A message that
  fails to send shows Try Again and Delete.
- Chat markup: bold, italic, strikethrough, code, links, mentions.
- Attachments as a chip that opens the file.
- Command-K to jump to a conversation, Command-1 to Command-9 for recent
  conversations, a Settings window, standard menus.
- Notifications for new messages, and a count of unread conversations on the
  Dock icon.
- Read markers kept in step with Google Chat on other devices.


## Conversations

- Start a conversation with a person in the organization, or resume the
  existing one. (October 2, 2026)
- Command-N opens a list of people. Select one or more people and click Chat,
  or click Cancel. Double-click one person to start a direct message.
  (October 2, 2026)
- If a conversation with the same people exists, open it, not a new one.
  Match people by ID, not by display name. (October 2, 2026)
- Titles follow name changes on the next launch. (October 2, 2026)
- Launch with no conversation selected. (October 2, 2026)


## Sidebar

- Group chats separate from direct messages. (October 2, 2026)
- Meeting chats separate from the spaces that people created. (October 2,
  2026)
- Section names that stay visible and go to their section on a click. Then
  changed to a tabbed view, one tab for each section. (October 2, 2026)
- The date of the most recent activity, in gray, next to each conversation.
  (October 2, 2026)


## Configuration

All in the Settings window (October 2, 2026, unless stated):

- Hide direct messages with deleted users. On by default.
- Show the date of the most recent activity. On by default.
- Sort conversations alphabetically, as an alternative to most recent first.
- Hide direct messages with apps. When on, it also turns on and locks the
  setting "Hide direct messages with unnamed apps".
- Quit when the window is closed. Off by default.


## Directory access

- When the organization does not let apps read its directory, the New
  Conversation sheet shows a yellow triangle at the top. A click on the
  triangle opens a panel with a short explanation. A close button and a
  second click on the triangle close the panel. (October 2, 2026)
- No Check Again link, and no warning in Settings. (October 2, 2026)
- Less space between people in the list. (October 2, 2026)


## Messages and attachments

- When a message comes in, the view scrolls down to show it. (October 6,
  2026)
- The scroll goes all the way down. The newest message does not sit against
  the input field. (October 7, 2026)
- The owner asked for a "mac-assed" app (see "The app"). The scroll follows
  from that request in one case that the owner did not describe: when the
  person scrolled up to read older messages, a new message does not move
  the view. A "New messages" button shows, and a click on it scrolls to the
  end. Mac chat apps commonly behave this way. The owner confirmed this
  reading on October 7, 2026.
- A click on an image must not open a browser page that fails. (October 2,
  2026)
- Images shown in the conversation. (October 2, 2026)
- The pointing-hand cursor over links. (October 2, 2026)


## Prompt delivery

- New messages without the delay of polling. "polling's kinda janky."
  (October 6, 2026)
- No extra step for colleagues: "I'd like someone to just sign in, accept
  the grant for access to Google, and be running." (October 6, 2026)
- A sign in the app when the relay is down and the app polls: "New message
  notification server is down; polling for new messages every X second."
  (October 7, 2026)
- While the app polls, the rate follows activity: fast during a
  conversation, slower after a while without messages. (October 7, 2026)
- One check, not a separate one for the open conversation. A wait that
  backs off exponentially. (October 7, 2026)
- The sidebar line for a relay that is down shows, live, when the next
  check happens. (October 7, 2026)
- The polling wait can grow to 10 minutes, with a "check now" button.
  (October 7, 2026)
- The same rate in the background as in front: "might be actively working
  on something with a colleague and swapping back and forth." (October 7,
  2026)
- Fewer attempts to reach a relay that is down: waits that grow to 15
  minutes. An attempt at once when a message is sent or received. (October
  7, 2026)
- No message content on the owner's server. A compromised server can show
  that a message arrived, but not what it says. (October 6, 2026)


## Sign-in and the Keychain

- An explanation of why GChat uses the Keychain, so that people do not worry
  about the prompt. Keep the token in the Keychain. (October 2, 2026)


## Distribution

- Package the app for colleagues at Zia Consulting. (October 2, 2026)
- The organization's client ID inside the app, so that colleagues do not
  paste it. (October 2, 2026)
- An app icon. (October 2, 2026)
- A different icon for development builds, for example a hammer on the normal
  icon. (October 3, 2026)
- The commit ID as the version. The About window shows the version, the build
  number, the build date and a link to the source on GitHub. (October 2,
  2026)
- The About window says "a vibe-coded native Mac application for Google
  Chat", and shows no "(1)" for a development build. Its version line has
  the form "(commit 112 at Oct 7, 2026 12:04 PM)". A development build says
  that it is one, with the date and time of the build, because it can
  contain code that is not committed. (October 7, 2026)
- A development workflow: use the released app every day, use the
  development build only to review a change, and switch between them with no
  friction. (October 3, 2026)
- The app sees that a new version exists, and updates itself. The version
  stays the number of commits. Releases are in the Hetzner bucket
  mmuller-gchat. (October 8, 2026)
- Release notes, written by Claude Code when a release is published. The
  notes of the first release list the core features. The update window
  shows the notes of all releases since the version that runs, not only of
  the newest. A style guide in docs/ keeps the notes of all releases
  consistent, also when they show together. (October 8, 2026)
- The release notes can be read in the app without an update, in a window.
  The app contains its notes, so the window needs no network and marks no
  section as the current version. The update window shows the newer notes.
  (October 8, 2026)


## Added without a request

These features trace to no request. The owner must keep or remove each
one:

- Unread dots on the sidebar tabs.
- A warning in Settings when macOS has notifications turned off for GChat,
  with a button that opens System Settings.
- Save As in the menu of an image or a file.
- A line at the bottom of the sidebar for connection problems, including the
  message "Google asked GChat to slow down".
- A list of people from existing conversations in the New Conversation sheet,
  when the directory is not available.
- Edited and deleted messages change in an open conversation at once, when
  push delivery works. The events for them came with push delivery.
- Two settings for updates: "Check for updates automatically" and
  "Download and install updates automatically".
- The editor that opens with the release notes before a release is
  published, and the --no-edit option that skips it.
