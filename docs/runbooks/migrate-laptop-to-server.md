# Runbook: migrate the laptop world to the production server

Moves the Minecraft server volume and the Panel state (database, `APP_KEY`) from the laptop stack in `local/` to a host provisioned by `3-ansible/`. Tested path: laptop export, then import into a fresh panel stack (see "Verification").

## What moves

| Item | Where it lives | Moves via |
|---|---|---|
| World, plugin data, configs generated at runtime | `<VOLUMES_DIR>/<server-uuid>/` | `volume-<uuid>.tar.zst` (numeric owners kept, uid 988) |
| Panel database (servers, mounts, egg, allocations, users) and `.env` with `APP_KEY` | Panel container | `panel-state.tar.zst` |
| Plugin pins, configs, custom jars | Git / jar lock | Not moved: the server gets them from the infra repo and the jar lock |

The bundle contains secrets (`APP_KEY` encrypts API keys and node tokens). Keep it private and delete it after the import. Panel DB engines must match (SQLite on both is the default).

## Steps

**1. On the laptop: export** (stops the server gracefully, so the world is saved):

```bash
export HG_ROOT=$HOME/hg-local HG_REPO=$PWD
set -a; . local/stack.env; set +a      # zsh/bash: expands $HG_ROOT / $HG_REPO
HG_STACK_ENV=local/stack.env scripts/migrate-state.sh export --stop ~/hg-migration-$(date +%F)
```

**2. Prepare the target.** From the laptop, with the target in `3-ansible/inventory/production.yml`:

```bash
cd 3-ansible
ansible-playbook -i inventory/production.yml site.yml -e hg_provision_server=false
```

This builds the host, Docker, Wings, Panel and Caddy, and creates an empty node, but no server. Put the premium jar on the controller (`hg_premium_jars`) so it lands in `/srv/heldengilde/custom-jars`.

**3. Copy the bundle** (the volume is owned by uid 988, so the copy lands as the bundle only):

```bash
rsync -a ~/hg-migration-2026-11-01/ hgadmin@server:/home/hgadmin/hg-migration/
```

**4. On the server: import** (as root; stops Wings, restores volume and panel state, re-points node and mounts, creates fresh API keys):

```bash
sudo /srv/heldengilde/gitops/scripts/migrate-state.sh import /home/hgadmin/hg-migration
```

**5. Re-render the Wings config and start everything:**

```bash
cd 3-ansible
ansible-playbook -i inventory/production.yml site.yml --tags node,server,agent,backups
```

**6. Check**, then delete the bundle on both machines:

- Log in to the Panel. The admin account is the **laptop's** (the import replaced the database); change its password.
- The server shows under the node, starts, and `/data` has your world.
- Players connect on the real address; `hg-gitops` timers are active (`systemctl list-timers 'hg-*'`).

## Notes and limits

- The server's `server.properties` and plugin data came from the laptop. Settings from `4-server/env/server.env` are re-applied by itzg at every start, so the server converges on Git state.
- Resource limits (memory, disk) in the Panel database are the laptop's; adjust them in the Panel if the server has less RAM.
- Allocations keep their ports. If the real address differs, Java/Bedrock clients only need the new hostname.
- `--force` on import moves a non-empty target volume aside (`<uuid>.pre-import-<epoch>`) instead of overwriting it. Nothing is deleted.
- Cross-engine (SQLite to MariaDB) migration is not supported.
