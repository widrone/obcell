# Testing

There are two kinds of tests, and they run in different places:

| Test | Where | Time |
|---|---|---|
| Quick checks: ansible-lint, syntax check, filter unit tests, shellcheck | GitHub Actions on every push ([`.github/workflows/checks.yml`](../.github/workflows/checks.yml)), or locally | minutes |
| Full install matrix: `tests/matrix.sh` | a **test machine** with LXD | ~1–3 h per release the first time (the OCUDU gNB compiles), much less on re-runs |
| Drift check of a real Obcell: `ansible-playbook site.yml --limit <Obcell> --check --diff` | the Obcell, read-only | minutes |

Never run the full matrix on an Obcell box. The reference Obcell, for example, has 4 threads and is a live Obcell.

## The test machine

Any Linux box with snapd, sudo, and ideally 8+ CPU threads, 16+ GB RAM and 100+ GB free
disk. Each release container is limited to 8 GiB RAM by default (`OBCELL_TEST_MEM`) and uses
about 25 GB of disk.

```bash
git clone https://github.com/widrone/obcell && cd obcell
tests/lxd/setup-host.sh          # installs + initialises LXD, checks resources, ./bootstrap.sh
```

If the machine also runs Docker, Docker's `FORWARD DROP` policy cuts LXD containers off from
the internet. setup-host.sh checks for it and, if lxdbr0 isn't let through yet, prints how to
install [`tests/lxd/lxdbr0-forward.service`](../tests/lxd/lxdbr0-forward.service): a small
unit that adds two `DOCKER-USER` rules for lxdbr0 now and at every boot. Docker's own
containers are not affected.

setup-host.sh also says how many releases fit side by side (about 4 CPUs, 10 GiB RAM and
25 GiB disk each), so you know whether `--parallel` is safe on this machine.

## Running the matrix

```bash
tests/matrix.sh                      # 22.04, 24.04, 26.04 one after another
tests/matrix.sh 24.04                # one release
tests/matrix.sh --parallel           # all at once (needs ~4 CPUs, 8 GiB RAM, 25 GiB disk per release)
tests/matrix.sh --fresh 26.04        # delete the container first: a true from-scratch install
tests/matrix.sh --only radio 24.04   # just one phase on an already-built container
tests/matrix.sh --help
```

For each release, in its own container (`obcell-jammy`, `obcell-noble`, `obcell-resolute`):

| Phase | What it does | Pass means |
|---|---|---|
| install | `site.yml` from scratch, then `verify.yml` | no failed task; all units, containers, endpoints and 7 core NFs healthy |
| idempotent | `site.yml` again | `changed=0` |
| radio | `tests/lxd/radio-smoke.sh` | the gNB (ZeroMQ) gets **NG Setup** with the AMF; if srsUE was built, a virtual **UE attaches**, gets a PDU session and pings the core gateway (`10.45.0.1`) |

By default each container **installs itself** (`--controller inside`): the repo is copied
in, `./bootstrap.sh` creates the Ansible venv with that release's Python, and the playbook
runs with `ansible_connection: local`. That is exactly what a new Obcell box does, so it also
tests the ansible-core version picked for that release. `--controller outside` drives the
containers from the test machine's own venv instead.

srsUE is built by default (`-e srsue_enabled=true`), which adds about 30 minutes;
`--no-srsue` skips it, and then the UE end-to-end check reports SKIP.

## Results

```
tests/.work/results/latest -> <UTC time>/
  summary.md                 table per release + the first failure / non-idempotent tasks
  <release>/install.log      full Ansible output
  <release>/idempotent.log
  <release>/radio.log        RESULT ng_setup=…, RESULT e2e=… lines + gNB/UE logs on failure
  <release>/result.env       the same results as key=value (for scripts)
```

`tests/.work/` is git-ignored. When you record results in a task file, paste the
summary table, not the logs.

## Working inside a test container

