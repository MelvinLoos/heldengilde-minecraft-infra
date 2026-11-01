# shellcheck shell=bash
# Shared helpers for scripts/. Source it; do not execute.
# Loads the stack description written by Ansible (or local/stack.env on the laptop):
#   COMPOSE_FILE STATE_DIR PANEL_URL PANEL_HOST PANEL_DB VOLUMES_DIR GITOPS_SRC JARS_SRC SERVER_NAME NODE_* ...
for _f in "${HG_STACK_ENV:-/etc/hg-gitops/stack.env}" "${HG_BACKUP_ENV:-/etc/hg-gitops/backup.env}"; do
  # shellcheck disable=SC1090
  if [ -f "$_f" ]; then set -a; . "$_f"; set +a; fi
done
unset _f

log() { printf '%s %s: %s\n' "$(date -u +%FT%TZ)" "$(basename "$0")" "$*"; }
die() { log "ERROR: $*" >&2; exit 1; }

dc() { docker compose -f "${COMPOSE_FILE:?COMPOSE_FILE not set}" "$@"; }
artisan() { dc exec -T -u www-data panel php artisan "$@"; }

app_api() { # path [curl args]
  local p=$1; shift
  curl -fsS -H "Host: ${PANEL_HOST:-panel}" -H "Authorization: Bearer $(cat "${STATE_DIR:?}/app-key")" \
    -H "Accept: application/json" "${PANEL_URL:-http://127.0.0.1:8081}/api/application$p" "$@"
}
client_api() { # identifier method path [curl args]
  local id=$1 m=$2 p=$3; shift 3
  curl -fsS -X "$m" -H "Host: ${PANEL_HOST:-panel}" -H "Authorization: Bearer $(cat "${STATE_DIR:?}/client-key")" \
    -H "Accept: application/json" -H "Content-Type: application/json" \
    "${PANEL_URL:-http://127.0.0.1:8081}/api/client/servers/$id$p" "$@"
}
