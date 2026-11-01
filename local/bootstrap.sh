#!/usr/bin/env bash
# Brings up the local Panel, creates admin + node, and writes the Wings config.
# Idempotent: re-running reuses existing state under HG_ROOT.
set -euo pipefail

cd "$(dirname "$0")"
export HG_ROOT="${HG_ROOT:-$HOME/hg-local}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@heldengilde.local}"
ADMIN_PASS="${ADMIN_PASS:-$(cat "$HG_ROOT/admin-password" 2>/dev/null || openssl rand -hex 12)}"

mkdir -p "$HG_ROOT"/{etc,lib,tmp,log,gitops,custom-jars,config}
echo "$ADMIN_PASS" > "$HG_ROOT/admin-password"; chmod 600 "$HG_ROOT/admin-password"

panel() { docker compose exec -T -u www-data panel "$@"; }
artisan() { panel php artisan "$@"; }

docker compose up -d panel
echo "waiting for panel..."
for _ in $(seq 60); do
  curl -fs -o /dev/null -H 'Host: panel' http://127.0.0.1:8081/ && break
  sleep 2
done

# Headless equivalent of the web installer: create the SQLite DB, migrate, mark installed.
if ! artisan migrate:status >/dev/null 2>&1; then
  panel touch /pelican-data/database/database.sqlite
  artisan migrate --seed --force
fi
panel sed -i 's/^APP_INSTALLED=false/APP_INSTALLED=true/' /pelican-data/.env

if ! artisan p:user:make --email="$ADMIN_EMAIL" --username=admin --password="$ADMIN_PASS" --admin=1 --silent 2>/dev/null; then
  echo "admin user probably exists already"
fi

if ! artisan p:node:list 2>/dev/null | grep -q hg-local; then
  artisan p:node:make --name=hg-local --description="local spike" --locationId=1 \
    --fqdn=wings --public=1 --scheme=http --proxy=0 --maintenance=0 \
    --maxMemory="${NODE_MEM_MB:-49152}" --overallocateMemory=0 --maxDisk="${NODE_DISK_MB:-102400}" --overallocateDisk=0 \
    --maxCpu=0 --overallocateCpu=0 --uploadSize=100 \
    --daemonListeningPort=8080 --daemonConnectingPort=8080 --daemonSFTPPort=2022 \
    --daemonBase="$HG_ROOT/lib/volumes" --silent
fi

artisan p:node:configuration 1 --format=yaml > "$HG_ROOT/etc/config.yml"
echo "wrote $HG_ROOT/etc/config.yml"

# API keys for the spike scripts (application + client), created once.
if [ ! -s "$HG_ROOT/app-key" ] || [ ! -s "$HG_ROOT/client-key" ]; then
  umask 077
  # shellcheck disable=SC2016 # the $ signs are PHP, not shell
  raw="$(artisan tinker --execute='
    $u = App\Models\User::where("username", "admin")->first();
    $svc = app(App\Services\Api\KeyCreationService::class);
    $perms = array_fill_keys(App\Models\ApiKey::getPermissionList(), 3);
    $app = $svc->setKeyType(App\Models\ApiKey::TYPE_APPLICATION)->handle(["user_id" => $u->id, "memo" => "spike-app", "allowed_ips" => [], "permissions" => $perms]);
    $cli = $svc->setKeyType(App\Models\ApiKey::TYPE_ACCOUNT)->handle(["user_id" => $u->id, "memo" => "spike-client", "allowed_ips" => []]);
    echo "APP=" . $app->identifier . $app->token . "\nCLI=" . $cli->identifier . $cli->token . "\n";')"
  sed -n 's/^.*APP=//p' <<<"$raw" > "$HG_ROOT/app-key"
  sed -n 's/^.*CLI=//p' <<<"$raw" > "$HG_ROOT/client-key"
fi

# Wings runs in a container: use HG_ROOT-based paths (identical on host and in Wings),
# reach the panel over the compose network, and allow the spike's mount sources.
python3 - "$HG_ROOT" <<'PY'
import re, sys
root = sys.argv[1]
p = f"{root}/etc/config.yml"
s = open(p).read()
# APP_URL is http://panel:8081 (browser); inside the compose network the panel answers on port 80.
s = re.sub(r"remote: 'http://[^']*'", "remote: 'http://panel'", s)
# The browser console opens a WebSocket to Wings with the panel's origin; Wings rejects unknown origins.
s = s.replace("allowed_origins: []", "allowed_origins:\n  - http://panel:8081")
s = s.replace("allowed_mounts: []", f"allowed_mounts:\n  - {root}/gitops\n  - {root}/custom-jars\n  - {root}/config\n  - {root}/lib/volumes")
s = re.sub(r"(system:\n)", rf"\1  root_directory: {root}/lib\n  log_directory: {root}/log\n  tmp_directory: {root}/tmp\n  archive_directory: {root}/lib/archives\n  backup_directory: {root}/lib/backups\n  user:\n    passwd:\n      directory: {root}/etc\n  machine_id:\n    directory: {root}/etc/machine-id\n", s, count=1)
open(p, "w").write(s)
PY
docker compose --profile wings up -d wings
docker compose restart wings
