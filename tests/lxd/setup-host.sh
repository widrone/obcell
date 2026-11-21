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
[ "$cpus" -ge 12 ] && [ "$mem" -ge 30 ] && ok "enough for tests/matrix.sh --parallel"

echo "== Networking"
# Docker on the same host sets the iptables FORWARD policy to DROP, which silently breaks
# the containers' internet access through lxdbr0.
if command -v docker >/dev/null && sudo iptables -S FORWARD 2>/dev/null | grep -q '^-P FORWARD DROP'; then
  warn "Docker set FORWARD to DROP; LXD containers will have no internet. Allow the bridge with:"
  echo "      sudo iptables -I DOCKER-USER -i lxdbr0 -j ACCEPT"
  echo "      sudo iptables -I DOCKER-USER -o lxdbr0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
  echo "    (make it permanent with iptables-persistent, or run the tests on a host without Docker)"
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
