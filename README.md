# GChat

A native Mac app for Google Chat: your direct messages, group chats, spaces
and meeting chats in a Mac window, with notifications, without a browser tab.
It covers basic chat, not everything Google Chat can do.

It is not a Google product.

What you need:

- A Google Workspace account. Google's Chat API does not work for personal
  gmail.com accounts.
- macOS 15 or later.
- An OAuth client in a Google Cloud project of your organization. Builds made
  for an organization have it built in; otherwise each person pastes its ID
  at sign-in. Creating one takes about ten minutes.

Documentation, in docs/:

- install.md: installing and signing in, for Zia Consulting colleagues
- using.md: what the app does and its keyboard shortcuts and settings
- google-cloud-setup.md: creating the OAuth client, and troubleshooting
  sign-in
- how-it-works.md: how it gets messages, what it stores, its limits
- building.md: building, the development workflow and making releases
- signing-certificate.md: the Developer ID certificate used for signing
- directory-sharing-request.md: the Workspace setting that lets the app
  list everyone in the organization
- TODO.md: planned work
