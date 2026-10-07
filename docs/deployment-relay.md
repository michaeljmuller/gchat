# Deployment of the relay

Setting up the relay that receives Workspace Events notices and passes them
to GChat. For the owner of the organization's Google Cloud project, and for
the release manager of the Hetzner host. Why the relay exists is in design.md. Its interface is
in api-contract.md.

This is a procedure for people, not a script. Deployment, Caddy, DNS, server
secrets and backups belong to the release manager. The repository supplies
the container and states what it needs.


## Packaging

    Component         src/python/relay
    Container         src/docker/relay/Dockerfile
    Compose file      src/docker/docker-compose.yml (project name gchat)
    Host port         8086 (in the ports registry)
    Address           https://gchat-relay.themullers.org
    Version check     GET /healthz shows the commit and its date


## Cloud setup, once for each Cloud project

The owner of the Cloud project does these steps in the Google Cloud console,
in the project that holds the GChat OAuth client. The relay must be running
at its public address before step 7, because Pub/Sub starts pushing at once.

1. Make sure that the project has a billing account. Pub/Sub needs one, even
   when the use stays inside the free tier. In Billing > Budgets & alerts, a
   budget of about 5 US dollars a month sends an email if something goes
   wrong.
2. Go to APIs & Services > Library. Enable "Cloud Pub/Sub API" and "Google
   Workspace Events API". Do not use Pub/Sub Lite, which is a different
   product that Google is retiring.
3. Go to Pub/Sub > Topics and click Create topic. For Topic ID, type
   gchat-events. Clear "Add a default subscription". Click Create.
4. Open the topic, open its Permissions, and click Add principal. For the
   principal, type chat-api-push@system.gserviceaccount.com. For the role,
   select Pub/Sub Publisher. Click Save. This lets Google Chat publish events
   to the topic.

   If the console refuses this principal, the organization policy
   "Domain restricted sharing" (iam.allowedPolicyMemberDomains) is on. It
   allows roles only for accounts of the organization, and this account
   belongs to Google. An admin with the Organization Policy Administrator
   role can allow it for this project.

   Not verified yet: that this is the right principal for Workspace Events.
   Google's documentation names it for Chat. If GChat later fails to make
   its Workspace Events subscription with the error INVALID_PUBSUB_TOPIC,
   this grant is the first thing to look at.
5. Go to IAM & Admin > Service Accounts and click Create service account.
   For the name, type gchat-relay. Click Done without granting any role, and
   do not make a key. Pub/Sub signs its pushes as this account. The relay
   only checks the signature. The person who makes the push subscription in
   step 7 needs the role Service Account User on this account. A project
   Owner has it already.
6. Allow Pub/Sub to sign as the service account. Go to IAM & Admin > IAM,
   and select "Include Google-provided role grants". Find the principal
   service-<project number>@gcp-sa-pubsub.iam.gserviceaccount.com. If it
   does not have the role Service Account Token Creator, open the gchat-relay
   service account, open Permissions, and grant that role to this
   principal. Not verified yet: whether new projects have the grant already.
7. Go to Pub/Sub > Subscriptions and click Create subscription:
   - Subscription ID: gchat-relay.
   - Topic: gchat-events.
   - Delivery type: Push.
   - Endpoint URL: https://gchat-relay.themullers.org/v1/pubsub/push
   - Enable authentication: on. Service account: gchat-relay. Audience:
     type the endpoint URL again,
     https://gchat-relay.themullers.org/v1/pubsub/push. It must equal
     PUSH_AUDIENCE on the relay.
   - Message retention duration: 1 day.
   - Retry policy: retry after exponential backoff delay.
   Click Create.

The values for the release manager:

    PUSH_SERVICE_ACCOUNT  the email address of the service account from step 5
    PUSH_AUDIENCE         https://gchat-relay.themullers.org/v1/pubsub/push
    PUBSUB_SUBSCRIPTION   projects/<project ID>/subscriptions/gchat-relay
    ALLOWED_CLIENT_IDS    the OAuth client ID of GChat in this project
    ALLOWED_DOMAINS       the Workspace domain, for example ziaconsulting.com

None of these values is a secret. The host holds no Google credentials.

One relay accepts pushes from one Pub/Sub subscription, so it serves the
organization of one Cloud project. A second organization needs a second
relay, or a change to the relay (to-do.md).


## On the host, for the release manager

1. Pull the repository on the host.
2. Copy src/docker/.env.example to src/docker/.env and fill in the five
   values above.
3. Start the relay:

       cd src/docker
       podman compose up -d --build relay

4. Add the Caddy block and reload Caddy:

       gchat-relay.themullers.org {
           reverse_proxy host.containers.internal:8086
       }

   Caddy passes the event stream through without buffering. Nothing more is
   needed for it.
5. Add a DNS record for gchat-relay.themullers.org that points to the host.
6. Make sure that lingering is on for the user that runs Podman, so that the
   relay starts again after a reboot:

       loginctl enable-linger <user>

7. Make sure that the relay works:

       curl https://gchat-relay.themullers.org/healthz

   The answer shows "ok" and the commit. The log of the relay shows a warning
   if PUSH_SERVICE_ACCOUNT is empty.

A development or test relay on the same host is possible: a second
subdomain, host port and push subscription, and its own copy of the
repository. Claim the port in the ports registry first.


## Updates

Pull the repository, then run the command from step 4 again. Copies of GChat
that are connected lose their stream and connect again. They catch up by
refreshing, so no message is lost.


## Run it on a development Mac

Google cannot push to a development Mac, so a Mac can test only the stream
and the checks, with PUSH_SERVICE_ACCOUNT empty in src/docker/.env:

    cd src/docker
    docker compose up -d --build relay
    curl http://localhost:8086/healthz

A test of the whole chain needs a relay at a public HTTPS address, on the
host. The tests run in a container:

    docker compose --profile tools run --rm --build tests
