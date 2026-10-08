#!/bin/bash
# Publishes a release so that installed copies of GChat update themselves:
# signs the disk image for Sparkle, and uploads the disk image, the release
# notes and the appcast (the list of releases that the app reads).
# scripts/release.sh calls it.
#
#   scripts/release/publish.sh build/release/GChat-COMMIT.dmg
#
# Needs: the disk image and the release notes from one run of
# scripts/release.sh, Config/Release.env with the bucket and its keys (see
# Release.env.example), and the Sparkle key in the login Keychain under the
# account gchat (docs/prerequisites.md).

set -euo pipefail

dmg=${1:-}
if [ $# -ne 1 ] || [ ! -f "$dmg" ]; then
    echo "usage: scripts/release/publish.sh build/release/GChat-COMMIT.dmg" >&2
    exit 2
fi
dmg=$(cd "$(dirname "$dmg")" && pwd)/$(basename "$dmg")
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/release/bucket.sh
. scripts/release/bucket.sh

name=$(basename "$dmg" .dmg)
commit=${name#GChat-}
case "$commit" in
    *-modified) die "$name was built from uncommitted changes; commit and release again" ;;
esac
git cat-file -e "$commit^{commit}" 2>/dev/null || die "$commit is not a commit in this repository"
build=$(git rev-list --count "$commit")

xcrun stapler validate -q "$dmg" || die "$name.dmg is not notarized"

# The app contains the notes, so they must be the ones from the same run.
page=build/release/publish/release-notes.html
[ -f "$page" ] || die "no $page; scripts/release.sh writes it before it builds the app"
[ "$(head -1 "$page")" = "<!-- version $build -->" ] \
    || die "$page is not for version $build; run scripts/release.sh again"

# An app with another appcast address, without the key, or with other notes
# is not the release that this script describes.
app=$(dirname "$dmg")/export/GChat.app
if [ -d "$app" ]; then
    plist="$app/Contents/Info.plist"
    feed=$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$plist" 2>/dev/null || true)
    key=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$plist" 2>/dev/null || true)
    [ "$feed" = "$base/appcast.xml" ] \
        || die "the app reads '$feed', but this release goes to $base/appcast.xml; fix GCHAT_APPCAST_URL in Config/Local.xcconfig or S3_PREFIX in Config/Release.env"
    [ -n "$key" ] || die "the app has no Sparkle public key; set GCHAT_SPARKLE_PUBLIC_KEY in Config/Base.xcconfig"
    cmp -s "$page" "$app/Contents/Resources/ReleaseNotes.html" \
        || die "the release notes in the app are not $page; run scripts/release.sh again"
fi

tools=
for candidate in build/release-derived build; do
    if [ -x "$candidate/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast" ]; then
        tools="$candidate/SourcePackages/artifacts/sparkle/Sparkle/bin"
        break
    fi
done
[ -n "$tools" ] || die "no Sparkle tools; build the app first"

# generate_appcast works on a folder: the appcast so far, the disk image,
# and the notes under the name of the disk image.
work=build/release/appcast
rm -rf "$work"
mkdir -p "$work"
if fetch appcast.xml "$work/appcast.xml"; then
    previous=$(newest_version "$work/appcast.xml")
    if [ -n "$previous" ] && [ "$previous" -ge "$build" ]; then
        die "version $previous is already published, and this is version $build"
    fi
fi
cp "$dmg" "$work/"
cp "$page" "$work/$name.html"

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
