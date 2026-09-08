# Deploy this fork with Dokploy and GHCR

The `Publish fork image to GHCR` workflow builds the fork on each push to `develop`, or when started manually through GitHub Actions. It uses GitHub's built-in `GITHUB_TOKEN`; no Docker Hub account or personal publishing token is required.

Images are built natively for `linux/amd64` and `linux/arm64`. Each image is checked for its source commit, compiled frontend assets, and required media libraries before publication. The combined tags are published only after both architecture checks pass.

- Registry/image: `ghcr.io/bahraindesigners/chatwoot`
- Versioned tag: `sha-<full Git commit SHA>`
- Moving tag: `develop`

Use the exact versioned tag shown in the successful workflow summary for production and rollback. Publishing an image does not deploy it to your server.

## First publication and package visibility

GitHub initially creates container packages as private. For anonymous pulls, open the `chatwoot` package under the GitHub account's Packages tab, then Package settings, and set visibility to Public. A public source repository does not automatically make its package public.

If keeping the image private, configure GHCR credentials in Dokploy using the GitHub username and a classic personal access token with `read:packages`, entered directly in Dokploy. Do not put tokens in this repository or in image build arguments.

## Update an existing Dokploy deployment

1. Back up PostgreSQL, stored attachments, and the current Dokploy configuration. Record the currently deployed image tag or digest.
2. Review the running Chatwoot version before upgrading to this fork.
3. In the existing Compose service, replace the image for both Rails/web and Sidekiq with the same published SHA tag. If an anchor supplies both image fields, change that shared value.
4. Preserve service names, PostgreSQL/Redis settings, environment variables, domain routing, and persistent volume names. Both services need access to the same attachment storage; for local storage, retain the shared `/app/storage` mount.
5. Redeploy the existing services. This WhatsApp patch adds no database migration. If also upgrading Chatwoot versions, follow that version's migration procedure.
6. Verify web and worker health, image previews, outgoing and incoming WhatsApp images, a document, and a voice note with a test contact. Confirm actual delivery on WhatsApp.

Do not replace a live deployment with the repository's example Compose file: its database and volume settings are examples, not your production configuration. Keep the previous image available for rollback.
