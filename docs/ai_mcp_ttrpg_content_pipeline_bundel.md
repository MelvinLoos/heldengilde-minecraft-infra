# Implementatiebundel #2: AI, MCP Server & TTRPG Content Pipeline

**Doelstelling:** Een AI-gestuurde content-pipeline waarmee we het eigen **Heldengilde TTRPG-systeem** (klassen, magie, lore, puzzels en normen/waarden) naadloos vertalen naar **100% MythicMobs-compatibele** configuraties (`MythicMobs`, `MythicDungeons 2.1.0` en `BetonQuest`).

---

## 1. De "Unified Mythic Stack" voor jullie Eigen TTRPG

Omdat we willen dat magie, karakters, monsters én dungeon-puzzels naadloos met elkaar praten, standaardiseren we op het **MythicCraft ecosysteem** aangevuld met `BetonQuest` en `AuraSkills`:

* **`MythicMobs` (De Centrale Skill Engine):** Elke spreuk, klasse-vaardigheid, puzzeleffect en eindbaas-actie in jullie TTRPG wordt geschreven als een *MythicMobs Skill* (`Skills/*.yml`).
* **`HeldengildeParty` (Spreukenboeken, Staven & TTRPG Relieken):** Onze eigen plugin laat spelers items (zoals een Toverstaf of Grimoire uit jullie TTRPG) vasthouden en met rechtermuisknop een `MythicMobs` skill afvuren, na een mana-check via `AuraSkills` (zie ADR 0008).
* **`MythicDungeons 2.1.0` (Puzzel-Interactie):** Deuren, kristallen en *Push-Blocks* in dungeons kunnen reageren op specifieke `MythicMobs` skills of variabelen (bijv. een deur die alleen opengaat als een speler een specifieke spreuk uit jullie TTRPG op een runensteen cast).
* **`BetonQuest` (Verhaal & Theory of Mind):** Heeft native integratie met `MythicMobs` en `MythicDungeons` (kan spreuken/items geven, dungeons starten en controleren welke keuzes een groep heeft gemaakt).

---

## 2. Het AI Skill- & Contextbestand (`heldengilde-content/CLAUDE.md`)

Plaats dit bestand in de root van de **`heldengilde-content`** repository. Zowel jouw lokale coding agent (Claude Code / Cursor) als de Discord Bot lezen dit bestand als hun vaste instructieset.

```markdown
# Heldengilde Content Repository — AI Architect & DM Skill (`CLAUDE.md`)

Je bent de **Heldengilde TTRPG-naar-Minecraft Architect**. Je vertaalt de lore, spelregels, magie en avonturen van het eigen TTRPG-systeem van **De Heldengilde** naar foutloze, samenwerkende configuraties voor PaperMC `26.3`.

## 1. Pedagogische Kernregels (ALTIJD AFDWINGEN)
Elke quest, spreuk, NPC en dungeon die je genereert MOET voldoen aan het Pedagogisch Kader van De Heldengilde:
1. **Duidelijkheid boven Subtiliteit:** Jongeren in onze neurodiverse doelgroep (ASS, ADHD, hoogbegaafdheid) lopen vast op vage hints of sarcasme. NPC-dialogen in `BetonQuest` bevatten altijd expliciete doelen, heldere keuzes en optionele *Tone Indicators* (bijv. `[Serieus]`, `[Grapje]`, `[Hint]`).
2. **Co-op & Party Samenstelling (Max. 6 Spelers):** Ontwerp nooit "solo hack & slash" opdrachten. Elke dungeon of missie vereist dat verschillende rollen uit onze TTRPG samenwerken (bijv. Speler A gebruikt een spreuk of staat op een drukplaat zodat Speler B een code kan lezen of een blok kan verschuiven).
3. **Theory of Mind boven Geweld:** Minstens 50% van de conflicten met NPCs of eindbazen moet oplosbaar zijn door empathie, luisteren, onderhandelen of het oplossen van een omgevingspuzzel in plaats van puur vechten.
4. **De Veilige Cirkel (Falen mag):** Bestraf een foute puzzelkeuze of een mislukte worp nooit met het verlies van items of een oneerlijke dood. Geef constructieve feedback en laat het verhaal op een andere manier doorgaan (*Resilience*).
5. **Taal:** Alle in-game teksten, NPC-dialogen, item-namen en lore zijn in toegankelijk, helder **Nederlands**. Alle YAML-sleutels, bestandsnamen en comments voor developers zijn in het **Engels**.

## 2. Heldengilde TTRPG Systeem-Koppeling
Lees de TTRPG-brondocumenten in `docs/ttrpg-source/` voor:
- De Klassen / Archetypes en hun kernkwaliteiten.
- Het Magie- & Vaardighedensysteem (vertaal elke spreuk naar een item met `HgSpell`-tags in `MythicMobs/Items/` + een skill in `MythicMobs/Skills/`).
- De Wereld-lore, Steden (gekoppeld aan onze Azgaar/WorldPainter kaart) en Factions.

## 3. Technische Architectuur & Single-Writer Paden
Schrijf uitsluitend naar de volgende mappen in deze repository:
- `BetonQuest/QuestPackages/<pakket-naam>/`
  - `package.yml` (NPC-koppelingen, events, objectives, conditions, journal entries)
  - `conversations/<npc>.yml` (Vertakkende dialogen met heldere keuzes)
- `MythicMobs/Mobs/<categorie>.yml` (Monsters, puzzelelementen, interactieve kristallen)
- `MythicMobs/Skills/<categorie>.yml` (Spreuken, baas-mechanieken en puzzel-triggers)
- `MythicMobs/Items/<categorie>.yml` (TTRPG Toverboeken, Staven, Relieken met `HgSpell`/`HgManaCost`-tags)

*Raak `server-owned/` (Citizens & MythicDungeons snapshots) NOOIT handmatig aan tenzij expliciet gevraagd om een dungeon-trigger te koppelen.*

## 4. Naadloze Integratie-Patronen (MythicMobs <-> BetonQuest <-> MythicDungeons)
Gebruik deze vaste patronen zodat alle systemen met elkaar samenwerken:
- **TTRPG Spreuk op Puzzel-Object:**
  Maak voor een puzzelelement in een dungeon een onzichtbare of vermomde MythicMob (bijv. `RunicCrystal`) met `DamageModifiers: [ ALL 0 ]` en een `~onDamaged` of `Aura` check die luistert naar een specifieke TTRPG-spreuk tag, en vervolgens een `MythicDungeons` trigger aanroept via `command{c="md trigger <dungeon> <trigger_id>"}`.
- **BetonQuest Start Dungeon:**
  Gebruik in `BetonQuest` het commando-event of de native integratie om een party van max. 6 spelers een `MythicDungeons` instance in te sturen zodra de dialoog-puzzel bij de wachter is opgelost.
```

