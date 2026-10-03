# Request: let internal apps read the organization directory

A request to the Google Workspace admins of an organization, from a person
who uses GChat. Why GChat needs the directory is in design.md.

Requested by: [name]. Date: [date].
Needs: the administrator privileges Directory settings and Service Settings.


## The request

The request is two changes, made together, so that only apps built inside
the organization can read the directory.

1. Restrict contacts and directory data to internal apps. In the Admin
   console, go to Security > Access and data control > API controls:
   - In Manage Google Services, set Contacts to Restricted.
   - Select "Trust internal apps".
2. Let apps read the directory. In the Admin console, go to Directory >
   Directory settings > Sharing settings > External Directory sharing.
   Change "Authenticated user basic profile fields" to "Organization data and
   authenticated user basic profile fields".

Do step 1 first. Without step 1, step 2 lets any app that an employee
approves read the directory.


## Reason

GChat is a Mac app for Google Chat. It uses the public APIs of Google with
the sign-in of the person who uses it. To start a conversation, it lists the
people in the organization through the People API. Google refuses that call
with "The G Suite domain admin has disabled external directory sharing". So
GChat lists only people who already have a conversation with the requester.


## What each change does

Directory sharing (step 2): today, a third-party app can read only the name,
photo and email address of the signed-in user. After the change, an app can
read the directory that the user already sees in Gmail and Contacts. The
user must first sign in to the app and allow a directory or contacts
permission.

According to Google, the setting:

- It applies to the People API, the CardDAV API and the Contacts API.
- It never shares personal contacts, private profile data, or suspended or
  deleted users.
- It takes up to 24 hours to apply.
- It shares nothing with people outside the organization. "External" means
  apps that are not from Google.

API controls (step 1): only trusted apps can use a service marked
Restricted. "Trust internal apps" makes every internal app trusted. An
internal app has its OAuth client in a Google Cloud project of the
organization, or is an Apps Script project of an employee. An admin must
approve each app from an outside publisher. The consent screen cannot
override this.

Together, the two changes give the directory to internal apps and keep it
from outside apps.


## Risks of directory sharing

The setting applies to the whole organization and has no list of apps.
Without step 1:

- Any app that an employee approves can copy the whole directory. That
  includes apps from outside publishers. The directory has names, email
  addresses, photos and other published fields, for example titles, phone
  numbers and managers.
- Consent phishing gets more valuable. An attacker who tricks one employee
  into approving an app gets the directory, not only one profile.
- One compromised account or stolen token can export the whole directory
  quickly through the API.
- Copied data cannot be recalled. A current staff list with roles helps
  targeted phishing and impersonation.

With step 1, these risks apply only to internal apps and to outside apps
that an admin approved.


## Risks of the API controls changes

Restricting Contacts:

- It can stop apps that people use today. According to Google, apps that
  are not trusted stop working when a service becomes Restricted, and Google
  revokes their tokens. Examples are contact sync on phones and in mail
  apps, and outside CRM or calendar tools. Before the change, look at the
  list of accessed apps in API controls and approve the apps that must
  continue to work.
- It adds work. An admin must review each outside app that needs contacts.
  Until then, users see a "blocked by admin" message.
- It covers contacts only. Mail, Drive, Chat and Calendar are separate
  services, each with its own Restricted setting.

"Trust internal apps":

- It trusts every internal app, not only GChat. An employee who can make a
  Cloud project or an Apps Script project can build an app that reads the
  directory, with no admin review.
- It applies to every Restricted service, not only Contacts. If Gmail, Drive
  or Chat is Restricted now or later, internal apps get those services too.
- Each user must still sign in and allow the permissions, and an internal
  app gets only the data of those users. But this control does not stop a
  careless or malicious internal script that colleagues approve.
- An attacker who takes over an employee account can make an internal app.
  That attacker can already read the directory in Google's own apps. The
  added risk is a fast and complete export.

These steps reduce the risk from internal apps:

- Limit who can make Cloud projects in the organization (the Project Creator
  role) and who can use Apps Script.
- Set the consent screen of internal apps to Internal, so that outside
  accounts cannot use them.
- If "Trust internal apps" is too broad, leave it off and approve only the
  GChat client, in Manage App Access, with access set to Specific Google
  data. Client ID: [client ID]

Not verified yet:

- That Contacts is in the list in Manage Google Services, and that
  restricting it blocks the directory permission of the People API
  (directory.readonly). Google's help page does not list the services. A
  test with an outside app answers the question.
- The current state of "Trust internal apps". It can already be on.

If Contacts cannot be restricted, there is a stricter setting for apps that
are not configured: "Allow users to access third-party apps that only ask
for Google sign-in info". It blocks all Google data from every app that is
not approved, so its impact is much larger.


## Other ways to reduce risk

- Before step 2, look at the fields that the directory publishes, and remove
  fields that must not be widely available.
- After the change, and from time to time, review the OAuth token audit log.
- Both changes can be reverted. A revert stops further access but does not
  recall data that was already copied.


## About GChat

The OAuth client of GChat is in a Google Cloud project of the organization,
and its consent screen is Internal. So GChat is an internal app, and only
accounts of the organization can sign in. GChat reads names, email addresses
and photos from the directory and keeps them on the user's Mac. It has no
server and sends them nowhere else. GChat also uses Google Chat permissions.
With "Trust internal apps" on, these continue to work if Chat becomes a
Restricted service.


## If the answer is no

GChat continues to work. It can start conversations with people who already
have a conversation with the requester. The first message to anyone else
must go through chat.google.com.


## References

- Let third-party apps access Directory data:
  https://knowledge.workspace.google.com/admin/users/let-third-party-apps-access-directory-data
- Control which apps access Google Workspace data:
  https://knowledge.workspace.google.com/admin/apps/control-which-apps-access-google-workspace-data
- People API, people.listDirectoryPeople:
  https://developers.google.com/people/api/rest/v1/people/listDirectoryPeople

The option names come from these pages. Not verified yet: the names and the
paths in the Admin console of this organization.
