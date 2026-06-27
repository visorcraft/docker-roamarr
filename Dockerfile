# syntax=docker/dockerfile:1
# SPDX-FileCopyrightText: 2026 VisorCraft LLC
# SPDX-License-Identifier: GPL-3.0-only
#
# Roamarr container image.
#
# Multi-stage build that fetches the Roamarr source from GitHub and builds the
# production SvelteKit (adapter-node) bundle, then ships it on a slim runtime
# image with only production dependencies.
#
# Build args:
#   ROAMARR_REF   git ref (branch, tag, or commit) of visorcraft/roamarr to build.
#                 Defaults to "master".
#   NODE_VERSION  Node.js major to build and run on. Defaults to 22 (Roamarr
#                 requires Node.js >= 22.12).
#
# Build:
#   podman build -t roamarr .
#   docker build  -t roamarr .
#
# Pin a release:
#   podman build --build-arg ROAMARR_REF=v0.3.2 -t roamarr:0.3.2 .
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

# ---- build stage: fetch source and build the production app ----------------
FROM node:${NODE_VERSION}-bookworm AS build
ARG ROAMARR_REF
RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
# Roamarr must be public for an unauthenticated clone at build time.
RUN git clone --depth 1 --branch "${ROAMARR_REF}" https://github.com/visorcraft/roamarr.git .

# Full dependency install (incl. devDependencies) is required to run the
# SvelteKit/Vite production build.
RUN npm ci --no-audit --no-fund
RUN npm run build

# Reinstall only production dependencies for the runtime image. Native modules
# (better-sqlite3) are compiled here in the build stage where toolchain is
# available, then copied whole into the slim runtime.
RUN npm ci --omit=dev --no-audit --no-fund && npm cache clean --force

# ---- runtime stage: slim image with only production deps and built app ------
FROM node:${NODE_VERSION}-bookworm-slim AS runtime
LABEL org.opencontainers.image.title="Roamarr" \
      org.opencontainers.image.source="https://github.com/visorcraft/roamarr" \
      org.opencontainers.image.licenses="GPL-3.0-only"

ENV NODE_ENV=production \
    PORT=3000 \
    DATABASE_PATH=/data/roamarr.db

WORKDIR /app
COPY --from=build /app/package.json /app/package-lock.json ./
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/build ./build
COPY --from=build /app/drizzle ./drizzle

RUN mkdir -p /data
VOLUME /data
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD node -e "fetch('http://127.0.0.1:'+process.env.PORT+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "build"]
