#!/usr/bin/env bash
# hg-gitops: pull-based host agent (ADR 0003). Runs from systemd timers as root on the host;
# the game container never gets Git access or tokens.
#
#   sync-infra               fast-forward the infra checkout (read-only deploy key); jars if the lock changed
#   sync-custom-jars         fetch + sha256-verify the jars from custom-jars.lock.json
#   deploy-content           content repo main -> server volume (rsync --delete on Git-owned dirs), then reload plugins
#   snapshot-server-content  server-owned YAML -> branch autosync/server of the content repo (a CI workflow opens the PR)
#   sync                     sync-infra, deploy-content (what the frequent timer runs)
#
# Config: /etc/hg-gitops/agent.env (override with HG_AGENT_ENV).
set -euo pipefail

# shellcheck disable=SC1090
. "${HG_AGENT_ENV:-/etc/hg-gitops/agent.env}"
: "${HG_ROOT:?}" "${HG_VOLUMES_DIR:?}" "${HG_SERVER_NAME:?}"
STATE="${HG_STATE_DIR:-$HG_ROOT/state}"
GITOPS="$HG_ROOT/gitops"
CONTENT="$HG_ROOT/content"
AUTOSYNC="$HG_ROOT/content-autosync"
PANEL_URL="${HG_PANEL_URL:-http://127.0.0.1:8081}"
PANEL_HOST="${HG_PANEL_HOST:-panel}"
SERVER_UID="${HG_SERVER_UID:-988}"
SERVER_GID="${HG_SERVER_GID:-988}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { printf '%s hg-gitops: %s\n' "$(date -u +%FT%TZ)" "$*"; }
die() { log "ERROR: $*" >&2; exit 1; }

git_ssh() { # key
  if [ -s "$1" ]; then echo "ssh -i $1 -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"; else echo ssh; fi
}

# Clones or hard-resets DIR to origin/BRANCH. Prints "changed" on stdout when HEAD moved.
git_pull() { # dir repo branch keyfile
  local dir=$1 repo=$2 branch=$3 key=$4 before="" after=""
  export GIT_SSH_COMMAND; GIT_SSH_COMMAND="$(git_ssh "$key")"
  if [ ! -d "$dir/.git" ]; then
    git clone --quiet --branch "$branch" "$repo" "$dir"
    echo changed; return
  fi
  before=$(git -C "$dir" rev-parse HEAD)
  git -C "$dir" fetch --quiet origin "$branch"
  git -C "$dir" reset --quiet --hard "origin/$branch"
  after=$(git -C "$dir" rev-parse HEAD)
  [ "$before" = "$after" ] || echo changed
}

# --- Pelican API ---------------------------------------------------------------------------------
server_info() { # prints "<uuid> <identifier>"
  curl -fsS -H "Host: $PANEL_HOST" -H "Authorization: Bearer $(cat "$STATE/app-key")" -H "Accept: application/json" \
    "$PANEL_URL/api/application/servers" \
    | jq -r --arg n "$HG_SERVER_NAME" '.data[]|select(.attributes.name==$n)|"\(.attributes.uuid) \(.attributes.identifier)"' | head -1
}
client() { # method path [curl args]
  local m=$1 p=$2; shift 2
  curl -fsS -X "$m" -H "Host: $PANEL_HOST" -H "Authorization: Bearer $(cat "$STATE/client-key")" \
    -H "Accept: application/json" -H "Content-Type: application/json" "$PANEL_URL/api/client/servers/$IDENT$p" "$@"
}
is_running() { [ "$(client GET /resources | jq -r .attributes.current_state)" = running ]; }
console() { client POST /command -d "$(jq -nc --arg c "$1" '{command:$c}')" >/dev/null; }

resolve_server() {
  read -r UUID IDENT < <(server_info) || true
  [ -n "${UUID:-}" ] || die "server '$HG_SERVER_NAME' not found in the panel"
  VOL="$HG_VOLUMES_DIR/$UUID"
  [ -d "$VOL" ] || die "volume $VOL does not exist yet (server not installed?)"
}

# --- Subcommands ---------------------------------------------------------------------------------
cmd_sync_custom_jars() {
  "$HERE/fetch-custom-jars.sh" "$GITOPS/4-server/custom-jars.lock.json" "$HG_ROOT/custom-jars" --allow-missing-premium
}

cmd_sync_infra() {
  if [ ! -d "$GITOPS/.git" ]; then log "infra checkout is not a Git repo (rsync mode), skipping"; return; fi
  local lock_before lock_after
  lock_before=$(sha256sum "$GITOPS/4-server/custom-jars.lock.json" | cut -d' ' -f1)
  if [ "$(git_pull "$GITOPS" "" "${HG_INFRA_BRANCH:-main}" "$STATE/deploy_infra")" = changed ]; then
    log "infra updated to $(git -C "$GITOPS" rev-parse --short HEAD); config applies at the next server restart"
  fi
  lock_after=$(sha256sum "$GITOPS/4-server/custom-jars.lock.json" | cut -d' ' -f1)
  [ "$lock_before" = "$lock_after" ] || cmd_sync_custom_jars
}

