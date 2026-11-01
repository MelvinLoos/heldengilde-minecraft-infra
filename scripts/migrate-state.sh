#!/usr/bin/env bash
# Moves the whole Minecraft state from one Pelican host (the laptop) to another (the production server).
#
#   migrate-state.sh export [--stop] OUT_DIR   snapshot server volume + panel DB/APP_KEY into OUT_DIR
#   migrate-state.sh import [--force] IN_DIR   restore them on this host and re-point the node/mounts
#
# The server must be stopped for a consistent world; --stop does that gracefully via the Client API.
# Volumes are read and written through a throwaway container when the host user cannot touch them
# (Wings creates them as uid 988), so the laptop needs only Docker. See docs/runbooks/migrate-laptop-to-server.md.
#
# Config: HG_STACK_ENV (default /etc/hg-gitops/stack.env) must define COMPOSE_FILE STATE_DIR VOLUMES_DIR
# PANEL_URL PANEL_HOST PANEL_DB SERVER_NAME GITOPS_SRC JARS_SRC CONFIG_SRC, plus NODE_NAME for imports.
# Hooks for the Wings process: WINGS_STOP_CMD / WINGS_START_CMD (default: systemctl stop|start wings).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$here/lib.sh"

: "${VOLUMES_DIR:?}" "${SERVER_NAME:?}" "${STATE_DIR:?}"
TAR_IMAGE="${TAR_IMAGE:-alpine:3}"
WINGS_STOP_CMD="${WINGS_STOP_CMD:-systemctl stop wings}"
WINGS_START_CMD="${WINGS_START_CMD:-systemctl start wings}"

# vol_tar_out DIR: tar stream of DIR's contents on stdout, preserving numeric owners.
vol_tar_out() {
  if [ -r "$1" ] && [ -x "$1" ] && [ "$(find "$1" ! -readable -print -quit 2>/dev/null)" = "" ]; then
    tar -C "$1" --numeric-owner -cf - .
  else
    docker run --rm -v "$1:/src:ro" "$TAR_IMAGE" tar -C /src --numeric-owner -cf - .
  fi
}
# vol_tar_in DIR: extract a tar stream from stdin into DIR as the original owners.
vol_tar_in() {
  mkdir -p "$1"
  if [ "$(id -u)" = 0 ]; then
    tar -C "$1" --numeric-owner -xpf -
  else
    docker run --rm -i -v "$1:/dst" "$TAR_IMAGE" tar -C /dst --numeric-owner -xpf -
  fi
}
vol_is_empty() { [ -z "$(docker run --rm -v "$1:/v:ro" "$TAR_IMAGE" ls -A /v 2>/dev/null)" ]; }

server_row() { app_api /servers | jq -r --arg n "$SERVER_NAME" '.data[]|select(.attributes.name==$n)|"\(.attributes.uuid) \(.attributes.identifier)"' | head -1; }

do_export() {
  local stop=0 out
  [ "${1:-}" = --stop ] && { stop=1; shift; }
  out="${1:?output directory}"
  read -r uuid ident < <(server_row) || true
  [ -n "${uuid:-}" ] || die "server '$SERVER_NAME' not found in the panel"
  local state; state=$(client_api "$ident" GET /resources | jq -r .attributes.current_state)
  if [ "$state" != offline ]; then
    [ "$stop" = 1 ] || die "server is $state; stop it first or pass --stop"
    log "stopping server (graceful, saves the world)"
    client_api "$ident" POST /power -d '{"signal":"stop"}' >/dev/null
    for _ in $(seq 90); do
      [ "$(client_api "$ident" GET /resources | jq -r .attributes.current_state)" = offline ] && break
      sleep 2
    done
    [ "$(client_api "$ident" GET /resources | jq -r .attributes.current_state)" = offline ] || die "server did not stop in time"
  fi
  mkdir -p "$out"; chmod 700 "$out"
  log "snapshotting volume $VOLUMES_DIR/$uuid"
  vol_tar_out "$VOLUMES_DIR/$uuid" | zstd -q -T0 -f -o "$out/volume-$uuid.tar.zst"
  "$here/panel-state.sh" export "$out/panel-state.tar.zst"
  jq -n --arg uuid "$uuid" --arg name "$SERVER_NAME" --arg db "${PANEL_DB:-sqlite}" --arg ts "$(date -u +%FT%TZ)" \
    '{server_uuid:$uuid, server_name:$name, panel_db:$db, created:$ts}' > "$out/manifest.json"
  ( cd "$out" && sha256sum -- *.tar.zst manifest.json > SHA256SUMS )
  log "export complete: $out ($(du -sh "$out" | cut -f1))"
}

