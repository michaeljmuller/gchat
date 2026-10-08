# Release

Making a disk image of GChat for other people, and publishing it so that
installed copies update themselves, for the developer. What must be in place
first is in prerequisites.md. The guide for the people who install it is in
install.md. How updates work is in design.md.


## Make a release

1. Commit all changes and push them. The script stops at once when there
   are uncommitted changes, or when the commit is not on the remote branch,
   unless the release is not published (--no-publish or --no-notarize). A
   build from uncommitted changes gets "-modified" after the commit ID.
2. Make sure that Config/Local.xcconfig has the client ID of the
   organization that gets this release, and the address of its appcast.
3. Run:

       scripts/release.sh

4. The script shows the release notes that Claude Code wrote, and asks
   what to do:
   - Press Return to use the notes.
   - Type e to open them in the editor. Lines that start with # are left
     out. With no lines left, the release has no notes.
   - Type a request, for example "be more concise" or "put the fixes
     last". Claude Code writes the notes again.

   The script shows the result and asks again, until the answer is Return.
5. Wait for the build and for notarization, usually one to five minutes.
6. The script uploads the release. Installed copies see it at their next
   check, within a day.

The disk image is build/release/GChat-COMMIT.dmg, where COMMIT is the short
commit ID. The editor is the one in the EDITOR variable, or vi.

Options:

    --no-notarize   stop before notarization, to test the build steps. macOS
                    warns people who open such a disk image. Nothing is
                    published.
    --no-publish    make the notarized disk image, and upload nothing
    --no-edit       use the release notes as Claude Code wrote them, with
                    no question

A release cannot be taken back. A copy that installed it does not go to an
older version. To correct a release, publish a newer one.


## What the release script does

1. Runs scripts/release-notes.sh (next section). The notes come first,
   because the app contains them.
2. Archives the Release configuration for Apple silicon and Intel. The
   build records the commit ID, the number of commits and the time of the
   commit for the About window, and copies the release notes into the app.
   The number of commits is also the version that macOS and the updater
   use.
3. Exports the app, signed with the Developer ID Application certificate,
   with a secure timestamp and the hardened runtime.
4. Makes a disk image with the app and a link to /Applications, and signs it.
5. Sends the disk image to Apple for notarization with the credentials
   gchat-notary, and waits.
6. Staples the notarization ticket to the disk image and asks Gatekeeper to
   assess it.
7. Runs scripts/publish.sh on the disk image.

The script prints which organization's client ID is in the build.


## What the release notes script does

scripts/release-notes.sh writes the notes for the commit that is checked
out. It uploads nothing, so it can also run alone, to see what Claude Code
writes:

    scripts/release-notes.sh

1. Downloads appcast.xml and release-notes.html from the folder of the
   organization in the bucket. The appcast is the list of releases that
   installed copies read. Without an appcast, this is the first release.
2. Stops if the bucket already has this version or a newer one.
3. Asks Claude Code for the notes: the changes since the last published
   version, or the core features for the first release. The rules are in
   release-notes-style.md. If Claude Code is not installed or fails, the
   notes start as the list of commit subjects.
4. Shows the notes and asks for changes, as in "Make a release", step 4. A
   request goes to Claude Code with the notes so far. Where the request and
   release-notes-style.md differ, the request is correct for that release.
   The notes stay a flat list: the page has no headings inside a release.
5. Writes build/release/publish/release-notes.html: the new notes as a
   section above the sections of the earlier releases.

Without Config/Release.env, scripts/release.sh skips this script. The app
then has no notes, and the release is not published.


## What the publish script does

scripts/publish.sh publishes one disk image. It can run alone, on a disk
image that scripts/release.sh made with --no-publish, as long as
build/release is unchanged since then:

    scripts/publish.sh build/release/GChat-COMMIT.dmg

1. Stops if the disk image is from uncommitted changes or is not notarized.
   Stops if the app in build/release/export reads a different appcast than
   the one that the script writes, or contains other release notes than
   build/release/publish/release-notes.html.
2. Downloads appcast.xml again, and stops if the bucket already has this
   version or a newer one.
3. Runs generate_appcast of Sparkle. It signs the disk image with the
   Sparkle key and adds the release, with the notes page, to the appcast.
4. Uploads the disk image, release-notes.html and appcast.xml, in that
   order, and makes sure that each one downloads without a sign-in.


## What is in the bucket

One folder for each organization's build. For Zia Consulting:

    https://mmuller-gchat.fsn1.your-objectstorage.com/zia/appcast.xml
    https://mmuller-gchat.fsn1.your-objectstorage.com/zia/release-notes.html
    https://mmuller-gchat.fsn1.your-objectstorage.com/zia/GChat-COMMIT.dmg

Anyone with an address can download. The newest disk image is also the one
to give to a colleague who installs GChat for the first time. Old disk
images stay in the bucket.


## Test an update

Not done yet (October 8, 2026). Do it with the first releases:

1. Publish a release and install it from the disk image.
2. Make two more releases, each from a new commit.
3. In the installed copy, choose GChat > Check for Updates.
4. Make sure that the window shows the notes of the two new releases, and
   not the notes of the installed one.
5. Click Install Update. Make sure that GChat starts again, that the About
   window shows the new commit, and that the sign-in is still there.
6. Choose GChat > Release Notes. Make sure that the window shows all three
   releases, in light and dark appearance.

To make an installed copy look for an update at its next launch, without a
wait of a day:

    defaults delete org.themullers.gchat SULastCheckTime


## Distribute

Installed copies update themselves. A colleague who has no copy yet needs
the address of the newest disk image, and install.md.

Not decided yet: how colleagues learn about GChat. For about 30 colleagues
in one Workspace organization, an announcement in a Chat space is enough.

Do not give everybody the app in the same few minutes. Each first launch
reads the member list of every conversation, and many first launches
together can exceed the quota of the Cloud project (to-do.md). Updates do
not have this problem: an update keeps what the copy stored.


## Before the first distribution

- Use the release for a while. Notifications, sending, scrolling, group
  chats and sign-out had no review on screen when this was written (October
  2026).
- Discuss the plan with the people at Zia Consulting who own IT and
  security.
