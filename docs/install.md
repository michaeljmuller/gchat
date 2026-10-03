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
- New messages show within a few seconds. A notification can take up to 15
  seconds, because GChat asks Google for new messages at intervals.
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
  Google.

Sign Out, in Settings, deletes the token and the cached files. To remove
the access of GChat at Google, go to myaccount.google.com > Security >
Third-party apps.


## Update

Install a new version the same way, and replace the old one in the
Applications folder. The sign-in stays.
