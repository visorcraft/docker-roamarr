# syntax=docker/dockerfile:1
# SPDX-FileCopyrightText: 2026 VisorCraft LLC
# SPDX-License-Identifier: GPL-3.0-only
#
# Roamarr container image.
#
# Roamarr's persistence layer is MongrelDB Kit, a TypeScript layer over a native
# Rust storage engine (the `mongreldb` NAPI addon). Roamarr depends on both via
# local `file:` paths, so this image clones all three public repos in a sibling
# layout, builds the native addon and the Kit, then builds the SvelteKit
# (adapter-node) bundle and ships it on a slim runtime image.
#
#   /src/mongreldb       (engine + native addon)
#   /src/mongreldb_kit   (Kit: schema/query/migrations over the addon)
#   /src/roamarr         (the app; file: deps resolve to the two siblings)
#
# The native addon is built **--release**. A debug build is ~3-4x slower at
# runtime (notably on bulk inserts/deletes), so never substitute `build:debug`.
#
# Build args:
#   ROAMARR_REF / MONGRELDB_REF / MONGRELDB_KIT_REF
#                 git ref (branch, tag, or commit) of each repo. Default "master".
#   NODE_VERSION  Node.js major to build and run on. Default 22 (Roamarr requires
#                 Node.js >= 22.12).
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
ARG MONGRELDB_REF=master
ARG MONGRELDB_KIT_REF=master

# ---- build stage: fetch sources and build addon + Kit + app -----------------
FROM node:${NODE_VERSION}-bookworm AS build
ARG ROAMARR_REF
ARG MONGRELDB_REF
ARG MONGRELDB_KIT_REF

# git + a Rust toolchain (for the native addon) + a C toolchain for native crate
# deps. rustup honours any rust-toolchain.toml in the engine repo.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git ca-certificates curl build-essential pkg-config protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /src
# Sibling layout so Roamarr's file: deps (../mongreldb..., ../mongreldb_kit...)
# and each package's own node_modules resolve at build and run time.
RUN git clone --depth 1 --branch "${MONGRELDB_REF}"     https://github.com/visorcraft/MongrelDB.git     mongreldb \
    && git clone --depth 1 --branch "${MONGRELDB_KIT_REF}" https://github.com/visorcraft/MongrelDB-Kit.git mongreldb_kit \
    && git clone --depth 1 --branch "${ROAMARR_REF}"     https://github.com/visorcraft/roamarr.git       roamarr

# 1) Native addon — RELEASE build (`npm run build` === `napi build --release`).
WORKDIR /src/mongreldb/crates/mongreldb-node
RUN npm install --no-audit --no-fund --no-save \
    && npm run build

# 2) Kit — link the native peer dependency, then compile TypeScript to dist/.
WORKDIR /src/mongreldb_kit/packages/kit
RUN npm install --no-audit --no-fund --legacy-peer-deps \
    && ln -sfn ../../../../mongreldb/crates/mongreldb-node node_modules/mongreldb \
    && npm run build

# 3) Roamarr — file: deps resolve to the sibling builds via npm's symlinks.
WORKDIR /src/roamarr
RUN npm ci --no-audit --no-fund \
    && npm run build

# Stage a minimal runtime tree, preserving the sibling layout the symlinks need.
# Only ship the addon's published artifacts (not target/ or its devDeps), the
# Kit's dist + prod node_modules, and the app's build + prod node_modules.
RUN set -eux; \
    mkdir -p /out/mongreldb/crates/mongreldb-node \
             /out/mongreldb_kit/packages/kit \
             /out/roamarr; \
    cd /src/mongreldb/crates/mongreldb-node; \
    cp index.js native.js index.d.ts native.d.ts package.json mongreldb.*.node \
       /out/mongreldb/crates/mongreldb-node/; \
    cd /src/mongreldb_kit/packages/kit; \
    npm prune --omit=dev --no-audit --no-fund || true; \
    cp -a dist package.json node_modules /out/mongreldb_kit/packages/kit/; \
    ln -sfn ../../../../mongreldb/crates/mongreldb-node \
       /out/mongreldb_kit/packages/kit/node_modules/mongreldb; \
    cd /src/roamarr; \
    npm prune --omit=dev --no-audit --no-fund || true; \
    cp -a build node_modules package.json package-lock.json /out/roamarr/

# ---- runtime stage: slim image with the built app + its native deps ----------
FROM node:${NODE_VERSION}-bookworm-slim AS runtime
LABEL org.opencontainers.image.title="Roamarr" \
      org.opencontainers.image.source="https://github.com/visorcraft/roamarr" \
      org.opencontainers.image.licenses="GPL-3.0-only"

ENV NODE_ENV=production \
    PORT=3000 \
    MONGREL_DATABASE_PATH=/data/roamarr.kitdb

WORKDIR /src/roamarr
COPY --from=build /out/ /src/

RUN mkdir -p /data
VOLUME /data
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD node -e "fetch('http://127.0.0.1:'+process.env.PORT+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "build"]
