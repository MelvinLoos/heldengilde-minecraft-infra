#!/usr/bin/env bash
# Starts the systemd Ubuntu 24.04 test host on 127.0.0.1:2222 (root login by key, replaced by the
# bootstrap role's hardening). Prints the inventory to use. Idempotent.
set -euo pipefail
cd "$(dirname "$0")"
HG_ROOT="${HG_ROOT:-$HOME/hg-local}"
key="$HG_ROOT/target-key"
mkdir -p "$HG_ROOT"
[ -f "$key" ] || ssh-keygen -q -t ed25519 -N '' -f "$key"
docker build -q -t hg-target:24.04 . >/dev/null
docker rm -f hg-target >/dev/null 2>&1 || true
docker volume rm -f hg-target-docker hg-target-containerd >/dev/null 2>&1 || true
docker volume create hg-target-docker >/dev/null
docker volume create hg-target-containerd >/dev/null
docker run -d --name hg-target --privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  --tmpfs /run --tmpfs /run/lock -v hg-target-docker:/var/lib/docker -v hg-target-containerd:/var/lib/containerd -p 127.0.0.1:2222:22 hg-target:24.04 >/dev/null
docker exec -i hg-target bash -c "mkdir -p /root/.ssh && cat > /root/.ssh/authorized_keys" < "$key.pub"
docker exec hg-target bash -c "echo 'PermitRootLogin prohibit-password' > /etc/ssh/sshd_config.d/00-test.conf && systemctl restart ssh"
echo "target up: ssh -i $key -p 2222 root@127.0.0.1"
