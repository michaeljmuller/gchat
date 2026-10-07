# Deployment of the relay

Setting up the relay that passes Workspace Events notices to GChat. For the
owner of the organization's Google Cloud project, and for the release manager
of the Hetzner host. Why the relay exists is in design.md. Its interface is
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
in the project that holds the GChat OAuth client:

1. Go to APIs & Services > Library. Enable "Cloud Pub/Sub API" and "Google
   Workspace Events API".
2. Go to Pub/Sub > Topics and click Create topic. For Topic ID, type
   gchat-events. Clear "Add a default subscription". Click Create.
3. Open the topic, open its Permissions, and click Add principal. For the
   principal, type chat-api-push@system.gserviceaccount.com. For the role,
   select Pub/Sub Publisher. Click Save. This lets Google Chat publish events
   to the topic.
4. Go to Pub/Sub > Subscriptions and click Create subscription. For
   Subscription ID, type gchat-relay. For the topic, select gchat-events. For
   Delivery type, select Pull. Set Message retention duration to 1 day. Click
   Create.
5. Go to IAM & Admin > Service Accounts and click Create service account.
   For the name, type gchat-relay. Click Done without granting any project
   role.
6. Open the gchat-relay subscription from step 4, open its Permissions, and
   click Add principal. For the principal, type the email address of the
   service account from step 5. For the role, select Pub/Sub Subscriber.
   Click Save. This is the only permission the service account gets.
7. Open the service account, open Keys, and click Add key > Create new key >
   JSON. Give the downloaded file to the release manager through a private
   channel. Do not put it in the repository or in a chat message.

If step 7 shows that key creation is disabled, an organization policy
(iam.disableServiceAccountKeyCreation) blocks it. Organizations made since
2024 have that policy on by default. A Workspace admin with the Organization
Policy Administrator role can allow keys for this project. Not verified yet:
whether the Zia Consulting organization has the policy on.

The values for the release manager:

    PUBSUB_SUBSCRIPTION   projects/<project ID>/subscriptions/gchat-relay
    ALLOWED_CLIENT_IDS    the OAuth client ID of GChat in this project
    ALLOWED_DOMAINS       the Workspace domain, for example ziaconsulting.com

One relay reads one Pub/Sub subscription, so it serves the organization of
one Cloud project. A second organization needs a second relay, or a change
to the relay (to-do.md).


## On the host, for the release manager

1. Pull the repository on the host.
2. Put the service account key at volumes/secrets/relay-service-account.json
   in the repository folder. The folder is not in git. Make the file readable
   only by the user that runs Podman.
3. Copy src/docker/.env.example to src/docker/.env and fill in the three
   values above.
4. Start the relay:

       cd src/docker
       podman compose up -d --build relay

5. Add the Caddy block and reload Caddy:

       gchat-relay.themullers.org {
           reverse_proxy host.containers.internal:8086
       }

   Caddy passes the event stream through without buffering. Nothing more is
   needed for it.
6. Add a DNS record for gchat-relay.themullers.org that points to the host.
7. Make sure that lingering is on for the user that runs Podman, so that the
   relay starts again after a reboot:

       loginctl enable-linger <user>

8. Make sure that the relay works:

       curl https://gchat-relay.themullers.org/healthz

   The answer shows "ok" and the commit. The log of the relay shows a warning
   if PUBSUB_SUBSCRIPTION is empty, and an error if the key file is missing.


## Updates

Pull the repository, then run the command from step 4 again. Copies of GChat
that are connected lose their stream and connect again. They catch up by
refreshing, so no message is lost.


## Run it on a development Mac

To try the HTTP side without Google Cloud, leave PUBSUB_SUBSCRIPTION empty in
src/docker/.env, then:

    cd src/docker
    docker compose up -d --build relay
    curl http://localhost:8086/healthz

The tests run in a container:

    docker compose --profile tools run --rm --build tests
