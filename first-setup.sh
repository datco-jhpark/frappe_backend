#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"

log() {
  printf '[first-setup] %s\n' "$*"
}

die() {
  printf '[first-setup][error] %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

need_cmd docker

if ! docker compose version >/dev/null 2>&1; then
  die "docker compose is not available. Please install Docker Compose v2 (docker compose)."
fi

cd "$PROJECT_DIR"

# 1) Ensure .env exists
if [[ ! -f .env ]]; then
  if [[ -f example.env ]]; then
    log "Creating .env from example.env"
    cp example.env .env
  else
    die "example.env not found and .env is missing"
  fi
else
  log ".env already exists (skipping create)"
fi

# Helpers to read simple KEY=VALUE from .env
read_env_value() {
  local key="$1"
  local value
  value="$(grep -E "^${key}=" .env 2>/dev/null | head -n 1 | sed -E "s/^${key}=//")"
  printf '%s' "$value"
}

SITE_NAME="${SITE_NAME:-$(read_env_value FRAPPE_SITE_NAME_HEADER)}"
SITE_NAME="${SITE_NAME:-erp.localhost}"

ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"
DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-$(read_env_value DB_PASSWORD)}"
DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-admin}"

HTTP_PUBLISH_PORT="${HTTP_PUBLISH_PORT:-$(read_env_value HTTP_PUBLISH_PORT)}"
HTTP_PUBLISH_PORT="${HTTP_PUBLISH_PORT:-8080}"

log "Using settings:"
log "  PROJECT_DIR=$PROJECT_DIR"
log "  SITE_NAME=$SITE_NAME"
log "  ADMIN_PASSWORD=(hidden)"
log "  DB_ROOT_PASSWORD=(hidden)"
log "  HTTP_PUBLISH_PORT=$HTTP_PUBLISH_PORT"

# 2) Fix WSL Docker credential helper issue if present
DOCKER_CONFIG_DIR="${DOCKER_CONFIG:-$HOME/.docker}"
DOCKER_CONFIG_JSON="$DOCKER_CONFIG_DIR/config.json"

if [[ -f "$DOCKER_CONFIG_JSON" ]] && grep -q '"credsStore"\s*:\s*"desktop\.exe"' "$DOCKER_CONFIG_JSON"; then
  ts="$(date +%Y%m%d%H%M%S)"
  backup="$DOCKER_CONFIG_JSON.bak.$ts"
  log "Detected credsStore=desktop.exe in $DOCKER_CONFIG_JSON (can break pulls in WSL)."
  log "Backing up to $backup and rewriting config.json to '{}'"
  cp "$DOCKER_CONFIG_JSON" "$backup"
  printf '{}' > "$DOCKER_CONFIG_JSON"
else
  log "Docker credsStore fix not needed"
fi

# 3) Pull images & start services
log "Pulling images"
docker compose --project-directory "$PROJECT_DIR" pull

log "Starting containers"
docker compose --project-directory "$PROJECT_DIR" up -d

# 4) Wait a bit for backend container to be ready
log "Waiting for backend container to respond"
for i in {1..60}; do
  if docker compose --project-directory "$PROJECT_DIR" exec -T backend bash -lc 'true' >/dev/null 2>&1; then
    break
  fi
  sleep 2
  if [[ "$i" -eq 60 ]]; then
    die "backend container did not become ready in time"
  fi
done

# 5) Create site if missing
SITE_PATH="/home/frappe/frappe-bench/sites/$SITE_NAME"
if docker compose --project-directory "$PROJECT_DIR" exec -T backend bash -lc "test -d '$SITE_PATH'" >/dev/null 2>&1; then
  log "Site already exists: $SITE_NAME (skipping bench new-site)"
else
  log "Creating site: $SITE_NAME"
  docker compose --project-directory "$PROJECT_DIR" exec -T backend bash -lc \
    "bench new-site '$SITE_NAME' --admin-password '$ADMIN_PASSWORD' --mariadb-root-password '$DB_ROOT_PASSWORD' --install-app erpnext"
fi

# 6) Migrate and enable scheduler
log "Running migrate"
docker compose --project-directory "$PROJECT_DIR" exec -T backend bash -lc "bench --site '$SITE_NAME' migrate"

log "Enabling scheduler"
docker compose --project-directory "$PROJECT_DIR" exec -T backend bash -lc "bench --site '$SITE_NAME' enable-scheduler"

# 7) Quick HTTP check
log "Checking HTTP response on http://localhost:${HTTP_PUBLISH_PORT}"
if command -v curl >/dev/null 2>&1; then
  code="$(curl -fsS -o /dev/null -w '%{http_code}' "http://localhost:${HTTP_PUBLISH_PORT}" || true)"
  log "HTTP status: ${code:-N/A}"
else
  log "curl not found; skipping HTTP check"
fi

log "Done. Open: http://localhost:${HTTP_PUBLISH_PORT}"
log "Login: Administrator / $ADMIN_PASSWORD"
