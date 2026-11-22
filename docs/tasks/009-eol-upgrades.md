---
id: 009
title: Plan the MongoDB 6.0 and Node 20 upgrades
status: done
where: test machine
needs_human: yes      # approve before touching a real Obcell's database
depends_on: [003]
---

## Goal

A tested, written procedure that moves an existing 22.04 Obcell off end-of-life components
without losing data. Doing it on the reference Obcell is a separate, human-approved step.

## Context

- MongoDB 6.0 (on 22.04 Obcells) has been end of life since mid-2025. MongoDB supports
  upgrades one major at a time: 6.0 → 7.0 → 8.0, and each step needs
  `setFeatureCompatibilityVersion`. New 24.04/26.04 Obcells start on 8.0.
- Node 20 (only used to build the Open5GS WebUI from source) has been end of life since
  April 2026. Check whether WebUI v2.8.0 builds on Node 22 or 24.
- Data that matters: the Open5GS subscribers (SIM keys). `obcell backup` dumps them
  (mongodump), and `restore.yml` restores them with mongorestore, which works across
  majors. The simplest safe route might be: back up, install 8.0 fresh, restore.

## Steps

1. In a 22.04 test container (task 002), add a few test subscribers and run `obcell backup`.
2. Try both routes:
   - (a) in-place 6.0→7.0→8.0 with FCV steps;
   - (b) back up, purge, install 8.0, run `restore.yml`.
   Time each, and check that the subscribers, the WebUI login and verify still work.
3. Try `nodejs_major: 22` (and 24) for the WebUI build.
4. Write the procedure into `docs/` (or as playbook vars plus a small upgrade playbook),
   and open a follow-up task for applying it to the reference Obcell, marked `needs_human: yes`.

## Done when

- [x] One route is documented and tested twice in a container, with no subscriber loss.
- [x] There's a Node version recommendation, with the build result.

## Findings

### 2026-11-22: both routes tested, Node.js 24 chosen

**Versions.** MongoDB 9.0 exists too, but nothing here has been tested on it, so the target
stays 8.0 (EOL 2029-10-31), the same as 24.04/26.04 boxes. jammy has 6.0, 7.0 and 8.0 packages
(7.0 isn't published for noble, which doesn't matter: noble boxes started on 8.0).
Node.js: 20 EOL 2026-04-30, 22 EOL 2027-04-30, 24 EOL 2028-04-30, 26 LTS since 2026-10-28.

**What changed in the repo** (branch `eol-upgrades`):

- `mongodb_version: "8.0"` and `nodejs_major: 24` on every release.
- open5gs role: a box keeps the MongoDB series it has (warning when it differs), and other
  series' repos and keys are removed. Before, changing `mongodb_version` added a second
  repo and left the old server installed, and `apt upgrade` would then have pulled a major
  that can't start on the data.
- open5gs role: Node.js moves up to `nodejs_major` (version pattern). The WebUI is rebuilt
  when it was built with another Node.js or Open5GS version (stamp file
  `/usr/lib/node_modules/open5gs/.obcell-build`), keeping its `.env` session secrets. Check
  mode reports both instead of failing on a repo it hasn't fetched.
- `upgrade.yml` (new): `obcell backup`, refuses while on air, then per step: FCV check, repo
  swap, all seven `mongodb-org*` packages pinned to the next series (`mongodb-org` depends on
  its parts without versions, so naming only it would leave the old server), restart, raise
  the FCV. `--check` shows the plan only.
- `tests/lxd/upgrade-smoke.sh` (new), [docs/upgrades.md](../upgrades.md), README, testing.md.

**Test runs** in `obcell-jammy` on the test machine. Built from `edfae77` (MongoDB 6.0.30,
Node.js 20.20.2), 36 min, install + health PASS. `seed` added 5 subscribers with random keys
to the test SIM: `accounts=1 subscribers=6 sha256=9f7c9d1f40396fb8`. `state` checks that
fingerprint (every document of the `open5gs` database), the FCV, and a WebUI login that lists
the subscribers through the WebUI's own API.

