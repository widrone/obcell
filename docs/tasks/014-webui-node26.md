---
id: 014
title: Run the Open5GS WebUI on Node.js 26
status: todo
where: test machine
needs_human: no
depends_on: [009]
---

## Goal

`nodejs_major: 26` works: the WebUI builds, starts and logs in. Needed before Node.js 24's
end of life (2028-04-30).

## Context

- Found in [task 009](009-eol-upgrades.md) (2026-11-22): with Node.js 26.13.1 the WebUI
  (Open5GS v2.8.0) builds, then crashes at start:
  `buffer-equal-constant-time/index.js:37: TypeError: Cannot read properties of undefined (reading 'prototype')`
  (`SlowBuffer.prototype.equal`). Newer Node.js removed `SlowBuffer`. The module comes in via
  `jsonwebtoken` → `jws` → `jwa`.
- `verify.yml` catches it (the WebUI URL doesn't answer), but `site.yml` doesn't: systemd
  restarts the service forever.

## Steps

1. Check whether a newer Open5GS release has updated the WebUI's dependencies. If it has,
   moving `open5gs_version` might be all that's needed.
2. Otherwise, try an npm `overrides` entry for `jwa` (a version that doesn't need
   `buffer-equal-constant-time`), applied as a patch in the WebUI build.
3. Test on a container with Node.js 24 with `tests/lxd/upgrade-smoke.sh 22.04 webui 26`
   (docs/testing.md#upgrade-test), then the full matrix.

## Done when

- [ ] The WebUI starts on Node.js 26, and `upgrade-smoke.sh … state` shows `login=PASS`.
- [ ] The matrix passes on all releases with `nodejs_major: 26`.

## Findings
