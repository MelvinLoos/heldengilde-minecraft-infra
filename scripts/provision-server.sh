#!/usr/bin/env bash
# Creates (idempotently) the Minecraft server through the Pelican Application API: egg import,
# allocation, server, then the Mounts from ADR 0002. Shared by local/ and the Ansible role hg_server.
#
# Required env: COMPOSE_FILE (panel compose file), STATE_DIR (holds app-key, node-id)
# Optional env: PANEL_URL PANEL_HOST EGG_FILE SERVER_NAME SERVER_PORT SERVER_MEMORY_MB SERVER_DISK_MB
#   SERVER_IMAGE EXTRA_ENV_JSON VOLUMES_DIR GITOPS_SRC JARS_SRC CONFIG_SRC
set -euo pipefail

: "${COMPOSE_FILE:?}" "${STATE_DIR:?}"
PANEL_URL="${PANEL_URL:-http://127.0.0.1:8081}"
PANEL_HOST="${PANEL_HOST:-panel}"
here="$(cd "$(dirname "$0")" && pwd)"
EGG_FILE="${EGG_FILE:-$here/../4-server/egg.yaml}"
SERVER_NAME="${SERVER_NAME:-hg-paper}"
SERVER_PORT="${SERVER_PORT:-25565}"
SERVER_MEMORY_MB="${SERVER_MEMORY_MB:-20480}"
SERVER_DISK_MB="${SERVER_DISK_MB:-40960}"
SERVER_IMAGE="${SERVER_IMAGE:-itzg/minecraft-server:java25}"
EXTRA_ENV_JSON="${EXTRA_ENV_JSON:-{\}}"
VOLUMES_DIR="${VOLUMES_DIR:-/var/lib/pelican/volumes}"
GITOPS_SRC="${GITOPS_SRC:-/srv/heldengilde/gitops}"
JARS_SRC="${JARS_SRC:-/srv/heldengilde/custom-jars}"
CONFIG_SRC="${CONFIG_SRC:-$GITOPS_SRC/4-server/config}"
KEY="$(cat "$STATE_DIR/app-key")"
NODE_ID="$(cat "$STATE_DIR/node-id" 2>/dev/null || echo 1)"
API="$PANEL_URL/api/application"
EGG_NAME="$(sed -n 's/^name: *//p' "$EGG_FILE" | head -1 | tr -d "\"'")"

api() { # method path [curl args]
  local m=$1 p=$2; shift 2
  curl -sS --fail-with-body -X "$m" -H "Host: $PANEL_HOST" -H "Authorization: Bearer $KEY" \
    -H "Accept: application/json" -H "Content-Type: application/json" "$API$p" "$@"
}
egg_id() { api GET /eggs | jq -r --arg n "$EGG_NAME" '.data[]|select(.attributes.name==$n)|.attributes.id' | head -1; }

# 1. Egg (imported once by name; delete the egg in the panel to re-import a changed one)
id=$(egg_id)
if [ -z "$id" ]; then
  echo "importing egg $EGG_NAME"
  curl -fsS -X POST -H "Host: $PANEL_HOST" -H "Authorization: Bearer $KEY" -H "Accept: application/json" \
    -H "Content-Type: application/yaml" --data-binary "@$EGG_FILE" "$API/eggs/import" >/dev/null
  id=$(egg_id)
fi
echo "egg_id=$id"

# 2. Allocation
if [ "$(api GET "/nodes/$NODE_ID/allocations" | jq --argjson p "$SERVER_PORT" '[.data[]|select(.attributes.port==$p)]|length')" = 0 ]; then
  api POST "/nodes/$NODE_ID/allocations" -d "{\"ip\":\"0.0.0.0\",\"ports\":[\"$SERVER_PORT\"]}" >/dev/null
fi
alloc=$(api GET "/nodes/$NODE_ID/allocations" | jq -r --argjson p "$SERVER_PORT" '.data[]|select(.attributes.port==$p)|.attributes.id')

# 3. Server
find_srv() { api GET /servers | jq -c --arg n "$SERVER_NAME" '.data[]|select(.attributes.name==$n)|.attributes|{id,uuid}' | head -1; }
srv=$(find_srv)
if [ -z "$srv" ]; then
  env_json=$(api GET "/eggs/$id?include=variables" | jq -c '[.attributes.relationships.variables.data[].attributes|{(.env_variable):.default_value}]|add')
  body=$(jq -nc --argjson env "$(jq -nc --argjson a "$env_json" --argjson b "$EXTRA_ENV_JSON" '$a + $b')" \
    --argjson egg "$id" --argjson alloc "$alloc" --arg name "$SERVER_NAME" --arg img "$SERVER_IMAGE" \
    --argjson mem "$SERVER_MEMORY_MB" --argjson disk "$SERVER_DISK_MB" '{
    name:$name, user:1, egg:$egg, docker_image:$img,
    startup:"itzg-entrypoint", environment:$env,
    limits:{memory:$mem,swap:0,disk:$disk,io:500,cpu:0},
    feature_limits:{databases:0,backups:5,allocations:1}, allocation:{default:$alloc}}')
  api POST /servers -d "$body" | jq -c '.errors // empty' >&2
  srv=$(find_srv)
fi
sid=$(jq -r .id <<<"$srv"); suuid=$(jq -r .uuid <<<"$srv")
echo "server id=$sid uuid=$suuid"

# 4. Mounts. POST /mounts ignores all fields in panel v1.0.0-beta38 (no validation rules), so use tinker.
mount() { # name source target readonly(true|false)
  docker compose -f "$COMPOSE_FILE" exec -T -u www-data panel php artisan tinker --execute="
    \$m = App\\Models\\Mount::firstOrNew(['name' => '$1']);
    \$m->forceFill(['uuid' => \$m->uuid ?: (string) Illuminate\\Support\\Str::uuid(), 'source' => '$2', 'target' => '$3', 'read_only' => $4, 'user_mountable' => false])->save();
    \$m->servers()->syncWithoutDetaching([$sid]);
    echo 'mount $1 -> $3 ok';" 2>&1 | tail -1
  echo
}
mount "$SERVER_NAME-data"   "$VOLUMES_DIR/$suuid" /data    false
mount "$SERVER_NAME-gitops" "$GITOPS_SRC"         /gitops  true
mount "$SERVER_NAME-jars"   "$JARS_SRC"           /plugins true
mount "$SERVER_NAME-config" "$CONFIG_SRC"         /config  true
