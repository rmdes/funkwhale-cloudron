# Funkwhale for Cloudron

[![Cloudron](https://img.shields.io/badge/Cloudron-package-blue)](https://cloudron.io)
[![Funkwhale](https://img.shields.io/badge/Funkwhale-2.0.0--rc13-purple)](https://funkwhale.audio)

[Cloudron](https://cloudron.io) package for [Funkwhale](https://funkwhale.audio) v2 — a self-hosted, federated music streaming platform.

Funkwhale lets you listen, upload, and share music and audio within a decentralized network using ActivityPub federation. It supports the Subsonic API for compatibility with existing music apps.

## Overview

This package runs Funkwhale v2 inside a single Cloudron container with four processes:

| Process | Role | Details |
|---------|------|---------|
| **nginx** | Reverse proxy | Routes requests to the API, serves frontend SPA and static/media files |
| **gunicorn** | ASGI web server | Django REST API with Uvicorn workers on port 5000 |
| **celery worker** | Task processor | Background jobs (imports, federation, transcoding) |
| **celery beat** | Task scheduler | Periodic tasks (federation polling, cleanup) |

### Cloudron Addons Used

| Addon | Purpose |
|-------|---------|
| **PostgreSQL** | Primary database for users, music metadata, playlists |
| **Redis** | Cache and Celery message broker |
| **Local Storage** | Persistent storage for media, music files, and Django static files |
| **Sendmail** | Outgoing email (password resets, notifications) |

## Installation

### Prerequisites

- A [Cloudron](https://cloudron.io) instance (min box version 8.1.0)
- The [Cloudron CLI](https://docs.cloudron.io/packaging/cli/) installed on your local machine

### Build and Install

```bash
git clone git@github.com:rmdes/funkwhale-cloudron.git
cd funkwhale-cloudron

# Build the Docker image
cloudron build

# Install on your Cloudron (replace 'fw' with your desired subdomain)
cloudron install --location fw
```

### Create Admin Account

After installation, open a **Web Terminal** for the app from the Cloudron dashboard and run:

```bash
source /app/code/venv/bin/activate
funkwhale-manage createsuperuser
```

Follow the prompts to set your admin username, email, and password.

## Architecture

```
Cloudron (handles TLS, DNS, backups, authentication)
└── Container
    ├── nginx (:8000)           ← Cloudron routes traffic here
    │   ├── /                   → Frontend SPA (Vue.js)
    │   ├── /api/               → gunicorn (:5000)
    │   ├── /federation/        → gunicorn (:5000)
    │   ├── /rest/              → gunicorn (:5000) [Subsonic API]
    │   ├── /.well-known/       → gunicorn (:5000) [WebFinger/nodeinfo]
    │   ├── /media/             → /app/data/media/ (direct serve)
    │   ├── /_protected/media/  → /app/data/media/ (auth via X-Accel-Redirect)
    │   ├── /_protected/music/  → /app/data/music/ (auth via X-Accel-Redirect)
    │   └── /staticfiles/       → /app/data/static/
    ├── gunicorn (:5000)        ← Django ASGI app (main process, PID 1)
    ├── celery worker           ← Background task processing
    └── celery beat             ← Periodic task scheduling
```

### Directory Layout

```
/app/code/              # Immutable application code (rebuilt on updates)
├── api/                # Django REST API (Python)
├── front/dist/         # Vue.js frontend (pre-built static files)
└── venv/               # Python virtual environment

/app/data/              # Persistent data (survives updates, backed up by Cloudron)
├── config/.secret_key  # Django secret key (auto-generated on first run)
├── media/              # User uploads (avatars, playlist covers, attachments)
├── music/              # Music library files
└── static/             # Django collectstatic output

/app/pkg/               # Package scripts
├── start.sh            # Startup script
└── nginx.conf          # nginx config template
```

### How It Works

On every container start, `start.sh`:

1. Creates persistent directories under `/app/data/` if they don't exist
2. Generates a Django secret key on first run (persisted in `/app/data/config/.secret_key`)
3. Maps Cloudron addon environment variables (`CLOUDRON_*`) to Funkwhale equivalents (`DATABASE_URL`, `CACHE_URL`, `FUNKWHALE_HOSTNAME`, etc.)
4. Runs `collectstatic` and database migrations (idempotent)
5. Substitutes the app domain into the nginx config
6. Starts nginx, celery worker, and celery beat as background processes
7. Starts gunicorn as PID 1 (Cloudron monitors this for health)

### Environment Variable Mapping

| Cloudron Addon | Funkwhale Variable |
|----------------|-------------------|
| `CLOUDRON_APP_DOMAIN` | `FUNKWHALE_HOSTNAME` |
| `CLOUDRON_POSTGRESQL_*` | `DATABASE_URL` (constructed as connection string) |
| `CLOUDRON_REDIS_*` | `CACHE_URL`, `CELERY_BROKER_URL` |
| `CLOUDRON_MAIL_SMTP_*` | `EMAIL_CONFIG` |
| `CLOUDRON_MAIL_FROM` | `DEFAULT_FROM_EMAIL` |

## Data Migration

If you have an existing Funkwhale instance and want to migrate to Cloudron, follow these steps.

### 1. Export from your existing instance

```bash
# Database dump (on your existing server)
sudo -u postgres pg_dump -Fc funkwhale > funkwhale.dump

# Copy media and music files
tar czf funkwhale-media.tar.gz -C /srv/funkwhale/data media/
tar czf funkwhale-music.tar.gz -C /srv/funkwhale/data music/
```

### 2. Transfer files to Cloudron

Copy `funkwhale.dump`, `funkwhale-media.tar.gz`, and `funkwhale-music.tar.gz` to a location accessible from the Cloudron app's terminal (e.g., `/tmp/` inside the container).

### 3. Import into Cloudron

Open a **Web Terminal** for the Funkwhale app in the Cloudron dashboard:

```bash
# Stop background services first
pkill -f celery || true

# Restore the database
pg_restore -h "${CLOUDRON_POSTGRESQL_HOST}" \
  -p "${CLOUDRON_POSTGRESQL_PORT}" \
  -U "${CLOUDRON_POSTGRESQL_USERNAME}" \
  -d "${CLOUDRON_POSTGRESQL_DATABASE}" \
  --clean --if-exists /tmp/funkwhale.dump

# Extract media and music
tar xzf /tmp/funkwhale-media.tar.gz -C /app/data/
tar xzf /tmp/funkwhale-music.tar.gz -C /app/data/

# Fix permissions
chown -R cloudron:cloudron /app/data

# Run migrations in case versions differ
source /app/code/venv/bin/activate
funkwhale-manage migrate --noinput
```

Restart the app from the Cloudron dashboard after the import.

### 4. Verify

- Existing users can log in
- Music library appears intact
- Media files (avatars, covers) display correctly
- Playlists, favorites, and listening history are preserved

## Upgrading Funkwhale

To update to a new Funkwhale version:

1. Edit the `FUNKWHALE_VERSION` ARG in the `Dockerfile`
2. Update `upstreamVersion` in `CloudronManifest.json`
3. Bump `version` in `CloudronManifest.json`
4. Add a changelog entry in `CHANGELOG.md`
5. Rebuild and update:

```bash
cloudron build
cloudron update --app fw
```

Database migrations run automatically on startup.

## Features

- **Music Streaming** — Upload, organize, and stream your music library
- **Federation** — Share and discover music across Funkwhale instances via ActivityPub
- **Subsonic API** — Use existing Subsonic-compatible apps (DSub, Ultrasonic, Clementine, etc.)
- **Podcasts** — Subscribe to and manage podcast feeds
- **Channels** — Publish audio content with RSS feeds
- **Playlists & Radio** — Create playlists, favorites, and auto-generated radio stations

## Troubleshooting

### Check service status

From the Cloudron web terminal:

```bash
# Check which processes are running
ps aux

# Check nginx logs
cat /var/log/nginx/error.log

# Check Funkwhale API logs (gunicorn output goes to Cloudron logs)
# View from Cloudron dashboard → App → Logs
```

### Health check fails

The health check endpoint is `/api/v2/instance/nodeinfo/2.0/`. If the app shows as unhealthy:

1. Check that gunicorn is running: `ps aux | grep gunicorn`
2. Check that nginx is running: `ps aux | grep nginx`
3. Test the API directly: `curl -s http://localhost:5000/api/v2/instance/nodeinfo/2.0/`
4. Test through nginx: `curl -s http://localhost:8000/api/v2/instance/nodeinfo/2.0/`

### Music uploads fail

Large file uploads (up to 2GB) are supported. If uploads fail:

1. Check available disk space: `df -h /app/data/`
2. Verify permissions: `ls -la /app/data/music/`
3. Check nginx body size limit is applied: `grep client_max_body_size /run/nginx.conf`

### Federation not working

Ensure your Cloudron domain has proper DNS and that `/.well-known/` endpoints are accessible:

```bash
curl -s https://your-domain/.well-known/nodeinfo
curl -s https://your-domain/.well-known/webfinger?resource=acct:user@your-domain
```

## Development

### Building locally with Docker

```bash
docker build -t funkwhale-cloudron .
docker run --rm -it funkwhale-cloudron /bin/bash
# Inspect: venv exists, funkwhale-manage available, front/dist has files
```

### Project structure

```
funkwhale-cloudron/
├── CloudronManifest.json   # Cloudron app metadata, addons, health check
├── Dockerfile              # Build: cloudron/base + Funkwhale artifacts + venv
├── start.sh                # Startup: env mapping, migrations, 4-process launch
├── nginx.conf              # Internal routing (no TLS — Cloudron handles that)
├── DESCRIPTION.md          # App store listing
├── POSTINSTALL.md          # Post-install instructions
├── CHANGELOG.md            # Version history
└── logo.png                # App icon
```

## Roadmap

- [ ] LDAP/SSO integration (Funkwhale has native LDAP support)
- [ ] OIDC single sign-on via Cloudron
- [ ] Dynamic worker count based on container memory
- [ ] Stable release packaging (currently tracking v2 release candidates)

## References

- [Funkwhale Documentation](https://docs.funkwhale.audio)
- [Funkwhale Source Code](https://dev.funkwhale.audio/funkwhale/funkwhale)
- [Cloudron Packaging Guide](https://docs.cloudron.io/packaging/)
- [Cloudron CLI Reference](https://docs.cloudron.io/packaging/cli/)

## License

MIT
