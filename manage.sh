#!/bin/bash
set -eu

# Wrapper to run funkwhale-manage commands with the correct environment.
# Used by Cloudron scheduler tasks and can be called manually.
#
# Usage: /app/pkg/manage.sh <command> [args...]

# Map CLOUDRON_ addons to Funkwhale env vars
DJANGO_SECRET_KEY=$(cat /app/data/config/.secret_key)
export FUNKWHALE_HOSTNAME="${CLOUDRON_APP_DOMAIN}"
export FUNKWHALE_PROTOCOL="https"
export DJANGO_SECRET_KEY
export DATABASE_URL="postgresql://${CLOUDRON_POSTGRESQL_USERNAME}:${CLOUDRON_POSTGRESQL_PASSWORD}@${CLOUDRON_POSTGRESQL_HOST}:${CLOUDRON_POSTGRESQL_PORT}/${CLOUDRON_POSTGRESQL_DATABASE}"
export CACHE_URL="redis://:${CLOUDRON_REDIS_PASSWORD}@${CLOUDRON_REDIS_HOST}:${CLOUDRON_REDIS_PORT}/0"
export CELERY_BROKER_URL="${CACHE_URL}"
export MEDIA_ROOT="/app/data/media"
export STATIC_ROOT="/app/data/static"
export MUSIC_DIRECTORY_PATH="/app/data/music"
export MUSIC_DIRECTORY_SERVE_PATH="/app/data/music"
export FUNKWHALE_FRONTEND_PATH="/app/code/front/dist"
export FUNKWHALE_SPA_HTML_ROOT="/app/code/front/dist/index.html"
export DJANGO_SETTINGS_MODULE="config.settings.production"
export REVERSE_PROXY_TYPE="nginx"
export EMAIL_CONFIG="smtp://${CLOUDRON_MAIL_SMTP_USERNAME}:${CLOUDRON_MAIL_SMTP_PASSWORD}@${CLOUDRON_MAIL_SMTP_SERVER}:${CLOUDRON_MAIL_SMTP_PORT}"
export DEFAULT_FROM_EMAIL="${CLOUDRON_MAIL_FROM}"

source /app/code/venv/bin/activate

exec gosu cloudron:cloudron funkwhale-manage "$@"
