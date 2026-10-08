#!/bin/bash
# Makes sure that everything a published release needs is in place, before
# scripts/release.sh writes notes, builds or notarizes anything. Reports all
# problems, not only the first.
#
#   scripts/support/check-publish.sh
#
# Checks: Config/Release.env and access to the bucket, the appcast address
# and the Sparkle public key in the build settings, the Sparkle private key in
# the login Keychain, the notarization credentials, and that this version is
# not published yet. How to set each one up is in docs/prerequisites.md.

set -euo pipefail

cd "$(dirname "$0")/../.."
# shellcheck source=scripts/support/bucket.sh
. scripts/support/bucket.sh

problems=()

# The values that the build puts in the app, with Local.xcconfig applied.
settings=$(xcodebuild -project GChat.xcodeproj -scheme GChat -configuration Release -showBuildSettings 2>/dev/null)
setting() {
    echo "$settings" | sed -n "s/^ *$1 = //p" | head -1
}

if [ -z "$(setting GCHAT_SPARKLE_PUBLIC_KEY)" ]; then
    problems+=("GCHAT_SPARKLE_PUBLIC_KEY is empty in Config/Base.xcconfig. Without it the app has no updater.")
fi
feed=$(setting GCHAT_APPCAST_URL)
if [ "$feed" != "$base/appcast.xml" ]; then
    problems+=("GCHAT_APPCAST_URL is '$feed', but the release goes to $base/appcast.xml. Fix Config/Local.xcconfig, or S3_PREFIX in Config/Release.env.")
fi

# Looks for the item only. It does not read the key, so macOS does not ask.
if ! security find-generic-password -s "https://sparkle-project.org" -a gchat >/dev/null 2>&1; then
    problems+=("The login Keychain has no Sparkle key for the account gchat. Make it with generate_keys --account gchat.")
fi

profile=${NOTARY_PROFILE:-gchat-notary}
if ! xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1; then
    problems+=("The notarization credentials '$profile' do not work. Store them with xcrun notarytool store-credentials.")
fi

code=$(s3 -o /dev/null -w '%{http_code}' "$base/appcast.xml" || true)
case "$code" in
    200)
        previous=$(s3 "$base/appcast.xml" | newest_version /dev/stdin)
        build=$(git rev-list --count HEAD)
        if [ -n "$previous" ] && [ "$previous" -ge "$build" ]; then
            problems+=("Version $previous is already published, and this is version $build.")
        fi
        ;;
    404) ;;
    *) problems+=("Could not read the bucket at $base (HTTP $code). Make sure that the keys in Config/Release.env are correct.") ;;
esac

if ! command -v claude >/dev/null; then
    echo "note: Claude Code is not installed; the release notes start as the commit subjects" >&2
fi

if [ ${#problems[@]} -gt 0 ]; then
    echo "error: this release cannot be published:" >&2
    for problem in "${problems[@]}"; do
        echo "  - $problem" >&2
    done
    echo "See docs/prerequisites.md. For a build that is not published, use --no-publish." >&2
    exit 1
fi
echo "Ready to publish to $base"
