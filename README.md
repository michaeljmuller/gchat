# GChat

A native Mac client for Google Chat. SwiftUI, no web view, no third-party
dependencies. It covers basic chat: the conversation list, reading, sending,
unread markers and notifications.

It talks to the Google Chat REST API as you, using an OAuth client that you
create in your own Google Cloud project. Google Chat's API only works for
Google Workspace accounts; personal gmail.com accounts cannot use it.


## Google Cloud console setup

Do this once per Workspace organization. If you use the app with two
organizations (personal and work), do it in each one and keep both client IDs.
It takes about ten minutes. Nothing here costs money.

The console's page names change from time to time. If a label below does not
match, search for it in the console's search bar at the top.

1. Create a project

   Open https://console.cloud.google.com/ and sign in with the Workspace
   account you want to chat from. Click the project picker in the top bar,
   then New Project. Name it anything (for example "GChat Mac"). Make sure
   Organization shows your Workspace domain, not "No organization"; the
   Internal setting in step 4 depends on it. Click Create, then select the
   new project in the project picker.

2. Enable the two APIs

   Go to APIs & Services > Library. Search for "Google Chat API", open it,
   click Enable. Go back to the Library, search for "People API", open it,
   click Enable. The People API is what turns user IDs into names and photos.

3. Configure the Chat app

   Google requires every project that calls the Chat API to have a Chat app
   configured, even when it only acts as you. Calls fail until this is saved.

   Go to APIs & Services > Enabled APIs & services > Google Chat API, then
   the Configuration tab. Fill in:

   - App name: GChat Mac (anything)
   - Avatar URL: any https image URL, for example
     https://developers.google.com/chat/images/quickstart-app-avatar.png
   - Description: Native Mac client (anything)
   - Interactive features: turn this off. The app never receives events, and
     with it off the page asks for nothing else.

   Click Save. This does not publish anything to other people.

4. Set up the consent screen

   Go to Google Auth Platform (older consoles call it APIs & Services >
   OAuth consent screen). If it shows Get started, click it and enter:

   - App name: GChat Mac
   - User support email: your address
   - Audience: Internal. This limits sign-in to your organization, needs no
     Google review, and the sign-in does not expire.
   - Contact email: your address

   Then open Data Access, click Add or remove scopes, and paste these lines
   into the "Manually add scopes" box:

       https://www.googleapis.com/auth/chat.spaces.readonly
       https://www.googleapis.com/auth/chat.spaces.create
       https://www.googleapis.com/auth/chat.messages
       https://www.googleapis.com/auth/chat.memberships.readonly
       https://www.googleapis.com/auth/chat.users.readstate
       https://www.googleapis.com/auth/directory.readonly
       openid
       https://www.googleapis.com/auth/userinfo.email
       https://www.googleapis.com/auth/userinfo.profile

   Click Add to table, then Update, then Save.

   What they are for: list your conversations, start a direct message or
   group chat, read and send messages, list members (to name direct messages),
   read and set unread markers, list the organization's people with their
   names and photos, and identify you.

5. Create the OAuth client

   In Google Auth Platform open Clients (older consoles: APIs & Services >
   Credentials), click Create client (or Create credentials > OAuth client
   ID) and enter:

   - Application type: iOS. This is correct for a Mac app; it is the client
     type with no secret that redirects back to a native app.
   - Name: GChat Mac
   - Bundle ID: org.themullers.gchat
   - App Store ID and Team ID: leave empty

   Click Create. Copy the Client ID. It looks like
   1234567890-abc123.apps.googleusercontent.com. You can find it again
   later on the Clients page. It is an identifier, not a secret.

6. Sign in

   Start GChat, paste the client ID, click Sign In with Google. A browser
   sheet opens. Choose your Workspace account and allow every permission
   listed; the app refuses to continue if one is left unticked.

To switch organizations, choose Sign Out in Settings, paste the other
organization's client ID, and sign in again.

### If something goes wrong

During sign-in, in the browser sheet:

- "Access blocked: GChat Mac can only be used within its organization"
  (Error 403: org_internal). You picked an account outside the organization
  that owns the project. Pick the right account, or create the project in
  the other organization.
