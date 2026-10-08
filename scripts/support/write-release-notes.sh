#!/bin/bash
# Writes the release notes for the next release, before the app is built,
# because the app contains them. scripts/release.sh calls it.
#
#   scripts/support/write-release-notes.sh [--no-edit]
#
# Claude Code (the claude command) writes the notes for the changes since the
# last published version, after docs/release-notes-style.md. For the first
# release it lists the core features. Without Claude Code, the notes start as
# the commit subjects.
#
# The script then shows the notes and asks what to do: use them, open them in
# an editor, or give Claude Code a request for a revision, for example "be
# more concise". It asks again after each change. --no-edit uses the notes
# without the question.
#
# The result is build/release/publish/release-notes.html: the notes of all
# releases, newest first. The same page goes into the app (the Release Notes
# window), into the appcast (the update window) and into the bucket.
#
# Uploads nothing. Needs Config/Release.env, to read the earlier notes.

set -euo pipefail

edit=yes
for option in "$@"; do
    case "$option" in
        --no-edit) edit=no ;;
        *) echo "usage: scripts/support/write-release-notes.sh [--no-edit]" >&2; exit 2 ;;
    esac
done

cd "$(dirname "$0")/../.."
# shellcheck source=scripts/support/bucket.sh
. scripts/support/bucket.sh

# The version that Sparkle compares, the same number that release.sh builds in.
build=$(git rev-list --count HEAD)
day=$(date -j -f %s "$(git log -1 --format=%ct)" "+%B %-d, %Y")

work=build/release/publish
rm -rf "$work"
mkdir -p "$work"

previous=
if fetch appcast.xml "$work/appcast.xml"; then
    previous=$(newest_version "$work/appcast.xml")
fi
if [ -n "$previous" ] && [ "$previous" -ge "$build" ]; then
    die "version $previous is already published, and this is version $build"
fi
fetch release-notes.html "$work/earlier-notes.html" || true

if [ -n "$previous" ]; then
    # The version is the number of commits, so commit number N is version N.
    range="$(git rev-list --reverse HEAD | sed -n "${previous}p")..HEAD"
    task="The last published version is $previous. Commit range: $range."
    echo "Writing release notes for version $build (changes since version $previous)"
else
    range=HEAD
    task="This is the first release."
    echo "Writing release notes for version $build (first release)"
fi
if [ -f "$work/earlier-notes.html" ]; then
    task="$task The file with the earlier notes is $work/earlier-notes.html."
else
    task="$task There is no file with earlier notes."
fi

notes="$work/notes.txt"
# start_notes: the comment lines at the top of the notes file.
start_notes() {
    {
        echo "# Release notes for version $build, $day."
        echo "# One line for each change, each starting with \"- \". Lines that start"
        echo "# with # are left out. With no lines, this version gets no notes."
        echo "# The rules are in docs/release-notes-style.md."
    } > "$notes"
}
# ask_claude TEXT: the lines that Claude Code writes go to generated.txt.
# Fails without Claude Code, and when the reply has no lines.
ask_claude() {
    command -v claude >/dev/null \
        && claude -p "$(cat scripts/support/release-notes-prompt.txt)

$1" --allowedTools "Read" "Bash(git log:*)" "Bash(git show:*)" "Bash(git diff:*)" < /dev/null > "$work/reply.txt" \
        && grep '^- ' "$work/reply.txt" > "$work/generated.txt"
}

start_notes
if ask_claude "$task"; then
    cat "$work/generated.txt" >> "$notes"
else
    echo "warning: Claude Code wrote no notes; using the commit subjects" >&2
    echo "# Claude Code wrote no notes. These are the commit subjects." >> "$notes"
    git log --reverse --format='- %s' "$range" >> "$notes"
fi

while [ "$edit" = yes ]; do
    # Rules above and below the notes show where they start and end.
    echo
    echo "======== Release notes for version $build ========"
    echo
    grep '^- ' "$notes" || echo "(no notes)"
    echo
    echo "======== End of the release notes ========"
    echo
    echo "What next?"
    echo "  Return     use these notes"
    echo "  e          open them in the editor"
    echo "  a request  Claude Code writes them again, for example: be more concise"
    printf '> '
    read -r answer || answer=
    case "$answer" in
        "") break ;;
        e | E) ${EDITOR:-vi} "$notes" ;;
        *)
            echo "Revising"
            if ask_claude "$task

These are the notes so far:

$(grep '^- ' "$notes" || true)

The developer asks for this change to the notes: $answer

Apply the request. Change only what the request asks for. If the request
and the style guide differ, the request is correct for this release. The
form of the reply stays the same: lines that start with \"- \", and nothing
else."; then
                start_notes
                cat "$work/generated.txt" >> "$notes"
            else
                echo "warning: Claude Code wrote no revision; the notes are unchanged" >&2
            fi
            ;;
    esac
done

# The page with the notes of all releases, newest first. In the update
# window, Sparkle marks the section of the version that runs with the class
# sparkle-installed-version. The style hides that section and the older ones,
# so the window shows the releases that the copy does not have yet. Anywhere
# else, the page shows all releases. The first line names the version, for
# scripts/support/publish.sh.
page="$work/release-notes.html"
{
    echo "<!-- version $build -->"
    cat <<'EOF'
<style>
:root { color-scheme: light dark; }
body { font: 13px -apple-system, sans-serif; margin: 12px 16px; }
h3 { font-size: 13px; margin: 16px 0 4px; }
div:first-of-type h3 { margin-top: 0; }
h3 span { font-weight: normal; opacity: 0.6; margin-left: 6px; }
ul { margin: 0; padding-left: 18px; }
li { margin: 3px 0; }
.sparkle-installed-version, .sparkle-installed-version ~ div { display: none; }
</style>
<!-- releases -->
EOF
    if grep -q '^- ' "$notes"; then
        echo "<div data-sparkle-version=\"$build\">"
        echo "<h3>Version $build <span>$day</span></h3>"
        echo "<ul>"
        grep '^- ' "$notes" \
            | sed -e 's/^- *//' -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's|.*|<li>&</li>|'
        echo "</ul>"
        echo "</div>"
    else
        echo "No release notes for version $build" >&2
    fi
    if [ -f "$work/earlier-notes.html" ]; then
        sed '1,/<!-- releases -->/d' "$work/earlier-notes.html"
    fi
} > "$page"
echo "Release notes: $page"
