# Shared by check-publish.sh, write-release-notes.sh and publish.sh, which read
# it with ".": the
# bucket that holds the releases, from Config/Release.env, and signed requests
# to it. Run from the root of the repository.

die() {
    echo "error: $*" >&2
    exit 1
}

[ -f Config/Release.env ] || die "no Config/Release.env; copy Config/Release.env.example"
set -a
# shellcheck disable=SC1091
. Config/Release.env
set +a
for key in S3_ENDPOINT S3_BUCKET S3_PREFIX S3_ACCESS_KEY_ID S3_SECRET_ACCESS_KEY; do
    [ -n "${!key:-}" ] || die "$key is not set in Config/Release.env"
done
host=${S3_ENDPOINT#https://}
# The public address of the folder for this organization's build.
base="https://$S3_BUCKET.$host/$S3_PREFIX"

# The keys go to curl in a configuration that it reads from a pipe, so they
# do not show in the list of processes.
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

# The newest version in an appcast file, or nothing.
newest_version() {
    grep -o '<sparkle:version>[0-9]*' "$1" | grep -o '[0-9]*$' | sort -n | tail -1
}
