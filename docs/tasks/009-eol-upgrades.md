---
id: 009
title: Plan the MongoDB 6.0 and Node 20 upgrades
status: todo
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

- [ ] One route is documented and tested twice in a container, with no subscriber loss.
- [ ] There's a Node version recommendation, with the build result.

## Findings
