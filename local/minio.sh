#!/usr/bin/env bash
# Starts local MinIO, creates the backup bucket and registers it as the Panel's backup host.
set -euo pipefail
cd "$(dirname "$0")"
export HG_ROOT="${HG_ROOT:-$HOME/hg-local}" HG_REPO="$PWD/.."
pw="${HG_MINIO_PASSWORD:-hgminio-local-only}"
docker compose --profile backup up -d minio
for _ in $(seq 30); do curl -fs -o /dev/null http://127.0.0.1:9000/minio/health/live && break; sleep 1; done
# Bucket creation with plain curl + SigV4 (no mc needed). 409 = already exists.
code=$(curl -s -o /dev/null -w '%{http_code}' -X PUT --user "hgminio:$pw" --aws-sigv4 "aws:amz:us-east-1:s3" http://127.0.0.1:9000/heldengilde-backups)
[ "$code" = 200 ] || [ "$code" = 409 ] || { echo "bucket create failed: $code" >&2; exit 1; }
COMPOSE_FILE="$PWD/compose.yml" S3_ENDPOINT=http://minio:9000 S3_REGION=us-east-1 S3_BUCKET=heldengilde-backups \
  S3_KEY=hgminio S3_SECRET="$pw" NODE_NAME=hg-local ../scripts/backup-host.sh
