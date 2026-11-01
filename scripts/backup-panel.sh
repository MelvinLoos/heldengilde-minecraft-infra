#!/usr/bin/env bash
# Daily Panel state backup (DB + APP_KEY): local copy with retention, plus upload to the S3-compatible
# bucket when S3_* is configured. Worlds are NOT here: those use Pelican's own scheduled backups (ADR 0003).
# Upload uses curl's SigV4 support, so no S3 client has to be installed (works with MinIO, B2, Hetzner, ...).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$here/lib.sh"

HG_ROOT="${HG_ROOT:?}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
dir="$HG_ROOT/backups/panel"; mkdir -p "$dir"; chmod 700 "$dir"
name="panel-state-$(date -u +%Y%m%dT%H%M%SZ).tar.zst"

"$here/panel-state.sh" export "$dir/$name"

if [ -n "${S3_ENDPOINT:-}" ]; then
  curl -fsS --retry 3 -T "$dir/$name" --user "$S3_KEY:$S3_SECRET" \
    --aws-sigv4 "aws:amz:${S3_REGION:-auto}:s3" "${S3_ENDPOINT%/}/$S3_BUCKET/panel-state/$name"
  log "uploaded to s3://$S3_BUCKET/panel-state/$name"
fi
find "$dir" -name 'panel-state-*.tar.zst' -mtime "+$RETENTION_DAYS" -delete
