# Prerequisites

Everything that must be in place before GChat can be built, run or released,
for the developer. How to build is in development.md. How to release is in
release.md.


## On the Mac

- macOS 15 or later to run the app. Development used macOS 27.
- Xcode 16 or later, the full app from the App Store. Development used
  Xcode 27.
- git.
- Docker Desktop, for the relay. It is built, run and tested in containers,
  so no Python is installed on the Mac.

Nothing else is installed. The Mac app has no third-party dependencies.


## On the host

For the relay: the Hetzner host with rootless Podman and Caddy, a DNS record
for gchat-relay.themullers.org, and host port 8086. Details are in
deployment-relay.md.


## Apple accounts and certificates

- An Apple Developer Program membership. The current team is Michael Muller,
  team ID 84URFQ3GPW.
- A Developer ID Application certificate, with its private key, in the login
  Keychain of the Mac that builds. Every build needs it, including Debug
  builds. The current certificate is valid until September 17, 2031. How to
  make one is in signing-certificate.md.
- For a release: notarization credentials stored in the login Keychain under
  the name gchat-notary. They come from an App Store Connect API key with the
  Developer role. Store them with:

      xcrun notarytool store-credentials gchat-notary \
          --key <path to AuthKey_KEYID.p8> --key-id <KEYID> --issuer <issuer ID>

  Keep the .p8 file outside the repository. The API key is made in App Store
  Connect under Users and Access > Integrations > App Store Connect API.


## Google

- A Google Workspace organization. Personal gmail.com accounts cannot use the
  Google Chat API.
- A Google Cloud project in that organization. It needs the Google Chat API,
  the People API, a Chat app configuration, and a consent screen with the
  Internal audience. It also needs an OAuth client of type iOS for the
  bundle ID org.themullers.gchat. The steps are in google-cloud-setup.md.
- For a build with a built-in client ID: Config/Local.xcconfig with the
  client ID and the organization name. Copy Config/Local.xcconfig.example.
  The file is not in git.

For push delivery: a billing account linked to the Cloud project (Pub/Sub
requires one, even inside its free tier), the Cloud Pub/Sub API, the Google
Workspace Events API, a topic, a push subscription and a service account
without keys, in the same Cloud project. The steps are in
deployment-relay.md.

Optional, for the list of everyone in the New Conversation sheet: the
organization lets apps read its directory. See
directory-sharing-request.md.
