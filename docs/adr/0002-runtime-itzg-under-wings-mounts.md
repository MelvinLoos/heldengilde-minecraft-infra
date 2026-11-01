# ADR 0002: Runtime: itzg under Wings via Pelican Mounts

- Status: proposed (pending the Phase 1 spike result)
- Date: 2026-11-01

## Context

Wings creates containers without `Cmd`/`Entrypoint`, mounts the server volume at `/home/container`, runs as `988:988` with a read-only rootfs, and removes anonymous volumes on recreate. itzg keeps its state in `/data` (see ADR 0001 A1, A2).

## Decision

Use `itzg/minecraft-server` with Pelican Mounts:

| Host source | Container target | Mode |
|---|---|---|
| `/var/lib/pelican/volumes/<uuid>` | `/data` | rw |
| `/srv/heldengilde/gitops` | `/gitops` | ro |
| `/srv/heldengilde/custom-jars` | `/plugins` | ro |

All config is delivered through egg variables and itzg-native features (`MODRINTH_PROJECTS=@file`, `PLUGINS`, `/config` sync, `PATCH_DEFINITIONS`, `RCON_CMDS_STARTUP`). No custom start script, no Git inside the container.

## Spike (Phase 1)

Must pass: persistent `/data` bind with no anonymous volume; container user `988:988` with `UID`/`GID=988` and no chown/gosu/setpriv attempt; `Done` detection and graceful stop; world survives container recreate; plugin, custom-jar, config-sync, interpolation and patch features work; file manager and backups see the data.

## Fallback

Pelican's standard Paper yolk egg, with plugin installs handled by the host agent.

## Result

_To be filled in after the spike._