| # | Run | MongoDB | Node.js | Time | Fingerprint | WebUI | verify |
|---|---|---|---|---|---|---|---|
| 1 | route a: `upgrade.yml`, then site.yml | 6.0.30 → 7.0 → 8.0.38, FCV 8.0 | 20 → 24.22.3 | upgrade 71 s, site 187 s | same | PASS | PASS |
| – | site.yml again (idempotence) + radio-smoke | | | | | | `changed=0`; NG Setup, UE e2e PASS |
| – | `reset-old` | → 6.0.30 | → 20 | 108 s | same | PASS | |
| 2 | route b: backup, wipe, fresh 8.0, `mongorestore --drop`, site.yml | → 8.0.38, FCV 8.0 | 20 → 26.13.1 | 114 s + site 124 s | same | **FAIL** (Node 26, below) | **FAIL** (WebUI URL) |
| – | Node.js 26 → 24 (purge, `webui 24`) | | → 24.22.3 | 92 s | same | PASS | |
| – | `reset-old` | → 6.0.30 | → 20 | 117 s | same | PASS | |
| 3 | route a, first run: `OBCELL_TEST_MONGODB=7.0` | → 7.0.48, FCV 7.0 | 20 → 22.23.5 | upgrade 45 s, site 188 s | same | PASS | PASS |
| 4 | route a, second run: on to 8.0 | 7.0.48 → 8.0.38, FCV 8.0 | 22 → 24.22.3 | upgrade 36 s, site 210 s | changed, see below | PASS | PASS; NG Setup, UE e2e PASS |

- **Route a is the documented route.** It ran twice (#1 in one go, #3+#4 in two runs, which
  is also the "upgrade.yml stopped partway" case), with no subscriber lost.
- **Run #4's fingerprint** differs only in the test SIM's `imeisv` and `security.sqn`; the 5
  seeded subscribers and the account are byte-identical to the reference. Cause: the AMF still
  held the test UE's context from the radio check after run #1 (the resets don't restart
  it). Its mobile-reachable timer fired at 20:11:26 UTC (`Network-initiated De-register UE`,
  UDM then talked to the UDR), 13 s before run #4 took its fingerprint. That's the core
  writing runtime fields in normal operation, not the upgrade. `reset-old` now restarts the AMF.
- **Route b works** (same data), but it is the rollback route, not the main one. It needs
  `mongorestore --drop`: `restore.yml` keeps documents that are already there, and a fresh
  install has already provisioned the SIMs from secrets and, if the WebUI was rebuilt, the
  default admin account. Those would win over the backup (edited SIMs back to the secrets
  values, a changed admin password back to `1423`).
- **Node.js 26:** the WebUI builds, then crash-loops at start: `buffer-equal-constant-time`
  (via `jsonwebtoken` → `jws` → `jwa`) reads `SlowBuffer.prototype`, which newer Node.js
  removed. site.yml doesn't notice (systemd restarts the service), verify.yml does. New
  [task 014](014-webui-node26.md). **Node.js 22 and 24 both build and run**; 24 is the
  default because its support runs a year longer.
- **site.yml can't move Node.js down:** apt only picks an older version than the installed one
  at pin priority >= 1000, and the apt module's `allow_downgrade` doesn't get there
  ("no available installation candidate"). The role now asserts with a clear message instead.
  `reset-old` purges Node.js first.
- **Reference Obcell, read-only** (d648aaa): `upgrade.yml --check` plans 6.0 → 7.0 → 8.0;
  `site.yml --check --diff` shows `changed=4`, all the Node.js/WebUI move. Its WebUI has the
  `.env` with both secrets (mode 644, as the WebUI creates it). Applying it is
  [task 013](013-reference-eol-upgrade.md).

### 2026-11-22: full matrix with the new defaults (d648aaa)

| Release | ansible-core | Install | Health | Idempotent | NG Setup | UE end-to-end | Minutes |
|---|---|---|---|---|---|---|---|
| 24.04 (obcell-noble), existing container on Node 20 | 2.20.11 (inside) | PASS | PASS | PASS | PASS | PASS | 15 |
| 22.04 (obcell-jammy), fresh | 2.17.14 (inside) | PASS | PASS | PASS | PASS | PASS | 39 |
| 26.04 (obcell-resolute), fresh | 2.20.11 (inside) | PASS | PASS | PASS | PASS | PASS | 41 |

- 24.04: site.yml moved the existing box from Node.js 20 to 24 and rebuilt the WebUI
  (the other changed tasks were the container catching up on commits since it was built).
- 22.04 fresh: MongoDB 8.0 repo and Node.js 24 straight away, no "upgrade pending" note.
- noble and resolute now run MongoDB 8.0.38 and Node.js 24.22.3. The 22.04 container was
  deleted afterwards for disk, so the test machine is back to noble + resolute.

