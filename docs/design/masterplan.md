> **Superseded in part.** This is the original design document. Known faults and the corrected decisions are in [ADR 0001](../adr/0001-evaluation.md) to [ADR 0006](../adr/0006-client-mods-packwiz.md). The repo name `heldengilde-infra` is now `heldengilde-minecraft-infra`.

# Masterplan: De Heldengilde Minecraft Server

**Status:** Fase 8 - Gevalideerde Productie-Architectuur (Host-Based GitOps, Pelican Mounts & Paper 26.3)
**Doelstelling:** Een veilige, voorspelbare en prikkelvriendelijke online oefenruimte creëren waarin neurodiverse jongeren via avontuur, puzzels en creatie verbinding maken (Duidelijkheid = Veiligheid).

---

## 1. Vastgelegde Infrastructuur & Server-Opzet

* **Host:** Oracle Cloud Infrastructure (OCI) – `VM.Standard.A1.Flex` (4 ARM64 Ampere cores, 24 GB RAM, **max. 200 GB totaal Block Volume incl. boot-volume**, Ubuntu 24.04 LTS) op een **Pay-As-You-Go geüpgradede tenancy** (blijft 100% gratis binnen Always Free limieten, maar voorkomt dat Oracle de VM na 7 dagen rustige CPU-belasting terugvordert).
* **Orkestratie & Runtime:** **Pelican Panel** + *Wings* daemon (achter **Caddy TLS** voor zowel Panel, Wings WebSockets als BlueMap Basic Auth) in combinatie met **`itzg/minecraft-server:java25`** en **Paper `26.3`** (met `1.21.11` / `java21` als fallback).
* **Pelican Mounts Architectuur:**
  * **Mount 1 (`/data`):** Koppelt `/var/lib/pelican/volumes/<uuid>` direct aan `/data` in de container zodat de wereld, Pelican File Manager en S3-backups naadloos samenwerken.
  * **Mount 2 (`/gitops`, Read-Only):** Koppelt de lokale checkout van `heldengilde-infra/4-server` op de host read-only in de container voor native `itzg` config- en plugin-synchronisatie.
* **Server Architectuur (Alles-in-één Server met Multiverse):**
  * We draaien één **PaperMC `26.3`** container (gebudgetteerd op ~14–16 GB JVM Heap zodat er op de 24 GB host altijd genoeg RAM overblijft voor OS, Panel, MariaDB, Caddy en off-heap geheugen), met een start-cap van **30 gelijktijdige spelers**, `view-distance=8` en een vooraf gegenereerde wereld (*Chunky*).

---

## 2. Client Mod Installatie: 1-Klik Modrinth + `Packwiz` Bootstrap

Omdat PaperMC geen Fabric-servermods (zoals *AutoModpack*) draait, lossen we automatische updates aan de client-kant 100% server-onafhankelijk op:

1. **De 1-Klik Start (Modrinth App `.mrpack`):** Jongeren installeren eenmalig het **"Heldengilde Basis Profiel"** in de Modrinth App (bevat *Fabric*, *Sodium*, *Simple Voice Chat* en **`packwiz-installer-bootstrap`**).
2. **Automatische Updates via GitHub Pages (`Packwiz`):** De `packwiz-installer-bootstrap` controleert bij elke keer dat de speler op 'Play' drukt onze statische `pack.toml` op GitHub Pages en downloadt eventuele nieuwe client-mods automatisch. Server-side *Resource Packs* (voor custom icoontjes/geluiden) pusht PaperMC direct bij het inloggen.
3. **Bedrock / Console Spelers (`GeyserMC`):** Spelen zonder client-mods mee; hun *Quiet Corner* (`/rust`) gebruikt `/stopsound` en teleporteert hen direct naar de prikkelarme dimensie.

---

## 3. Wereld, Verkenning & De Gedeelde "Gilde-Atlas"

* **Admin-Only 3D Kaart (`BlueMap`):** Beveiligd met een wachtwoord via **Caddy Basic Auth** zodat alleen DM's en moderatoren de kaart van bovenaf kunnen zien.
* **Speler-Ervaring (De Gedeelde Gilde-Atlas):**
  * De wereld begint voor de community als *onbekend terrein (Fog of War)*.
  * Wanneer **Verkenners** nieuwe biomen, dorpen of verborgen tempels (gegenereerd met het `datapack:terralith` en *BetterStructures*) fysiek ontdekken en hun cartografie-data terugbrengen naar de Hub, wordt dat stuk van de wereld **voor de hele server zichtbaar** op de Gilde-Atlas.
* **Eigen Veilige Plek (Land Claiming):**
  * Met *GriefPrevention* (of *Lands* via `custom-jars/`) kan elke speler een eigen stukje grond claimen waar niemand zonder toestemming iets kan aanpassen.

---

## 4. Gameplay: Co-op Dungeons (`MythicDungeons 2.0`), Mega-Events & Beloningen