# rsync SRC/ DEST/ --delete, keeping the server user as owner.
mirror() { # src dest
  mkdir -p "$2"
  rsync -a --delete --chown="$SERVER_UID:$SERVER_GID" "$1/" "$2/"
}

cmd_deploy_content() {
  : "${HG_CONTENT_REPO:?}"
  local changed; changed=$(git_pull "$CONTENT" "$HG_CONTENT_REPO" "${HG_CONTENT_BRANCH:-main}" "$STATE/deploy_content")
  if [ -z "$changed" ] && [ -f "$STATE/content-deployed" ]; then return; fi
  resolve_server
  local sha; sha=$(git -C "$CONTENT" rev-parse HEAD)
  # Git-owned directories only. Everything the server owns is left alone (ADR 0003).
  # Git does not track empty directories, so a missing source dir means "nothing left": mirror an empty
  # dir so deletions propagate (B4). The checkout is known good here (git_pull just succeeded).
  empty=$(mktemp -d)
  mirror_or_empty() { mirror "$([ -d "$1" ] && echo "$1" || echo "$empty")" "$2"; }
  mirror_or_empty "$CONTENT/BetonQuest/QuestPackages" "$VOL/plugins/BetonQuest/QuestPackages"
  for d in Mobs Skills Items; do
    mirror_or_empty "$CONTENT/MythicMobs/$d" "$VOL/plugins/MythicMobs/$d"
  done
  rmdir "$empty"
  echo "$sha" > "$STATE/content-deployed"
  log "deployed content ${sha:0:8}"
  if is_running; then
    console "q reload"; console "mm reload"
    log "reloaded BetonQuest and MythicMobs"
  else
    log "server not running; plugins read the content at next start"
  fi
}

# Server-owned files that are small YAML and worth versioning. Worlds and schematics go to S3 backups.
snapshot_files() { # volume -> list of relative paths on stdout
  ( cd "$1" && {
      [ -f plugins/Citizens/saves.yml ] && echo plugins/Citizens/saves.yml
      find plugins/MythicDungeons/maps -mindepth 2 -maxdepth 2 -name '*.yml' 2>/dev/null
      find plugins/MythicDungeons/loottables -name '*.yml' 2>/dev/null
    } | sort )
}

cmd_snapshot_server_content() {
  : "${HG_CONTENT_REPO:?}"
  resolve_server
  if is_running; then
    console "save-all flush"; console "citizens save"
    sleep "${HG_SAVE_WAIT:-5}"
  fi
  export GIT_SSH_COMMAND; GIT_SSH_COMMAND="$(git_ssh "$STATE/deploy_content")"
  if [ ! -d "$AUTOSYNC/.git" ]; then git clone --quiet "$HG_CONTENT_REPO" "$AUTOSYNC"; fi
  git -C "$AUTOSYNC" fetch --quiet origin
  local main="${HG_CONTENT_BRANCH:-main}"
  # autosync/server is rebuilt from main each time, so it is always main + one snapshot commit.
  git -C "$AUTOSYNC" checkout --quiet -B autosync/server "origin/$main"
  local dest="$AUTOSYNC/server-owned"
  rm -rf "$dest/Citizens" "$dest/MythicDungeons"
  mkdir -p "$dest"
  snapshot_files "$VOL" | while read -r rel; do
    target="$dest/${rel#plugins/}"; mkdir -p "$(dirname "$target")"; cp "$VOL/$rel" "$target"
  done
  git -C "$AUTOSYNC" add -A server-owned
  if git -C "$AUTOSYNC" diff --cached --quiet; then log "no server-owned changes to snapshot"; return; fi
  git -C "$AUTOSYNC" -c user.name=hg-gitops -c user.email=hg-gitops@localhost \
    commit --quiet -m "chore(autosync): snapshot of server-owned content"
  # Skip the push when the remote branch already has the same snapshot on the same base, so an unchanged
  # server does not re-trigger the PR workflow every night.
  if [ "$(git -C "$AUTOSYNC" rev-parse -q --verify "origin/autosync/server^{tree}" || true)" = "$(git -C "$AUTOSYNC" rev-parse 'HEAD^{tree}')" ] \
     && [ "$(git -C "$AUTOSYNC" rev-parse -q --verify origin/autosync/server~1 || true)" = "$(git -C "$AUTOSYNC" rev-parse HEAD~1)" ]; then
    log "snapshot already pushed, nothing new"; return
  fi
  git -C "$AUTOSYNC" push --quiet --force origin autosync/server
  log "pushed autosync/server ($(git -C "$AUTOSYNC" rev-parse --short HEAD)); the content repo workflow opens the PR"
}

main() {
  mkdir -p "$STATE"
  exec 9>"$STATE/hg-gitops.lock"
  flock -n 9 || { log "another hg-gitops run is active, skipping"; exit 0; }
  case "${1:-}" in
    sync-infra) cmd_sync_infra ;;
    sync-custom-jars) cmd_sync_custom_jars ;;
    deploy-content) cmd_deploy_content ;;
    snapshot-server-content) cmd_snapshot_server_content ;;
    sync) cmd_sync_infra; cmd_deploy_content ;;
    *) die "usage: hg-gitops.sh sync-infra|sync-custom-jars|deploy-content|snapshot-server-content|sync" ;;
  esac
}
main "$@"
