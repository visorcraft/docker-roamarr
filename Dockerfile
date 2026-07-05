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
#                 Default "master".
#   NODE_VERSION  Node.js major to build and run on. Default 22 (Roamarr requires
#                 Node.js >= 22.12).
#
# Build:
#   podman build -t roamarr .
#   docker build  -t roamarr .
#
# Pin a release:
#   podman build --build-arg ROAMARR_REF=v0.10.1 -t roamarr:0.10.1 .
#
# Run:
#   podman run -d --name roamarr -p 3000:3000 \
#     -v roamarr-data:/data \
#     -e ROAMARR_SECRET="$(openssl rand -base64 32)" \
#     roamarr
#
# See README.md for docker-compose and full configuration.

ARG NODE_VERSION=22
ARG ROAMARR_REF=master

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
    && npm prune --omit=dev --no-audit --no-fund || true

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

RUN mkdir -p /data
VOLUME /data
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD node -e "fetch('http://127.0.0.1:'+process.env.PORT+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "build"]
