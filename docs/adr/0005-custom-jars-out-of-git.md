# ADR 0005: Licensed and custom jars stay out of Git

- Status: accepted
- Date: 2026-11-01

## Decision

Premium or custom jars (MythicDungeons 2.0.1+, optionally Lands, later `HeldengildeParty.jar`) are never committed (`*.jar` is gitignored). `4-server/custom-jars.lock` records filename, source (private OCI Object Storage, or a GitHub Release for our own plugin) and sha256. Ansible and the agent fetch and verify them into `/srv/heldengilde/custom-jars`, which is mounted read-only at `/plugins`; itzg syncs it into `/data/plugins` on each start.

## Consequences

CI boot tests cannot load premium jars, so MythicDungeons is covered by local runs only.
