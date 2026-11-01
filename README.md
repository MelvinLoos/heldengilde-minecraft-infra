# heldengilde-minecraft-infra

GitOps for the Heldengilde Minecraft server on any Ubuntu 24.04 host (`x86_64` or `arm64`: laptop test VM, spare PC at home, or a cloud VM): Ansible, Pelican Panel + Wings, and `itzg/minecraft-server` (Paper 26.2 now, 26.3 once CoreProtect supports it; Java 25). Oracle Cloud was dropped, see [ADR 0007](docs/adr/0007-provider-agnostic-ubuntu-hosts.md).

Quest and NPC content lives in the separate `heldengilde-minecraft-content` repo.

## Layout

| Path | Purpose |
|---|---|
| `1-host-bootstrap/` | Ansible role for a fresh Ubuntu 24.04 host: hardening, ufw + `DOCKER-USER`, Docker, Wings, optional Cloudflare Tunnel / Playit.gg |
| `3-ansible/` | `site.yml`: Panel + Caddy, Wings node, server, `hg-gitops` agent, backups. Inventory is the only thing that changes per host |
| `scripts/` | Host-agnostic scripts shared by laptop and server: `panel-init`, `provision-server`, `backup-host`, `backup-panel`, `panel-state`, `migrate-state` |
| `4-server/` | Server definition: plugins, jar lock, config, generated egg |
| `agent/` | `hg-gitops` host agent (systemd timers) and the jar fetcher |
| `local/` | Laptop Pelican + Wings (+ SeaweedFS S3) stack, spike tests, and `target/` (a systemd Ubuntu 24.04 container to test the Ansible roles) |
| `.github/workflows/` | CI: lint, egg-in-sync check, secret scan, boot test |
| `docs/adr/` | Architecture decisions (start with 0001) |
| `docs/runbooks/` | Laptop-to-server migration, backups and restores |
| `docs/implementation-plan.md` | Phases and their verification |
| `docs/design/` | Original design docs, superseded in part by the ADRs |

## Status

Phases 0-8 are done and verified locally (see [the plan](docs/implementation-plan.md)). Not yet exercised: a real server or home PC, arm64, the GitHub workflow (this repo has no remote), and a real DiscordSRV token.

## Run it on your laptop

Needs Docker (with the compose plugin) and about 25 GB of free RAM for the server (16 GB heap).

**1. Once: make `panel` and `wings` resolve to your machine.** The Panel and the browser console use those hostnames.

```bash
echo '127.0.0.1 panel wings' | sudo tee -a /etc/hosts
```

**2. Start the stack and create the server.**

```bash
export HG_ROOT=$HOME/hg-local HG_REPO=$PWD
local/bootstrap.sh                                   # Panel + admin + node + Wings (a few minutes)

# Files the server mounts: the repo, the pinned jars, and the premium MythicDungeons jar
mkdir -p $HG_ROOT/gitops $HG_ROOT/premium
cp /path/to/MythicDungeons-2.1.0.jar $HG_ROOT/premium/          # never committed
rsync -a --delete --exclude .git --exclude '*.jar' ./ $HG_ROOT/gitops/
HG_PREMIUM_DIR=$HG_ROOT/premium agent/fetch-custom-jars.sh 4-server/custom-jars.lock.json $HG_ROOT/custom-jars
chmod -R a+rX $HG_ROOT/custom-jars

set -a; . local/stack.env; set +a
CONFIG_SRC=$HG_ROOT/gitops/4-server/config SERVER_PORT=25565 scripts/provision-server.sh
```

`bootstrap.sh` and `provision-server.sh` are safe to re-run. Steps 1-2 were verified piecemeal (the Panel and node bootstrap, the provisioning script on a fresh host, the jar fetch), but this exact laptop sequence has not been run from an empty `$HG_ROOT` since the last changes.

**3. Open the Panel and start the server.**

| What | URL / address | Login |
|---|---|---|
| **Panel** (start, stop, console, files, backups) | http://panel:8081 | `admin@heldengilde.local`, password in `$HG_ROOT/admin-password` |
| **Panel admin area** (nodes, eggs, mounts, backup hosts) | http://panel:8081/admin | same |
| **Minecraft (Java)** | `localhost:25565` (the port you gave `SERVER_PORT`) | Minecraft 1.21.x or newer client (ViaVersion), online-mode account |
| Wings API | http://wings:8080 | not for browsers; the Panel console connects to it |
| Local S3 for backups (only after `local/s3.sh`) | http://127.0.0.1:8333 | API only, key `hgs3` |

