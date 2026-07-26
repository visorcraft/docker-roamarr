<!-- SPDX-FileCopyrightText: 2026 VisorCraft LLC -->
<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Roamarr - container image

This repository builds a ready-to-run container image for
[**Roamarr**](https://github.com/visorcraft/roamarr), the self-hosted
Trip Tracker-style travel organizer.

The `Dockerfile` is a two-stage build: it clones `visorcraft/roamarr` (the
`ROAMARR_REF` build arg, pinned to a release tag by default), runs `npm ci` to
fetch Roamarr's published dependencies — MongrelDB Kit and the prebuilt
`mongreldb` NAPI storage addon — builds the SvelteKit (adapter-node)
production bundle, then copies it onto a slim Node.js runtime with only
production dependencies. The MongrelDB database and receipt attachments live on
a single mounted volume so a container can be recreated or upgraded without data
loss.

## Quick start

```bash
# 1. Build the image from this repo
make build
# or: podman build --format docker -t roamarr .
# or: docker build -t roamarr .

# 2. Create a persistent volume and run
podman volume create roamarr-data
podman volume create roamarr-secrets
podman run -d --name roamarr \
  -p 3000:3000 \
  -v roamarr-data:/data \
  -v roamarr-secrets:/run/roamarr-secrets \
  --restart unless-stopped \
  roamarr
```

> With podman, build with `--format docker` (or `make build`) so the image's
> `HEALTHCHECK` is honored — podman's default OCI image format silently drops it.
> `docker build` always honors `HEALTHCHECK` and needs no flag.

Open `http://localhost:3000/setup` on first boot to create the admin account.

## docker-compose

A ready-to-use compose file is included as `docker-compose.yml`. No secret
generation is required:

```bash
docker compose up -d
```

See [`docker-compose.yml`](docker-compose.yml).

## Configuration

Roamarr is configured almost entirely through environment variables at boot and
through the in-app Settings area afterwards.

| Variable | Required | Default | Notes |
| -------- | -------- | ------- | ----- |
| `ROAMARR_SECRET` | no | generated once | Base64 32-byte key used for at-rest encryption. Stored mode `0600` in the separate secret volume. |
| `DATABASE_USER` | no | generated once | MongrelDB administrator username. Stored with the generated secret. |
| `DATABASE_PASS` | no | generated once | MongrelDB administrator password. Stored with the generated secret. |
| `DATABASE_PATH` | no | `/data/roamarr-db` | MongrelDB Kit data directory or file path. Receipt attachments are stored beside it under `/data/attachments/`. |
| `PORT` | no | `3000` | Port the adapter-node server listens on. |
| `ORIGIN` | no | none | Public origin (e.g. `https://roamarr.example.com`) for correct cookies/redirects behind a reverse proxy. |

### Volumes

| Container path | Purpose |
| -------------- | ------- |
| `/data` | MongrelDB database directory + receipt attachments. **Mount this as a named volume or host bind to persist data across upgrades.** |
| `/run/roamarr-secrets` | Generated encryption key and database credentials. Mount and back up separately. |

The container generates `ROAMARR_SECRET`, `DATABASE_USER`, and `DATABASE_PASS`
on first boot when omitted. It stores them in `/run/roamarr-secrets/credentials.json`
with mode `0600` and reuses them on every restart. Back up this volume separately.
Explicit environment values override generated values and are persisted for
later restarts. Never change these values after the database is created.

### Ports

| Port | Purpose |
| ---- | ------- |
| `3000` | Roamarr web UI / HTTP API. |

## Building a specific release

The `ROAMARR_REF` build arg selects the git ref (branch, tag, or commit) of
`visorcraft/roamarr` to build:

```bash
# Default build (Roamarr v0.37.18, the release this image tracks)
make build
# or: podman build --format docker -t roamarr .

# Override with a different ref (branch, tag, or commit)
make build TAG=edge REF=master
# or: podman build --format docker --build-arg ROAMARR_REF=master -t roamarr:edge .
```

`NODE_VERSION` (default `24`) selects the Node.js major for both build and
runtime stages. Roamarr requires Node.js >= 24.

## Upgrading

The database lives on the `/data` volume, so upgrades are safe:

```bash
podman pull <your-registry>/roamarr:latest   # or: make build
podman stop roamarr
podman rm roamarr
# Recreate with the SAME data and secret volumes as before
podman run -d --name roamarr -p 3000:3000 -v roamarr-data:/data \
  -v roamarr-secrets:/run/roamarr-secrets \
  --restart unless-stopped roamarr
```

Roamarr applies database migrations automatically on boot, before the scheduler
starts. **Always back up the `/data` volume before upgrading.**

## Architecture

Two-stage build on Debian Bookworm. The **build** stage (`node:24-bookworm`)
clones `visorcraft/roamarr` at `ROAMARR_REF` and runs `npm ci && npm run build`
(Vite/SvelteKit adapter-node); Roamarr pulls MongrelDB Kit and the prebuilt
`mongreldb` NAPI addon from npm, so no Rust toolchain is needed in this image.
The **runtime** stage (`node:24-bookworm-slim`) copies `build/`, the production
`node_modules`, and the package files, and serves them with `node build`. State
persists on the `/data` volume. The image carries a `HEALTHCHECK` (build with
`--format docker` / `make build` so podman keeps it).

## Support

- Roamarr application: [visorcraft/roamarr](https://github.com/visorcraft/roamarr)
- Security policy: [docs/SECURITY.md](https://github.com/visorcraft/roamarr/blob/master/docs/SECURITY.md)
- License: Roamarr is GPL-3.0-only. See the
  [application LICENSE](https://github.com/visorcraft/roamarr/blob/master/LICENSE).
