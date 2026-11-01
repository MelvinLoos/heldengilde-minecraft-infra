# Throwaway Ubuntu 24.04 "host" with systemd + sshd, used to test the Ansible roles locally.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends systemd systemd-sysv openssh-server python3 sudo \
      ca-certificates iproute2 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /run/sshd /root/.ssh && systemctl enable ssh \
 && systemctl mask getty.target systemd-logind.service
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
