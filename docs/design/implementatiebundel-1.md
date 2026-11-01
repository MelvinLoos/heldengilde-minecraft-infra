> **Superseded in part.** This is the original design document. Known faults and the corrected decisions are in [ADR 0001](../adr/0001-evaluation.md) to [ADR 0006](../adr/0006-client-mods-packwiz.md). The repo name `heldengilde-infra` is now `heldengilde-minecraft-infra`.

# Implementatiebundel #1: Host-Based GitOps, Pelican Mounts & Paper 26.3

Dit document bevat de herziene, productie-klare architectuur en configuratiebestanden voor **Laag 4** uit ons Masterplan, bijgewerkt na de technische audit op de Pelican *Wings* broncode en de `itzg/minecraft-server` runtime.

## 1. Kernprincipes van het Herziene Ontwerp

Om *data loss*, permissie-conflicten en onveilige tokens in de game-container te voorkomen, hanteren we vier strikte DevOps-principes:

1. **Pull-Based Host Agent (`hg-gitops`):** Er draait **geen Git en er staan geen GitHub-tokens** binnenin de Minecraft-container. Een lichtgewicht `systemd`-agent op de Ubuntu-host beheert de Git-checkouts en communiceert met de server via de Pelican Client API.
2. **Pelican Mounts voor `/data` en `/gitops`:**
   * Wings mount standaard `/home/container`. We configureren een **Pelican Mount** die de server-volumedirectory (`/var/lib/pelican/volumes/<uuid>`) direct op `/data` bind-mount, zodat `itzg`, de Pelican File Manager en de Pelican S3-backups exact dezelfde data zien.
   * Een tweede **Read-Only Pelican Mount** koppelt `/opt/heldengilde/infra/4-server` op de host aan `/gitops` in de container.
3. **Single-Writer Eigenaarschap (Geen Bi-Directionele Race Conditions):** Elke map heeft exact één eigenaar (Git óf de Server), gescheiden over twee repositories (`heldengilde-infra` en `heldengilde-content`).
4. **Paper `26.3` (Java 25) + `MythicDungeons 2.0.1+`:** We draaien op de nieuwste `itzg/minecraft-server:java25` met `MythicDungeons 2.0.1+` (geïnstalleerd vanuit `/gitops/custom-jars/`) en `Experimental.OneWorldDungeons: true`.

---

## 2. Single-Writer Content Matrix

