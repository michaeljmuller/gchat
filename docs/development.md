# Development

Building, testing and reviewing changes to GChat, for the developer. What
must be installed first is in prerequisites.md. Making a release is in
release.md.


## Build

In Xcode, open GChat.xcodeproj and click Run.

From the command line:

    xcodebuild -project GChat.xcodeproj -scheme GChat -configuration Debug \
        -derivedDataPath build build

The app is then at build/Build/Products/Debug/GChat.app.

The first build with a signing key shows a Keychain prompt that asks whether
codesign can use the key. Click Always Allow. If nobody answers the prompt,
a command line build waits forever.

Debug builds are signed with the Developer ID Application certificate, like
releases. design.md gives the reason. To build under a different team,
change DEVELOPMENT_TEAM in the project and install that team's Developer ID
Application certificate.

To build without an Apple Developer account, add these settings to the
xcodebuild command:

    CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= CODE_SIGN_STYLE=Automatic

The result runs only on the Mac that built it. Each such build has a new
signature, so the Keychain asks for access after each build.


## Organization builds

If Config/Local.xcconfig exists, the build contains its client ID and
organization name. The sign-in screen then shows only a Sign In button.
Without the file, the sign-in screen asks for the client ID.
Config/Local.xcconfig.example shows the format. The file is not in git.

A Debug build has no updater (design.md), so it never replaces itself with
a release.


## Tests

The tests cover GChatKit, the code without a user interface. They need no
network:

    cd GChatKit && swift test

The views have no automated tests. Changes to the views need a review on
screen.


## The relay

The relay is a Python service in src/python/relay. It runs in a container
on the Mac, with nothing installed. Its tests:

    cd src/docker
    docker compose --profile tools run --rm --build tests

Running it locally, and deploying it, are in deployment.md.


## Development icon

Debug builds use the icon in GChat/Assets.xcassets/AppIconDev.appiconset: the
normal icon with an orange hammer badge. scripts/make-dev-icon.swift draws
it from the normal icon. After a change to the normal icon, run:

    swift scripts/make-dev-icon.swift

If the Dock or Finder shows an old icon after a build, refresh the cache of
macOS for the app:

    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f build/Build/Products/Debug/GChat.app


## Review a change

The owner uses the released app every day and switches to a Debug build
only to review a change:

1. The everyday copy is the latest release in /Applications, made from the
   same disk image that colleagues get.
2. To review a change, quit GChat, then open the Debug build. Its icon has a
   hammer badge. Its About window shows "Version development" and the time
   of the build.
3. When the change is ready, commit it and make a release (release.md).
   Install the new disk image over the copy in /Applications. Use it for a
   while before other people get it.

The Debug build and the release have the same bundle ID, so only one can run
at a time. If one is running, opening the other brings the running one to
the front. Both have the same signature identity, so they share the sign-in,
the preferences and the cache, and switching asks for nothing.
