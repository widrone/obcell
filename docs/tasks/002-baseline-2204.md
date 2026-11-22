---
id: 002
title: "Baseline: 22.04 still passes"
status: done
where: test machine
needs_human: no
depends_on: [001]
---

## Goal

Confirm that the jammy fresh install still passes on the new test machine after the recent
changes, so later failures on 24.04 and 26.04 can be blamed on the release, not on the
harness.

## Context

- On 2026-11-20 a jammy fresh install passed on the reference Obcell's LXD (outside controller,
  ansible-core 2.17): install, idempotent re-run (`changed=0`), verify (7/5/11 containers,
  7 NFs, 1 subscriber), and the zmq gNB got NG Setup.
- Since then:
  - The harness gained the inside controller (default) and `tests/matrix.sh`.
  - `radio-smoke.sh` and its UE end-to-end check were added; neither has run yet.
  - `ocudu_build_jobs` is now capped by RAM.
  - The relative `include_tasks` paths, the "Right machine?" guard and
    `mongodb_repo_release` were added.

## Steps

1. `tests/matrix.sh 22.04` (inside controller, srsUE built; expect ~1–2 h).
2. Read `tests/.work/results/latest/summary.md`.
3. If something fails: decide whether the harness or a role is at fault, fix it in a branch,
   re-run with `--only <phase>` where possible, and record it under Findings.
4. Also run once with `--controller outside` (`--only install,idempotent` is enough once the
   container is built). That covers the case of a laptop driving an Obcell box.

## Done when

- [x] 22.04: install, health, idempotent and NG Setup are PASS with the inside controller.
- [x] 22.04: install and idempotent are PASS with the outside controller.
- [x] The UE end-to-end result is recorded (PASS, or a link to task 005 if it fails).

## Findings

### 2026-11-22

On the test machine (task 001), `OBCELL_TEST_CPUS=8 OBCELL_TEST_MEM=16GiB`, commit bd3c1f5
(which includes the 24.04 and 26.04 fixes from tasks 003 and 004).

| Run | Controller | Install | Health | Idempotent | NG Setup | UE e2e | Min |
|---|---|---|---|---|---|---|---|
| `--fresh 22.04` | inside, ansible-core 2.17.14 | PASS | PASS | PASS | PASS | PASS | 38 |
| `--controller outside --only install,idempotent 22.04` | outside, 2.20.11 | PASS | PASS | PASS | – | – | 19 |

The outside run used the secrets the container had generated (copied to the controller's
`secrets/obcell-jammy/`); both of its site.yml runs reported `changed=0`, so a 2.20
controller leaves a box built by 2.17 exactly as it is. Without the box's own secrets an
outside run regenerates them and Authelia refuses its database (seen on 26.04, task 004).
