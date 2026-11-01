# 1-host-bootstrap

Ansible role `host_bootstrap` for any fresh **Ubuntu 24.04 LTS** host (`x86_64` or `arm64`). See ADR 0007.

It does: admin user + SSH key-only login, `sshd` hardening, unattended-upgrades, fail2ban, sysctl, `ufw`, `DOCKER-USER` rules, Docker Engine, the pinned checksum-verified Wings binary and systemd unit, and optional tunnels.

```bash
cd 1-host-bootstrap
ansible-playbook -i ../3-ansible/inventory/production.yml playbook.yml
```

Inventory and variables: see `../3-ansible/inventory/*.example`. Secrets (tunnel token, Playit secret) belong in the SOPS-encrypted group vars, never in plain inventory.

## Ingress profiles (`host_ingress`)

| Profile | Use when | Inbound ports |
|---|---|---|
| `direct` | Public IP (cloud VM) | ssh, 80/tcp, 443/tcp, 25565/tcp, 24454/udp, 19132/udp |
| `cloudflared` | Home PC: Panel + Wings over HTTPS without port-forwarding | ssh only |
| `playit` | Home PC: game ports (Java TCP, voice UDP, Bedrock UDP) | ssh only |

Cloudflare Tunnel carries HTTP(S) only on the free plan, so a home host uses `[cloudflared, playit]`: the tunnel for Panel/Wings hostnames and Playit.gg for Minecraft. The browser talks to Wings directly for the console websocket, so Wings needs its own tunnel hostname (ADR 0007).

## Firewall model

Docker bypasses `ufw` for published ports. The role therefore sets both layers: `ufw` for the host, and a `DOCKER-USER` chain (systemd unit `hg-docker-user-firewall`) that lets only the profile's ports through from the WAN interface. Rules match `--ctorigdstport`, the pre-DNAT port, because the chain sees the container's port otherwise. Wings allocations on other ports are therefore unreachable from the internet by design; add them to `host_game_*_ports`.

## Safety

- The SSH hardening refuses to run without `host_admin_authorized_keys` (lock-out guard) and validates `sshd -t` first.
- Wings is installed but only starts once `/etc/pelican/config.yml` exists (written by `3-ansible`).
