# ADR 0003: Single-writer content ownership

- Status: accepted
- Date: 2026-11-01

## Decision

Every path has exactly one writer. A pull-based host agent (`hg-gitops`) moves data; CI only validates.

| Content | Owner | Flow |
|---|---|---|
| Server config, plugins, custom-jar lock | Git (`heldengilde-minecraft-infra`) | Applied at next restart |
| BetonQuest packages, MythicMobs mobs/skills/items | Git (`heldengilde-minecraft-content`, PR-reviewed) | Agent `rsync --delete` into `/data`, then `bq reload` / `mm reload` through the Pelican Client API |
| Citizens `saves.yml`, MythicDungeons `dungeons/*.yml` trigger configs | Server | Agent runs `save-all` + `citizens save`, snapshots to branch `autosync/server`, auto-PR to `main`. Restore is a runbook |
| Worlds, OneWorldDungeons world, dungeon maps/schematics | Server | Pelican scheduled backups to OCI Object Storage (S3). Never in Git |

The game container gets no Git access and no tokens. The agent holds two deploy keys: read-only for infra, write for content only.

## Consequences

Removes the data-loss and privilege-escalation paths in ADR 0001 B1-B8 and C1-C3.
