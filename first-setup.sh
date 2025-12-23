#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"

log() {
  printf '[first-setup] %s\n' "$*"
}

die() {
  printf '[first-setup][오류] %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "필수 명령을 찾을 수 없습니다: $1"
}

need_cmd docker

if ! docker compose version >/dev/null 2>&1; then
  die "docker compose를 사용할 수 없습니다. Docker Compose v2(docker compose)를 설치해 주세요."
fi

cd "$PROJECT_DIR"

# 1) Ensure .env exists
if [[ ! -f .env ]]; then
  if [[ -f example.env ]]; then
    log "example.env로부터 .env를 생성합니다"
    cp example.env .env
  else
    die "example.env가 없고 .env도 없습니다"
  fi
else
  log ".env가 이미 존재합니다(생성 건너뜀)"
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

INSTALL_CUSTOM_APPS="${INSTALL_CUSTOM_APPS:-1}"
FORCE_SEED_ITEM_GROUPS="${FORCE_SEED_ITEM_GROUPS:-0}"

log "사용 설정:"
log "  PROJECT_DIR=$PROJECT_DIR"
log "  SITE_NAME=$SITE_NAME"
log "  ADMIN_PASSWORD=(숨김)"
log "  DB_ROOT_PASSWORD=(숨김)"
log "  HTTP_PUBLISH_PORT=$HTTP_PUBLISH_PORT"
log "  INSTALL_CUSTOM_APPS=$INSTALL_CUSTOM_APPS"
log "  FORCE_SEED_ITEM_GROUPS=$FORCE_SEED_ITEM_GROUPS"

# 2) Fix WSL Docker credential helper issue if present
DOCKER_CONFIG_DIR="${DOCKER_CONFIG:-$HOME/.docker}"
DOCKER_CONFIG_JSON="$DOCKER_CONFIG_DIR/config.json"

if [[ -f "$DOCKER_CONFIG_JSON" ]] && grep -q '"credsStore"\s*:\s*"desktop\.exe"' "$DOCKER_CONFIG_JSON"; then
  ts="$(date +%Y%m%d%H%M%S)"
  backup="$DOCKER_CONFIG_JSON.bak.$ts"
  log "$DOCKER_CONFIG_JSON 에서 credsStore=desktop.exe를 감지했습니다(WSL에서 pull이 실패할 수 있음)"
  log "$backup 로 백업 후 config.json을 '{}'로 재작성합니다"
  cp "$DOCKER_CONFIG_JSON" "$backup"
  printf '{}' > "$DOCKER_CONFIG_JSON"
else
  log "Docker credsStore 수정이 필요하지 않습니다"
fi

# 3) Pull images & start services
log "이미지를 가져오는 중(pull)"
docker compose --project-directory "$PROJECT_DIR" pull

log "컨테이너를 시작하는 중(up -d)"
docker compose --project-directory "$PROJECT_DIR" up -d

# 4) Wait a bit for backend container to be ready
log "backend 컨테이너 준비를 기다리는 중"
for i in {1..60}; do
  if docker compose --project-directory "$PROJECT_DIR" exec -T backend bash -lc 'true' >/dev/null 2>&1; then
    break
  fi
  sleep 2
  if [[ "$i" -eq 60 ]]; then
    die "backend 컨테이너가 제한 시간 내에 준비되지 않았습니다"
  fi
done

# 5) Create site if missing
SITE_PATH="/home/frappe/frappe-bench/sites/$SITE_NAME"
if docker compose --project-directory "$PROJECT_DIR" exec -T backend bash -lc "test -d '$SITE_PATH'" >/dev/null 2>&1; then
  log "사이트가 이미 존재합니다: $SITE_NAME (bench new-site 건너뜀)"
else
  log "사이트를 생성합니다: $SITE_NAME"
  docker compose --project-directory "$PROJECT_DIR" exec -T backend bash -lc \
    "bench new-site '$SITE_NAME' --admin-password '$ADMIN_PASSWORD' --mariadb-root-password '$DB_ROOT_PASSWORD' --install-app erpnext"
fi

# 6) Migrate and enable scheduler
log "마이그레이션 실행(bench migrate)"
docker compose --project-directory "$PROJECT_DIR" exec -T backend bash -lc "bench --site '$SITE_NAME' migrate"

# 6.1) Install local custom app (if present)
if [[ "$INSTALL_CUSTOM_APPS" == "1" ]] && [[ -d "$PROJECT_DIR/apps/custom_apps" ]]; then
  log "로컬 앱을 감지했습니다: apps/custom_apps"

  is_installed="0"
  if docker compose --project-directory "$PROJECT_DIR" exec -T backend bash -lc "bench --site '$SITE_NAME' list-apps" >/dev/null 2>&1; then
    if docker compose --project-directory "$PROJECT_DIR" exec -T backend bash -lc "bench --site '$SITE_NAME' list-apps" | tr -d '\r' | grep -Fxq "custom_apps"; then
      is_installed="1"
    fi
  elif docker compose --project-directory "$PROJECT_DIR" exec -T backend bash -lc "test -f '/home/frappe/frappe-bench/sites/$SITE_NAME/apps.txt'" >/dev/null 2>&1; then
    if docker compose --project-directory "$PROJECT_DIR" exec -T backend bash -lc "cat '/home/frappe/frappe-bench/sites/$SITE_NAME/apps.txt'" | tr -d '\r' | grep -Fxq "custom_apps"; then
      is_installed="1"
    fi
  fi

  if [[ "$is_installed" == "1" ]]; then
    log "custom_apps가 이미 $SITE_NAME 에 설치되어 있습니다(install-app 건너뜀)"
  else
    log "$SITE_NAME 에 custom_apps를 설치합니다"
    docker compose --project-directory "$PROJECT_DIR" exec -T \
      -e FORCE_SEED_ITEM_GROUPS="$FORCE_SEED_ITEM_GROUPS" \
      backend bash -lc "bench --site '$SITE_NAME' install-app custom_apps"
    log "custom_apps 설치 후 마이그레이션을 다시 실행합니다"
    docker compose --project-directory "$PROJECT_DIR" exec -T backend bash -lc "bench --site '$SITE_NAME' migrate"
  fi
else
  log "apps/custom_apps가 없거나 INSTALL_CUSTOM_APPS != 1 입니다(custom app 설치 건너뜀)"
fi

log "스케줄러를 활성화합니다"
docker compose --project-directory "$PROJECT_DIR" exec -T backend bash -lc "bench --site '$SITE_NAME' enable-scheduler"

# 7) Quick HTTP check
log "HTTP 응답을 확인합니다: http://localhost:${HTTP_PUBLISH_PORT}"
if command -v curl >/dev/null 2>&1; then
  code="$(curl -fsS -o /dev/null -w '%{http_code}' "http://localhost:${HTTP_PUBLISH_PORT}" || true)"
  log "HTTP 상태 코드: ${code:-N/A}"
else
  log "curl이 없어 HTTP 확인을 건너뜁니다"
fi

log "완료. 브라우저에서 열기: http://localhost:${HTTP_PUBLISH_PORT}"
log "로그인: Administrator / $ADMIN_PASSWORD"
