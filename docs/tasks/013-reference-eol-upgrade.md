---
id: 013
title: Upgrade MongoDB and Node.js on the reference Obcell
status: todo          # all checks pass (2026-11-23); waiting for the owner's WebUI login
where: reference Obcell
needs_human: yes      # touches the live Obcell's subscriber database; needs an explicit OK in the conversation
depends_on: [009]
---

## Goal

The reference Obcell runs MongoDB 8.0 and the current `nodejs_major`, with every subscriber and
the WebUI login unchanged, and `site.yml --check --diff` back at `changed=0`.

## Context

- The procedure is [docs/upgrades.md](../upgrades.md), tested in [task 009](009-eol-upgrades.md).
- The reference Obcell is a 22.04 box on MongoDB 6.0.30 and Node.js 20.20.2 (2026-11-22).
- Read-only previews on it (2026-11-22, branch `eol-upgrades` at d648aaa, defaults 8.0 / 24):
  - `upgrade.yml --check`: plan `MongoDB 6.0 -> 7.0 -> 8.0`, the cell is off air.
  - `site.yml --check --diff` (all roles): `changed=4`, all in the open5gs role: NodeSource
    repository (`node_20.x` → `node_24.x`), `Node.js 24 would come from the new repository`,
    `WebUI would be rebuilt` (`open5gs 2.8.0 node 20 -> open5gs 2.8.0 node 24`), and the new
    build stamp. Plus the "MongoDB upgrade pending" note.
- Its WebUI was installed by hand before the automation. It has the `.env` with both
  secrets, which the rebuild keeps.

## Steps

1. **Ask the human** for a time when the cell and the WebUI aren't needed. The cell must be off air.
2. `ansible-playbook upgrade.yml --limit <host> --check` and `site.yml --check --diff`.
   Explain every change, as in task 007.
3. With the human's OK, follow docs/upgrades.md steps 3 to 5.
4. Compare before and after: the number of subscribers and accounts
   (`mongosh --quiet open5gs --eval 'db.subscribers.countDocuments()'`), a WebUI login,
   and `obcell status`.

## Done when

- [x] `mongod --version` is 8.0.x and the FCV is 8.0.
- [x] `node --version` is the `nodejs_major` from `group_vars/all/main.yml`.
- [ ] The subscriber and account counts are the same as before, and the WebUI login works.
      (Counts and the whole database: same. Login: waiting for the owner, see Findings.)
- [x] `verify.yml` passes and `site.yml --check --diff` reports `changed=0`.

## Findings

### 2026-11-23: upgraded, main at e1429a5

Asked for by the owner in the conversation ("upgrade … now"). The cell was off air (gNB unit
inactive and disabled) and stayed that way. Followed docs/upgrades.md steps 2 to 5, run on the
box itself.

| Step | Result | Time |
|---|---|---|
| `upgrade.yml --check` | plan `MongoDB 6.0 -> 7.0 -> 8.0`, the cell is off air, `changed=0` | |
| `site.yml --check --diff` | `changed=4`, the same four as on 2026-11-22, plus the "upgrade pending" note | 1 min 40 s |
| `upgrade.yml` | `obcell backup` (archive includes `open5gs-mongo.archive.gz`), 6.0 → 7.0 → 8.0, FCV raised after each step, `changed=14`, `failed=0` | 68 s |
| `site.yml --check --diff` | the same four Node.js/WebUI changes; "upgrade pending" now skipped | |
| `site.yml` | `changed=10`: NodeSource repository, Node.js 24, WebUI build (5 tasks), build stamp, WebUI restart, and the admin-account task (see below) | 3 min 7 s |
| `verify.yml` | `changed=0`, `failed=0` | |
| `site.yml --check --diff` | `changed=0` | |

Before and after, compared with a state script (versions, FCV, repositories, a sha256 over every
document of every collection in the `open5gs` database, a hash of the WebUI's `.env`, units):

| | Before | After |
|---|---|---|
| MongoDB | 6.0.30, FCV 6.0, `mongodb-org-6.0.list` | 8.0.38, FCV 8.0, `mongodb-org-8.0.list` |
| Node.js | 20.20.2, no build stamp | 24.22.3, stamp `open5gs 2.8.0 node 24` |
| `open5gs` database | accounts=1 subscribers=1 | the same, and the same sha256 |
| WebUI `.env` (session secrets) | | unchanged (same hash) |
| WebUI | `/api/auth/csrf` 200, front door 302 (login page) | the same |
| MongoDB, UDR, PCF, HSS, PCRF, WebUI, AMF | active | active |
| gNB | inactive, disabled | inactive, disabled |

The whole-box snapshot from task 008 (services, containers, network, web front doors, probes,
alerts, radio feed, Intercom, Open Live, on-air control, OwnTracks) is identical before and
after. `obcell status` differs only in uptime, load and temperature (62 °C → 80 °C right after
the WebUI build).

- The task "Default WebUI admin account (admin / 1423) if none exists" reports `changed` on
  every WebUI rebuild because it is a plain `command`. It runs Open5GS's `mongo-init.js`, which
  only adds an account when none exists: the database hash shows it changed nothing here.
- No scripted WebUI login on this box: its admin password isn't in `secrets/` (the account was
  made by hand before the automation). The database and the `.env` are unchanged, so the
  existing password and sessions still work; the owner's browser login closes the last box.
