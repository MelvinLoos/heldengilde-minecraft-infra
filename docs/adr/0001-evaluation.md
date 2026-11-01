# ADR 0001: Evaluation of the original design

- Status: accepted
- Date: 2026-11-01

## Context

The masterplan (`docs/design/masterplan.md`) and implementation bundle #1 (`docs/design/implementatiebundel-1.md`) were evaluated against the Pelican Wings source, the itzg docs, the Modrinth API and the PaperMC Fill API. The bundle does not work as written. This ADR records the findings; the follow-up ADRs record the resulting decisions.

## A. Blockers (the setup doesn't work)

| # | Finding | Evidence / consequence |
|---|---|---|
| A1 | **The egg `startup` command is never run.** Wings sets no `Cmd` or `Entrypoint` and only passes `STARTUP` as an env var, which yolk images `eval`. itzg runs its own `ENTRYPOINT /start`. | The pre-start and post-stop hooks never run. |
| A2 | **The world is wiped on every start.** The Wings volume is mounted at `/home/container`, but itzg uses `/data`. That makes `/data` an anonymous volume, and Wings recreates the container with `RemoveVolumes: true`. | Every world and config is deleted on restart. Backups and the file manager see an empty directory. |
| A3 | **The bootstrap can't get started.** The pre-start script lives inside the repo it is supposed to clone, and the install script runs in a throwaway `alpine` container. | The first start always fails. |
| A4 | **The `export`s never reach itzg.** The pre-start script runs as a child process (`script && /start`). | No plugins get installed and the heap is 1 GB. |
| A5 | **The egg JSON is invalid** (`\a` escape in the install script). | Egg import fails. |
| A6 | **AutoModpack is Fabric/Forge/NeoForge/Quilt only.** It needs a modded server. | Masterplan §2 needs a different mechanism (see the client-mods decision). |

## B. Data loss & sync-design faults

| # | Finding |
|---|---|
| B1 | **Bi-directional sync without merge.** Git and the server write the same paths, and `cp` decides the winner. Each path needs exactly one owner. |
| B2 | **`cp -ru` with Git mtimes loses DM work.** Scenario: post-stop's push is rejected because main has moved, and `set -e` aborts. On the next start, `reset --hard` gives the old file a fresh mtime. `cp -u` then overwrites the DM's newer copy. |
| B3 | Post-stop runs even when pre-start failed (`a && b; c`). Git changes made while the server runs are reverted by the next post-stop. |
| B4 | Deletions never propagate, so removed content comes back ("zombie content"). The two docs also disagree (`cp` vs `rsync --delete`). |
| B5 | Content is pushed to `main`, not `content-staging`. The Discord bot puts quests live before review, and post-stop then pushes them to `main`, which bypasses the approval. |
| B6 | Binary world and schematic data (MythicDungeons maps, or the shared world with `OneWorldDungeons`) doesn't belong in Git; it goes to backups. The small dungeon trigger YAML (`plugins/MythicDungeons/dungeons/*.yml`) *can* be snapshotted to Git. |
| B7 | The nightly copy has no `save-all` or plugin save first, and the container has no cron. |
| B8 | CI copying `config-patches/*` into a running server reinstates the literal `${CFG_*}` placeholders and overwrites DM content that hasn't been synced yet. |

## C. Security

| # | Finding |
|---|---|
| C1 | A GitHub PAT sits in the committed egg default. It is also in `.git/config` inside `/data`, readable by DM subusers. |
| C2 | The server gets write access to the infra repo, including the workflows that hold the OCI SSH key. Auto-updating plugins can therefore escalate to root on the VM. |
| C3 | CI deploys by SSH as a docker-group user (root-equivalent) with port 22 open to GitHub runners. It is push-based, and `head -1` picks an arbitrary container. |
| C4 | Secrets are not "in-memory": itzg interpolates **on disk** in `/data`, so they land in backups and the file manager. `ENV_VARIABLE_PREFIX` is the wrong name (it should be `REPLACE_ENV_VARIABLE_PREFIX`), and `CFG_RCON_PASSWORD` is never defined. |
| C5 | BlueMap has no auth of its own, so the password has to come from Caddy (basic auth or forward-auth). |
| C6 | Docker bypasses UFW. The OCI NSG is the real firewall, plus `DOCKER-USER` rules. Keep Oracle's 169.254.0.0/16 iptables rules. |

## D. Plugin list (Modrinth API, filtered on Paper + 26.3)

> Snapshot taken before the Phase 2 boot test. The final pins are in `4-server/plugins.txt` (Paper 26.2). CoreProtect did not start on 26.3, so BetonQuest, GriefPrevention and Terralith moved to their 26.2 builds. See [ADR 0004](0004-mc-version-and-java25.md).

