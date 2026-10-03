#!/bin/bash
# Builds a signed, notarized disk image of GChat for other people.
#
#   scripts/release.sh VERSION [--no-notarize]
#
# VERSION is the version people see, such as 1.0. The build number is the
# number of commits, so every release from a new commit is higher.
#
# Needs: the Developer ID Application certificate in the login keychain, and
# notarization credentials stored with
#   xcrun notarytool store-credentials gchat-notary ...
# (set NOTARY_PROFILE to use another name). Config/Local.xcconfig decides
# which organization's client ID is built in.
#
# The result is build/release/GChat-VERSION.dmg.

set -euo pipefail

version=${1:?usage: scripts/release.sh VERSION [--no-notarize]}
notarize=yes
[ "${2:-}" = "--no-notarize" ] && notarize=no

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
out=build/release
profile=${NOTARY_PROFILE:-gchat-notary}
build_number=$(git rev-list --count HEAD)

if [ -n "$(git status --porcelain)" ]; then
    echo "warning: uncommitted changes; the release will not match any commit" >&2
fi
if [ -f Config/Local.xcconfig ]; then
    echo "Built-in organization: $(sed -n 's/^GCHAT_ORGANIZATION *= *//p' Config/Local.xcconfig)"
else
    echo "No Config/Local.xcconfig: people will have to paste a client ID"
fi

rm -rf "$out"
mkdir -p "$out"

echo "Building version $version ($build_number)"
xcodebuild -project GChat.xcodeproj -scheme GChat -configuration Release \
    -derivedDataPath build/release-derived -archivePath "$out/GChat.xcarchive" \
    MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build_number" \
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
