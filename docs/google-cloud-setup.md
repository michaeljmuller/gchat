# Google Cloud setup

Making the OAuth client that GChat signs in with, and fixing sign-in
problems. For a person with access to the Google Cloud console of the
Workspace organization. What else a build needs is in prerequisites.md.

Each Workspace organization needs its own OAuth client. For a build with a
built-in client ID (development.md), one person in the organization does
this once, for everyone. For two organizations, do it in each, and keep both
client IDs. It takes about ten minutes and costs nothing.

The names of console pages change from time to time. If a label does not
match, use the search bar at the top of the console.


## Make the OAuth client

1. Open https://console.cloud.google.com/ and sign in with an account of the
   Workspace organization.
2. Click the project picker in the top bar, then New Project.
3. Type a name, for example "GChat Mac".
4. Make sure that Organization shows the Workspace domain, not "No
   organization". The Internal audience in step 15 needs it.
5. Click Create, then select the new project in the project picker.
6. Go to APIs & Services > Library, search for "Google Chat API", open it,
   and click Enable.
7. In the Library, search for "People API", open it, and click Enable. The
   People API gives names and photos for user IDs.
8. Go to APIs & Services > Enabled APIs & services > Google Chat API, and
   open the Configuration tab. Google requires a Chat app configuration for
   every project that calls the Chat API. Calls fail until it is saved.
9. In App name, type a name, for example "GChat Mac". Google Chat shows this
   name next to messages sent from GChat.
10. In Avatar URL, type the URL of any image, for example
    https://developers.google.com/chat/images/quickstart-app-avatar.png
11. In Description, type a description, for example "Native Mac client".
12. Turn off Interactive features. GChat receives no events, and the page
    then needs nothing else.
13. Click Save. This publishes nothing to other people.
14. Go to Google Auth Platform. Older consoles call it APIs & Services >
    OAuth consent screen. If the page shows Get started, click it.
15. Type the app name and a support email address. For Audience, select
    Internal, then type a contact email address. Internal limits sign-in to
    the organization, needs no review by Google, and does not expire.
16. Open Data Access and click Add or remove scopes.
17. Paste these lines into the box "Manually add scopes":

        https://www.googleapis.com/auth/chat.spaces.readonly
        https://www.googleapis.com/auth/chat.spaces.create
        https://www.googleapis.com/auth/chat.messages
        https://www.googleapis.com/auth/chat.memberships.readonly
        https://www.googleapis.com/auth/chat.users.readstate
        https://www.googleapis.com/auth/directory.readonly
        openid
        https://www.googleapis.com/auth/userinfo.email
        https://www.googleapis.com/auth/userinfo.profile

18. Click Add to table, then Update, then Save.
19. Open Clients. Older consoles call it APIs & Services > Credentials.
    Click Create client, or Create credentials > OAuth client ID.
20. For Application type, select iOS. This type is correct for a Mac app. It
    has no client secret and returns to a native app.
21. In Name, type "GChat Mac". In Bundle ID, type org.themullers.gchat. Leave
    App Store ID and Team ID empty.
22. Click Create and copy the Client ID. It looks like
    1234567890-abc123.apps.googleusercontent.com. The Clients page shows it
    again later. The client ID is an identifier, not a secret.

The scopes give GChat these permissions:

- List conversations, and start direct messages and group chats.
- Read and send messages.
- List the members of conversations, for titles.
- Read and set read markers.
- Read the directory, for names, photos and the list of people.
- Identify the person who is signed in.


## Sign in

1. Open GChat.
2. If GChat shows a field for the client ID, paste the client ID.
3. Click Sign In with Google.
4. Select the Workspace account and allow every permission. GChat stops the
   sign-in if a permission is not allowed.

To change to another organization, click Sign Out in Settings, then sign in
with the client ID of the other organization.


## Problems during sign-in

These messages show in Google's sign-in sheet:

- "Access blocked: GChat Mac can only be used within its organization"
  (Error 403: org_internal). The account is not in the organization that
  owns the project. Select an account of that organization, or make the
  project in the other organization.
- "Error 400: admin_policy_enforced". A Workspace admin limits which apps
  can use Chat data. An admin must allow GChat in the Admin console under
  Security > Access and data control > API controls. The admin selects
  "Trust internal apps", or adds the client ID as a trusted app.
- "Error 401: invalid_client". The client ID is wrong, or the client was
  deleted.
- "Error 400: invalid_request" or "redirect_uri_mismatch". The client is not
  of type iOS. Make a new client (steps 19 to 22).


## Problems after sign-in

These messages and symptoms show in GChat:

- "Google Chat API has not been used in project ... or it is disabled". Step
  6 was not done. After the API is enabled, it can take a minute to work.
- "Google Chat app not found. To create a Chat app, you must turn on the
  Chat API and configure the app in the Google Cloud console." Steps 8 to
  13 were not done or not saved.
- "These permissions were not granted". A permission was not allowed on the
  consent page. Sign in again and allow all of them.
- "Request had insufficient authentication scopes". A scope was added after
  the sign-in. Sign out and sign in again.
- People show as "Unknown", and direct messages as "Direct Message". The
  People API is not enabled (step 7), or the organization turned off contact
  sharing (Admin console > Directory > Directory settings).
- The New Conversation sheet shows a yellow triangle, and the panel shows
  "The G Suite domain admin has disabled external directory sharing". The
  organization does not let apps read its directory. The sheet then lists
  only people from existing conversations. A Workspace admin can change the
  setting. The request, with its risks, is in directory-sharing-request.md.
- "Your sign-in has expired". Google revoked the refresh token. If the
  audience of the consent screen is External and in testing, tokens expire
  after 7 days. Use Internal (step 15).
