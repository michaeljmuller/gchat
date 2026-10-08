#!/bin/bash
# Publishes a release so that installed copies of GChat update themselves:
# writes the release notes, signs the disk image for Sparkle, and uploads the
# disk image, the notes and the appcast (the list of releases that the app
# reads). scripts/release.sh calls it.
#
#   scripts/publish.sh build/release/GChat-COMMIT.dmg [--no-edit] [--dry-run]
#
# --no-edit publishes the release notes as written, without the editor.
# --dry-run writes the release notes to build/release/publish and stops. It
# signs and uploads nothing, so it accepts an image that is not notarized.
#
# Needs: Config/Release.env with the bucket and its keys (see
# Release.env.example), the Sparkle key in the login Keychain under the
# account gchat (docs/prerequisites.md), and a build of the app, which
# downloads the Sparkle tools. Claude Code (the claude command) writes the
# release notes after docs/release-notes-style.md. Without it, the editor
# opens with the commit subjects.

set -euo pipefail

usage() {
    echo "usage: scripts/publish.sh build/release/GChat-COMMIT.dmg [--no-edit] [--dry-run]" >&2
    exit 2
}
die() {
    echo "error: $*" >&2
    exit 1
}

edit=yes
dry_run=no
dmg=
for option in "$@"; do
    case "$option" in
        --no-edit) edit=no ;;
        --dry-run) dry_run=yes ;;
        -*) usage ;;
        *) dmg=$option ;;
    esac
done
[ -n "$dmg" ] || usage
[ -f "$dmg" ] || die "no such file: $dmg"

root=$(cd "$(dirname "$0")/.." && pwd)
dmg=$(cd "$(dirname "$dmg")" && pwd)/$(basename "$dmg")
cd "$root"

name=$(basename "$dmg" .dmg)
commit=${name#GChat-}
case "$commit" in
    *-modified) die "$name was built from uncommitted changes; commit and release again" ;;
esac
git cat-file -e "$commit^{commit}" 2>/dev/null || die "$commit is not a commit in this repository"
# The version that Sparkle compares, the same number that release.sh builds in.
build=$(git rev-list --count "$commit")
day=$(date -j -f %s "$(git log -1 --format=%ct "$commit")" "+%B %-d, %Y")

[ -f Config/Release.env ] || die "no Config/Release.env; copy Config/Release.env.example"
set -a
# shellcheck disable=SC1091
. Config/Release.env
set +a
for key in S3_ENDPOINT S3_BUCKET S3_PREFIX S3_ACCESS_KEY_ID S3_SECRET_ACCESS_KEY; do
    [ -n "${!key:-}" ] || die "$key is not set in Config/Release.env"
done
host=${S3_ENDPOINT#https://}
base="https://$S3_BUCKET.$host/$S3_PREFIX"

# Signed requests to the bucket. The keys go to curl in a configuration that
# it reads from a pipe, so they do not show in the list of processes.
s3() {
    curl -sS --aws-sigv4 "aws:amz:${host%%.*}:s3" \
        -K <(printf 'user = "%s:%s"\n' "$S3_ACCESS_KEY_ID" "$S3_SECRET_ACCESS_KEY") "$@"
}
# fetch NAME FILE: fails, with no file, when the bucket does not have NAME.
fetch() {
    local code
    code=$(s3 -o "$2" -w '%{http_code}' "$base/$1")
    case "$code" in
        200) return 0 ;;
        404) rm -f "$2"; return 1 ;;
        *) die "could not read $base/$1 (HTTP $code)" ;;
    esac
}
# put FILE NAME TYPE: uploads a file that anyone can read.
put() {
    echo "Uploading $2"
    s3 --fail -o /dev/null -H "x-amz-acl: public-read" -H "Content-Type: $3" -T "$1" "$base/$2" \
        || die "could not upload $2"
}

# An app with another appcast address, or without the key, never sees what
# this script uploads.
plist=$(dirname "$dmg")/export/GChat.app/Contents/Info.plist
if [ -f "$plist" ]; then
    feed=$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$plist" 2>/dev/null || true)
    key=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$plist" 2>/dev/null || true)
    [ "$feed" = "$base/appcast.xml" ] \
        || die "the app reads '$feed', but this release goes to $base/appcast.xml; fix GCHAT_APPCAST_URL in Config/Local.xcconfig or S3_PREFIX in Config/Release.env"
    [ -n "$key" ] || die "the app has no Sparkle public key; set GCHAT_SPARKLE_PUBLIC_KEY in Config/Base.xcconfig"
