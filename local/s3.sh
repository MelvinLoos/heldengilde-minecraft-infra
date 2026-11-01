#!/usr/bin/env bash
# Starts the local S3-compatible store (SeaweedFS), creates the backup bucket and registers it as the
# Panel's backup host. Works the same against any S3 endpoint (B2, Hetzner Object Storage, ...).
set -euo pipefail
cd "$(dirname "$0")"
export HG_ROOT="${HG_ROOT:-$HOME/hg-local}"
secret="${HG_S3_SECRET:-hgs3-local-only}"
docker compose --profile backup up -d s3
for _ in $(seq 40); do curl -s -o /dev/null http://127.0.0.1:8333/ && break; sleep 1; done
# Bucket creation with plain curl + SigV4 (no S3 client needed). 409 = already exists.
code=$(curl -s -o /dev/null -w '%{http_code}' -X PUT --user "hgs3:$secret" --aws-sigv4 "aws:amz:us-east-1:s3" http://127.0.0.1:8333/heldengilde-backups)
[ "$code" = 200 ] || [ "$code" = 409 ] || { echo "bucket create failed: $code" >&2; exit 1; }
COMPOSE_FILE="$PWD/compose.yml" S3_ENDPOINT=http://s3:8333 S3_REGION=us-east-1 S3_BUCKET=heldengilde-backups \
  S3_KEY=hgs3 S3_SECRET="$secret" NODE_NAME=hg-local ../scripts/backup-host.sh
