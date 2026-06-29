<!-- SPDX-FileCopyrightText: 2026 VisorCraft LLC -->
<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Roamarr - container image

This repository builds a ready-to-run container image for
[**Roamarr**](https://github.com/visorcraft/roamarr), the self-hosted
TripIt-style travel organizer.

The `Dockerfile` is a multi-stage build that clones Roamarr and its persistence
layer — MongrelDB and MongrelDB Kit — from GitHub (latest `master` by default),
builds the native storage addon and the Kit, compiles the SvelteKit production
bundle, and ships it on a slim Node.js runtime with only production
dependencies. The MongrelDB database directory and receipt attachments live on a
single mounted volume so a container can be recreated or upgraded without data
loss.

> The native addon is built `--release`. A debug build is several times slower;
> the Dockerfile never uses `build:debug`.

## Quick start

```bash
# 1. Build the image from this repo
podman build -t roamarr .
# or: docker build -t roamarr .

# 2. Create a persistent volume and run
podman volume create roamarr-data
podman run -d --name roamarr \
  -p 3000:3000 \
  -v roamarr-data:/data \
  -e ROAMARR_SECRET="$(openssl rand -base64 32)" \
  --restart unless-stopped \
  roamarr
```

Open `http://localhost:3000/setup` on first boot to create the admin account.

## docker-compose

A ready-to-use compose file is included as `docker-compose.yml`:

```bash
openssl rand -base64 32   # use this output for ROAMARR_SECRET below
docker compose up -d
```

See [`docker-compose.yml`](docker-compose.yml).

## Configuration

Roamarr is configured almost entirely through environment variables at boot and
through the in-app Settings area afterwards.

| Variable | Required | Default | Notes |
| -------- | -------- | ------- | ----- |
| `ROAMARR_SECRET` | **yes** | none | Base64 32-byte key used for at-rest encryption. The app refuses to boot without it. Generate with `openssl rand -base64 32`. |
| `MONGREL_DATABASE_PATH` | no | `/data/roamarr.kitdb` | MongrelDB Kit data directory. Receipt attachments are stored beside it under `/data/attachments/`. |
| `PORT` | no | `3000` | Port the adapter-node server listens on. |
| `ORIGIN` | no | none | Public origin (e.g. `https://roamarr.example.com`) for correct cookies/redirects behind a reverse proxy. |

### Volumes

| Container path | Purpose |
| -------------- | ------- |
| `/data` | MongrelDB database directory + receipt attachments. **Mount this as a named volume or host bind to persist data across upgrades.** |

### Ports

| Port | Purpose |
| ---- | ------- |
| `3000` | Roamarr web UI / HTTP API. |

## Building a specific release

The `ROAMARR_REF` build arg selects the git ref (branch, tag, or commit) of
`visorcraft/roamarr` to build:

```bash
# Latest master (default)
podman build -t roamarr .

# Pinned release tag
podman build --build-arg ROAMARR_REF=v0.3.7 -t roamarr:0.3.7 .
```

`NODE_VERSION` (default `22`) selects the Node.js major for both build and
runtime stages. Roamarr requires Node.js >= 22.12.

## Upgrading

The database lives on the `/data` volume, so upgrades are safe:

```bash
podman pull <your-registry>/roamarr:latest   # or: podman build -t roamarr .
podman stop roamarr
podman rm roamarr
# Recreate with the SAME -v roamarr-data:/data as before
podman run -d --name roamarr -p 3000:3000 -v roamarr-data:/data \
  -e ROAMARR_SECRET='<same secret as before>' --restart unless-stopped roamarr
```

Roamarr applies database migrations automatically on boot, before the scheduler
starts. **Always back up the `/data` volume before upgrading.**

## Architecture

This image is built on Debian Bookworm (`node:22-bookworm-slim` runtime). The
build stage installs a Rust toolchain and compiles the native MongrelDB storage
addon (`mongreldb`, a NAPI `.node`) in `--release` mode alongside MongrelDB Kit;
the built artifacts are staged into the slim runtime. Roamarr, MongrelDB, and
MongrelDB Kit are cloned in a sibling layout (selectable per repo via the
`ROAMARR_REF`, `MONGRELDB_REF`, and `MONGRELDB_KIT_REF` build args) so Roamarr's
local `file:` dependencies resolve.

## Support

- Roamarr application: [visorcraft/roamarr](https://github.com/visorcraft/roamarr)
- Security policy: [docs/SECURITY.md](https://github.com/visorcraft/roamarr/blob/master/docs/SECURITY.md)
- License: Roamarr is GPL-3.0-only. See the
  [application LICENSE](https://github.com/visorcraft/roamarr/blob/master/LICENSE).
