# Request: allow third-party apps to read the organization directory

Requested by: [name]
Date: [date]
For: Google Workspace administrator with the Directory settings privilege


## The request

Change one Google Workspace setting:

    Admin console > Directory > Directory settings > Sharing settings >
    External Directory sharing

    from:  Authenticated user basic profile fields
    to:    Organization data and authenticated user basic profile fields


## Why

I use a native Mac client for Google Chat (GChat) that talks to Google's
public APIs with my own sign-in. To start a conversation with a colleague it
shows a list of people in the organization, which it gets from the Google
People API (the people.listDirectoryPeople method, with the
directory.readonly permission).

With the current setting Google refuses that call with: "The G Suite domain
admin has disabled external directory sharing." The app then only lists
people I already have a conversation with. Everything else in the app works
without this change.


## What the setting does

Google's description of the two options, from its admin help:

- Authenticated user basic profile fields (current): "Share only the
  authenticated user's name, photo, and email address to enable Google
  Sign-In if the user grants the appropriate scopes."
- Organization data and authenticated user basic profile fields (requested):
  "Share all Directory information that is shared within your organization.
  This information includes profile information for users in your
  organization that admins, users, and shared external contacts have
  created."

In plain terms: today a third-party app can learn who the signed-in user is
and nothing about anyone else. After the change, a third-party app that a
user has signed in to, and granted directory permission, can read the same
directory that the user can already see in Gmail, Contacts and Chat.

Scope of the setting, per Google:

- It applies to three APIs: the People API, the CardDAV API and the Contacts
  API v3, and to apps that use them. Google's examples are iOS Mail and
  third-party contacts apps on Android.
- It never shares users' personal contacts or private profile data, and it
  does not include suspended or deleted users.
- A change can take up to 24 hours to apply.


## What it does not do

- It does not share anything with people outside the organization. "External"
  refers to apps other than Google's own, not to external people.
- It does not give any app access by itself. An app reads the directory only
  after a user in the organization signs in to it and approves a directory or
  contacts permission on Google's consent screen.
- It does not change what users can see. Anyone in the organization can
  already browse the directory in Google's own apps.
- It does not touch mail, files, calendars or chat content.


## Risks

The setting is organization-wide. It cannot be limited to one app from this
screen, so the change is broader than the one app that prompted it.

1. Any app an employee approves can copy the directory. That includes apps
   from outside publishers. What it can read is whatever the directory
   holds: names, email addresses, photos, and any other fields the
   organization publishes there, such as job titles, phone numbers,
   departments and managers, plus shared external contacts.

2. Consent phishing. An attacker can build an app that asks for directory
   permission and trick one employee into approving it. Today that yields
   only that employee's own profile. After the change it yields the
   directory.

3. Bulk export. A person or malware with access to one account can already
   read the directory through Google's web apps, but slowly. The API makes
   it fast and complete. The same applies to a stolen app token.

4. Once copied, the data is outside Google's controls. A complete,
   current staff list with roles is useful for targeted phishing and
   impersonation, and it cannot be recalled.

5. Apps the organization already allows, such as mail and contacts apps on
   phones, will start receiving directory data they do not receive today.

How large this is depends on how sensitive the directory is. If it holds
only names and work email addresses that are largely discoverable anyway,
the added exposure is modest. If it holds personal phone numbers or
reporting lines, it is larger.


## Mitigations

- Restrict which third-party apps may access Workspace data. In the Admin
  console under Security > Access and data control > API controls, access
  can be limited to apps that an admin has marked as trusted, by OAuth
  client ID. With that in place, only approved apps can use the directory,
  whatever employees click. This is the main control, and it turns an
  organization-wide change into a per-app decision. To confirm before
  relying on it: that the organization's API controls cover the People API
  directory permission.
- Review what the directory contains before changing the setting, and
  remove or hide fields that should not be widely available (Directory
  settings > Profile editing and visibility settings).
- Limit who appears in the directory for whom, using directory visibility
  settings or custom directories, if parts of the organization should not
  be listed.
- Monitor. The Admin console's token and OAuth audit logs show which apps
  have been granted which permissions, and by whom. Review them after the
  change and periodically.
- Keep user awareness current on approving unfamiliar apps on Google's
  consent screen.
- The change is reversible. Setting the option back stops further reads at
  once (allowing for propagation time). It does not recall data already
  copied.


## About the app that prompted this

- Its OAuth client lives in a Google Cloud project inside this organization,
  with the consent screen set to Internal, so only accounts in the
  organization can sign in to it.
- From the directory it reads names, email addresses and photos. It keeps
  them on the user's Mac, in the app's local preferences. It has no server
  and sends them nowhere else.
- OAuth client ID, for marking as trusted: [client ID]

These points describe one app. They do not reduce the organization-wide
effect of the setting described under Risks.


## If the answer is no

The app keeps working. New conversations can be started with anyone I already
have a conversation with; for someone new, the first message has to be sent
from chat.google.com. A possible later change to the app is to start a
conversation by typing a colleague's email address, which would not need the
directory.


## References

- Google Workspace Admin Help, "Let third-party apps access Directory data":
  https://knowledge.workspace.google.com/admin/users/let-third-party-apps-access-directory-data
  (also reachable as https://support.google.com/a/answer/6343701)
- People API, people.listDirectoryPeople:
  https://developers.google.com/people/api/rest/v1/people/listDirectoryPeople

The quoted option descriptions and the scope of the setting are from the
first reference. Check the wording against the live page before sending. The
Admin console paths under Mitigations are from general knowledge of the
console and should be verified by the administrator.
