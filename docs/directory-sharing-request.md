# Request: let internal apps read the organization directory

Requested by: [name]. Date: [date].
Needs: the Directory settings and Service Settings administrator privileges.


## The request

Two changes, made together so that only apps built inside the organization
gain directory access.

1. Restrict contacts and directory data to internal apps.
   Admin console > Security > Access and data control > API controls:
   - Manage Google Services: set Contacts to Restricted.
   - Tick "Trust internal apps".

2. Turn on directory sharing for apps.
   Admin console > Directory > Directory settings > Sharing settings >
   External Directory sharing: change "Authenticated user basic profile
   fields" to "Organization data and authenticated user basic profile
   fields".

Do step 1 first. Step 2 without step 1 opens the directory to any app an
employee approves.


## Why

I use a native Mac client for Google Chat that calls Google's public APIs
with my own sign-in. To start a conversation with a colleague it lists the
people in the organization through the People API. Google currently refuses
that call ("The G Suite domain admin has disabled external directory
sharing"), so the app only lists people I already have a conversation with.
Everything else in the app works without this change.


## What each change does

Directory sharing (step 2). Today a third-party app can read only the
signed-in user's own name, photo and email. After the change, an app that a
user has signed in to and granted a directory or contacts permission can
read the directory that user already sees in Gmail and Contacts. Per Google,
this applies to the People, CardDAV and Contacts APIs, never includes
personal contacts, private profile data, or suspended or deleted users, and
can take up to 24 hours to apply. It shares nothing with people outside the
organization; "external" means apps other than Google's own.

API controls (step 1). A service marked Restricted can be used only by apps
that are trusted. "Trust internal apps" makes every internal app trusted. An
internal app is one whose OAuth client is in a Google Cloud project owned by
the organization, or an Apps Script project written by an employee. Apps
from outside publishers are refused unless an admin approves them one by
one, whatever a user clicks on the consent screen. Together the two changes
mean: internal apps can read the directory, outside apps cannot.


## Risks of directory sharing

The setting is organization-wide and has no per-app list of its own. Without
step 1:

- Any app an employee approves, including apps from outside publishers, can
  copy the whole directory: names, emails, photos and any other published
  fields such as titles, phone numbers and managers.
- Consent phishing gets more valuable. Tricking one employee into approving
  an app yields the directory, where today it yields one profile.
- One compromised account or stolen app token can export the directory
  quickly and completely through the API.
- Copied data cannot be recalled, and a current staff list with roles is
  useful for targeted phishing and impersonation.

With step 1 in place, outside apps are shut out and these risks are limited
to internal apps and to outside apps an admin has approved.


## Risks of the API controls changes

From restricting Contacts:

- It can break apps people use today. Per Google, when a service becomes
  Restricted, installed apps that are not trusted stop working and their
  tokens are revoked. That may include contact sync on phones and in mail
  clients, and CRM or calendar tools from outside publishers. Check the
  accessed-apps list under API controls first and approve what should keep
  working.
- It is ongoing work. Outside apps that need contacts have to be reviewed
  and approved, and users see a "blocked by admin" message until they are.
- It covers contacts only. Mail, Drive, Chat and Calendar are separate
  services with their own Restricted setting.

From "Trust internal apps":

- It trusts every internal app, not only this one. Any employee who can
  create a Cloud project or an Apps Script project in the organization can
  build an app that reads the directory, with no admin review.
- It applies to every Restricted service, not only Contacts. If Gmail, Drive
  or Chat are Restricted now or later, internal apps get those too.
- The user still has to sign in and approve the permissions, and an internal
  app only reaches the data of the people who do. But a careless or
  malicious internal script that colleagues are persuaded to approve is not
  stopped by this control.
- An attacker who takes over an employee account could create an internal
  app. That attacker can already read the directory through Google's own
  apps, so the added exposure is speed and completeness of export.

What narrows the internal-app risk:

- Limit who can create Cloud projects in the organization (the Project
  Creator role) and who can use Apps Script.
- Set OAuth consent screens to Internal, so internal apps cannot be used by
  outside accounts.
- If trusting all internal apps is too broad, leave the box unticked and
  approve this one client instead, under Manage App Access, with access set
  to Specific Google data. Client ID: [client ID]

To confirm before relying on step 1: that Contacts appears in the Manage
Google Services list and that restricting it blocks the People API directory
permission (directory.readonly). Google's help page does not list the
services. A test with an outside app answers it. Also confirm the current
state of "Trust internal apps"; it may already be ticked. If Contacts cannot be
restricted, the alternative is the stricter setting for unconfigured apps,
"Allow users to access third-party apps that only ask for Google sign-in
info", which blocks every unapproved app from all Google data and has a much
larger impact.


## Other mitigations

- Review what the directory publishes and remove fields that should not be
  widely available before step 2.
- Review the OAuth token audit log after the change and periodically.
- Both changes are reversible. Reverting stops further access but does not
  recall data already copied.


## About the app

Its OAuth client is in a Google Cloud project inside this organization with
the consent screen set to Internal, so it counts as an internal app and only
our accounts can sign in. From
the directory it reads names, emails and photos and keeps them on the user's
Mac. It has no server and sends them nowhere else. It also uses Google Chat
permissions; with "Trust internal apps" ticked that keeps working even if
Chat is a Restricted service.


## If the answer is no

The app keeps working. New conversations can be started with anyone I already
have one with; a first message to someone new has to be sent from
chat.google.com.


## References

- Let third-party apps access Directory data:
  https://knowledge.workspace.google.com/admin/users/let-third-party-apps-access-directory-data
- Control which apps access Google Workspace data:
  https://knowledge.workspace.google.com/admin/apps/control-which-apps-access-google-workspace-data
- People API, people.listDirectoryPeople:
  https://developers.google.com/people/api/rest/v1/people/listDirectoryPeople

Check Google's wording and the console paths against the live pages before
acting; the option names here were taken from those pages but not verified
in this organization's console.
