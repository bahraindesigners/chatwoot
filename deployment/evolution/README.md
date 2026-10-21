# Evolution service for internal WhatsApp inboxes

Evolution runs alongside the Chatwoot fork and connects Baileys instances through
Chatwoot's existing API inboxes. It does not change the official WhatsApp channel.
The Oman customer-service number stays on the separate official Cloud API path.

This integration uses Evolution's native Chatwoot adapter, rather than maintaining
a second adapter inside Rails. Each internal number has its own Evolution instance
and API inbox. Pair it as a linked device while leaving its phone app installed.

## Start the service

The optional Compose file builds `chatwoot-evolution:2.3.7-chatwoot.1` from the
immutable upstream 2.3.7 runtime and a checksum-verified source archive. Its patch
keeps routing configuration local to each operation, detects previously accepted
message IDs, and reports confirmed delivery failures without resending uncertain
or partially accepted deliveries. Both this companion image and the Chatwoot
changes are required for the reliability fixes. Upgrading Chatwoot alone does not
patch an existing Evolution container. PostgreSQL, Redis and WhatsApp session files have separate persistent volumes. The database and
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

The CLI uses the same account-scoped Chatwoot endpoints as the dashboard. It needs
only `CHATWOOT_API_TOKEN` (or an interactive prompt), never the global Evolution
API key. The administrator should be limited to the Chatwoot account being
integrated. The server chooses the canonical instance name and stores the managed
provider metadata, callback and deletion lifecycle.

Create an inbox, assign agents, and use the returned inbox ID (for example, 4):

```sh
python3 deployment/evolution/manage.py \
  --chatwoot-url https://customerservice.lamma.online --account-id 1 \
  create --inbox-name "Internal Operations" --dry-run
python3 deployment/evolution/manage.py \
  --chatwoot-url https://customerservice.lamma.online --account-id 1 \
  create --inbox-name "Internal Operations"
python3 deployment/evolution/manage.py \
  --chatwoot-url https://customerservice.lamma.online --account-id 1 \
  qr 4 --output /tmp/internal-operations-qr.png
python3 deployment/evolution/manage.py \
  --chatwoot-url https://customerservice.lamma.online --account-id 1 status 4
```

The `qr` command creates/configures the Evolution instance on first use. On an
already connected phone it renews Chatwoot credentials without disconnecting the
phone. The old direct-Evolution CLI interface is replaced; existing unmanaged
inboxes need operator review before migration. Do not rename/repoint an active
instance or create a second linked device as an automatic migration.

When a QR is returned, open the image and scan it from the internal number's WhatsApp **Linked devices**.
The QR file is created with mode 0600 and will not overwrite an existing file.
Remove it after pairing. An expired QR can be regenerated into a new file. The
connection state must become `open`. Pairing grants Evolution access to that
number's messages, so the phone owner must complete that step.

Verify a real inbound text and attachment from a test contact, a reply from an
assigned Chatwoot agent, and reconnection after restarting `evolution-api`. These
are acceptance checks; a healthy container alone does not establish delivery.

## Connection and delivery recovery

The dashboard polls current connection state and the current QR while pairing.
It also checks whether Evolution's stored Chatwoot authorization still belongs to
a user with access to this account. **Reconnect Chatwoot** renews that authorization
using the current administrator without unlinking an already connected phone.
No tokens or provider configuration are returned to the browser.

A failed Evolution message's **Retry** action explicitly redelivers that message
through its API-inbox webhook. The companion skips message IDs it already recorded
as accepted. Confirmed pre-send failures mark the original message failed; a network
failure after a send attempt remains uncertain and is not automatically retried.
Accepted sends are not changed to failed because later bookkeeping fails. Delivery
is not claimed to be exactly once across a provider crash before its send receipt
is persisted. Check the recipient before manually repeating an uncertain send.

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
- [Instance API routes](https://github.com/evolution-foundation/evolution-api/blob/2.3.7/src/api/routes/instance.router.ts)
- [Chatwoot adapter and API inbox creation](https://github.com/evolution-foundation/evolution-api/blob/2.3.7/src/api/integrations/chatbot/chatwoot/services/chatwoot.service.ts)
- [Chatwoot configuration fields](https://github.com/evolution-foundation/evolution-api/blob/2.3.7/src/api/integrations/chatbot/chatwoot/dto/chatwoot.dto.ts)

Runtime image is version-pinned; the upstream source links describe the contracts
used when this integration was added. Validate the contracts before changing versions.