- "Error 400: admin_policy_enforced". The Workspace admin restricts which
  apps may use Chat data. An admin has to allow it in the Admin console
  under Security > Access and data control > API controls: either tick
  "Trust internal apps" or add this client ID as a trusted app.
- "Error 401: invalid_client". The client ID has a typo or was deleted.
- "Error 400: invalid_request" or "redirect_uri_mismatch". The client was
  not created with application type iOS. Create a new one (step 5).

After sign-in, in the app:

- "Google Chat API has not been used in project ... or it is disabled".
  Step 2 was skipped. Enabling can take a minute to take effect.
- "Google Chat app not found. To create a Chat app, you must turn on the
  Chat API and configure the app in the Google Cloud console." Step 3 was
  skipped or not saved.
- "These permissions were not granted". A box was left unticked on the
  consent page. Sign in again and allow all of them.
- "Request had insufficient authentication scopes". A scope was added to
  the project after you signed in. Sign out and sign in again.
- People show as "Unknown" and direct messages as "Direct Message". The
  People API is not enabled (step 2), or the organization has contact
  sharing turned off (Admin console > Directory > Directory settings).
- The New Conversation sheet says the directory could not be loaded, with
  "The G Suite domain admin has disabled external directory sharing". The
  organization shares only the signed-in user's own profile with third-party
  apps, not the directory. A Workspace super admin can change that in the
  Admin console under Directory > Directory settings > Sharing settings >
  External Directory sharing, from "Authenticated user basic profile fields"
  to "Organization data and authenticated user basic profile fields". It
  applies to every third-party app in the organization. Until then the sheet
  lists only people you already have a conversation with.
- "Your sign-in has expired". The refresh token was revoked or, if the
  consent screen audience is External and in Testing, it expired after 7
  days. Use Internal (step 4).


## Building

Requirements: a Mac with Xcode 16 or later. The app runs on macOS 15 or later.

In Xcode: open GChat.xcodeproj and press Run.

Both Debug and Release builds are signed with the "Developer ID Application"
certificate of the team set in the build settings (DEVELOPMENT_TEAM,
currently 84URFQ3GPW). Debug builds use it too, not a development
certificate, on purpose; see "Development workflow" below. To build under
another team, change DEVELOPMENT_TEAM, and have a Developer ID Application
certificate for that team in your keychain. The first signed build shows a
Keychain prompt asking whether codesign may use the signing key. Choose
Always Allow, otherwise command line builds wait on that prompt forever.

From the command line:

    xcodebuild -project GChat.xcodeproj -scheme GChat -configuration Release \
        -derivedDataPath build build

The app is then at build/Build/Products/Release/GChat.app. Copy it to
/Applications.

Debug builds use a separate icon with an orange hammer badge, so a
development copy is easy to tell from a release. It is generated from the
normal icon by scripts/make-dev-icon.swift; run that again after changing
the icon.

To make a signed, notarized disk image for other people, run
scripts/release.sh; see the comments at its top for what it needs. The
About window shows the commit the release was built from, the build number
(the number of commits) and the build date.

To build a copy for an organization with its OAuth client ID built in, copy
Config/Local.xcconfig.example to Config/Local.xcconfig and fill in the client
ID and organization name. That file is not committed. A build with a
built-in ID shows only a Sign In button; "Use a different organization…" on
the sign-in screen still allows pasting another client ID. Without the file,
the sign-in screen asks for the client ID as before.

To build without an Apple Developer account, add
CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= CODE_SIGN_STYLE=Automatic to the
xcodebuild command. That signs for this Mac only. The Keychain treats
differently signed builds as different apps, so you may be asked for Keychain
access or have to sign in again after switching between them.


## Development workflow

The aim is to use the same build coworkers use every day, and switch to a
development build only while reviewing a new feature.

1. Everyday copy: the latest release, installed in /Applications from the
   disk image that scripts/release.sh makes, the same file coworkers get.
2. Reviewing a change: quit GChat, then run the Debug build (Xcode's Run, or
   build/Build/Products/Debug/GChat.app). Its icon has an orange hammer badge
   and its About window says "Version development".
3. When the change is ready: commit, run scripts/release.sh, install the new
   disk image over the copy in /Applications, use it for a while, then hand
   it out.

