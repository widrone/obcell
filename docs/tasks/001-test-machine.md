---
id: 001
title: Set up the test machine
status: todo
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

- [ ] `tests/lxd/setup-host.sh` ends with "Ready."
- [ ] A test container has internet access.
- [ ] Machine specs (CPUs, RAM, free disk, LXD version) are noted under Findings.

## Findings
