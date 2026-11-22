---
id: 001
title: Set up the test machine
status: done
where: test machine
needs_human: yes      # a human provides the machine and sudo
depends_on: []
---

## Goal

A Linux machine, not an Obcell box, that can run `tests/matrix.sh`: LXD installed and
initialised, the controller venv bootstrapped, and enough CPU, RAM and disk.

## Context

- The full tests compile the OCUDU gNB (and srsRAN_4G) in each release container. On the reference Obcell
  (4 threads) that takes too long, and it is a live Obcell, so the tests moved here.
- Recommended: 8+ CPU threads, 16+ GB RAM, 100+ GB free disk. `--parallel` needs about
  4 CPUs and 8 GiB per release.
- See [docs/testing.md](../testing.md).

## Steps

1. Human: provide the machine with sudo, and clone the repo there.
2. Run `tests/lxd/setup-host.sh`. It installs LXD (snap), adds the user to the `lxd` group
   (re-login and run again), runs `lxd init --auto` with a dir pool, checks resources,
   checks Docker's FORWARD policy, and runs `./bootstrap.sh`.
3. If it warns about `FORWARD DROP` (Docker on the same host), apply the two printed
   iptables rules. That's a change to the host, so ask the human first.
4. Smoke-test the harness without a full build:
   `tests/lxd/run.sh 22.04 up && tests/lxd/run.sh 22.04 shell` (check that `ping -c1 ubuntu.com`
   works inside), then `exit`.

## Done when

- [x] `tests/lxd/setup-host.sh` ends with "Ready."
- [x] A test container has internet access.
- [x] Machine specs (CPUs, RAM, free disk, LXD version) are noted under Findings.

## Findings

### 2026-11-22

The test machine is a KVM VM on the tailnet, reached over SSH from the controller.

| | |
|---|---|
| OS | Ubuntu 24.04.5 LTS, kernel 6.8 |
| CPUs | 16 vCPUs (Xeon E5-2620 v4), VT-x |
| RAM | 125 GiB |
| Disk | ~59 GiB free on `/`, where the LXD `dir` pool lives: two release containers at a time |
| LXD | 5.21.9 (snap, `5.21/stable`), `lxd init --auto --storage-backend=dir`, lxdbr0 10.127.21.1/24 |

- It also runs other Docker workloads, so Docker's `FORWARD DROP` cut the containers off
  from the internet (bridge reachable, `curl https://github.com` failed). Fixed with
  `tests/lxd/lxdbr0-forward.service`; afterwards a test container got HTTP 200 from GitHub.
- `setup-host.sh` warned about `FORWARD DROP` even after the fix and said "enough for
  `--parallel`" although only two containers fit on the disk. Both fixed in 3de1af6; it now
  ends with "Ready." and says "room for 2 releases at once (disk is the limit)".
- On Ubuntu 24.04 the `lxd-installer` package's `lxc` stub installs the LXD snap the first
  time anything runs `lxc`, even `lxc version`. Check `snap list` before probing a machine.
- Because the machine is shared, the runs use `OBCELL_TEST_CPUS=8 OBCELL_TEST_MEM=16GiB`
  (8 of 16 CPUs; 16 GiB lets the gNB build use all 8, since build jobs = min(CPUs, RAM / 2 GiB)),
  one release at a time.
