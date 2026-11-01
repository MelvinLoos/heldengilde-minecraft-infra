# ADR 0007: Provider-agnostic Ubuntu hosts (OCI dropped)

Status: accepted. Supersedes the OCI parts of the masterplan, ADR 0001 section F and the Phase 4/5 plan (OpenTofu + cloud-init).

## Context

Oracle Cloud account reliability is a blocker (F2: reclaimed instances, out-of-capacity A1). The first world, Spawn Hub, NPCs and dungeons will be built on the developer's 64 GB laptop. Production will later be either an on-premise spare PC or a generic cloud VM (non-profit grant, Hetzner). Both run Ubuntu 24.04 LTS on `x86_64` or `arm64`.

## Decision

1. **No cloud-specific IaC.** `1-terraform/` and `2-cloud-init/` are not built; the placeholder directories were removed. Provisioning the machine itself (VM, DNS) is out of scope; the repo starts at "a fresh Ubuntu 24.04 host reachable over SSH".
2. **`1-host-bootstrap/`** is an Ansible role (`host_bootstrap`) that takes such a host and applies: SSH/OS hardening, unattended-upgrades, `ufw` plus `DOCKER-USER` rules, Docker Engine, the pinned Pelican Wings binary (sha256-verified, per architecture), and an optional ingress profile.
3. **Ingress profiles** (`host_ingress`): `direct` (public IP, ports opened), `cloudflared` (Cloudflare Tunnel for Panel/Wings HTTPS, no router port-forwarding, no home IP leak) or `playit` (Playit.gg agent for the game ports). Cloudflare Tunnel only carries HTTP(S) on the free plan, so Minecraft TCP/UDP needs Playit.gg (or `direct`); this is documented in the role README.
4. **`3-ansible/`** deploys the Panel stack (Caddy, DB), the Wings node configuration, the `hg-gitops` agent and backup jobs. The inventory is the only thing that changes between the laptop test target and the real host.
5. **Local = production shape.** `local/` stays the laptop stack (Panel + Wings in Docker under `$HG_ROOT`). The agent takes all paths from `/etc/hg-gitops/agent.env`, so the same scripts run against `$HG_ROOT` on the laptop and `/srv/heldengilde` on a server.
6. **Backups use any S3-compatible endpoint.** Pelican's native S3 backup disk is configured with endpoint, region, bucket and path-style flag. SeaweedFS (compose profile, `local/s3.sh`; MinIO no longer publishes images) for the laptop; Backblaze B2, Hetzner Object Storage or Azure Blob (via an S3 gateway) in production.
7. **Laptop-to-server migration** is `scripts/migrate-state.sh` (export/import) plus a runbook (`docs/runbooks/migrate-laptop-to-server.md`).
8. **Panel database:** SQLite by default (one admin, tiny data, identical to the local stack, so a bundle is portable). MariaDB is a supported variable (`panel_db: mariadb`) and the migration script handles either, but a bundle cannot cross engines.

## Consequences

- F1, F2 and F6-related OCI concerns (200 GB limit, idle reclaim, NSG) no longer apply. The firewall is now the host (`ufw` + `DOCKER-USER`) plus whatever the provider offers.
- Wings' arm64/amd64 difference is handled by selecting the release asset by `ansible_architecture`. The server image is multi-arch; arm64 is still untested (laptop is x86_64).
- Full memory limits are used locally (laptop has 64 GB): no scaled-down heap in `local/`.
- A home host behind a tunnel has no inbound access for the Panel's browser-to-Wings websocket unless Wings is also exposed through the tunnel (its own hostname). The `cloudflared` profile therefore exposes both `panel.<domain>` and `wings.<domain>`.
