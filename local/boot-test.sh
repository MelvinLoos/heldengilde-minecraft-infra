#!/usr/bin/env bash
# Boots the server definition in plain Docker (same mounts and env as production) and
# fails on plugin load errors. Premium jars are used if found in $HG_PREMIUM_DIR.
# Usage: [HG_EXTRA_ENV="VERSION=26.2 PAPER_BUILD=135"] local/boot-test.sh [--keep]
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
work="${HG_BOOT_DIR:-$HOME/hg-local/boottest}"
image="${ITZG_IMAGE:-itzg/minecraft-server:java25}"
name=hg-boottest
timeout="${BOOT_TIMEOUT:-600}"

rm -rf "$work"; mkdir -p "$work/data" "$work/jars" "$work/config"
"$repo/agent/fetch-custom-jars.sh" "$repo/4-server/custom-jars.lock.json" "$work/jars" --allow-missing-premium

extra=()
for kv in ${HG_EXTRA_ENV:-}; do extra+=(-e "$kv"); done

docker rm -f "$name" >/dev/null 2>&1 || true
docker run -d --name "$name" --user "$(id -u):$(id -g)" \
  --env-file "$repo/4-server/env/server.env" \
  -e UID="$(id -u)" -e GID="$(id -g)" -e ONLINE_MODE=FALSE -e MEMORY=3G \
  -e CFG_DISCORD_BOT_TOKEN=boot-test-token -e CFG_DISCORDSRV_REQUIRE_LINK=false "${extra[@]}" \
  -v "$work/data:/data" -v "$repo:/gitops:ro" -v "$work/jars:/plugins:ro" \
  -v "$repo/4-server/config:/config:ro" \
  "$image" >/dev/null
echo "image: $(docker image inspect "$image" --format '{{index .RepoDigests 0}}' 2>/dev/null || echo "$image")"

up=1
for _ in $(seq $((timeout / 5))); do
  if docker logs "$name" 2>&1 | grep -q 'Done (.*)! For help'; then up=0; break; fi
  [ "$(docker inspect -f '{{.State.Running}}' "$name")" = true ] || break
  sleep 5
done
docker logs "$name" > "$work/boot.log" 2>&1 || true
fails=0
if [ "$up" != 0 ]; then echo "FAIL server did not reach Done"; tail -20 "$work/boot.log" | cut -c1-220; fails=1; else echo "PASS server reached Done"; fi

bad=$(grep -E 'ERROR\]|SEVERE|Could not load|Error occurred while enabling|Unsupported API|Failed to' "$work/boot.log" | grep -v '\[DiscordSRV\]' | grep -v 'sessionserver.mojang.com' || true)
if [ -n "$bad" ]; then echo "FAIL errors in log:"; echo "$bad" | head -15 | cut -c1-220; fails=1; else echo "PASS no ERROR/SEVERE/load errors in log"; fi

if [ "$up" = 0 ]; then
  plugins=$(docker exec "$name" rcon-cli plugins 2>/dev/null | tr -d '\r' | sed 's/§.//g')
  echo "$plugins"
  disabled=$(grep -oE '\[[A-Za-z0-9_-]+\] Disabling [A-Za-z0-9_-]+ v' "$work/boot.log" | sort -u || true)
  disabled=$(echo "$disabled" | grep -v DiscordSRV || true)
  [ -z "$disabled" ] || { echo "FAIL plugins disabled during boot: $disabled"; fails=1; }
fi

if [ "$up" = 0 ]; then
  ok=1
  for _ in $(seq 10); do
    if docker exec "$name" rcon-cli "gamerule keep_inventory" 2>/dev/null | grep -q true; then ok=0; break; fi
    sleep 3
  done
  if [ "$ok" = 0 ]; then echo "PASS RCON_CMDS_STARTUP applied (keep_inventory=true)"; else echo "FAIL RCON_CMDS_STARTUP not applied"; fails=1; fi
fi

# shellcheck disable=SC2317 # helper functions are called through chk
if [ "$up" = 0 ]; then
  docker logs "$name" > "$work/boot.log" 2>&1 || true
  chk() { # name command...
    local n=$1; shift
    if "$@"; then echo "PASS $n"; else echo "FAIL $n"; fails=1; fi
  }
  geyser_port() { grep -E '\[Geyser-Spigot\]' "$work/boot.log" | grep -q 19132; }
  bluemap_up() {
    for _ in $(seq 30); do
      docker exec "$name" bash -c 'exec 3<>/dev/tcp/127.0.0.1/8100' 2>/dev/null && return 0
      sleep 3
    done
    return 1
  }
  # shellcheck disable=SC2016 # literal ${CFG_ search
  no_placeholders() { ! grep -rqF '${CFG_' "$work/data/plugins" --include='*.yml' --include='*.conf' --include='*.properties'; }
  chk "voice chat listens on 24454" grep -q 'Voice chat server started at port 24454' "$work/boot.log"
  chk "Geyser uses port 19132" geyser_port
  chk "BlueMap webserver listens on 8100" bluemap_up
  chk "no unresolved CFG placeholders in plugin configs" no_placeholders
fi

[ "${1:-}" = "--keep" ] || docker rm -f "$name" >/dev/null 2>&1 || true
echo "boot log: $work/boot.log  failures: $fails"
exit "$fails"
