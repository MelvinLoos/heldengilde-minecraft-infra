# heldengilde-minecraft-infra

GitOps for the Heldengilde Minecraft server: OCI ARM64 host (OpenTofu), cloud-init, Ansible, Pelican Panel + Wings, and `itzg/minecraft-server` (Paper 26.3, Java 25).

Quest and NPC content lives in the separate `heldengilde-minecraft-content` repo.

## Layout

| Path | Purpose |
|---|---|
| `1-terraform/` | OCI network and VM |
| `2-cloud-init/` | First-boot install (Docker, Wings binary) |
| `3-ansible/` | Panel, Wings config, API bootstrap |
| `4-server/` | Server definition: plugins, config, patches, egg |
| `agent/` | `hg-gitops` host agent (systemd timers) |
| `local/` | Local Pelican + Wings test stack and spike tests |
| `docs/adr/` | Architecture decisions (start with 0001) |
| `docs/design/` | Original design docs, superseded in part by the ADRs |

## Status

Phases 0 (scaffold) and 1 (runtime spike, go) are done. Next: Phase 2 (server definition). See ADR 0002.

## Local spike

```bash
export HG_ROOT=$HOME/hg-local
local/bootstrap.sh          # panel + admin + node + Wings
local/spike/provision.sh    # egg, allocation, server, mounts
local/spike-test.sh         # PASS/FAIL checks for the runtime
```
