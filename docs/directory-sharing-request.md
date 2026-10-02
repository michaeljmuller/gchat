# Request: let approved apps read the organization directory

Requested by: [name]. Date: [date].
Needs: the Directory settings and Service Settings administrator privileges.


## The request

Two changes, made together so that only approved apps gain directory access.

1. Restrict which apps can read contacts and directory data.
   Admin console > Security > Access and data control > API controls >
   Manage Google Services: set Contacts to Restricted.
   Then under Manage App Access, add this OAuth client and give it access
   (Specific Google data limited to its scopes, or Trusted):
   [client ID]

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
an admin has configured as Trusted or as Specific Google data. Everything
else is refused, whatever a user clicks on the consent screen. This turns
the organization-wide directory setting into a per-app decision.


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

With step 1 in place these are limited to the apps that were approved.


## Risks of the API controls restriction

- It can break apps people use today. Per Google, when a service becomes
  Restricted, installed apps that are not trusted stop working and their
  tokens are revoked. That may include contact sync on phones and in mail
  clients, CRM and calendar tools, and Apps Script projects that read
  contacts. Check the accessed-apps list under API controls first and
  approve what should keep working.
- It is ongoing work. New apps that need contacts have to be reviewed and
  approved, and users will hit a "blocked by admin" message until they are.
- Approval is by OAuth client ID and is only as good as the review. Trusted
  grants access to every Google service, restricted or not; Specific Google
  data limits an app to named scopes and is the safer choice.
- "Trust internal apps" approves every app built inside the organization,
  including scripts any employee writes. Leave it off unless that is
  intended, and approve this client individually.
- Restricting Contacts does not cover other data. Mail, Drive, Chat and
  Calendar are separate services with their own Restricted setting.

To confirm before relying on step 1: that Contacts appears in the Manage
Google Services list and that restricting it blocks the People API directory
permission (directory.readonly). Google's help page does not list the
services. A test with an unapproved app answers it. If Contacts cannot be
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
the consent screen set to Internal, so only our accounts can sign in. From
the directory it reads names, emails and photos and keeps them on the user's
Mac. It has no server and sends them nowhere else. It also uses Google Chat
permissions, so if Chat is a Restricted service the same client needs to be
approved for that too.


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