| Entry | Status |
|---|---|
| `automodpack` | ❌ Fabric/Forge only |
| `floodgate` | ❌ Modrinth has the Fabric/NeoForge build only. Get the Paper build from the GeyserMC download API. |
| `geyser` | ⚠️ 26.3 builds are tagged beta only. Also take it from the GeyserMC download API, with the build pinned. |
| `betonquest` | ⚠️ 26.3 only has `3.3.0-DEV-*` builds. Pin an explicit DEV build; it is a Phase 2 risk. |
| `coreprotect` | ⚠️ There is **no 26.3-tagged build**; the latest is up to 26.2. Boot-test it. This is the trigger for the 26.2 fallback. |
| `mythicdungeons` | Modrinth only has the frozen free branch (≤1.21.11). Use the 2.0.1+ premium jar as a custom jar. |
| `packetevents` | ✅ `2.14.0+spigot` (26.3). Add it for the `Spectator.UseLegacy: false` setting. |
| `waystones-paper` | ❌ Does not exist |
| `lands` | ❌ Not on Modrinth (premium). Use the custom-jar route if you buy it, or `griefprevention` (✅ 26.3). |
| `citizens` | ❌ Not on Modrinth. Use a pinned `PLUGINS` URL from the Citizens CI. |
| `spark` | ❌ Modrinth build is Fabric/Forge only. Paper bundles spark, so remove it. |
| `unifiedmetrics` | ❌ Abandoned since 2023. Choose a maintained exporter. |
| `terralith` | ⚠️ Use `datapack:terralith` (`2.6.5+26.3` exists). It only affects chunks generated after install. |
| mythicmobs 5.14.0, multiverse-core 5.8.2, discordsrv 1.30.5, betterstructures, bluemap, simple-voice-chat, luckperms, viaversion | ✅ Stable 26.3 builds |
| Inline `# comments` | ❌ They break the slug parsing. Use itzg's native `MODRINTH_PROJECTS=@file` with full-line comments only. |

## E. Configuration correctness

- **E1.** The default `1.21.4` is stale. The target was 26.3/Java 25; after the Phase 2 boot test it is 26.2/Java 25 (ADR 0004).
- **E2.** `paper-global.yml` belongs in `/data/config/`.
- **E3.** itzg rewrites `server.properties` from env vars and manages RCON itself, and Pelican sets `SERVER_PORT`. Use env vars as the single source, with no hard-coded `server-port` or `rcon.*`.
- **E4.** `keepInventory` is a per-world gamerule. Set it with `RCON_CMDS_STARTUP`.
- **E5.** A heap equal to the container limit gets OOM-killed. Use about 75–80% of the limit, and budget for the Panel stack on the same host.
- **E6.** Use one whitelist mechanism: DiscordSRV's linked-account requirement or the vanilla whitelist, not both.
- **E7.** 60 players at view distance 10 on 4 Ampere cores is optimistic. Start with about 30, view distance 8 and a pre-generated world.
- **E8.** The egg `features` are yolk-only. Take `startup.done` from a real Pelican export. Pin image tags.
- **E9.** yamllint `default` is too strict for plugin YAML and only checks syntax, so a boot test is needed.
- **E10.** Bedrock players get no voice chat and no client mods. `/rust` can't mute game sounds server-side.

## F. Masterplan infra (layers 1–3)

> OCI was dropped afterwards ([ADR 0007](0007-provider-agnostic-ubuntu-hosts.md)). F1 and F2 are historical; F3–F5 still apply to any host.

- **F1.** The OCI Always Free 200 GB total includes the boot volume.
- **F2.** Idle Always Free instances get reclaimed. Upgrade to Pay-As-You-Go, and plan for A1 out-of-capacity retries.
- **F3.** The browser opens the console websocket directly to Wings, so Wings needs TLS (via Caddy). Public `:8080` over plain HTTP won't work.
- **F4.** Port 24455 is unexplained. UDP 24454 (voice) and 19132 (Geyser) need Pelican allocations.
- **F5.** The Wings config only exists after layer 3. Cloud-init only installs; Ansible configures.
- **F6.** To my knowledge there is no official BetonQuest web editor with publish-to-server (masterplan §9B).
- **F7.** (Out of scope.) LLM processing of minors' chats needs AVG/GDPR compliance (DPIA, parental consent). Discord's minimum age is 13.

## G. Review notes on the rev-2 input

- **G1. Phase 1 privilege model.** Wings starts the container *already* as `988:988` (`conf.User`). So itzg's root branch (`chown` + `gosu`/`setpriv`) shouldn't execute at all. Wings drops a specific list of capabilities (including `dac_override`, `fowner`, `setpcap`), not `ALL`, and sets `no-new-privileges` and a read-only rootfs. The spike tests `UID=988`/`GID=988` explicitly, as requested, and asserts that no privilege-drop or chown is attempted.
- **G2. Client resource pack.** Paper doesn't *host* resource packs. It sends `resource-pack` (URL), `resource-pack-sha1` and `require-resource-pack` to the client. Host the zip on the same GitHub Pages site as the packwiz pack.
- **G3. packwiz hook.** Confirm that the Modrinth App's pre-launch hook can come preconfigured from the `.mrpack` instead of being set per player. Otherwise use Prism Launcher for the hook. This is deferred.

---

## H. Findings from the Phase 1 spike (2026-11-01)

See [ADR 0002](0002-runtime-itzg-under-wings-mounts.md) for the full list. Short version:

- itzg's `/config` sync defaults to `/data/config` and lets newer files in `/data` win. Both defaults break the Git-owned zone and need overriding (`COPY_CONFIG_DEST`, `SYNC_SKIP_NEWER_IN_DESTINATION`).
- Pelican panel `v1.0.0-beta38`: `POST /api/application/mounts` ignores all fields (upstream bug), so mounts are created with `artisan tinker`.
- The original bundle's idea of replacing config on each start with a script was also unnecessary: itzg does this natively.
