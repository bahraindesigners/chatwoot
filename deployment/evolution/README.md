# Evolution service for internal WhatsApp inboxes

Evolution runs alongside the Chatwoot fork and connects Baileys instances through
Chatwoot's existing API inboxes. It does not change the official WhatsApp channel.
The Oman customer-service number stays on the separate official Cloud API path.

This integration uses Evolution's native Chatwoot adapter, rather than maintaining
a second adapter inside Rails. Each internal number has its own Evolution instance
and API inbox. Pair it as a linked device while leaving its phone app installed.

## Start the service

The optional Compose file pins Evolution to the verified `v2.3.7` image. PostgreSQL,
Redis and WhatsApp session files have separate persistent volumes. The database and
Redis have no published ports; the API binds only to localhost on port 8081.

```sh
cp .env.evolution.example .env.evolution
chmod 600 .env.evolution
openssl rand -hex 32
openssl rand -hex 32
```

Put the two different generated values in `EVOLUTION_API_KEY` and
`EVOLUTION_DB_PASSWORD`. These fields are required. Keep the database password
hexadecimal because it is embedded in a database URL. Do not commit the secrets.

For the repository's production Compose stack, use the **same Compose project name
and base configuration** as the existing installation:

```sh
docker compose --env-file .env --env-file .env.evolution \
  -f docker-compose.production.yaml -f docker-compose.evolution.yaml \
  up -d evolution-api evolution-postgres evolution-redis
```

The files share the default Compose network, so Chatwoot can reach the callback at
`http://evolution-api:8080/chatwoot/webhook/<instance>`. Starting just these three
services does not recreate Rails or Sidekiq. Do not change the existing project's
name or use the repository's stock Chatwoot image to replace the deployed fork.

For an isolated development stack:

```sh
docker compose --env-file .env.evolution -p chatwoot-evolution \
  -f docker-compose.evolution.yaml up -d --wait
```

If Chatwoot runs in another Compose project or in Dokploy, attach `evolution-api`
to a network reachable by Chatwoot and set `EVOLUTION_SERVER_URL` to its callback
address on that network. Evolution must also reach Chatwoot's URL. Use a private
network where possible. Evolution's `/chatwoot/webhook/<instance>` callback is
unauthenticated upstream: keep it accessible only to Chatwoot, and keep the other
Evolution routes private. A predictable instance name is not webhook authentication.
Do not expose the whole API on a public reverse proxy just to receive callbacks.

For remote administration, forward the localhost API port over SSH rather than
exposing it publicly:

```sh
ssh -L 8081:127.0.0.1:8081 user@server
```

## Create an internal-number inbox

### From the Chatwoot dashboard

Deploy this fork's dashboard changes, then set these variables on **both Rails and
Sidekiq** once. Use the same API key already configured on the Evolution service:

```dotenv
EVOLUTION_API_URL=http://lamma-evolution-api:8080
EVOLUTION_API_KEY=<existing Evolution API key>
```

The URL above is the private network alias used by the Lamma Dokploy deployment.
For the repository's merged Compose stack, use `http://evolution-api:8080` instead.
Keep `FRONTEND_URL` set to Chatwoot's reachable HTTPS URL. The dashboard card is
hidden until both Evolution variables are configured. Neither variable is sent
to the browser.

As a Chatwoot administrator:

1. Open **Settings → Inboxes → Add inbox → Evolution WhatsApp**.
2. Enter a unique inbox name and create the inbox.
3. Assign agents, then continue to the pairing screen.
4. Scan its QR from the number's WhatsApp **Linked devices → Link a device**.
5. Wait for **Connected**, open the inbox, and verify a new inbound message and reply.

Chatwoot creates the API inbox, callback, Evolution instance and native integration.
Only the exact server-configured Evolution callback for a verified Evolution inbox
can use its private network address. Other webhooks keep Chatwoot's public-address
protection. Evolution callback redirects are not followed.
It disables group chats and old-message/contact imports. A failed pairing can be
retried from **Settings → Inboxes → your inbox → Settings** without creating another
inbox. Deleting the inbox schedules deletion of its Evolution instance through
Sidekiq. Its name and callback cannot be edited because Evolution routes by name.