---

## 3. De Custom Heldengilde MCP Server (`mcp-heldengilde-server`)

Deze **Model Context Protocol (MCP)** server (FastMCP / Python) geeft de coding agent directe tools om jullie TTRPG-bronnen te doorzoeken en gegenereerde YAML-bestanden live te testen tegen de lokale PaperMC-container.

### Code: `tools/mcp-heldengilde/server.py`

```python
#!/usr/bin/env python3
"""
Heldengilde MCP Server for Claude Code / Cursor.
Bridges our custom TTRPG source docs, MythicMobs/BetonQuest YAML validation,
and live reload testing against the local/Pelican PaperMC server.
"""
import os
import subprocess
from pathlib import Path
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("Heldengilde-Minecraft-TTRPG")

CONTENT_ROOT = Path(os.environ.get("HG_CONTENT_ROOT", ".")).resolve()
TTRPG_DOCS_DIR = CONTENT_ROOT / "docs" / "ttrpg-source"


@mcp.tool()
def search_ttrpg_rules_and_lore(query: str) -> str:
    """
    Search the official Heldengilde TTRPG rulebooks, classes, spells, and lore
    located in docs/ttrpg-source/ before generating quests, items, or skills.
    """
    if not TTRPG_DOCS_DIR.exists():
        return "TTRPG source directory (docs/ttrpg-source/) does not exist yet."

    matches = []
    q_lower = query.lower()
    for path in TTRPG_DOCS_DIR.rglob("*"):
        if path.suffix.lower() in {".md", ".txt", ".yml", ".yaml", ".json"}:
            text = path.read_text(encoding="utf-8", errors="ignore")
            for idx, line in enumerate(text.splitlines(), start=1):
                if q_lower in line.lower():
                    snippet = "\n".join(text.splitlines()[max(0, idx - 3): idx + 5])
                    matches.append(f"--- {path.relative_to(CONTENT_ROOT)}:{idx} ---\n{snippet}")
                    if len(matches) >= 15:
                        return "\n\n".join(matches)
    return "\n\n".join(matches) if matches else f"No matches found for '{query}'."


@mcp.tool()
def list_ingame_npcs_and_dungeons() -> str:
    """
    Inspect server-owned snapshots (Citizens saves.yml and MythicDungeons YAML)
    so generated BetonQuest packages bind to real NPC IDs and Dungeon names.
    """
    citizens_file = CONTENT_ROOT / "server-owned" / "Citizens" / "saves.yml"
    dungeons_dir = CONTENT_ROOT / "server-owned" / "MythicDungeons" / "dungeons"

    report = ["=== Registered Citizens NPCs ==="]
    if citizens_file.exists():
        for line in citizens_file.read_text(encoding="utf-8", errors="ignore").splitlines():
            if line.strip().startswith(("'0':", "'1':", "'2':", "name:", "uuid:")):
                report.append(line)
    else:
        report.append("No Citizens saves.yml snapshot found yet.")

    report.append("\n=== Registered MythicDungeons ===")
    if dungeons_dir.exists():
        for d_file in dungeons_dir.glob("*.yml"):
            report.append(f"- Dungeon ID: {d_file.stem} ({d_file.name})")
    else:
        report.append("No MythicDungeons snapshots found yet.")

    return "\n".join(report)


@mcp.tool()
def live_reload_and_verify() -> str:
    """
    Trigger a live BetonQuest ('bq reload') and MythicMobs ('mm reload') on the
    local test server and return any syntax/reference errors from latest.log.
    """
    cmd_script = CONTENT_ROOT.parent / "heldengilde-infra" / "agent" / "hg-gitops.sh"
    if cmd_script.exists():
        res = subprocess.run(
            ["bash", str(cmd_script), "deploy-content"],
            capture_output=True,
            text=True,
            check=False,
        )
        return f"Deploy exit={res.returncode}\nSTDOUT:\n{res.stdout}\nSTDERR:\n{res.stderr}"
    return "Local hg-gitops.sh not found; run yamllint and the CI boot-test container instead."


if __name__ == "__main__":
    mcp.run()
```

### Configuratie voor de Agent (`.mcp.json` in `heldengilde-content`)
```json
{
  "mcpServers": {
    "heldengilde-ttrpg": {
      "command": "python3",
      "args": ["tools/mcp-heldengilde/server.py"],
      "env": {
        "HG_CONTENT_ROOT": "."
      }
    }
  }
}
```