# syntax=docker/dockerfile:1
# SPDX-FileCopyrightText: 2026 VisorCraft LLC
# SPDX-License-Identifier: GPL-3.0-only
#
# Roamarr container image.
#
# Roamarr's persistence layer is MongrelDB Kit, a TypeScript layer over a native
# Rust storage engine (the `mongreldb` NAPI addon). Roamarr consumes both via
# published npm packages, so this image clones Roamarr and runs `npm ci` to fetch
# the matching addon/Kit builds, then builds the SvelteKit (adapter-node) bundle
# and ships it on a slim runtime image.
#
# Build args:
#   ROAMARR_REF   git ref (branch, tag, or commit) of visorcraft/roamarr.
#                 Default "v0.37.20" (the Roamarr release this image tracks).
#   NODE_VERSION  Node.js major to build and run on. Default 24 (Roamarr requires
#                 Node.js >= 24).
#
# Build (use the docker image format so the HEALTHCHECK is honored; podman's
# default OCI format drops it):
#   make build                              # or:
#   podman build --format docker -t roamarr .
#   docker build -t roamarr .
#
# Build a different ref:
#   make build TAG=edge REF=master          # or:
#   podman build --format docker --build-arg ROAMARR_REF=master -t roamarr:edge .
#
# Run (secrets are generated once inside the persistent volume):
#   podman run -d --name roamarr -p 3000:3000 \
#     -v roamarr-data:/data \
#     -v roamarr-secrets:/run/roamarr-secrets \
#     roamarr
#
# See README.md for docker-compose and full configuration.

ARG NODE_VERSION=24
ARG ROAMARR_REF=v0.37.20

# ---- build stage: fetch Roamarr and build the production bundle ------------
FROM node:${NODE_VERSION}-bookworm AS build
ARG ROAMARR_REF

RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone --depth 1 --branch "${ROAMARR_REF}" https://github.com/visorcraft/roamarr.git

WORKDIR /src/roamarr
RUN npm ci --no-audit --no-fund \
    && npm run build \
    && (npm prune --omit=dev --no-audit --no-fund || true)

# ---- runtime stage: slim image with the built app ---------------------------
FROM node:${NODE_VERSION}-bookworm-slim AS runtime
LABEL org.opencontainers.image.title="Roamarr" \
      org.opencontainers.image.source="https://github.com/visorcraft/roamarr" \
      org.opencontainers.image.licenses="GPL-3.0-only"

ENV NODE_ENV=production \
    PORT=3000 \
    DATABASE_PATH=/data/roamarr-db

WORKDIR /src/roamarr
COPY --from=build /src/roamarr/build /src/roamarr/build
COPY --from=build /src/roamarr/node_modules /src/roamarr/node_modules
COPY --from=build /src/roamarr/package.json /src/roamarr/package.json
COPY --from=build /src/roamarr/package-lock.json /src/roamarr/package-lock.json
COPY docker-entrypoint.mjs /src/roamarr/docker-entrypoint.mjs

RUN mkdir -p /data /run/roamarr-secrets
VOLUME ["/data", "/run/roamarr-secrets"]
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD node -e "fetch('http://127.0.0.1:'+process.env.PORT+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "docker-entrypoint.mjs"]
