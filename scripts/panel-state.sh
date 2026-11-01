#!/usr/bin/env bash
# Exports or imports the Panel's own state: the database and /pelican-data/.env (it holds APP_KEY, which
# encrypts API keys and node tokens, so the two must travel together).
#   panel-state.sh export OUT.tar.zst
#   panel-state.sh import IN.tar.zst
# The bundle contains secrets: keep it private. A bundle can only be imported into the same DB engine.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$here/lib.sh"

PANEL_DB="${PANEL_DB:-sqlite}"
mode="${1:?export|import}"; file="${2:?bundle file}"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

wait_panel() {
  for _ in $(seq 60); do
    curl -fs -o /dev/null -H "Host: ${PANEL_HOST:-panel}" "${PANEL_URL:-http://127.0.0.1:8081}/" && return 0
    sleep 2
  done
  die "panel did not come back"
}

case "$mode" in
  export)
    dc exec -T -u www-data panel cat /pelican-data/.env > "$work/panel.env"
    if [ "$PANEL_DB" = sqlite ]; then
      # VACUUM INTO gives a consistent snapshot while the panel is running.
      dc exec -T -u www-data panel sh -c 'rm -f /tmp/snap.sqlite; php -r '"'"'(new PDO("sqlite:/pelican-data/database/database.sqlite"))->exec("VACUUM INTO \"/tmp/snap.sqlite\"");'"'"'; cat /tmp/snap.sqlite; rm -f /tmp/snap.sqlite' > "$work/db.sqlite"
    else
      # shellcheck disable=SC2016 # expanded inside the db container
      dc exec -T db sh -c 'mariadb-dump -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" --single-transaction --routines "$MARIADB_DATABASE"' > "$work/db.sql"
    fi
    jq -n --arg db "$PANEL_DB" --arg ts "$(date -u +%FT%TZ)" '{panel_db:$db, created:$ts}' > "$work/meta.json"
    tar -C "$work" -cf - . | zstd -q -T0 -o "$file" -f
    chmod 600 "$file"
    log "exported panel state to $file ($(du -h "$file" | cut -f1))"
    ;;
  import)
    tar -C "$work" --zstd -xf "$file"
    [ "$(jq -r .panel_db "$work/meta.json")" = "$PANEL_DB" ] \
      || die "bundle uses $(jq -r .panel_db "$work/meta.json") but this stack uses $PANEL_DB; cross-engine import is not supported"
    dc stop panel
    if [ "$PANEL_DB" = sqlite ]; then
      dc cp "$work/db.sqlite" panel:/pelican-data/database/database.sqlite
      dc cp "$work/panel.env" panel:/pelican-data/.env
      dc run --rm --no-deps -u root --entrypoint chown panel www-data:www-data \
        /pelican-data/database/database.sqlite /pelican-data/.env
      dc start panel
    else
      dc up -d db
      # shellcheck disable=SC2016 # expanded inside the db container
      dc exec -T db sh -c 'mariadb -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE"' < "$work/db.sql"
      dc cp "$work/panel.env" panel:/pelican-data/.env
      dc run --rm --no-deps -u root --entrypoint chown panel www-data:www-data /pelican-data/.env
      dc start panel
    fi
    wait_panel
    artisan migrate --force >/dev/null
    log "imported panel state from $file"
    ;;
  *) die "usage: panel-state.sh export|import FILE" ;;
esac
