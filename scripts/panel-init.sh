#!/usr/bin/env bash
# Initialises a running Pelican Panel container headlessly: schema, admin user, node and API keys.
# Shared by local/bootstrap.sh and the Ansible role pelican_panel, so laptop and server behave the same.
# Idempotent. Writes into STATE_DIR: admin-password, app-key, client-key, wings-config.yml.
#
# Required env:
#   COMPOSE_FILE   compose file that defines the `panel` service
# Optional env:
#   STATE_DIR (default $HG_ROOT or ./state)  PANEL_URL (http://127.0.0.1:8081)  PANEL_HOST (Host header)
#   ADMIN_EMAIL ADMIN_USER  NODE_NAME NODE_FQDN NODE_SCHEME(http|https) NODE_BEHIND_PROXY(0|1) NODE_PORT NODE_CONNECT_PORT
#   NODE_MEM_MB NODE_DISK_MB  VOLUMES_DIR (Wings data root)  PANEL_DB (sqlite|mariadb)  PANEL_ENV_FILE
set -euo pipefail

: "${COMPOSE_FILE:?compose file with a panel service}"
STATE_DIR="${STATE_DIR:-${HG_ROOT:-./state}}"
PANEL_URL="${PANEL_URL:-http://127.0.0.1:8081}"
PANEL_HOST="${PANEL_HOST:-panel}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@heldengilde.local}"
ADMIN_USER="${ADMIN_USER:-admin}"
NODE_NAME="${NODE_NAME:-hg-local}"
NODE_FQDN="${NODE_FQDN:-wings}"
NODE_SCHEME="${NODE_SCHEME:-http}"
NODE_BEHIND_PROXY="${NODE_BEHIND_PROXY:-0}"
NODE_PORT="${NODE_PORT:-8080}"
NODE_CONNECT_PORT="${NODE_CONNECT_PORT:-$NODE_PORT}"
NODE_MEM_MB="${NODE_MEM_MB:-8192}"
NODE_DISK_MB="${NODE_DISK_MB:-20480}"
VOLUMES_DIR="${VOLUMES_DIR:-/var/lib/pelican/volumes}"
PANEL_DB="${PANEL_DB:-sqlite}"
PANEL_ENV_FILE="${PANEL_ENV_FILE:-/pelican-data/.env}"

mkdir -p "$STATE_DIR"
umask 077
[ -s "$STATE_DIR/admin-password" ] || openssl rand -hex 12 > "$STATE_DIR/admin-password"
ADMIN_PASS="$(cat "$STATE_DIR/admin-password")"

panel() { docker compose -f "$COMPOSE_FILE" exec -T -u www-data panel "$@"; }
artisan() { panel php artisan "$@"; }

echo "waiting for panel..."
for _ in $(seq 90); do
  curl -fs -o /dev/null -H "Host: $PANEL_HOST" "$PANEL_URL/" && break
  sleep 2
done

# Headless equivalent of the web installer.
if ! artisan migrate:status >/dev/null 2>&1; then
  [ "$PANEL_DB" = sqlite ] && panel touch /pelican-data/database/database.sqlite
  artisan migrate --seed --force
fi
panel sed -i 's/^APP_INSTALLED=false/APP_INSTALLED=true/' "$PANEL_ENV_FILE"

artisan p:user:make --email="$ADMIN_EMAIL" --username="$ADMIN_USER" --password="$ADMIN_PASS" --admin=1 --silent 2>/dev/null \
  || echo "admin user probably exists already"

if ! artisan p:node:list 2>/dev/null | grep -q "$NODE_NAME"; then
  artisan p:node:make --name="$NODE_NAME" --description="managed by hg" --locationId=1 \
    --fqdn="$NODE_FQDN" --public=1 --scheme="$NODE_SCHEME" --proxy="$NODE_BEHIND_PROXY" --maintenance=0 \
    --maxMemory="$NODE_MEM_MB" --overallocateMemory=0 --maxDisk="$NODE_DISK_MB" --overallocateDisk=0 \
    --maxCpu=0 --overallocateCpu=0 --uploadSize=100 \
    --daemonListeningPort="$NODE_PORT" --daemonConnectingPort="$NODE_CONNECT_PORT" --daemonSFTPPort=2022 \
    --daemonBase="$VOLUMES_DIR" --silent
fi
node_id="$(artisan p:node:list --format=json 2>/dev/null | jq -r --arg n "$NODE_NAME" '.[]|select(.name==$n)|.id' 2>/dev/null || true)"
echo "${node_id:-1}" > "$STATE_DIR/node-id"
artisan p:node:configuration "${node_id:-1}" --format=yaml > "$STATE_DIR/wings-config.yml"

if [ ! -s "$STATE_DIR/app-key" ] || [ ! -s "$STATE_DIR/client-key" ]; then
  # shellcheck disable=SC2016 # the $ signs are PHP, not shell
  raw="$(artisan tinker --execute='
    $u = App\Models\User::where("username", "'"$ADMIN_USER"'")->first();
    $svc = app(App\Services\Api\KeyCreationService::class);
    $perms = array_fill_keys(App\Models\ApiKey::getPermissionList(), 3);
    $app = $svc->setKeyType(App\Models\ApiKey::TYPE_APPLICATION)->handle(["user_id" => $u->id, "memo" => "hg-app", "allowed_ips" => [], "permissions" => $perms]);
    $cli = $svc->setKeyType(App\Models\ApiKey::TYPE_ACCOUNT)->handle(["user_id" => $u->id, "memo" => "hg-client", "allowed_ips" => []]);
    echo "APP=" . $app->identifier . $app->token . "\nCLI=" . $cli->identifier . $cli->token . "\n";')"
  sed -n 's/^.*APP=//p' <<<"$raw" > "$STATE_DIR/app-key"
  sed -n 's/^.*CLI=//p' <<<"$raw" > "$STATE_DIR/client-key"
fi
echo "panel initialised; state in $STATE_DIR"
