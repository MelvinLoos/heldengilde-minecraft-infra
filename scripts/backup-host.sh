#!/usr/bin/env bash
# Registers (idempotently) an S3-compatible bucket as the Panel's backup host and attaches it to a node.
# Works for MinIO, Backblaze B2, Hetzner Object Storage, ... (ADR 0007). Credentials come from env only.
#
# Required env: COMPOSE_FILE S3_ENDPOINT S3_REGION S3_BUCKET S3_KEY S3_SECRET
# Optional env: S3_PATH_STYLE (true|false, default true) NODE_NAME (default hg-local) BACKUP_HOST_NAME
set -euo pipefail

: "${COMPOSE_FILE:?}" "${S3_ENDPOINT:?}" "${S3_REGION:?}" "${S3_BUCKET:?}" "${S3_KEY:?}" "${S3_SECRET:?}"
S3_PATH_STYLE="${S3_PATH_STYLE:-true}"
NODE_NAME="${NODE_NAME:-hg-local}"
BACKUP_HOST_NAME="${BACKUP_HOST_NAME:-hg-s3}"

# Values travel as env vars into PHP so quoting never matters.
docker compose -f "$COMPOSE_FILE" exec -T -u www-data \
  -e "BH_NAME=$BACKUP_HOST_NAME" -e "BH_NODE=$NODE_NAME" -e "BH_ENDPOINT=$S3_ENDPOINT" -e "BH_REGION=$S3_REGION" \
  -e "BH_BUCKET=$S3_BUCKET" -e "BH_KEY=$S3_KEY" -e "BH_SECRET=$S3_SECRET" -e "BH_PATH=$S3_PATH_STYLE" \
  panel php artisan tinker --execute='
    $h = App\Models\BackupHost::firstOrNew(["name" => getenv("BH_NAME")]);
    $h->forceFill(["schema" => "s3", "configuration" => [
      "region" => getenv("BH_REGION"), "key" => getenv("BH_KEY"), "secret" => getenv("BH_SECRET"),
      "bucket" => getenv("BH_BUCKET"), "endpoint" => getenv("BH_ENDPOINT"),
      "use_path_style_endpoint" => getenv("BH_PATH") === "true"]])->save();
    $n = App\Models\Node::where("name", getenv("BH_NODE"))->firstOrFail();
    $n->backupHosts()->syncWithoutDetaching([$h->id]);
    echo "backup host " . $h->name . " attached to node " . $n->name . "\n";' 2>&1 | tail -1
