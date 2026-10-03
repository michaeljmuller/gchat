# Functional specification

What GChat does, for anyone who uses, reviews or tests it. Why it is built
this way is in design.md. The requests behind each feature are in
requirements.md.


## Sign-in

- The sign-in screen has a Sign In with Google button. Google's sign-in page
  opens in a system sheet.
- A build with an organization's client ID shows the heading "Sign in to
  Google Chat at" and the organization name, and no field for the client ID.
  The link "Use a different organization…" shows the field. The link "Use"
  and the organization name returns to the built-in client ID.
- A build without a client ID shows a field for it.
- GChat stops the sign-in if the person signing in does not allow every
  permission on Google's consent page.
- GChat stays signed in across launches. Sign Out in Settings signs out.


## Window and sidebar

- One main window. GChat launches with no conversation selected.
- The sidebar has a tab for each kind of conversation that exists: Direct
  (direct messages), Groups (group chats), Spaces and Meetings. GChat
  remembers the selected tab. A dot on a tab means that it has unread
  conversations.
- Meeting chats are the chats that Google Meet makes for calendar events.
  GChat shows them under Meetings, with a video icon.
- In a tab, an unread conversation has a bold title and a dot.
- The date of the most recent activity is in gray at the right of each
  conversation: the time for today, "Yesterday", the weekday in the last
  week, then the date. The full date and time show on hover.
- The search field searches all four kinds of conversation together and shows
  the results under headings.
- Conversations are sorted by most recent activity, or alphabetically
  (configuration).
- A line at the bottom of the sidebar shows connection problems.
- Opening a conversation from Command-K, a shortcut or a notification selects
  its tab.


## Conversation titles

- A direct message has the other person's name.
- A group chat has the first names of the members, in alphabetical order,
  with "Deleted User" last if a member's account was deleted.
- A direct message with a deleted account is titled "Deleted User".
- A direct message with a Chat app has the app's name, or "App" if Google
  gives no name.
- Titles follow name changes on the next launch.


## Transcript

- Messages show the sender's name and avatar, the time, and a separator for
  each day. Consecutive messages from one sender within five minutes share
  one header.
- Text shows Chat markup: bold, italic, strikethrough, code, code blocks,
  links, bullets and mentions. Links are underlined and show the
  pointing-hand cursor.
- Text can be selected. The context menu has Look Up, Copy and Services.
- Images uploaded to Chat appear in the transcript, up to 360 by 270 points.
  A click opens the image in Quick Look.
- Other uploaded files appear as a chip. A click opens the file in Quick
  Look.
- The context menu of an image or a chip has Open and Save As.
- Files from Google Drive appear as a chip that opens in the browser.
- Older messages load when the transcript is scrolled to the top, or with
  Load Earlier Messages.
- Opening a conversation marks it as read here and in Google Chat on other
  devices. A conversation read on another device becomes read here too.


## Sending

- Return sends. Shift-Return or Option-Return adds a line break.
- A message shows in gray until Google accepts it. If sending fails, the
  message shows the reason, Try Again and Delete.


## New conversations

- Command-N opens the New Conversation sheet with a list of people and a
  search field.
- One selected person starts a direct message. Two or more start a group
  chat. Chat starts it and Cancel closes the sheet. A double-click on a
  person starts a direct message.
- If a direct message with that person exists, or a group chat with exactly
  those people, GChat opens it. GChat matches people by user ID.
- The list is the organization's directory, up to 2000 people.
- If the organization does not let apps read its directory, the list has the
  people from existing conversations only. A yellow triangle then shows at
  the top of the sheet. A click on it opens a panel that explains the reason
  and shows Google's error. The close button, or a second click on the
  triangle, closes the panel.


## Notifications and the Dock

- GChat posts a notification for each new message from another person in a
  conversation that is not on screen. A click opens that conversation.
- The Dock icon shows the number of unread conversations.
- Closing the window leaves GChat running, so notifications continue. A
  click on the Dock icon shows the window again.


## Keyboard shortcuts

    Command-N          New Conversation
    Command-K          jump to a conversation by name
    Command-1 to 9     the nine most recently active conversations
    Command-R          refresh the conversation list and the open
                       conversation
    Command-comma      Settings
    Return             send
    Shift-Return       line break


## Settings window

General:

- Quit GChat when the window is closed. Off by default.

Sidebar:

- Sort conversations: most recent first (default) or alphabetically.
- Show date of last activity. On by default.
- Hide direct messages with deleted users. On by default.
- Hide direct messages with apps. Off by default. When on, the next setting
  is on and locked.
- Hide direct messages with unnamed apps. On by default.

The settings for hidden conversations also apply to Command-K and to
Command-1 to Command-9.

Notifications:

- Notify me about new messages. On by default.
- Show message text in notifications. On by default.
- If macOS has notifications turned off for GChat, a warning shows with a
  button that opens System Settings.

Account:

- The signed-in name and email address, the OAuth client ID, and Sign Out.


## About window

GChat > About GChat shows "Version" with the commit ID and, in brackets, the
build number, then the build date and a link to the source code. A
development build shows "Version development".


## Messages sent from GChat

Google Chat shows a label next to the sender's name on messages that GChat
sends. The label has the app name from the organization's Cloud project.
Google adds it to every message sent through the API.
