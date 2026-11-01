# Runbook: backups and restores

## What is backed up, where

| Data | Mechanism | Destination | Schedule |
|---|---|---|---|
| Worlds, OneWorldDungeons world, dungeon maps | Pelican backups (`feature_limits.backups`) | S3-compatible bucket registered by `scripts/backup-host.sh` | Pelican schedule per server (create one in the Panel: daily, keep 7) |
| Panel database + `APP_KEY` | `scripts/backup-panel.sh` (systemd `hg-backup-panel.timer`) | `/srv/heldengilde/backups/panel/` and `s3://<bucket>/panel-state/` | daily 03:30, local retention `hg_db_dump_retention_days` |
| Citizens, MythicDungeons YAML | `hg-gitops snapshot-server-content` | branch `autosync/server` of the content repo | daily 04:00 |
| Config, plugin pins | Git | infra repo | n/a |

S3 endpoints: MinIO locally (`local/minio.sh`), and for production any S3-compatible service (Backblaze B2, Hetzner Object Storage, ...): set `hg_s3_endpoint`, `hg_s3_region`, `hg_s3_bucket`, `hg_s3_path_style` and the `hg_s3_key`/`hg_s3_secret` secrets. The `APP_KEY` travels inside the panel bundle, so use a private bucket (and a bucket-side encryption policy if the provider offers one).

## Restore the world

1. Panel, server, **Backups**, pick the backup, **Restore** (stops the server first). Pelican downloads from S3 and unpacks over `/data`.
2. Start the server and check `latest.log`.

## Restore the Panel (database lost)

```bash
# On the host. Pick a bundle from /srv/heldengilde/backups/panel/ or download one from the bucket.
sudo /srv/heldengilde/gitops/scripts/panel-state.sh import /path/panel-state-<ts>.tar.zst
sudo rm /srv/heldengilde/state/app-key /srv/heldengilde/state/client-key
sudo env "$(cat /etc/hg-gitops/stack.env | xargs)" /srv/heldengilde/gitops/scripts/panel-init.sh
```

## Restore content the server owns

Open the PR `autosync/server` history in the content repo and check out the files you need into `server-owned/`; then copy them to the server volume while the server is stopped (the agent never writes these paths back).

## Test the restore regularly

Run `local/minio.sh`, create a backup of the local server in the Panel, and restore it into a second server. A backup you have never restored is a guess.
