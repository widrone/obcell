#!/usr/bin/env bash
# Fresh-install test of the whole Obcell in an LXD container (no radio: sdr_type=zmq).
#   tests/lxd/run.sh [RELEASE]                 create container (if needed) + run site.yml + verify.yml
#   tests/lxd/run.sh [RELEASE] up              only create/prepare the container
#   tests/lxd/run.sh [RELEASE] destroy         delete the container
#   tests/lxd/run.sh [RELEASE] shell           root shell in the container
#   tests/lxd/run.sh [RELEASE] <ansible args>  e.g. --tags base,docker
#   OBCELL_TEST_CONTROLLER=inside tests/lxd/run.sh ...  run Ansible inside the container (bootstrap.sh there)
# RELEASE: 22.04 (default, container obcell-jammy), 24.04 (obcell-noble), 26.04 (obcell-resolute)
set -euo pipefail
cd "$(dirname "$0")/../.."
. tests/lxd/lib.sh
REL=22.04
case "${1:-}" in 2[0-9].04) REL=$1; shift ;; esac
C=$(container_for "$REL")
INV="-i tests/lxd/inventory.yml --limit $C"
if [ "${1:-}" = destroy ]; then lxc delete -f $C; exit; fi
if [ "${1:-}" = shell ]; then exec lxc exec $C -- bash -l; fi
command -v lxc >/dev/null || die "LXD is not installed; run tests/lxd/setup-host.sh first"
if ! lxc info $C >/dev/null 2>&1; then
  # OBCELL_TEST_CPUS: LXD limits.cpu (a count like 4, or a set like 2-5); unset = all CPUs.
  # OBCELL_TEST_MEM: memory limit per container (the OCUDU build wants ~2 GiB per job).
  lxc launch ubuntu:$REL $C \
    -c security.nesting=true \
    -c security.syscalls.intercept.mknod=true -c security.syscalls.intercept.setxattr=true \
    ${OBCELL_TEST_CPUS:+-c limits.cpu="$OBCELL_TEST_CPUS"} -c limits.memory="${OBCELL_TEST_MEM:-8GiB}"
  lxc config device add $C tun unix-char path=/dev/net/tun
  lxc config device override $C root size=40GiB 2>/dev/null || true
fi
# runc >= 1.3.3 (CVE-2025-52881 fix) reopens sysctl files, which older LXD AppArmor
# profiles deny inside nested containers. Test container only; it stays unprivileged.
# The intercom SFU asks for ulimit rtprio 99, so the container must allow it.
if ! lxc config get $C raw.lxc | grep -q 'apparmor.profile=unconfined' \
   || [ "$(lxc config get $C limits.kernel.rtprio)" != 99 ]; then
  lxc config set $C raw.lxc 'lxc.apparmor.profile=unconfined'
  lxc config set $C limits.kernel.rtprio=99
  lxc restart $C 2>/dev/null || lxc start $C
fi
for _ in $(seq 60); do lxc exec $C -- systemctl is-system-running 2>/dev/null | grep -qE 'running|degraded' && break; sleep 2; done
# With the profile unconfined, dockerd would still see AppArmor "enabled" and fail to
# read its profile list, so mask the flag for the test container (before Docker starts).
lxc exec $C -- sh -c 'cat > /etc/systemd/system/obcell-test-mask-apparmor.service' <<'UNIT'
[Unit]
Description=Hide AppArmor from Docker (LXD test container only)
DefaultDependencies=no
Before=containerd.service docker.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'echo N > /run/apparmor-disabled; mountpoint -q /sys/module/apparmor/parameters/enabled || mount --bind /run/apparmor-disabled /sys/module/apparmor/parameters/enabled'
[Install]
WantedBy=sysinit.target
UNIT
lxc exec $C -- sh -c 'systemctl daemon-reload; systemctl enable --now obcell-test-mask-apparmor.service >/dev/null 2>&1; if systemctl is-active -q docker; then systemctl restart containerd docker; fi'
if [ "${1:-}" = up ]; then exit; fi
if [ "${OBCELL_TEST_CONTROLLER:-outside}" = inside ]; then
  # Like a new box: copy the repo in (tracked + new files, never secrets/), bootstrap the
  # controller with the container's own Python, run the playbook against itself.
  lxc exec $C -- sudo -u ubuntu mkdir -p /home/ubuntu/obcell-src
  git ls-files -co --exclude-standard -z | tar c --null -T - \
    | lxc exec $C -- sudo -u ubuntu tar x -C /home/ubuntu/obcell-src
  q=$(printf ' %q' "$@")
  lxc exec $C -- sudo -iu ubuntu bash -c "cd ~/obcell-src && ./bootstrap.sh && . ./activate && \
    ansible --version | head -1 && \
    ansible-playbook -i tests/lxd/inventory-local.yml --limit $C site.yml $q && \
    ansible-playbook -i tests/lxd/inventory-local.yml --limit $C verify.yml"
  exit
fi
# ansible-playbook writes secrets to secrets/$C/ (generated, like on any new box)
ansible-playbook $INV site.yml "$@"
ansible-playbook $INV verify.yml
