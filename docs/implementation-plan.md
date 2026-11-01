# Implementation plan (rev. 3)

Rev. 3 drops OCI ([ADR 0007](adr/0007-provider-agnostic-ubuntu-hosts.md)). Build and verify on the laptop, deploy to any Ubuntu 24.04 host later by changing the Ansible inventory.

| Phase | Deliverable | Status | Verified by |
|---|---|---|---|
| 0 | Scaffold, ADRs | done | pre-commit |
| 1 | Runtime spike (itzg under Wings Mounts) | done | `local/spike-test.sh` (23 checks) |
| 2 | Server definition (Paper 26.2, 17 plugins) | done | `local/boot-test.sh` |
| 3 | CI (lint, gitleaks, boot test) | done | `local/lint.sh`, actionlint |
| 4+5 | `1-host-bootstrap/`: hardening, ufw + DOCKER-USER, Docker, Wings binary, optional cloudflared/Playit | done | ansible-lint, syntax-check, run against an Ubuntu 24.04 systemd container |
| 6 | `3-ansible/`: Panel stack (Caddy, DB), Wings node, API bootstrap, jar fetch, agent, backups | done | ansible-lint, syntax-check, template render, container run |
| 7 | `agent/`: `hg-gitops` (`sync-infra`, `sync-custom-jars`, `deploy-content`, `snapshot-server-content`) | done | end-to-end against the local stack |
| 8 | S3-compatible backups (SeaweedFS locally), restore runbook, `scripts/migrate-state.sh` | done | backup to MinIO, export/import round trip |

Deferred: Discord quest bot, `HeldengildeParty` plugin, client packwiz pipeline, Gilde-Atlas, metrics exporter, arm64 verification, CI run on GitHub (no remote yet).
