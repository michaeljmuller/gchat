# Building, development and releases

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


# Development workflow

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