```bash
tests/lxd/run.sh 24.04 up             # create/prepare the container only
tests/lxd/run.sh 24.04 shell          # root shell inside it
tests/lxd/run.sh 24.04 --tags ocudu   # outside controller, one role
OBCELL_TEST_CONTROLLER=inside tests/lxd/run.sh 26.04 --tags base
tests/lxd/radio-smoke.sh 24.04
tests/lxd/run.sh 24.04 destroy
```

Environment: `OBCELL_TEST_CPUS` (LXD `limits.cpu`, e.g. `4` or `2-5`; default all),
`OBCELL_TEST_MEM` (default `8GiB`), `OBCELL_ANSIBLE_VENV`.

## Testing reset.yml

`reset.yml` should leave a box like a fresh Ubuntu plus the base tools. To check that, compare
a fresh container with the same container after install + reset:

1. `tests/lxd/run.sh 22.04 destroy`, then `tests/lxd/run.sh 22.04 up`; record the state
   (installed packages, apt sources and keys, users, groups, unit files, `/etc` entries, links).
2. Install (a partial install is enough: `tests/lxd/run.sh 22.04 --tags base,docker,core,sdr,cli,control`;
   `verify.yml` then fails on the missing gNB, which is expected), and start some Docker stack.
3. `ansible-playbook -i tests/lxd/inventory.yml --limit obcell-jammy reset.yml -e obcell_reset_confirm=obcell-jammy`,
   then `lxc restart obcell-jammy`, and record the state again.

Last run (2026-11-21, 22.04): nothing from the fresh state was missing. What was left is
the base role's packages (kept on purpose), `/etc/iptables/rules.v6` from iptables-persistent,
the avahi line commented out again, and `~/obcell-backups`. A second `reset.yml` on the reset box
runs clean. snapd fails in these containers after any reboot, reset or not, because the test
container hides AppArmor (see below).

## Upgrade test

`tests/lxd/upgrade-smoke.sh` tests [upgrades.md](upgrades.md) in the 22.04 container (the only
release with MongoDB 6.0 and 7.0 packages). It needs a container installed with the old
versions: build it from a commit before the upgrade work (`edfae77`), or put an installed one
back with `reset-old`.

```bash
tests/lxd/upgrade-smoke.sh 22.04 seed          # 5 more subscribers with random keys; saves the reference dump
tests/lxd/upgrade-smoke.sh 22.04 route-a 24    # upgrade.yml in place, site.yml (Node 24), verify.yml
tests/lxd/upgrade-smoke.sh 22.04 reset-old     # back to MongoDB 6.0 + Node 20 with the reference data
tests/lxd/upgrade-smoke.sh 22.04 route-b 24    # backup, wipe, fresh MongoDB, mongorestore --drop, site.yml
tests/lxd/upgrade-smoke.sh 22.04 webui 26      # only move Node.js (WebUI rebuild)
```

Each run ends with `STATE` lines: package versions, FCV, apt repositories, a fingerprint of
the whole `open5gs` database (`accounts=1 subscribers=6 sha256=…`) and a WebUI login that
lists the subscribers through the WebUI's API. The fingerprint must match the one `seed`
printed. `OBCELL_TEST_MONGODB=7.0` stops route a at 7.0.

## What the test containers need (and why)

The containers are unprivileged with nesting. Docker 29 inside LXD needs these, and
`run.sh` and `tests/lxd/group_vars/obcell.yml` set them **for the test containers only**:

- **`fuse-overlayfs` storage driver, containerd snapshotter off.** Docker's default overlayfs
  snapshotter can't mount on LXD's `dir` pool.
- **`limits.kernel.rtprio=99`.** The intercom SFU asks for `ulimit rtprio 99`.
- **AppArmor:** `lxc.apparmor.profile=unconfined`, plus a boot unit that hides AppArmor from
  Docker. runc ≥ 1.3.3 (the CVE-2025-52881 fix) reopens sysctl files, which LXD 5.0's
  AppArmor profile denies inside nested containers.

The test vars use `sdr_type: zmq` (no RF) and a public 3GPP test SIM (`999700000000099`,
TS 35.208 test set 1). `radio-smoke.sh` refuses to start any gNB whose config isn't the
ZeroMQ driver.
