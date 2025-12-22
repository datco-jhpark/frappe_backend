#!/usr/bin/env bash
set -euo pipefail

SITE_NAME=${1:-erp.localhost}
DB_ROOT_PASSWORD=${2:-admin}
ADMIN_PASSWORD=${3:-admin}

export FORCE_SEED_ITEM_GROUPS=1

docker compose down -v

docker compose up -d

sleep 10

for svc in backend queue-short queue-long scheduler; do
	docker compose exec "$svc" bench pip install -e apps/custom_apps
 done

docker compose exec backend bash -lc "grep -qxF custom_apps sites/apps.txt || echo custom_apps >> sites/apps.txt"

docker compose exec backend bench new-site "$SITE_NAME" \
	--mariadb-user-host-login-scope='%' \
	--db-root-username root \
	--db-root-password "$DB_ROOT_PASSWORD" \
	--admin-password "$ADMIN_PASSWORD" \
	--install-app erpnext \
	--set-default \
	--force

docker compose exec backend bench --site "$SITE_NAME" install-app custom_apps

docker compose exec backend bench --site "$SITE_NAME" execute custom_apps.setup.install.seed_item_groups --kwargs "{'force': True}"

docker compose exec backend bench --site "$SITE_NAME" migrate

docker compose exec backend bench build

docker compose restart backend frontend websocket queue-short queue-long scheduler

echo "OK: http://localhost:8080 (Site: $SITE_NAME)"
echo "Login: Administrator / $ADMIN_PASSWORD"
