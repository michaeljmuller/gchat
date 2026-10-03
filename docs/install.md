# GChat for Zia Consulting

GChat is a Mac app for Google Chat. It shows your direct messages, group chats,
spaces and meeting chats, and lets you read, send and get notifications,
without a browser tab. It covers basic chat only.

It is a personal project, not a Google product, and is not supported by Zia
IT. Questions go to Mike Muller.


## Install

1. Open the GChat disk image (GChat-<version>.dmg).
2. Drag GChat onto the Applications folder.
3. Open GChat from Applications. The first time, macOS asks whether to open
   an app downloaded from the internet; choose Open.

Requires macOS 15 or later.


## Sign in

Click Sign In with Google, choose your Zia Google account, and allow every
permission on Google's screen. GChat refuses to continue if one is left
unticked.

macOS shows a small banner in the top-right corner asking whether GChat may
send notifications. Choose Allow, or you will not be told about new messages.
If you missed it: GChat Settings > Notifications shows a button to fix it.


## Good to know

- Messages you send from GChat show a small label next to your name in
  Google Chat, saying they were sent from another app.
- Command-N starts a new conversation. It lists only people you already have
  a conversation with; for someone new, send the first message from
  chat.google.com.
- Command-K jumps to a conversation by name. Return sends; Shift-Return
  starts a new line.
- New messages appear within a few seconds, and notifications can take up to
  15 seconds, because the app checks for them regularly.
- Closing the window leaves GChat running so notifications keep arriving.
  Settings can change that.
- Not supported: replying inside a thread, reactions, editing or deleting
  messages, sending files, and searching message text.


## What GChat stores

- Your Google sign-in token, in your Mac's Keychain, as "GChat Google
  sign-in". Not your Google password, which GChat never sees.
- Names, photos and conversation titles, in the app's preferences on your
  Mac.
- Images and files you open, in the app's cache on your Mac, up to 300 MB.
- Messages are kept in memory only, and nothing is sent anywhere except
  Google.

Sign Out (in Settings) deletes the token and the cached files. To remove the
app's access from Google's side, go to myaccount.google.com > Security >
Third-party apps.


## Updating

Install a new version the same way, replacing the old one in Applications.
You stay signed in.
