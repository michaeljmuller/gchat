#!/bin/bash
# Builds a signed, notarized disk image of GChat for other people, and
# publishes it so that installed copies update themselves.
#
#   scripts/release.sh [--no-notarize] [--no-publish] [--no-edit]
#
# --no-notarize also skips publishing. --no-edit uses the release notes
# without the question about changes (scripts/release-notes.sh).
#
# Stops when there are uncommitted changes or commits that are not pushed,
# unless the release is not published. A build from uncommitted changes gets
# "-modified" after the commit ID.
#
# The release notes come first, because the app contains them.
#
# The About window shows the commit ID, with "-modified" added when there are
# uncommitted changes, the number of commits and the time of the commit. The
# Xcode build records these itself (the "Record commit" build phase). The
# number of commits is also the version that macOS and Finder show, because
# macOS uses it to tell which copy is newer.
#
# Needs: the Developer ID Application certificate in the login keychain, and
# notarization credentials stored with
#   xcrun notarytool store-credentials gchat-notary ...
# (set NOTARY_PROFILE to use another name). Config/Local.xcconfig decides
# which organization's client ID is built in. Publishing needs more: see
# scripts/publish.sh.
#
# The result is build/release/GChat-COMMIT.dmg.

set -euo pipefail

notarize=yes
publish=yes
notes_options=()
for option in "$@"; do
    case "$option" in
        --no-notarize) notarize=no; publish=no ;;
        --no-publish) publish=no ;;
        --no-edit) notes_options+=("$option") ;;
        *) echo "usage: scripts/release.sh [--no-notarize] [--no-publish] [--no-edit]" >&2; exit 2 ;;
    esac
done

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
out=build/release
profile=${NOTARY_PROFILE:-gchat-notary}
build_number=$(git rev-list --count HEAD)
version=$(git rev-parse --short HEAD)

if [ -n "$(git status --porcelain)" ]; then
    if [ "$publish" = yes ]; then
        echo "error: uncommitted changes; commit them, or use --no-publish for a build that is not published" >&2
        git status --short >&2
        exit 1
    fi
    echo "warning: uncommitted changes; the release will not match any commit" >&2
    version="$version-modified"
fi
# A published release names its commit in the About window, and its version
# is the number of commits. Both are only safe when the commit is on the
# remote: a local commit can still be changed, and then they match nothing.
if [ "$publish" = yes ]; then
    upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) \
        || { echo "error: this branch has no upstream branch; push it first" >&2; exit 1; }
    git fetch --quiet "${upstream%%/*}" \
        || { echo "error: could not reach the remote to make sure that the commit is pushed" >&2; exit 1; }
    if ! git merge-base --is-ancestor HEAD "$upstream"; then
        echo "error: $version is not on $upstream; push, or use --no-publish for a build that is not published" >&2
        exit 1
    fi
fi
if [ -f Config/Local.xcconfig ]; then
    echo "Built-in organization: $(sed -n 's/^GCHAT_ORGANIZATION *= *//p' Config/Local.xcconfig)"
else
    echo "No Config/Local.xcconfig: people will have to paste a client ID"
fi

rm -rf "$out"
mkdir -p "$out"

# Writes build/release/publish/release-notes.html, which the "Record commit"
# build phase copies into the app.
notes="$root/$out/publish/release-notes.html"
if [ -f Config/Release.env ]; then
    scripts/release-notes.sh ${notes_options[@]+"${notes_options[@]}"}
else
    echo "No Config/Release.env: no release notes, and nothing is published"
    publish=no
fi

echo "Building version $version ($build_number)"
xcodebuild -project GChat.xcodeproj -scheme GChat -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath build/release-derived -archivePath "$out/GChat.xcarchive" \
    MARKETING_VERSION="$build_number" CURRENT_PROJECT_VERSION="$build_number" \
    GCHAT_RELEASE_NOTES="$notes" \
    -quiet archive

echo "Signing with Developer ID"
xcodebuild -exportArchive -archivePath "$out/GChat.xcarchive" \
    -exportOptionsPlist Config/ExportOptions.plist -exportPath "$out/export" -quiet
app="$out/export/GChat.app"
codesign --verify --strict --deep "$app"

echo "Making the disk image"
staging="$out/dmg"
mkdir -p "$staging"
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
dmg="$out/GChat-$version.dmg"
hdiutil create -quiet -volname "GChat $version" -srcfolder "$staging" -format UDZO "$dmg"
codesign --sign "Developer ID Application" --timestamp "$dmg"

if [ "$notarize" = yes ]; then
    echo "Notarizing (usually a few minutes)"
    xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait
    xcrun stapler staple -q "$dmg"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
else
    echo "Skipped notarization: macOS will warn people who open this image"
fi

rm -rf "$staging" "$out/GChat.xcarchive"
echo "Done: $dmg"

if [ "$publish" = yes ]; then
    scripts/publish.sh "$dmg"
else
    echo "Not published: installed copies do not see this release"
fi
