# GChat for Zia Consulting

Installing GChat and signing in, for Zia Consulting colleagues. What GChat
does in detail is in behavior.md.

GChat is a Mac app for Google Chat. It shows direct messages, group chats,
spaces and meeting chats, and it posts notifications for new messages,
without a browser tab. It covers basic chat only.

GChat is a personal project of Mike Muller. It is not a Google product, and
Zia IT does not support it. Questions go to Mike Muller.

GChat needs macOS 15 or later.


## Install

1. Open the GChat disk image (GChat-VERSION.dmg).
2. Drag GChat onto the Applications folder.
3. Open GChat from the Applications folder. The first time, macOS asks
   whether to open an app downloaded from the internet. Click Open.


## Sign in

1. Click Sign In with Google.
2. Select the Zia Google account.
3. Allow every permission on Google's page. GChat stops the sign-in if a
   permission is not allowed.

After the sign-in, macOS shows a small notification in the top-right corner
of the screen. It asks whether GChat can send notifications. Click Allow.
Without it, GChat cannot announce new messages. If the notification went
away, GChat shows a warning in Settings > Notifications, with a button that
opens System Settings.


## Things to know

- Google Chat shows a small label next to the sender's name on messages sent
  from GChat. The label says that the message came from another app.
- Command-N starts a conversation. It lists only people who already have a
  conversation with the person signed in. The first message to anyone else
  must go through chat.google.com.
- Command-K jumps to a conversation by name. Return sends a message.
  Shift-Return adds a line break.
- New messages show within about a second. If the relay of GChat cannot be
  reached, GChat says so at the bottom of the sidebar and checks for
  messages at intervals. After a long time without messages, an interval
  can be up to 10 minutes. The Check Now button checks at once.
- Closing the window leaves GChat running, so notifications continue. A
  setting changes this.
- GChat cannot reply inside a thread, add reactions, edit or delete
  messages, send files, or search message text.


## What GChat keeps on the Mac

- The sign-in token from Google, in the login Keychain, as "GChat Google
  sign-in". GChat never sees the Google password.
- Names, photos and conversation titles, in the preferences of the app.
- Images and files that were opened, in the cache of the app, up to 300 MB.
- Messages stay in memory only. GChat sends nothing anywhere except to
  Google. To look for a new version, GChat reads a file on a server that
  Mike Muller rents. That request holds the version of GChat and of macOS,
  and nothing about the account or the messages.

Sign Out, in Settings, deletes the token and the cached files. To remove
the access of GChat at Google, go to myaccount.google.com > Security >
Third-party apps.


## Update

GChat looks for a new version once a day. When one exists, a window shows
what changed. Click Install Update. GChat downloads the new version,
replaces itself and starts again. The sign-in stays.

To look at once, choose GChat > Check for Updates. Settings > General has
a setting that installs new versions without a question.

A copy from before October 8, 2026 has no Check for Updates in the GChat
menu. Install the new disk image once, the same way as the first time, and
replace the old copy in the Applications folder.
