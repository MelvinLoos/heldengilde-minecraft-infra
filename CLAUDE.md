# Conventions

- Code, comments, docs and ADRs are in English. In-game and DM-facing text is Dutch.
- Repo names: `heldengilde-minecraft-infra`, `heldengilde-minecraft-content`.
- Single writer per path (ADR 0003). The game container gets no Git access and no tokens.
- Never commit secrets or `*.jar` files (ADR 0005). Pin every plugin and image version.
- Wings ignores the egg `startup` and mounts data at `/home/container`; itzg needs the `/data` Pelican Mount (ADR 0002).
- Shell scripts must pass `shellcheck`; YAML must pass `yamllint`.
- Active Minecraft version is Paper 26.2 on `itzg/minecraft-server:java25` (ADR 0004). Plugin pins are per Minecraft version: never mix `plugins.txt` and `plugins-26.3.txt`.
- `4-server/egg.yaml` is generated: edit `4-server/env/server.env`, then `rm 4-server/egg.yaml && 4-server/build-egg.sh > 4-server/egg.yaml` (the shell has `noclobber`). CI fails if it is out of sync.
- Plugin configs that must be right on first boot go in `4-server/config/` as whole files; itzg patches only apply to files that already exist.
- Premium jars (MythicDungeons) are never in Git or CI; verify author and main class before adding one to `custom-jars.lock.json`.
- The local shell wraps commands with `rtk`, which truncates `curl` and `docker logs`; use `rtk proxy <cmd>` when scripting. The local stack lives in `~/hg-local` (set `HG_ROOT`).
- Do not delete or force-overwrite local Pelican servers/dirs without asking; create new ones instead.
