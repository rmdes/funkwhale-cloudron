#!/bin/bash
set -eu

echo "=> Starting Funkwhale for Cloudron"

# =============================================================================
# Data directory setup (runs every start, idempotent)
# =============================================================================
mkdir -p /app/data/media /app/data/music /app/data/static /app/data/config
mkdir -p /run/client_body /run/proxy_temp /run/fastcgi_temp /run/scgi_temp /run/uwsgi_temp

# =============================================================================
# First-run: generate Django secret key (persisted across restarts/updates)
# =============================================================================
if [[ ! -f /app/data/config/.secret_key ]]; then
    echo "=> First run detected, generating secret key..."
    python3 -c "import secrets; print(secrets.token_hex(32))" > /app/data/config/.secret_key
fi

DJANGO_SECRET_KEY=$(cat /app/data/config/.secret_key)

# =============================================================================
# Environment variables: map CLOUDRON_ addons → Funkwhale config
# =============================================================================

# Core
export FUNKWHALE_HOSTNAME="${CLOUDRON_APP_DOMAIN}"
export FUNKWHALE_PROTOCOL="https"
export DJANGO_SECRET_KEY

# Database (Cloudron PostgreSQL addon)
export DATABASE_URL="postgresql://${CLOUDRON_POSTGRESQL_USERNAME}:${CLOUDRON_POSTGRESQL_PASSWORD}@${CLOUDRON_POSTGRESQL_HOST}:${CLOUDRON_POSTGRESQL_PORT}/${CLOUDRON_POSTGRESQL_DATABASE}"

# Cache & Celery broker (Cloudron Redis addon)
export CACHE_URL="redis://:${CLOUDRON_REDIS_PASSWORD}@${CLOUDRON_REDIS_HOST}:${CLOUDRON_REDIS_PORT}/0"
export CELERY_BROKER_URL="${CACHE_URL}"

# File paths (all under /app/data for persistence)
export MEDIA_ROOT="/app/data/media"
export STATIC_ROOT="/app/data/static"
export MUSIC_DIRECTORY_PATH="/app/data/music"
export MUSIC_DIRECTORY_SERVE_PATH="/app/data/music"

# Frontend (immutable, in /app/code)
export FUNKWHALE_FRONTEND_PATH="/app/code/front/dist"
export FUNKWHALE_SPA_HTML_ROOT="/app/code/front/dist/index.html"

# Django
export DJANGO_SETTINGS_MODULE="config.settings.production"
export REVERSE_PROXY_TYPE="nginx"
export FUNKWHALE_API_PORT="5000"

# Email (Cloudron sendmail addon)
export EMAIL_CONFIG="smtp://${CLOUDRON_MAIL_SMTP_USERNAME}:${CLOUDRON_MAIL_SMTP_PASSWORD}@${CLOUDRON_MAIL_SMTP_SERVER}:${CLOUDRON_MAIL_SMTP_PORT}"
export DEFAULT_FROM_EMAIL="${CLOUDRON_MAIL_FROM}"

# Workers — keep counts low for container memory budget
# Each gunicorn worker loads the full Django app (~150MB)
# Each celery worker subprocess does the same
# With 1GB limit: 2 gunicorn + 2 celery + beat + nginx fits comfortably
export FUNKWHALE_WEB_WORKERS="${FUNKWHALE_WEB_WORKERS:-2}"
export CELERYD_CONCURRENCY="${CELERYD_CONCURRENCY:-2}"

# =============================================================================
# Activate Python virtual environment
# =============================================================================
source /app/code/venv/bin/activate

# =============================================================================
# Django setup (idempotent - safe to run every start)
# =============================================================================
echo "=> Collecting static files..."
funkwhale-manage collectstatic --noinput

echo "=> Running database migrations..."
funkwhale-manage migrate --noinput

# =============================================================================
# Prepare nginx config (substitute domain)
# =============================================================================
sed "s/##APP_DOMAIN##/${CLOUDRON_APP_DOMAIN}/g" /app/pkg/nginx.conf > /run/nginx.conf

# =============================================================================
# Fix permissions
# =============================================================================
chown -R cloudron:cloudron /app/data

# =============================================================================
# Start services
# =============================================================================

echo "=> Starting nginx..."
nginx -c /run/nginx.conf &

echo "=> Starting celery worker..."
gosu cloudron:cloudron celery \
    --app funkwhale_api.taskapp worker \
    --loglevel INFO \
    --concurrency="${CELERYD_CONCURRENCY}" &

echo "=> Starting celery beat..."
gosu cloudron:cloudron celery \
    --app funkwhale_api.taskapp beat \
    --loglevel INFO \
    --schedule=/app/data/celerybeat-schedule &

echo "=> Starting gunicorn (main process)..."
cd /app/data
exec gosu cloudron:cloudron gunicorn config.asgi:application \
    --workers "${FUNKWHALE_WEB_WORKERS}" \
    --worker-class uvicorn.workers.UvicornWorker \
    --bind 0.0.0.0:"${FUNKWHALE_API_PORT}"
