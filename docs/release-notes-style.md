# Release notes style

How the release notes of GChat are written, for whoever writes them: the
developer, or Claude Code when scripts/release-notes.sh calls it. How a release is
made and published is in release.md. How the notes reach the update window
is in design.md.


## Where the notes show

Release notes show in two windows:

- The update window, when GChat offers a new version. It shows the notes of
  every release that is newer than the copy that runs, newest first. A
  colleague who skipped two releases sees three sections, one below the
  other.
- The Release Notes window (GChat > Release Notes). It shows the notes of
  the version that runs and of all earlier releases, newest first.

So a section is read in two ways: alone, and between other sections. It
must read correctly in both.


## The reader

The reader is a colleague who uses GChat. The reader is not a developer and
did not read the earlier notes.

- Describe what the reader can see or do in the app.
- Use the names that the app shows: the text of menus, buttons and
  settings. behavior.md has them.
- Do not use names from the code, the relay, Google Cloud or the build.


## What gets a line

A change gets a line if a colleague can notice it in the app: a new
feature, a changed behavior, a changed setting or shortcut, or a fault that
is gone.

These get no line:

- Changes to documents, scripts, tests and the to-do list.
- Changes to the relay, unless colleagues see a difference in the app.
- Changes to the code that do not change what the app does.
- A fault that was added and removed between two releases.
- A change that an earlier release already listed.

Several commits for one change get one line. If nothing is left, the notes
are one line:

    - This version has small corrections only.


## The first release

The first release has no earlier version to compare with. Its notes list the
main things that GChat does, from behavior.md and install.md, in 6 to 10
lines. They do not come from the commits.


## Form

The notes of one release are a flat list, 1 to 8 lines.
scripts/release-notes.sh adds the heading, with the version and the date, and the styling. The
writer supplies only the lines.

- Each line starts with "- " and is one sentence that ends with a period.
- Each line is in the present tense and says what GChat does now: "GChat
  shows images in the transcript."
- For a fault that is gone, say what works now. Name the old fault only when
  the line is not clear without it: "A conversation opens when a sender has
  no name."
- 20 words or fewer in a line.
- Order: new features, then changed behavior, then faults that are gone.
- No headings, no groups, no nesting.
- No markup: no HTML, no bold, no links, no emoji.
- No sentence before or after the list.
- Shortcuts as Command-K and Shift-Return. Menu paths as Settings >
  Notifications.
- No commit IDs, no version numbers, no dates, no names of people.


## Consistency between releases

Sections from different releases show together, so they must look like one
text:

- No words that point to another release: "also", "now also", "again",
  "still", "as before", "since the last version", "finally".
- One name for one thing in all releases. If earlier notes say
  "transcript", do not write "message list".
- The same sentence form in all releases. Do not change to "Added …" or
  "Fixed …".
- A line does not repeat a line of an earlier release. If a feature
  changed again, the line says what it does now.

The earlier notes are the reference for names, length and tone.
scripts/release-notes.sh saves them as build/release/publish/earlier-notes.html
before it asks for new notes. The first release has no such file. If the
earlier notes and this guide differ, this guide is correct.


## Examples

A first release:

    - GChat shows direct messages, group chats, spaces and meeting chats in one window.
    - GChat posts a notification for each new message in a conversation that is not on screen.
    - New messages show within about a second.
    - Command-K jumps to a conversation by name.
    - Command-N starts a conversation with a person who is already in a conversation.
    - Images show in the transcript, and a click opens them in Quick Look.
    - GChat installs new versions itself, and the app menu has Check for Updates.

A later release:

    - The sidebar says when GChat cannot reach its relay, and has a Check Now button.
    - The transcript scrolls to a new message only when the end of the transcript is on screen.
    - A conversation opens when a sender has no name.

A release with nothing to see:

    - This version has small corrections only.
