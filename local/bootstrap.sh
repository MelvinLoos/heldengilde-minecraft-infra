#!/usr/bin/env bash
# Brings up the local Panel, creates admin + node, and writes the Wings config.
# Idempotent: re-running reuses existing state under HG_ROOT.
set -euo pipefail

cd "$(dirname "$0")"
export HG_ROOT="${HG_ROOT:-$HOME/hg-local}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@heldengilde.local}"
ADMIN_PASS="${ADMIN_PASS:-$(cat "$HG_ROOT/admin-password" 2>/dev/null || openssl rand -hex 12)}"

mkdir -p "$HG_ROOT"/{etc,lib,tmp,log,gitops,custom-jars,config}
(umask 077; echo "$ADMIN_PASS" > "$HG_ROOT/admin-password")  # panel-init.sh reads it

docker compose up -d panel

# Schema, admin, node, API keys and the Wings config: shared with the server (Ansible pelican_panel).
COMPOSE_FILE="$PWD/compose.yml" STATE_DIR="$HG_ROOT" ADMIN_EMAIL="$ADMIN_EMAIL" \
  NODE_NAME=hg-local NODE_FQDN=wings NODE_SCHEME=http NODE_BEHIND_PROXY=0 NODE_PORT=8080 \
  NODE_MEM_MB="${NODE_MEM_MB:-49152}" NODE_DISK_MB="${NODE_DISK_MB:-102400}" \
  VOLUMES_DIR="$HG_ROOT/lib/volumes" PANEL_DB=sqlite \
  ../scripts/panel-init.sh
cp "$HG_ROOT/wings-config.yml" "$HG_ROOT/etc/config.yml"
echo "wrote $HG_ROOT/etc/config.yml"

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
