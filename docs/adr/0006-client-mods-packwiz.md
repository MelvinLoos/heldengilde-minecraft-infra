# ADR 0006: Client mod updates (deferred)

- Status: proposed, deferred
- Date: 2026-11-01

## Context

AutoModpack needs a Fabric/Forge server and cannot run on Paper (ADR 0001 A6).

## Direction

A 1-click Modrinth `.mrpack` profile plus `packwiz-installer-bootstrap` (pack hosted on GitHub Pages from a repo) for zero-click mod updates on launch.

## Open points

- Paper does not host resource packs. It sends `resource-pack` (URL), `resource-pack-sha1` and `require-resource-pack` to the client, so the zip is hosted on the same GitHub Pages site.
- Confirm that the Modrinth App's pre-launch hook can ship preconfigured in the `.mrpack`. Otherwise use Prism Launcher for the hook.
- Bedrock players get neither mods nor voice chat.