Evolution stores the pairing administrator's Chatwoot user token in its database.
Use an administrator limited to this Chatwoot account. If that user's access is
revoked or their token changes, pair again using an active administrator. Protect
Evolution's database and backups. The phone owner must still scan the QR; Chatwoot
cannot authorize a WhatsApp linked device on their behalf.

### Command-line fallback

Use a dedicated Chatwoot administrator account limited to the account being
integrated. Evolution needs its user access token to create inboxes and route
messages. The token is stored in Evolution's own database; protect its volumes and
backups. Creating a new user or granting access must be approved by the operator.

The helper uses Python's standard library. Tokens are read from hidden prompts or
`EVOLUTION_API_KEY` / `CHATWOOT_API_TOKEN` environment variables, never command-line
arguments. Use a unique inbox name and instance name per number. A collision with
an existing Chatwoot inbox is rejected before creating anything.

```sh
python3 deployment/evolution/manage.py create internal-operations-01 \
  --chatwoot-url https://customerservice.lamma.online \
  --account-id 1 --inbox-name 'Internal Operations' --dry-run

# Remove --dry-run when ready to create the instance and inbox.
python3 deployment/evolution/manage.py create internal-operations-01 \
  --chatwoot-url https://customerservice.lamma.online \
  --account-id 1 --inbox-name 'Internal Operations'
```

The helper enables `WHATSAPP-BAILEYS`, ignores groups, disables full-history sync
and contact/message imports, and configures Evolution to create an API inbox.
Evolution's bot contact is enabled for QR/status messages. It preserves Chatwoot
messages when they are deleted on WhatsApp. It does not send a WhatsApp message.

If instance creation succeeds but inbox configuration fails, the helper reports
the successful instance creation before the error. Inspect Evolution and Chatwoot
before retrying; it does not delete a partially configured instance or reuse a
pre-existing inbox automatically.

Assign agents under Chatwoot **Settings → Inboxes → Internal Operations**. Then:

```sh
python3 deployment/evolution/manage.py qr internal-operations-01 \
  --output /tmp/internal-operations-qr.png
python3 deployment/evolution/manage.py status internal-operations-01
```

Open the QR image and scan it from the internal number's WhatsApp **Linked devices**.
The QR file is created with mode 0600 and will not overwrite an existing file.
Remove it after pairing. An expired QR can be regenerated into a new file. The
connection state must become `open`. Pairing grants Evolution access to that
number's messages, so the phone owner must complete that step.

Verify a real inbound text and attachment from a test contact, a reply from an
assigned Chatwoot agent, and reconnection after restarting `evolution-api`. These
are acceptance checks; a healthy container alone does not establish delivery.

## Operations

```sh
docker compose --env-file .env.evolution -p chatwoot-evolution \
  -f docker-compose.evolution.yaml ps
docker compose --env-file .env.evolution -p chatwoot-evolution \
  -f docker-compose.evolution.yaml logs --tail 100 evolution-api
```

For a merged production stack, include its existing base file/env file/project
name in those commands. Back up the Evolution PostgreSQL and instances volumes.
Stopping containers retains data; do not use `down -v` on a real installation.
Keep upgrades explicit and verify inbound/outbound media and reconnection afterward.
Baileys is an unofficial linked-device integration and can disconnect or break
when WhatsApp changes; use the official Cloud API for customer-service numbers.

## Source contracts

- [Evolution v2.3.7 image](https://hub.docker.com/r/evoapicloud/evolution-api/tags?name=v2.3.7)
- [Evolution connection types and Chatwoot integration](https://github.com/evolution-foundation/evolution-api)
- [Instance API routes](https://github.com/evolution-foundation/evolution-api/blob/main/src/api/routes/instance.router.ts)
- [Chatwoot adapter and API inbox creation](https://github.com/evolution-foundation/evolution-api/blob/main/src/api/integrations/chatbot/chatwoot/services/chatwoot.service.ts)
- [Chatwoot configuration fields](https://github.com/evolution-foundation/evolution-api/blob/main/src/api/integrations/chatbot/chatwoot/dto/chatwoot.dto.ts)

Runtime image is version-pinned; the upstream source links describe the contracts
used when this integration was added. Validate the contracts before changing versions.
