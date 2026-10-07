# Release

Making a disk image of GChat for other people, and giving it to them, for the
developer. What must be in place first is in prerequisites.md. The guide for
the people who install it is in install.md.


## Make a release

1. Commit all changes. A release from uncommitted changes gets "-modified"
   after the commit ID, so it matches no commit.
2. Make sure that Config/Local.xcconfig has the client ID of the
   organization that gets this release.
3. Run:

       scripts/release.sh

4. Wait for notarization, usually one to five minutes.

The disk image is build/release/GChat-COMMIT.dmg, where COMMIT is the short
commit ID.

To test the steps before notarization, run:

    scripts/release.sh --no-notarize

macOS warns people who open a disk image that was not notarized.


## What the script does

1. Archives the Release configuration for Apple silicon and Intel. The
   build records the commit ID, the number of commits and the time of the
   commit for the About window. The number of commits is also the version
   that macOS shows.
2. Exports the app, signed with the Developer ID Application certificate,
   with a secure timestamp and the hardened runtime.
3. Makes a disk image with the app and a link to /Applications, and signs it.
4. Sends the disk image to Apple for notarization with the credentials
   gchat-notary, and waits.
5. Staples the notarization ticket to the disk image and asks Gatekeeper to
   assess it.

The script prints which organization's client ID is in the build.


## Distribute

Not decided yet: where colleagues download releases, and how they learn
about a new one. The candidates are in to-do.md. For about 30 colleagues in
one Workspace organization, the simplest choice is a Google Drive folder
shared with the organization, with an announcement in a Chat space.

GChat has no updater. A colleague gets a new version only by installing it
again.

Do not give everybody the app in the same few minutes. Each first launch
reads the member list of every conversation, and many first launches
together can exceed the quota of the Cloud project (to-do.md).


## Before the first distribution

- Use the release for a while. Notifications, sending, scrolling, group
  chats and sign-out had no review on screen when this was written (October
  2026).
- Discuss the plan with the people at Zia Consulting who own IT and
  security.
