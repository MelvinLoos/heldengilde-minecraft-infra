#!/usr/bin/env bash
# Phase 1 spike checks for ADR 0002 (itzg under Wings with Pelican Mounts).
# Prereq: ./bootstrap.sh and ./spike/provision.sh have run. Prints PASS/FAIL per check.
set -uo pipefail

HG_ROOT="${HG_ROOT:-$HOME/hg-local}"
BASE="http://127.0.0.1:8081/api/client/servers"
KEY="$(cat "$HG_ROOT/client-key")"
SUUID="${SUUID:-$(docker ps -a --filter "label=Service=Pelican" --format '{{.Names}}' | head -1)}"
SID="${SUUID%%-*}"
fails=0

c() { curl -fsS -H "Host: panel" -H "Authorization: Bearer $KEY" -H "Accept: application/json" -H "Content-Type: application/json" "$@"; }
state() { c "$BASE/$SID/resources" | jq -r .attributes.current_state; }
wait_state() { # state timeout
  for _ in $(seq "$(($2 / 3))"); do [ "$(state)" = "$1" ] && return 0; sleep 3; done
  return 1
}
check() { # name command...
  local n=$1; shift
  if "$@" >/dev/null 2>&1; then echo "PASS $n"; else echo "FAIL $n"; fails=$((fails + 1)); fi
}
dexec() { docker exec "$SUUID" "$@"; }

echo "server=$SUUID"
wait_state running 180 || { echo "FAIL server reached running (Done detected)"; exit 1; }
echo "PASS server reached running (Wings detected 'Done')"

# --- container / privilege model ---
insp() { docker inspect "$SUUID" --format "$1"; }
check "container user is 988:988"                [ "$(insp '{{.Config.User}}')" = "988:988" ]
check "rootfs is read-only"                      [ "$(insp '{{.HostConfig.ReadonlyRootfs}}')" = true ]
check "no-new-privileges set"                    bash -c "docker inspect '$SUUID' --format '{{.HostConfig.SecurityOpt}}' | grep -q no-new-privileges"
check "/data is a bind mount to the volume"      bash -c "docker inspect '$SUUID' --format '{{range .Mounts}}{{.Destination}} {{.Type}} {{.Source}}{{println}}{{end}}' | grep -q '^/data bind $HG_ROOT/lib/volumes/'"
check "no anonymous volumes"                     bash -c "[ -z \"\$(docker inspect '$SUUID' --format '{{range .Mounts}}{{if eq .Type \"volume\"}}x{{end}}{{end}}')\" ]"
check "no chown/gosu/setpriv errors in log"      bash -c "! docker logs '$SUUID' 2>&1 | grep -iE 'setpriv|gosu|chown:|operation not permitted'"
check "java runs as uid 988"                     bash -c "[ \"\$(docker exec '$SUUID' id -u)\" = 988 ]"

# --- itzg features ---
check "Modrinth plugins installed (LuckPerms)"   dexec sh -c 'ls /data/plugins | grep -qi luckperms'
check "Modrinth plugins installed (packetevents)" dexec sh -c 'ls /data/plugins | grep -qi packetevents'
check "/config sync + CFG_ interpolation"        dexec grep -q "secret: s3cret-from-env" /data/plugins/Spike/config.yml
check "/config sync keeps static value"          dexec grep -q "static: from-git" /data/plugins/Spike/config.yml
mkdir -p "$HG_ROOT/custom-jars"; echo spike > "$HG_ROOT/custom-jars/spike-marker.txt"

# --- persistence across container recreate ---
seed_before=$(dexec rcon-cli seed 2>/dev/null | tr -d '\r')
dexec rcon-cli "forceload add 0 0" >/dev/null 2>&1
sleep 2
dexec rcon-cli "setblock 0 100 0 minecraft:gold_block" >/dev/null 2>&1
dexec rcon-cli save-all flush >/dev/null 2>&1
echo "seed before: $seed_before"
cid_old=$(docker inspect "$SUUID" --format '{{.Id}}')
c -X POST "$BASE/$SID/power" -d '{"signal":"stop"}' >/dev/null
check "graceful stop reaches offline"            wait_state offline 90
check "stop saved the world"                     bash -c "docker logs '$SUUID' 2>&1 | grep -qiE 'saving (players|worlds|chunks)|all dimensions are saved'"
c -X POST "$BASE/$SID/power" -d '{"signal":"start"}' >/dev/null
wait_state running 180 || { echo "FAIL restart reached running"; fails=$((fails + 1)); }
cid_new=$(docker inspect "$SUUID" --format '{{.Id}}')
check "container was recreated on restart"       [ "$cid_old" != "$cid_new" ]
seed_after=$(dexec rcon-cli seed 2>/dev/null | tr -d '\r')
echo "seed after:  $seed_after"
check "world persisted (same seed)"              bash -c "[ -n '$seed_before' ] && [ '$seed_before' = '$seed_after' ]"
check "marker block persisted"                   bash -c "docker exec '$SUUID' rcon-cli 'forceload add 0 0' >/dev/null; sleep 2; docker exec '$SUUID' rcon-cli 'execute if block 0 100 0 minecraft:gold_block' | grep -qi 'passed'"
check "custom-jar dir synced to /data/plugins"   dexec test -f /data/plugins/spike-marker.txt

# --- Pelican file manager + backups see the data ---
check "file manager lists server.properties"     bash -c "curl -fsS -H 'Host: panel' -H 'Authorization: Bearer $KEY' -H 'Accept: application/json' '$BASE/$SID/files/list?directory=/' | jq -e '.data[]|select(.attributes.name==\"server.properties\")'"
bk=$(c -X POST "$BASE/$SID/backups" -d '{"name":"spike"}' | jq -r .attributes.uuid)
ok=1
for _ in $(seq 40); do
  done_at=$(c "$BASE/$SID/backups/$bk" | jq -r '.attributes.completed_at // empty')
  [ -n "$done_at" ] && { ok=0; break; }
  sleep 3
done
check "Pelican backup completes"                 [ "$ok" = 0 ]
check "backup is non-trivial in size"            bash -c "[ \"\$(curl -fsS -H 'Host: panel' -H 'Authorization: Bearer $KEY' -H 'Accept: application/json' '$BASE/$SID/backups/$bk' | jq -r .attributes.bytes)\" -gt 1000000 ]"

echo "failures: $fails"
exit "$fails"