Only one of the two can run at a time. Both have the bundle ID
org.themullers.gchat, so macOS treats them as the same app; opening one while
the other is running brings the running one to the front. A separate bundle
ID for development builds would allow both at once, but was decided against:
it would need its own sign-in, settings and notification permission, and
possibly its own OAuth client.

Why Debug builds are signed with the Developer ID certificate: the Keychain
lets an app read its saved sign-in only if the app's signature matches the
one that saved it. macOS identifies a Developer ID signed app by its team and
bundle ID, so Debug and Release builds signed this way count as the same app,
and switching between them neither asks for Keychain access nor signs you
out. With Debug builds signed by the development certificate, every switch
in either direction would ask until each was allowed, and a denied prompt
would sign the other copy out.

Costs of this choice: Developer ID is meant for distribution, not
development, though nothing enforces that outside the App Store. A Debug
build is signed exactly like a release, so only its icon and About window
tell it apart; do not hand Debug builds to anyone. Debug builds still carry
the permission Xcode's debugger needs (get-task-allow); releases do not.

Tests for the non-UI code:

    cd GChatKit && swift test


## Using it

- Sidebar: tabs for direct messages, group chats, spaces and meeting chats,
  most recently active on top. A dot on a tab means it has unread
  conversations. Searching looks through all four. Meeting chats are the ones
  Google Meet creates for calendar events; Google does not label them, so
  the app treats a named space without threading as a meeting chat. A dot and bold title mean unread. The search field filters.
- Command-N starts a new conversation. Pick one person for a direct message
  or several (Command-click or Shift-click) for a group chat, then click
  Chat. Double-clicking a person starts a direct message straight away. If
  a conversation with those people already exists, it is opened. The list
  comes from the organization's directory and is cut off at 2000 people.
- Return sends. Shift-Return or Option-Return starts a new line.
- Command-K jumps to a conversation by name. Command-1 to Command-9 open the
  nine most recently active conversations. Command-R refreshes.
- Scroll to the top of a conversation to load earlier messages.
- Notifications arrive for messages in conversations you are not looking at.
  Clicking one opens that conversation. The Dock badge counts unread
  conversations.
- Closing the window leaves GChat running, so notifications keep arriving;
  click the Dock icon to bring the window back. A setting makes closing the
  window quit the app instead.
- Settings (Command-comma): sort the sidebar by most recent activity or
  alphabetically, show or hide the date of last activity next to each
  conversation, hide direct messages with deleted users and with apps that Google
  gives no name for (both hidden by default), hide direct messages with all
  apps (off by default),
  the notification options, and Sign Out.
- Reading a conversation here marks it read in Google Chat on your other
  devices, and the other way round.


## Keychain access

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
ask (see "Development workflow"). An ad hoc signed build
(CODE_SIGN_IDENTITY=-) asks after every rebuild.


## How it works, and its limits

The Chat API has no way to push new messages to a client app, so the app
polls: the open conversation every 3 seconds and the conversation list every
15 seconds (10 and 30 seconds when the app is in the background). The
conversation list reports each conversation's last activity time, so one
request is enough to see which conversations have something new.

Not supported in this version: more than one account at a time, replying
inside a thread (thread replies appear inline in the timeline), reactions,
editing and deleting, inline images, uploading files, creating named
spaces, typing indicators and presence.

Messages edited or deleted elsewhere do not change in an open transcript until
the app is restarted, because polling only asks for newly created messages.
Unread markers are only loaded for conversations active in the last 90 days.

Images uploaded to Chat are shown in the transcript; click one to open it in
Quick Look. Other uploaded files appear as a chip that opens in Quick Look.
Right-click either for Save As. Downloaded files are kept in the app's Caches
folder, trimmed to 300 MB at launch and deleted on Sign Out. Google Drive
attachments open in the browser.

Tokens are stored in the login Keychain. Names, photos and conversation titles
are cached in the app's preferences. Messages are kept in memory only.


## Layout

    GChat.xcodeproj    Xcode project; picks up files in GChat/ automatically
    GChat/             the app: SwiftUI views, sign-in sheet, notifications
    GChatKit/          Swift package with everything that has no UI:
                       OAuth, Keychain, Chat and People API clients,
                       polling and unread tracking, text markup rendering
