# Google Cloud setup

GChat signs in with an OAuth client that lives in a Google Cloud project of
your organization. This page creates one. Organizations that ship a build with
their client ID built in (see building.md) only need to do this once, for
everyone.

Do this once per Workspace organization. If you use the app with two
organizations (personal and work), do it in each one and keep both client IDs.
It takes about ten minutes. Nothing here costs money.

The console's page names change from time to time. If a label below does not
match, search for it in the console's search bar at the top.

1. Create a project

   Open https://console.cloud.google.com/ and sign in with the Workspace
   account you want to chat from. Click the project picker in the top bar,
   then New Project. Name it anything (for example "GChat Mac"). Make sure
   Organization shows your Workspace domain, not "No organization"; the
   Internal setting in step 4 depends on it. Click Create, then select the
   new project in the project picker.

2. Enable the two APIs

   Go to APIs & Services > Library. Search for "Google Chat API", open it,
   click Enable. Go back to the Library, search for "People API", open it,
   click Enable. The People API is what turns user IDs into names and photos.

3. Configure the Chat app

   Google requires every project that calls the Chat API to have a Chat app
   configured, even when it only acts as you. Calls fail until this is saved.

   Go to APIs & Services > Enabled APIs & services > Google Chat API, then
   the Configuration tab. Fill in:

   - App name: GChat Mac (anything)
   - Avatar URL: any https image URL, for example
     https://developers.google.com/chat/images/quickstart-app-avatar.png
   - Description: Native Mac client (anything)
   - Interactive features: turn this off. The app never receives events, and
     with it off the page asks for nothing else.

   Click Save. This does not publish anything to other people.

4. Set up the consent screen

   Go to Google Auth Platform (older consoles call it APIs & Services >
   OAuth consent screen). If it shows Get started, click it and enter:

   - App name: GChat Mac
   - User support email: your address
   - Audience: Internal. This limits sign-in to your organization, needs no
     Google review, and the sign-in does not expire.
   - Contact email: your address

   Then open Data Access, click Add or remove scopes, and paste these lines
   into the "Manually add scopes" box:

       https://www.googleapis.com/auth/chat.spaces.readonly
       https://www.googleapis.com/auth/chat.spaces.create
       https://www.googleapis.com/auth/chat.messages
       https://www.googleapis.com/auth/chat.memberships.readonly
       https://www.googleapis.com/auth/chat.users.readstate
       https://www.googleapis.com/auth/directory.readonly
       openid
       https://www.googleapis.com/auth/userinfo.email
       https://www.googleapis.com/auth/userinfo.profile

   Click Add to table, then Update, then Save.

   What they are for: list your conversations, start a direct message or
   group chat, read and send messages, list members (to name direct messages),
   read and set unread markers, list the organization's people with their
   names and photos, and identify you.

5. Create the OAuth client

   In Google Auth Platform open Clients (older consoles: APIs & Services >
   Credentials), click Create client (or Create credentials > OAuth client
   ID) and enter:

   - Application type: iOS. This is correct for a Mac app; it is the client
     type with no secret that redirects back to a native app.
   - Name: GChat Mac
   - Bundle ID: org.themullers.gchat
   - App Store ID and Team ID: leave empty

   Click Create. Copy the Client ID. It looks like
   1234567890-abc123.apps.googleusercontent.com. You can find it again
   later on the Clients page. It is an identifier, not a secret.

6. Sign in

   Start GChat, paste the client ID, click Sign In with Google. A browser
   sheet opens. Choose your Workspace account and allow every permission
   listed; the app refuses to continue if one is left unticked.

To switch organizations, choose Sign Out in Settings, paste the other
organization's client ID, and sign in again.

## If something goes wrong

During sign-in, in the browser sheet:

- "Access blocked: GChat Mac can only be used within its organization"
  (Error 403: org_internal). You picked an account outside the organization
  that owns the project. Pick the right account, or create the project in
  the other organization.
- "Error 400: admin_policy_enforced". The Workspace admin restricts which
  apps may use Chat data. An admin has to allow it in the Admin console
  under Security > Access and data control > API controls: either tick
  "Trust internal apps" or add this client ID as a trusted app.
- "Error 401: invalid_client". The client ID has a typo or was deleted.
- "Error 400: invalid_request" or "redirect_uri_mismatch". The client was
  not created with application type iOS. Create a new one (step 5).

After sign-in, in the app:

- "Google Chat API has not been used in project ... or it is disabled".
  Step 2 was skipped. Enabling can take a minute to take effect.
- "Google Chat app not found. To create a Chat app, you must turn on the
  Chat API and configure the app in the Google Cloud console." Step 3 was
  skipped or not saved.
- "These permissions were not granted". A box was left unticked on the
  consent page. Sign in again and allow all of them.
- "Request had insufficient authentication scopes". A scope was added to
  the project after you signed in. Sign out and sign in again.
- People show as "Unknown" and direct messages as "Direct Message". The
  People API is not enabled (step 2), or the organization has contact
  sharing turned off (Admin console > Directory > Directory settings).
- The New Conversation sheet says the directory could not be loaded, with
  "The G Suite domain admin has disabled external directory sharing". The
  organization shares only the signed-in user's own profile with third-party
  apps, not the directory. A Workspace super admin can change that in the
  Admin console under Directory > Directory settings > Sharing settings >
  External Directory sharing, from "Authenticated user basic profile fields"
  to "Organization data and authenticated user basic profile fields". It
  applies to every third-party app in the organization. Until then the sheet
  lists only people you already have a conversation with.
- "Your sign-in has expired". The refresh token was revoked or, if the
  consent screen audience is External and in Testing, it expired after 7
  days. Use Internal (step 4).
