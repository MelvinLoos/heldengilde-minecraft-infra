# ADR 0008: Spell items go through a HeldengildeParty bridge

- Status: accepted
- Date: 2026-11-01

## Decision

The stack stays free apart from MythicDungeons, so there is no paid item-trigger plugin. Spells and abilities are MythicMobs skills (`MythicMobs/Skills/*.yml`) and spell items are plain MythicMobs items (`MythicMobs/Items/*.yml`) that carry tags: `HgSpell` (skill name), `HgManaCost` and optionally `HgCooldown`.

The future `HeldengildeParty` plugin listens for `PlayerInteractEvent`, reads the tags, checks and consumes mana through the AuraSkills API, applies the Heldengilde safety rules (for example no casting in the Quiet Corner) and casts the skill with `MythicBukkit.inst().getAPIHelper().castSkill(player, skillName)`.

## Consequences

- `HeldengildeParty` is on the critical path for player spells. Until it exists, spell items can be held but not cast.
- The tag contract lives in `CLAUDE.md` of the content repo and is provisional. When the plugin is built, verify how MythicMobs writes `NBT:` into the item's PDC.
- Item-trigger syntax (`~onUse`, `~onSwing`, `~onCrouch`) does not belong in item files; the content repo's `validate_content` tool rejects it.
- `custom-jars.lock.json` is unchanged.