do_import() {
  local force=0 in
  [ "${1:-}" = --force ] && { force=1; shift; }
  in="${1:?input directory}"
  : "${NODE_NAME:?}" "${GITOPS_SRC:?}" "${JARS_SRC:?}" "${CONFIG_SRC:?}"
  ( cd "$in" && sha256sum --check --quiet SHA256SUMS ) || die "checksum mismatch in $in"
  local uuid; uuid=$(jq -r .server_uuid "$in/manifest.json")
  [ "$(jq -r .panel_db "$in/manifest.json")" = "${PANEL_DB:-sqlite}" ] || die "panel DB engine differs from the bundle"

  log "stopping Wings"
  eval "$WINGS_STOP_CMD"

  local vol="$VOLUMES_DIR/$uuid"
  if ! vol_is_empty "$vol" 2>/dev/null; then
    [ "$force" = 1 ] || die "$vol is not empty; pass --force to move it aside to $vol.pre-import-$(date +%s)"
    mv "$vol" "$vol.pre-import-$(date +%s)"
  fi
  log "restoring volume $uuid"
  zstd -dcq "$in/volume-$uuid.tar.zst" | vol_tar_in "$vol"

  "$here/panel-state.sh" import "$in/panel-state.tar.zst"

  # The restored DB describes the laptop. Re-point node and mounts at this host.
  log "re-pointing node '$NODE_NAME' and mounts"
  # shellcheck disable=SC2016 # PHP, not shell
  dc exec -T -u www-data \
    -e "M_NODE=$NODE_NAME" -e "M_FQDN=${NODE_FQDN:-}" -e "M_SCHEME=${NODE_SCHEME:-https}" \
    -e "M_PROXY=${NODE_BEHIND_PROXY:-1}" -e "M_CONNECT=${NODE_CONNECT_PORT:-443}" -e "M_BASE=$VOLUMES_DIR" \
    -e "M_GITOPS=$GITOPS_SRC" -e "M_JARS=$JARS_SRC" -e "M_CONFIG=$CONFIG_SRC" -e "M_SERVER=$SERVER_NAME" \
    panel php artisan tinker --execute='
      $n = App\Models\Node::query()->orderBy("id")->firstOrFail();
      $n->forceFill(["name" => getenv("M_NODE"), "scheme" => getenv("M_SCHEME"), "behind_proxy" => getenv("M_PROXY") === "1",
        "daemon_connect" => (int) getenv("M_CONNECT"), "daemon_base" => getenv("M_BASE")]);
      if (getenv("M_FQDN") !== "") { $n->fqdn = getenv("M_FQDN"); }
      $n->save();
      $s = App\Models\Server::where("name", getenv("M_SERVER"))->firstOrFail();
      foreach (App\Models\Mount::all() as $m) {
        $src = match (true) {
          str_ends_with($m->name, "-data") => getenv("M_BASE") . "/" . $s->uuid,
          str_ends_with($m->name, "-gitops") => getenv("M_GITOPS"),
          str_ends_with($m->name, "-jars") => getenv("M_JARS"),
          str_ends_with($m->name, "-config") => getenv("M_CONFIG"),
          default => $m->source,
        };
        $m->forceFill(["source" => $src])->save();
      }
      echo "node and " . App\Models\Mount::count() . " mounts updated\n";' | tail -1

  # API keys were created against the old APP_KEY/DB state of THIS host before the import; make fresh ones.
  rm -f "$STATE_DIR/app-key" "$STATE_DIR/client-key"
  "$here/panel-init.sh"

  log "starting Wings (config must be re-rendered first: ansible-playbook site.yml --tags node)"
  eval "$WINGS_START_CMD" || true
  log "import complete"
}

case "${1:-}" in
  export) shift; do_export "$@" ;;
  import) shift; do_import "$@" ;;
  *) die "usage: migrate-state.sh export [--stop] OUT_DIR | import [--force] IN_DIR" ;;
esac
