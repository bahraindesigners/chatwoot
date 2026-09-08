# WhatsApp Cloud API image investigation and local fix

Investigated 8–9 September 2026 against Chatwoot 4.17.1 source. This fork preserves upstream history and adds the WhatsApp media fixes described below.

The changes address confirmed defects in this source. Production deployment and live WhatsApp delivery have not been verified. No customer messages were sent during validation.

## Findings

| Area | Finding | Change |
| --- | --- | --- |
| Outgoing attachments | The provider sends `attachment.download_url`, requiring Meta to fetch a URL from your storage/server. This exposes delivery to public URL, proxy, redirect, and remote-fetch failures. | Upload the stored file to `POST /v24.0/{phone_number_id}/media`, then send the returned media ID. Applies to ordinary image, audio, video, and document attachments. |
| Image format | Images can reach the provider with a MIME type such as WebP, which WhatsApp does not accept as an ordinary image. | Convert supported non-JPEG/PNG images to PNG using the existing Active Storage processor. Preserve the original file. Reject images above 5 MB after conversion with a readable error. |
| Incoming media lookup | An unsuccessful lookup previously returned nil. Chatwoot could save a message without its attachment, and subsequent webhook deliveries would find that message and skip it. | Raise on failed lookup so the message transaction rolls back and the webhook job can retry. Retain authorization-error tracking. |
| Incoming retries | The per-message Redis deduplication lock lives for one day and previously remained after a failed download. The job's retry then returned without processing the message. | Release the failed attempt's lock using an ownership token and the existing atomic compare-and-delete helper. Keep successful-message deduplication. |
| Error visibility | Delivery-status processing kept only Meta's code and title, dropping `error_data.details`. | Preserve the detailed rejection reason in the failed message. |

The incoming media lookup now uses Graph API v24.0, matching the existing attachment message endpoint. Text, template and Enterprise calling API versions are unchanged. No new production dependencies, database migrations, or configuration flags are required.

## Relevant upstream reports

These were open when checked:

- [#13540: Intermittent media failures and direct-upload request](https://github.com/chatwoot/chatwoot/issues/13540).
- [#15069: Proposed direct media upload fix](https://github.com/chatwoot/chatwoot/pull/15069), still open/unmerged. This local implementation follows the documented upload/media-ID flow and does not fall back to a public URL after a failed upload.
- [#12260: WebP/non-JPEG image rejection](https://github.com/chatwoot/chatwoot/issues/12260).
- [#13612: Incoming media connection resets inside Docker](https://github.com/chatwoot/chatwoot/issues/13612). This is a reported deployment/network problem; it is not proof that your server has the same fault. Retry handling is fixed locally, but persistent container networking failures still need server investigation.
- [#15007: Image preview failure](https://github.com/chatwoot/chatwoot/issues/15007). That report describes an image delivered to WhatsApp but failing to preview in Chatwoot. This source already uses stable message-ID list keys and image-load retries. No renderer change was made without reproducing that separate problem.
- [#15622: Image-header templates](https://github.com/chatwoot/chatwoot/issues/15622). Template headers use a separate parameter path; this patch does not change externally linked template images. Existing template checks are included in validation.

Meta's [official media API collection](https://www.postman.com/meta/whatsapp-business-platform/folder/13382743-ecb27be5-4d27-4763-bbee-6a8002c04bf3) documents media upload/retrieval, JPEG/PNG images and the 5 MB image limit. Direct Meta documentation pages returned rate-limit/fetch errors during research, so the official Meta Postman collection was used for the contract.

## Local verification

Validation uses synthetic contacts and repository image fixtures. Meta endpoints are simulated; a real WhatsApp delivery was not attempted.

- WhatsApp services, Enterprise WhatsApp services, webhook jobs/controller, and shared attachments: 463 examples passed, 0 failures.
- Frontend upload helpers and mixin: 35 tests passed.
- Focused checks: 7 passed, covering actual WebP-to-PNG bytes, multipart authentication and media IDs, original-file preservation, failed-upload status, image size rejection, failed incoming lookup, connection reset and recovery, duplicate suppression, and lock ownership against real isolated Redis.
- Ruby lint: all 11 changed Ruby files passed.
- Existing affected specs were updated for direct-upload payloads and the intentional change from silently accepting a missing image to raising a retryable failure. No new repository spec files were added.

Checks ran against isolated PostgreSQL and Redis instances. Dependency manifests and lockfiles were unchanged.

## Applying to production

1. Confirm the currently deployed Chatwoot version/source and review differences before upgrading.
2. Back up the database, stored attachments, and deployment configuration before release.
3. In Dokploy, build a new image from this repository's `develop` branch, with Dockerfile `docker/Dockerfile` and the repository root as build context. Merely restarting an official `chatwoot/chatwoot` image will not include these fixes.
4. Configure both the web application and Sidekiq worker to use that same newly built image. Keep their existing database, Redis, storage, and WhatsApp configuration.
5. If `ACTIVE_STORAGE_SERVICE=local`, the web and worker containers must share the same persistent `/app/storage` volume. For object storage, both must have working access to the same bucket. The worker now reads attachment bytes directly for outgoing uploads.
6. Verify with a consenting test contact: send a small JPEG and PNG, receive a customer image, confirm thumbnails and download, and confirm actual WhatsApp delivery status. Check a supported WebP upload if your selected upload UI permits it. Confirm a document and voice note still work.
7. If incoming downloads still fail, inspect the worker's access to `graph.facebook.com` and the media-download host returned by Meta, together with Sidekiq retries and storage errors. Do not expose bearer tokens or signed media URLs in shared logs.

For Dokploy/Coolify/Compose, the key requirement is building and selecting the patched image for both web and worker services; no platform-specific deployment was changed here. Keep the previous image available for rollback.

This prevents the identified failures for future attempts. It does not automatically restore images already saved without attachments, recover jobs already discarded before this fix, repair expired authorization, or correct persistent network/storage failures. Old one-day locks from the previous implementation may remain until expiry; do not clear Redis broadly. Recovery of historical images requires inspection of the affected messages and available media/webhook records on the server.
