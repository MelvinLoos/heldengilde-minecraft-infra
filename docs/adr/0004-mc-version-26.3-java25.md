# ADR 0004: Minecraft 26.3 on Java 25

- Status: accepted
- Date: 2026-11-01

## Decision

Target Paper `26.3` on `itzg/minecraft-server:java25`, pinned by versioned tag and digest.

MythicDungeons is the official 2.0.1+ build from the MythicCraft marketplace (Paper 26.1-26.3), not the frozen free branch on Modrinth. Config patch for `plugins/MythicDungeons/config.yml`: `Experimental.OneWorldDungeons: true` (less I/O on OCI block volumes) and `Spectator.UseLegacy: false` (requires `packetevents` in `plugins.txt`).

## Fallback ladder

If the Phase 2 boot test finds a hard blocker in a core plugin (BetonQuest, MythicMobs, Geyser, CoreProtect): first Paper 26.2, then 1.21.11 on `java21`.

## Known risks

- CoreProtect has no 26.3-tagged build (latest is 26.2).
- BetonQuest only has `3.3.0-DEV-*` builds for 26.3.
- Geyser 26.3 builds are tagged beta.