fi

if [ "$dry_run" = no ]; then
    xcrun stapler validate -q "$dmg" || die "$name.dmg is not notarized"
fi

work=build/release/publish
rm -rf "$work"
mkdir -p "$work"

previous=
if fetch appcast.xml "$work/appcast.xml"; then
    previous=$(grep -o '<sparkle:version>[0-9]*' "$work/appcast.xml" | grep -o '[0-9]*$' | sort -n | tail -1)
fi
if [ -n "$previous" ] && [ "$previous" -ge "$build" ]; then
    die "version $previous is already published, and this is version $build"
fi
fetch release-notes.html "$work/earlier-notes.html" || true

# --- Release notes ---------------------------------------------------------

if [ -n "$previous" ]; then
    # The version is the number of commits, so commit number N is version N.
    from=$(git rev-list --reverse "$commit" | sed -n "${previous}p")
    range="$from..$commit"
    task="The last published version is $previous. Commit range: $range."
    echo "Writing release notes for version $build (changes since version $previous)"
else
    range=
    task="This is the first release."
    echo "Writing release notes for version $build (first release)"
fi
if [ -f "$work/earlier-notes.html" ]; then
    task="$task The file with the earlier notes is $work/earlier-notes.html."
else
    task="$task There is no file with earlier notes."
fi

notes="$work/notes.txt"
{
    echo "# Release notes for version $build, $day."
    echo "# One line for each change, each starting with \"- \". Lines that start"
    echo "# with # are left out. With no lines, this version gets no notes."
    echo "# The rules are in docs/release-notes-style.md."
} > "$notes"
if command -v claude >/dev/null \
    && claude -p "$(cat scripts/release-notes-prompt.txt)

$task" --allowedTools "Read" "Bash(git log:*)" "Bash(git show:*)" "Bash(git diff:*)" > "$work/generated.txt" \
    && grep -q '^- ' "$work/generated.txt"; then
    grep '^- ' "$work/generated.txt" >> "$notes"
else
    echo "warning: Claude Code wrote no notes; using the commit subjects" >&2
    echo "# Claude Code wrote no notes. These are the commit subjects." >> "$notes"
    # shellcheck disable=SC2086
    git log --reverse --format='- %s' ${range:-$commit} >> "$notes"
fi
if [ "$edit" = yes ]; then
    ${EDITOR:-vi} "$notes"
fi

# The page with the notes of all releases, newest first. Sparkle marks the
# section of the version that runs with the class sparkle-installed-version.
# The style hides that section and the older ones, so the update window shows
# the releases that the copy does not have yet. The same page, opened in a
# browser, shows all releases.
page="$work/$name.html"
{
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

if [ "$dry_run" = yes ]; then
    echo "Dry run: nothing signed or uploaded. The notes are in $page"
    exit 0
fi

# --- Appcast and upload ----------------------------------------------------

tools=
for candidate in build/release-derived build; do
    if [ -x "$candidate/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast" ]; then
        tools="$candidate/SourcePackages/artifacts/sparkle/Sparkle/bin"
        break
    fi
done
[ -n "$tools" ] || die "no Sparkle tools; build the app first"

cp "$dmg" "$work/"
rm -f "$work/earlier-notes.html" "$work/notes.txt" "$work/generated.txt"
echo "Signing for Sparkle and making the appcast"
"$tools/generate_appcast" --account gchat \
    --download-url-prefix "$base/" \
    --embed-release-notes \
    --full-release-notes-url "$base/release-notes.html" \
    "$work"
grep -q "sparkle:edSignature" "$work/appcast.xml" || die "the appcast has no signature for $name.dmg"

# The appcast goes last: a copy that reads it must find the disk image.
put "$work/$name.dmg" "$name.dmg" application/x-apple-diskimage
put "$page" release-notes.html "text/html; charset=utf-8"
put "$work/appcast.xml" appcast.xml application/xml

for file in "$name.dmg" release-notes.html appcast.xml; do
    curl -sS --fail -o /dev/null -I "$base/$file" || die "$base/$file does not answer without a sign-in"
done
echo "Published version $build: $base/appcast.xml"