| Content / Pad | Eigenaar (Single Writer) | Repository / Opslag | Synchronisatie Flow |
| :--- | :--- | :--- | :--- |
| **Zone 1: Server Config & Plugins** (`server.properties`, `paper-global.yml`, `plugins.txt`, `custom-jars/`) | **Git** (DevOps) | `heldengilde-infra` | Host-agent pullt `/gitops` (read-only mount); `itzg` past alles declaratief toe bij container-start. |
| **Zone 2A: Tekstuele Quests & Mobs** (`BetonQuest/`, `MythicMobs/`) | **Git** (PR-reviewed / Discord Bot) | `heldengilde-content` | Host-agent doet `rsync --delete` naar het server-volume en roept `bq reload` / `mm reload` aan via de Pelican API. |
| **Zone 2B: In-Game Gebouwde NPCs & Dungeon-Triggers** (`Citizens/saves.yml`, `MythicDungeons/dungeons/*.yml`) | **Server** (DM's in-game) | `heldengilde-content` (`autosync/server` branch) | Host-agent stuurt `save-all` + `citizens save`, maakt een snapshot naar de `autosync/server` branch en opent automatisch een PR naar `main`. |
| **Zone 3: Werelden & Binaire Dungeon-Maps** (`world/`, `MythicDungeons/maps/`) | **Server** | **OCI Object Storage (S3)** | Geplande Pelican Backups (horen niet thuis in Git vanwege binaire omvang). |

---

## 3. Repository Mappenstructuur (`heldengilde-infra`)

```text
heldengilde-infra/
├── 1-terraform/                        # OCI VCN, NSG & ARM64 A1.Flex (<= 200GB totaal)
├── 2-cloud-init/                       # OS hardening, veilige iptables, Docker & Wings binary
├── 3-ansible/                          # Pelican Panel, MariaDB, Caddy TLS, Node & Mounts via API
├── 4-server/                           # Wordt Read-Only gemount op /gitops in de container
│   ├── egg-heldengilde-itzg.json       # Gepinde itzg Java 25 Egg (zonder secrets!)
│   ├── plugins.txt                     # Gepinde Modrinth plugins (native @/gitops/plugins.txt)
│   ├── startup-commands.txt            # RCON gamerules (keepInventory) bij opstarten
│   ├── custom-jars/                    # Lokale/Premium JARs (gekopieerd via COPY_PLUGINS_SRC)
│   │   ├── MythicDungeons-2.0.1.jar    # Ondersteunt Paper 26.3 + OneWorldDungeons
│   │   └── HeldengildeParty.jar        # Onze eigen maatwerk plugin
│   └── config/                         # Wordt door itzg gesynct naar /data met ${CFG_*} interpolatie
│       ├── bukkit.yml
│       ├── config/
│       │   └── paper-global.yml        # Correcte Paper 1.19+ submap (/data/config/paper-global.yml)
│       └── plugins/
│           ├── MythicDungeons/
│           │   └── config.yml          # OneWorldDungeons: true & PacketEvents spectator
│           └── DiscordSRV/
│               └── config.yml          # Gebruikt ${CFG_DISCORD_BOT_TOKEN}
├── agent/                              # Host-level GitOps systemd services & timers
│   ├── hg-gitops.sh
│   ├── hg-gitops-content.service
│   └── hg-gitops-snapshot.timer
└── local/                              # Lokale Docker Compose spike-omgeving (Phase 1)
    ├── compose.yml
    └── spike-test.sh
```

---

## 4. Declaratieve Configuratie (`4-server/`)

### A. `4-server/plugins.txt` (Native `itzg` Formaat)

Geen inline comments achter de slugs, zodat `MODRINTH_PROJECTS=@/gitops/plugins.txt` dit bestand foutloos en native inleest. Plugins die geen Paper-build op Modrinth hebben (`Floodgate`, `Citizens`) worden via de `PLUGINS` URL-variabele geladen, en `Spark` laten we weg omdat deze al standaard in Paper `26.3` zit ingebakken.

```text
# ==============================================================================
# Heldengilde Modrinth Plugins (Geladen via MODRINTH_PROJECTS=@/gitops/plugins.txt)
# ==============================================================================

# --- Toegankelijkheid & Protocollen ---
geyser
viaversion
viabackwards
packetevents

# --- Hybride Community, Audio & Veiligheid ---
simple-voice-chat
discordsrv
luckperms
coreprotect
griefprevention

# --- Wereld, Verkenning & Dungeons ---
multiverse-core
datapack:terralith
betterstructures
betonquest
mythicmobs

# --- Admin 3D Kaart (Beveiligd achter Caddy Basic Auth) ---
bluemap
```

### B. `4-server/startup-commands.txt` (Gamerules via `RCON_CMDS_STARTUP`)

Omdat `keepInventory` een *per-world gamerule* is en geen `server.properties` instelling, voert `itzg` deze commando's automatisch uit zodra de wereld geladen is:

```text
gamerule keepInventory true
gamerule doFireTick false
mv modify set keepInventory true world
```

### C. `4-server/config/plugins/MythicDungeons/config.yml`

```yaml
# ==============================================================================
# MythicDungeons 2.0.1+ Config (Paper 26.3 & One-World Optimalisatie)
# ==============================================================================
General:
  PartyPlugin: "HeldengildeParty"
  AutoSaveInterval: 10

Spectator:
  # Vereist PacketEvents: voorkomt hotbar-glitches en frustratie bij uitgeschakelde spelers
  UseLegacy: false

Experimental:
  # CRUCIAAL VOOR OCI BLOCK STORAGE: Draai alle dungeon-instances ver uit elkaar
  # in één gedeelde dimensie in plaats van losse wereldmappen te kopiëren per party!
  OneWorldDungeons: true
  OneWorldDungeonsWorld:
    Difficulty: NORMAL
    Time: 6000
    Weather: CLEAR
    GameRules:
      keepInventory: true
      doMobSpawning: false
      doFireTick: false
```

---

## 5. De Host-Level GitOps Agent (`agent/hg-gitops.sh`)

Dit script draait via een `systemd` timer op de Ubuntu-host (buiten de game-container) en gebruikt de **Pelican Client API** in plaats van onveilige SSH-acties vanuit GitHub Actions:

```bash
#!/usr/bin/env bash
# ==============================================================================
# Heldengilde Host-Level GitOps Agent (hg-gitops.sh)
# Modi:
#   sync-infra      -> Pullt heldengilde-infra naar /opt/heldengilde/infra (gemount op /gitops)
#   deploy-content  -> Synct BetonQuest/MythicMobs uit heldengilde-content & triggert live reload
#   snapshot-dm     -> Slaat Citizens & MythicDungeons YAML op en pusht naar autosync/server branch
# ==============================================================================
set -euo pipefail

MODE="${1:-}"
INFRA_DIR="/opt/heldengilde/infra"
CONTENT_DIR="/opt/heldengilde/content"
SERVER_VOL="/var/lib/pelican/volumes/${PELICAN_SERVER_UUID}"

pelican_cmd() {
    local cmd="$1"
    curl -fsSL -X POST "${PELICAN_PANEL_URL}/api/client/servers/${PELICAN_SERVER_SHORT_ID}/command" \
        -H "Authorization: Bearer ${PELICAN_CLIENT_API_KEY}" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -d "{\"command\": \"${cmd}\"}"
}

case "${MODE}" in
  sync-infra)
    cd "${INFRA_DIR}"
    git fetch origin main
    git reset --hard origin/main
    ;;

  deploy-content)
    cd "${CONTENT_DIR}"
    OLD_REV="$(git rev-parse HEAD)"
    git fetch origin main
    git reset --hard origin/main
    NEW_REV="$(git rev-parse HEAD)"

    if [[ "${OLD_REV}" != "${NEW_REV}" ]]; then
        rsync -a --delete "${CONTENT_DIR}/BetonQuest/QuestPackages/" "${SERVER_VOL}/plugins/BetonQuest/QuestPackages/"
        rsync -a --delete "${CONTENT_DIR}/MythicMobs/" "${SERVER_VOL}/plugins/MythicMobs/"
        chown -R 988:988 "${SERVER_VOL}/plugins/BetonQuest" "${SERVER_VOL}/plugins/MythicMobs"
        pelican_cmd "bq reload"
        pelican_cmd "mm reload"
        pelican_cmd "say §b[Heldengilde] §aNieuwe verhalen en puzzels zijn zojuist ingeladen!"
    fi
    ;;

  snapshot-dm)
    # 1. Forceer een nette plugin-save via de Pelican API vóórdat we bestanden kopiëren
    pelican_cmd "save-all flush"
    pelican_cmd "citizens save"
    sleep 3

    cd "${CONTENT_DIR}"
    git checkout -B autosync/server origin/main

    mkdir -p "${CONTENT_DIR}/server-owned/Citizens" "${CONTENT_DIR}/server-owned/MythicDungeons/dungeons"
    rsync -a "${SERVER_VOL}/plugins/Citizens/saves.yml" "${CONTENT_DIR}/server-owned/Citizens/saves.yml"
    rsync -a --delete --include='*.yml' --exclude='*' \
        "${SERVER_VOL}/plugins/MythicDungeons/dungeons/" "${CONTENT_DIR}/server-owned/MythicDungeons/dungeons/"

    if [[ -n "$(git status --porcelain)" ]]; then
        git add server-owned/
        git commit -m "chore(dm-snapshot): automated snapshot of in-game DM changes ($(date -Iseconds))"
        git push -f origin autosync/server
    fi
    ;;
esac
```
