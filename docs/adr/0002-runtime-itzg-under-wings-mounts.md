# ADR 0002: Runtime: itzg under Wings via Pelican Mounts

- Status: accepted (Phase 1 spike passed on 2026-11-01)
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

**GO.** `local/spike-test.sh` passes 23/23 checks against Pelican Panel `v1.0.0-beta38` and Wings `v1.0.0-beta29`, running `itzg/minecraft-server:java25` with Paper 26.3-235 on Java 25.0.5.

Verified:

- Wings starts the container as `988:988` with a read-only rootfs and `no-new-privileges`. With `UID=988`/`GID=988` set, itzg skips its root branch: no chown/gosu/setpriv error appears in the log.
- `/data` is a Pelican Mount (bind) onto the server volume, there are no anonymous volumes, and the world (same seed, marker block) survives a container recreate.
- Wings detects `Done`, and a console `stop` is graceful and saves the world.
- `MODRINTH_PROJECTS=@/gitops/...` installs LuckPerms and packetevents for 26.3.
- Files in the read-only `/plugins` mount are copied into `/data/plugins`.
- `/config` sync with `${CFG_*}` interpolation works, and a newer hand-edited file in `/data` is overwritten (Git wins).
- The Pelican file manager lists the data and a Pelican backup contains it.

### Required settings and gotchas found by the spike

1. `COPY_CONFIG_DEST=/data`. By default itzg syncs `/config` into `/data/config`, not `/data`.
2. `SYNC_SKIP_NEWER_IN_DESTINATION=false`. By default a newer file in `/data` wins over `/config`, which would silently break "Git owns Zone 1".
3. **Interpolated secrets land on disk** in `/data` (confirms ADR 0001 C4), so they end up in Pelican backups.
4. **`POST /api/application/mounts` is broken in panel v1.0.0-beta38**: `StoreMountRequest` has no rules, so all fields are dropped and the insert fails. Create mounts through `artisan tinker` (see `local/spike/provision.sh`) until fixed upstream. Attaching mounts to servers also goes through tinker.
5. The Application API egg import takes the **raw request body** (YAML or JSON), not a multipart upload. The egg `meta.version` must be `PLCN_v3`.
6. The panel image needs `DB_CONNECTION=sqlite` and `DB_DATABASE=...` once installed, otherwise its entrypoint waits for a MySQL server forever. Caddy's listener comes from `APP_URL`, so `APP_URL` must use the real host name.
7. Wings also mounts a generated `/etc/passwd`, `/etc/group` and a machine-id file into every server container. These are a Wings concern in production, but when Wings itself runs in a container (only in the local stack), `system.user.passwd.directory` and `system.machine_id.directory` must be host paths that exist at the same path inside Wings.
8. Mount sources must be listed in Wings' `allowed_mounts`.
9. Premium jars (MythicDungeons 2.0.1+) were not exercised: only a dummy file went through the `/plugins` sync. Test the real jar in Phase 2.
10. A world needs `forceload` before `setblock` via RCON when no player is online.

### Not yet verified

- Behaviour on an arm64 host (the spike ran on amd64; both `java25` images are multi-arch).
- `RCON_CMDS_STARTUP`, `PATCH_DEFINITIONS` and the `?`-optional Modrinth entries (planned for Phase 2).
