# How GChat works, and its limits

The Chat API has no way to push new messages to a client app, so the app
polls: the open conversation every 3 seconds and the conversation list every
15 seconds (10 and 30 seconds when the app is in the background). The
conversation list reports each conversation's last activity time, so one
request is enough to see which conversations have something new.

Not supported in this version: more than one account at a time, replying
inside a thread (thread replies appear inline in the timeline), reactions,
editing and deleting, uploading files, creating named spaces, searching
message text, typing indicators and presence.

Messages edited or deleted elsewhere do not change in an open transcript until
the app is restarted, because polling only asks for newly created messages.
Unread markers are only loaded for conversations active in the last 90 days.

# What is stored on the Mac

- The sign-in tokens, in the login Keychain (below).
- Names, photos, conversation titles and member lists, in the app's
  preferences, for the signed-in account only. Signing in to another account
  discards them.
- Downloaded attachments, in the app's Caches folder, trimmed to 300 MB at
  launch and deleted on Sign Out.
- Messages are kept in memory only.

When the organization does not let the People API return names, names come
from the Chat API's member lists instead.


# Keychain access

GChat saves one item in your login Keychain, named "GChat Google sign-in". It
holds the tokens Google issued when you signed in: a refresh token, a
short-lived access token and its expiry time. It never holds your Google
password, which you type into the system sign-in sheet and GChat does not see.

GChat reads the item at launch to keep you signed in, and rewrites it about
once an hour. Sign Out deletes it. Deleting it yourself in Keychain Access
signs GChat out.

macOS may show a prompt saying GChat wants to use confidential information
stored in "GChat Google sign-in". That is GChat reading its own item. It
appears when the running copy of GChat is signed differently from the copy
that saved the item. Choose Always Allow. Releases and Debug builds from this
project are all signed with the same Developer ID certificate, so they do not
ask (see "Development workflow" in building.md). An ad hoc signed build
(CODE_SIGN_IDENTITY=-) asks after every rebuild.


# Source layout

    GChat.xcodeproj    Xcode project; picks up files in GChat/ automatically
    GChat/             the app: SwiftUI views, sign-in sheet, notifications
    GChatKit/          Swift package with everything that has no UI:
                       OAuth, Keychain, Chat and People API clients,
                       polling and unread tracking, text markup rendering
    Config/            build settings; Local.xcconfig (not committed) holds
                       an organization's built-in client ID
    scripts/           release.sh and the development icon generator
    docs/              everything that is not in the README
