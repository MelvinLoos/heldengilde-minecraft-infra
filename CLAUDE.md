# Conventions

- Code, comments, docs and ADRs are in English. In-game and DM-facing text is Dutch.
- Repo names: `heldengilde-minecraft-infra`, `heldengilde-minecraft-content`.
- Single writer per path (ADR 0003). The game container gets no Git access and no tokens.
- Never commit secrets or `*.jar` files (ADR 0005). Pin every plugin and image version.
- Wings ignores the egg `startup` and mounts data at `/home/container`; itzg needs the `/data` Pelican Mount (ADR 0002).
- Shell scripts must pass `shellcheck`; YAML must pass `yamllint`.
