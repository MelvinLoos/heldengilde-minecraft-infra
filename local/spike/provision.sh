#!/usr/bin/env bash
# Creates the spike server through the Pelican Application API: egg import,
# allocation, server, then the three Mounts (ADR 0002). Idempotent per run.
set -euo pipefail

HG_ROOT="${HG_ROOT:-$HOME/hg-local}"
API="http://127.0.0.1:8081/api/application"
KEY="$(cat "$HG_ROOT/app-key")"
here="$(cd "$(dirname "$0")" && pwd)"
EGG_FILE="${EGG_FILE:-$here/egg-itzg.yaml}"
SERVER_NAME="${SERVER_NAME:-hg-spike}"
SERVER_PORT="${SERVER_PORT:-25565}"
SERVER_MEMORY_MB="${SERVER_MEMORY_MB:-3072}"
EXTRA_ENV_JSON="${EXTRA_ENV_JSON:-{\}}"
GITOPS_SRC="${GITOPS_SRC:-$HG_ROOT/gitops}"
CONFIG_SRC="${CONFIG_SRC:-$HG_ROOT/config}"
JARS_SRC="${JARS_SRC:-$HG_ROOT/custom-jars}"

api() { # method path [json-body]
  local m=$1 p=$2; shift 2
  curl -fsS -X "$m" -H "Host: panel" -H "Authorization: Bearer $KEY" \
    -H "Accept: application/json" -H "Content-Type: application/json" "$API$p" "$@"
}

# 1. Egg
egg_id=$(api GET /eggs | jq -r '.data[]|select(.attributes.name=="Heldengilde Paper (itzg)")|.attributes.id' | head -1)
if [ -z "$egg_id" ]; then
  echo "importing egg"
  curl -fsS -X POST -H "Host: panel" -H "Authorization: Bearer $KEY" -H "Accept: application/json" \
    -H "Content-Type: application/yaml" --data-binary "@$EGG_FILE" "$API/eggs/import" | jq -c '.attributes|{id,name}'
  egg_id=$(api GET /eggs | jq -r '.data[]|select(.attributes.name=="Heldengilde Paper (itzg)")|.attributes.id' | head -1)
fi
echo "egg_id=$egg_id"

# 2. Allocation
if [ "$(api GET /nodes/1/allocations | jq --argjson p "$SERVER_PORT" '[.data[]|select(.attributes.port==$p)]|length')" = 0 ]; then
  api POST /nodes/1/allocations -d "{\"ip\":\"0.0.0.0\",\"ports\":[\"$SERVER_PORT\"]}" >/dev/null
fi
alloc_id=$(api GET /nodes/1/allocations | jq -r --argjson p "$SERVER_PORT" '.data[]|select(.attributes.port==$p)|.attributes.id')
echo "allocation=$alloc_id"

# 3. Server
srv=$(api GET /servers | jq -c --arg n "$SERVER_NAME" '.data[]|select(.attributes.name==$n)|.attributes|{id,uuid}' | head -1)
if [ -z "$srv" ]; then
  env_json=$(api GET "/eggs/$egg_id?include=variables" | jq -c '[.attributes.relationships.variables.data[].attributes|{(.env_variable):.default_value}]|add')
  body=$(jq -nc --argjson env "$(jq -nc --argjson a "$env_json" --argjson b "$EXTRA_ENV_JSON" '$a + $b')" --argjson egg "$egg_id" --argjson alloc "$alloc_id" --arg name "$SERVER_NAME" --argjson mem "$SERVER_MEMORY_MB" '{
    name:$name, user:1, egg:$egg, docker_image:"itzg/minecraft-server:java25",
    startup:"itzg-entrypoint", environment:$env,
    limits:{memory:$mem,swap:0,disk:4096,io:500,cpu:0},
    feature_limits:{databases:0,backups:2,allocations:1}, allocation:{default:$alloc}}')
  api POST /servers -d "$body" | jq -c '.attributes|{id,uuid,identifier}'
  srv=$(api GET /servers | jq -c --arg n "$SERVER_NAME" '.data[]|select(.attributes.name==$n)|.attributes|{id,uuid}' | head -1)
fi
sid=$(jq -r .id <<<"$srv"); suuid=$(jq -r .uuid <<<"$srv")
echo "server id=$sid uuid=$suuid"

# 4. Mounts
# The Application API's POST /mounts ignores all fields in panel v1.0.0-beta38
# (StoreMountRequest has no rules, so validated() is empty), so use tinker.
mount() { # name source target readonly(true|false)
  docker compose -f "$here/../compose.yml" exec -T -u www-data panel php artisan tinker --execute="
    \$m = App\\Models\\Mount::firstOrNew(['name' => '$1']);
    \$m->forceFill(['uuid' => \$m->uuid ?: (string) Illuminate\\Support\\Str::uuid(), 'source' => '$2', 'target' => '$3', 'read_only' => $4, 'user_mountable' => false])->save();
    \$m->servers()->syncWithoutDetaching([$sid]);
    echo 'mount $1 -> $3 ok';" 2>&1 | tail -1
  echo
}
mount "$SERVER_NAME-data"   "$HG_ROOT/lib/volumes/$suuid" /data    false
mount "$SERVER_NAME-gitops" "$GITOPS_SRC"                  /gitops  true
mount "$SERVER_NAME-jars"   "$JARS_SRC"                    /plugins true
mount "$SERVER_NAME-config" "$CONFIG_SRC"                  /config  true