* **De Gouden Driehoek op Paper `26.3` (Standaard Party: Max 6 Spelers):** `BetonQuest` + **`MythicDungeons 2.0.1+`** + `MythicMobs`.
* **Waarom `MythicDungeons 2.0.1+` cruciaal is:**
  * Ondersteunt Paper `26.3` en bevat **`OneWorldDungeons: true`**, waarmee alle actieve dungeon-instances in één gedeelde dimensie draaien (geen zware schijf-I/O op Oracle Cloud).
  * Bevat ingebouwde **Push-Block Puzzels** (duwbare blokken voor Zelda-achtige kamerpuzzels) en een verbeterde *PacketEvents* Spectator-modus zodat uitgeschakelde spelers zonder frustratie bij hun groep blijven.
* **Het "Multi-Squad Raid" Model (Server-brede Mega-Events):** Grote events worden opgedeeld in samenwerkende Squads van 4-6 spelers (bijv. *Squad Alpha* kraakt de machinekamer-puzzel, *Squad Bravo* verdedigt de binnenplaats). Zo voorkom je sensorische overprikkeling op één kluitje.

---

## 5. Hybride Integratie: Discord & Neuro-Inclusieve Voice Chat

* **DiscordSRV Link-Requirement (Één Whitelist-bron):** In plaats van de vanilla `white-list=true` en DiscordSRV door elkaar te gebruiken, laten we **DiscordSRV** de toegang bewaken (*Require Linked Account*). Alleen jongeren op de Heldengilde Discord kunnen inloggen.
* **Proximity Voice Chat (`Simple Voice Chat` op `24454/udp`):** Inclusief 🎧 **Luister-modus icoon** (*"Ik luister mee, maar typ terug"*) en directe koppeling aan `/rust` en `/batterij rood`.

---

## 6. Blauwdruk Maatwerk Plugin #1: `HeldengildeParty`

* **Rol- & Kwaliteiten Profiel (`/rol`):** Spelers kiezen hun kracht: 🛡️ *Beschermer*, 🧩 *Puzzelaar*, 🧭 *Verkenner*, 💚 *Ondersteuner* of ⚙️ *Bouwer*.
* **Het In-Game "Avonturenbord":** Met 2 klikken een missie-oproep plaatsen op basis van gezochte rollen en communicatie-voorkeur, gekoppeld aan Discord (`#zoek-een-groep`), *Simple Voice Chat* groepen en *MythicDungeons 2.0* instances.

---

## 7. LLM Integraties, MCP Servers & AVG/Privacy Kaders

1. **De "Quest & Boss Architect" Pipeline (Filesystem MCP + Custom LLM Skills):** Beheer `BetonQuest/` en `MythicMobs/` in de aparte **`heldengilde-content`** repository met een `CLAUDE.md` Skill-bestand dat onze pedagogische kaders afdwingt.
2. **Semantische CI Boot-Test:** Een GitHub Action start bij elke Pull Request in `heldengilde-content` een tijdelijke `itzg` container op en controleert of `BetonQuest` en `MythicMobs` zonder `ERROR`/`SEVERE` in de logs opstarten.
3. **AVG / GDPR Safeguard:** Er worden **nooit** chatberichten of persoonsgegevens van minderjarige spelers naar externe LLM API's gestuurd zonder expliciete DPIA en ouderlijke toestemming; LLM's worden uitsluitend ingezet door begeleiders voor het genereren van quests en dungeons (`#🧙-quest-maker`).

---

## 8. Single-Writer GitOps & No-Code DM Workflows (`hg-gitops`)

Om *configuration drift* én dataverlies bij niet-technische begeleiders onmogelijk te maken, draait er een **Host-Level GitOps Agent (`hg-gitops`)** buiten de game-container en scheiden we elke map op basis van **Single-Writer Ownership**:

1. **Core Infra (`heldengilde-infra` ➡️ `/gitops` Read-Only Mount):** Alleen Git schrijft hier. Bevat `plugins.txt`, `custom-jars/` (`MythicDungeons-2.0.1.jar`, `HeldengildeParty.jar`) en `config/`. Secrets worden via **SOPS/Ansible Vault** in de Pelican Egg-variabelen gezet en niet in Git gecommit; DM-accounts in Pelican hebben via `file_denylist` geen toegang tot bestanden met tokens.
2. **Quests & Mobs (`heldengilde-content` ➡️ Server):** Gemaakt via de Discord `#🧙-quest-maker` bot of PR's. De `hg-gitops` agent op de host synct deze met `rsync --delete` naar het server-volume en roept via de Pelican Client API `bq reload` en `mm reload` aan.
3. **In-Game Gebouwde NPCs & Dungeon-Triggers (Server ➡️ `autosync/server` Branch):** Begeleiders bouwen in-game met hun `MythicDungeons` Toverstaf en `Citizens`. De `hg-gitops` agent stuurt periodiek `save-all flush` + `citizens save`, maakt een snapshot van de YAML-bestanden naar de `autosync/server` branch en opent automatisch een Pull Request.
4. **Werelden & Binaire Dungeon-Maps (Server ➡️ OCI S3 Backups):** Worden niet in Git opgeslagen, maar via Pelican's ingebouwde backup-systeem naar S3-compatibele OCI Object Storage geschreven.
