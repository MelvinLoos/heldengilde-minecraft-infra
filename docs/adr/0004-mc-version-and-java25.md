# ADR 0004: Minecraft version, Java 25 and the fallback ladder

- Status: accepted (amended 2026-11-01 after the Phase 2 boot test)
- Date: 2026-11-01

## Decision

**Primary target: Paper `26.2` (build 135) on `itzg/minecraft-server:java25`**, pinned by build number and image digest. Paper `26.3` was the first choice, but the Phase 2 boot test hit the fallback trigger:

- CoreProtect 24.1 (latest, 2026-09-24) refuses to start on 26.3 (`Minecraft 26.3 is not supported`). CoreProtect is how DMs roll back mistakes, which matters for the "failing is allowed" principle.
- Terralith's 26.3 build also does not parse on 26.2, so pins are per Minecraft version.

On 26.2 the whole stack (17 plugins) boots cleanly, and BetonQuest is a stable release (`3.2.0`) instead of a 26.3 DEV build.

`4-server/plugins-26.3.txt` is the upgrade candidate. Move to 26.3 when CoreProtect supports it: re-run `local/boot-test.sh` with `HG_EXTRA_ENV` pointing at that file.

## MythicDungeons

The official 2.1.0 build (MythicCraft marketplace, MarcatoSound) loads on 26.2 and 26.3. An earlier jar named `MythicDungeons.jar` (version 2.0.0, author "Codex", package `com.example`) was an unrelated plugin and was rejected. Check the author/main class of any new premium jar before adding it to the lock.

Its defaults are `OneWorldDungeons: false` and `Spectator.UseLegacy: true`. We set `true`/`false` in a full config file owned by Git (`4-server/config/plugins/MythicDungeons/config.yml`), not a patch: **itzg patches only apply to files that already exist**, so on a fresh server they are skipped until the second boot. `UseLegacy: false` needs `packetevents` (pinned in `plugins.txt`).

## Fallback ladder (unchanged)

26.3 -> 26.2 -> 1.21.11 on `java21`. We are on the second rung.

## Findings

- Plugin pins are per Minecraft version. Never mix pin files.
- BetterStructures hard-depends on WorldEdit (added to `plugins.txt`).
- Without `SKIP_DOWNLOAD_DEFAULTS=true`, itzg downloads default Paper/Bukkit/Spigot configs from a third-party GitHub repo. We disable that.
- Paper boot noise from Mojang session-server timeouts is external; the boot test ignores it.
