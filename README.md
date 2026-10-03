# GChat

GChat is a native Mac app for Google Chat. It shows direct messages, group
chats, spaces and meeting chats in a Mac window, and it posts notifications
for new messages. It covers basic chat, not every feature of Google Chat. It
is not a Google product.

GChat has these requirements:

- A Google Workspace account. The Google Chat API does not accept personal
  gmail.com accounts.
- macOS 15 or later.
- An OAuth client in a Google Cloud project that belongs to the Workspace
  organization. A build for an organization can contain the client ID.
  Otherwise, the person who signs in pastes the client ID.

The documents are in docs/:

- requirements.md: what was asked for
- functional-spec.md: what the app does, its shortcuts and its configuration
- design.md: how the app is built and why, and what it stores
- prerequisites.md: tools, accounts and keys that a build or release needs
- development.md: building, testing and reviewing changes
- release.md: making a disk image and distributing it
- install.md: installing and signing in, for Zia Consulting colleagues
- google-cloud-setup.md: creating the OAuth client, and sign-in problems
- signing-certificate.md: the Developer ID certificate and its renewal
- directory-sharing-request.md: a request to a Workspace admin to let apps
  read the directory
- to-do.md: work that was left out or deferred, with the reasons
