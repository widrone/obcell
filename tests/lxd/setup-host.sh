#!/usr/bin/env bash
# Prepare a TEST machine (not an Obcell box) for tests/matrix.sh. Safe to re-run.
#   - LXD from the snap, initialised with a dir storage pool and the lxdbr0 bridge
#   - your user in the lxd group
#   - checks: CPUs, RAM, disk, the Docker-vs-LXD forwarding problem
#   - the controller venv (./bootstrap.sh), used by --controller outside
# Needs sudo. Ubuntu/Debian-like host with snapd.
set -euo pipefail
cd "$(dirname "$0")/../.."
. tests/lxd/lib.sh
warn() { echo "  ! $*"; }
ok() { echo "  ok: $*"; }

echo "== LXD"
if ! command -v lxc >/dev/null; then
  command -v snap >/dev/null || die "snapd is needed to install LXD (sudo apt install snapd)"
  sudo snap install lxd
fi
ok "$(snap list lxd 2>/dev/null | awk 'NR==2{print "lxd "$2" ("$4")"}')"
if ! id -nG | tr ' ' '\n' | grep -qx lxd; then
  sudo usermod -aG lxd "$USER"
  warn "added $USER to the lxd group: log out and in (or run: newgrp lxd), then re-run this script"
  exit 0
fi
if ! lxc storage list --format csv 2>/dev/null | grep -q .; then
  lxd init --auto --storage-backend=dir
  ok "initialised (dir storage, lxdbr0)"
else
  ok "already initialised: $(lxc storage list --format csv | cut -d, -f1,2 | tr '\n' ' ')"
fi

echo "== Resources (each release container: OCUDU build ~2 GiB RAM per job, ~25 GiB disk)"
cpus=$(nproc); mem=$(free -g | awk '/^Mem:/{print $2}')
pool=$(lxc storage get default source 2>/dev/null || echo /var/snap/lxd/common/lxd)
disk=$(df -BG --output=avail "$pool" 2>/dev/null | tail -1 | tr -dc 0-9)
echo "  $cpus CPUs, $mem GiB RAM, ${disk:-?} GiB free for containers"
[ "$cpus" -ge 4 ] || warn "fewer than 4 CPUs: the gNB build takes hours"
[ "$mem" -ge 10 ] || warn "under 10 GiB RAM: run releases one at a time and set OBCELL_TEST_MEM lower"
[ "${disk:-0}" -ge 40 ] || warn "under 40 GiB free: one release at a time, destroy containers in between"
# How many release containers fit side by side: ~4 CPUs, ~10 GiB RAM (8 GiB limit + host
# headroom) and ~25 GiB disk each. The scarcest resource decides.
n=${#OBCELL_TEST_RELEASES[@]}
fit=$((cpus / 4)) limit="CPUs"
[ $((mem / 10)) -lt "$fit" ] && fit=$((mem / 10)) limit="RAM"
[ $((${disk:-0} / 25)) -lt "$fit" ] && fit=$((${disk:-0} / 25)) limit="disk"
if [ "$fit" -ge "$n" ]; then
  ok "enough for tests/matrix.sh --parallel ($n releases at once)"
elif [ "$fit" -ge 2 ]; then
  ok "room for $fit releases at once, not all $n ($limit is the limit): run them one after another, or e.g. tests/matrix.sh --parallel ${OBCELL_TEST_RELEASES[*]:0:$fit}"
else
  ok "one release at a time ($limit is the limit): tests/matrix.sh without --parallel"
fi

echo "== Networking"
# Docker on the same host sets the iptables FORWARD policy to DROP, which silently breaks
# the containers' internet access through lxdbr0, unless DOCKER-USER lets lxdbr0 through
# (tests/lxd/lxdbr0-forward.service adds exactly those two rules, at every boot).
if command -v docker >/dev/null && sudo iptables -S FORWARD 2>/dev/null | grep -q '^-P FORWARD DROP'; then
  if sudo iptables -C DOCKER-USER -i lxdbr0 -j ACCEPT 2>/dev/null &&
     sudo iptables -C DOCKER-USER -o lxdbr0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; then
    ok "Docker sets FORWARD to DROP, but DOCKER-USER lets lxdbr0 through"
    systemctl is-enabled -q lxdbr0-forward.service 2>/dev/null ||
      warn "those rules are not from lxdbr0-forward.service: make sure they come back after a reboot"
  else
    warn "Docker set FORWARD to DROP; LXD containers will have no internet. Let lxdbr0 through (now and at every boot) with:"
    echo "      sudo install -m 644 tests/lxd/lxdbr0-forward.service /etc/systemd/system/"
    echo "      sudo systemctl daemon-reload && sudo systemctl enable --now lxdbr0-forward.service"
    echo "    (or run the tests on a host without Docker)"
  fi
else
  ok "FORWARD policy does not block lxdbr0"
fi
if lxc network show lxdbr0 >/dev/null 2>&1; then
  ok "lxdbr0 $(lxc network get lxdbr0 ipv4.address)"
fi

echo "== Controller venv (Ansible)"
./bootstrap.sh
ok "$("$OBCELL_ANSIBLE_VENV/bin/ansible" --version | head -1)"

echo
echo "Ready. Next:  tests/matrix.sh            (all releases, one after another)"
echo "              tests/matrix.sh 24.04      (one release)"
echo "Results land in tests/.work/results/latest/summary.md"
