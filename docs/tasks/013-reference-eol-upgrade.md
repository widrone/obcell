---
id: 013
title: Upgrade MongoDB and Node.js on the reference Obcell
status: todo
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
- Read-only previews on it (2026-11-22, branch `eol-upgrades`, before the defaults changed):
  - `upgrade.yml --check -e mongodb_version=8.0`: plan `MongoDB 6.0 -> 7.0 -> 8.0`, the cell is off air.
  - `site.yml --tags open5gs --check -e nodejs_major=24 -e mongodb_version=8.0`: 4 changes
    (NodeSource repository, Node.js, WebUI rebuild, build stamp) plus the
    "MongoDB upgrade pending" note.
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

- [ ] `mongod --version` is 8.0.x and the FCV is 8.0.
- [ ] `node --version` is the `nodejs_major` from `group_vars/all/main.yml`.
- [ ] The subscriber and account counts are the same as before, and the WebUI login works.
- [ ] `verify.yml` passes and `site.yml --check --diff` reports `changed=0`.

## Findings