In the Panel: open the server, press **Start**, and wait for `Done` in the console (about 30 s on later starts; the first start downloads the image and plugins). Then join `localhost:25565` in Minecraft. First start of a world takes longer.

Not wired up yet locally: **Bedrock** (UDP 19132), **voice chat** (UDP 24454) and **BlueMap** (port 8100) need extra Pelican allocations that the provisioning script does not create yet. On a server, BlueMap is published at `https://<hg_bluemap_domain>` behind a password once that allocation exists.

**Day to day**

| I want to... | Do this |
|---|---|
| Stop or restart the server | Panel, server, **Stop** / **Restart** (a stop saves the world) |
| Change server settings or plugins | Edit `4-server/` (see below), copy to `$HG_ROOT/gitops` with the `rsync` line above, **Restart** |
| Take a backup | Panel, server, **Backups**. Local S3 target: `local/s3.sh` once |
| Stop everything | `docker compose -f local/compose.yml --profile wings down` (volumes and worlds are kept) |
| Start everything again | `docker compose -f local/compose.yml --profile wings up -d` |
| Move this world to a server | [Migration runbook](docs/runbooks/migrate-laptop-to-server.md) |

## Run it on a real server

You need an Ubuntu 24.04 host with SSH access (cloud VM, or a PC at home), a domain with DNS for `panel.<domain>` and `wings.<domain>` pointing at it (home PC with a tunnel: see `1-host-bootstrap/README.md`), and `ansible` on your laptop.

```bash
cd 3-ansible
ansible-galaxy collection install -r requirements.yml
cp inventory/production.yml.example inventory/production.yml     # set host, domains, SSH key, S3
ansible-playbook -i inventory/production.yml site.yml
```

| What | URL / address | Login |
|---|---|---|
| **Panel** | `https://panel.<domain>` | `hg_admin_email`; password in `/srv/heldengilde/state/admin-password` on the host (change it after first login) |
| **Wings** (the browser console connects here) | `https://wings.<domain>` | not for browsing |
| **BlueMap** | `https://<hg_bluemap_domain>` (if set) | user `heldengilde`, password from `hg_bluemap_basicauth_hash` |
| **Minecraft (Java)** | `<domain>:25565` | |
| Voice chat / Bedrock | UDP 24454 / UDP 19132 (ports are opened, allocations still to do) | |

The agent then keeps the host in sync every 5 minutes: infra repo changes apply at the next server restart, content-repo changes (quests, mobs) are deployed and reloaded without a restart, and server-owned YAML is snapshotted nightly to the `autosync/server` branch. Check it with `systemctl list-timers 'hg-*'` and `journalctl -u 'hg-gitops@*'` on the host.

To rehearse the exact playbook on your laptop first: `local/target/up.sh`, then `ansible-playbook -i inventory/laptop-test.yml site.yml` (Panel at `http://panel.test` inside that container only), and `local/agent-e2e.sh` to test the agent.

## Local spike

```bash
export HG_ROOT=$HOME/hg-local
local/bootstrap.sh          # panel + admin + node + Wings
local/spike/provision.sh    # egg, allocation, server, mounts
local/spike-test.sh         # PASS/FAIL checks for the runtime
```

## Server definition (`4-server/`)

| File | Purpose |
|---|---|
| `env/server.env` | Non-secret server settings; single source for the egg and the boot test |
| `plugins.txt` | Modrinth plugins, pinned, for the active Minecraft version (26.2) |
| `plugins-26.3.txt` | Upgrade candidate for 26.3 |
| `custom-jars.lock.json` | Non-Modrinth and premium jars, pinned by sha256 (never committed) |
| `config/` | Files synced into `/data` before start (Git wins) |
| `egg.yaml` | Generated by `build-egg.sh`; do not edit |

```bash
4-server/build-egg.sh > 4-server/egg.yaml          # regenerate after editing env/server.env
HG_PREMIUM_DIR=<dir with MythicDungeons-2.1.0.jar> local/boot-test.sh   # omit the dir in CI
```

## Checks

```bash
pipx install pre-commit yamllint && pre-commit install   # once
local/lint.sh              # same checks CI runs (yamllint, shellcheck, egg in sync, jar lock, pins)
local/boot-test.sh         # boots the server definition in Docker (~3 min)
```

CI (`.github/workflows/validate.yml`) runs lint, a full-history gitleaks scan and the boot test without the premium jar. It only validates; it never deploys. It has been linted with `actionlint` but has not yet run on GitHub, because this repo has no remote.

