# syntax=docker/dockerfile:1.7
# Preserve the upstream runtime, dependencies and database entrypoint.
FROM evoapicloud/evolution-api:v2.3.7@sha256:1bd8afc4a6cf48822e6cf02469aeae7bd35a12a6b616eacd1291926307f4d339 AS builder
ADD --checksum=sha256:4aee3973d0cc71e870049c4157642bcb7855050429b3dd455fef29f6c90b9861 https://codeload.github.com/evolution-foundation/evolution-api/tar.gz/cd800f2976e1e5b682fbf86a01ee4d85ae61f370 /tmp/evolution-source.tar.gz
COPY patches/2.3.7-chatwoot-reliability.patch /tmp/reliability.patch
RUN apk add --no-cache patch \
    && mkdir /tmp/source \
    && tar -xzf /tmp/evolution-source.tar.gz -C /tmp/source --strip-components=1 \
    && cd /tmp/source && patch -p1 < /tmp/reliability.patch \
    && cp -R src /evolution/src \
    && cp tsconfig.json tsup.config.ts /evolution/ \
    && cd /evolution && npm run build

FROM evoapicloud/evolution-api:v2.3.7@sha256:1bd8afc4a6cf48822e6cf02469aeae7bd35a12a6b616eacd1291926307f4d339
COPY --from=builder /evolution/dist /evolution/dist
LABEL org.opencontainers.image.description="Evolution 2.3.7 with scoped Chatwoot routing and delivery outcomes" \
      org.opencontainers.image.version="2.3.7-chatwoot.1" \
      org.opencontainers.image.revision="cd800f2976e1e5b682fbf86a01ee4d85ae61f370+chatwoot-reliability"
