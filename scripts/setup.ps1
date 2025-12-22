param(
	[string]$SiteName = "erp.localhost",
	[string]$DbRootPassword = "admin",
	[string]$AdminPassword = "admin"
)

$ErrorActionPreference = "Stop"

docker compose down -v

docker compose up -d

Start-Sleep -Seconds 10

$env:FORCE_SEED_ITEM_GROUPS = "1"

$services = @("backend", "queue-short", "queue-long", "scheduler")
foreach ($svc in $services) {
	docker compose exec $svc bench pip install -e apps/custom_apps
}

docker compose exec backend bash -lc "grep -qxF custom_apps sites/apps.txt || echo custom_apps >> sites/apps.txt"

docker compose exec backend bench new-site $SiteName --mariadb-user-host-login-scope='%' --db-root-username root --db-root-password $DbRootPassword --admin-password $AdminPassword --install-app erpnext --set-default --force

docker compose exec backend bench --site $SiteName install-app custom_apps

docker compose exec backend bench --site $SiteName execute custom_apps.setup.install.seed_item_groups --kwargs "{'force': True}"

docker compose exec backend bench --site $SiteName migrate

docker compose exec backend bench build

docker compose restart backend frontend websocket queue-short queue-long scheduler

Write-Host "OK: http://localhost:8080 (Site: $SiteName)"
Write-Host "Login: Administrator / $AdminPassword"
