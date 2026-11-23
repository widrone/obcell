---
id: 014
title: Run the Open5GS WebUI on Node.js 26
status: done
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

- [x] The WebUI starts on Node.js 26, and `upgrade-smoke.sh … state` shows `login=PASS`.
- [x] The matrix passes on all releases with `nodejs_major: 26`.

## Findings

### 2026-11-23: jwa pinned to 1.4.2, Node.js 26 by default

**Upstream:** no Open5GS release after v2.8.0. The WebUI commits on `main` since then don't touch
dependencies. Two of them are access-control fixes, now [task 015](015-webui-upstream-fixes.md).

**npm:** every `jwa` release still lists `buffer-equal-constant-time`, which has had no release
since 1.0.1 (2013). But `jwa` 1.4.2 and 2.0.1 (2025-05-07) only `require` it when
`crypto.timingSafeEqual` is missing, which it never is on Node.js 6.6+. WebUI v2.8.0's lockfile
has `jwa` 1.4.1, the last version that loads it at startup. `jws` 3.2.2 asks for `jwa ^1.4.1`,
and `jwa` is the only package that needs `buffer-equal-constant-time`.

**Changes:**

- `open5gs_webui_npm_overrides: {jwa: "1.4.2"}` (group_vars). Before `npm clean-install`, the
  build runs `npm pkg set overrides.jwa=1.4.2` and
  `npm install --package-lock-only --ignore-scripts`, which re-resolves the lockfile from
  metadata only.
- The build stamp carries the overrides (`open5gs 2.8.0 node 26 jwa@1.4.2`), so a box
  rebuilds once when they change.
- New handler "WebUI answers after the restart": `site.yml` now fails when the WebUI
  doesn't answer on `/api/auth/csrf` within 60 s, instead of passing while systemd restarts
  it forever.
- `nodejs_major: 26` (supported until 2029-04-30, a year longer than 24). Docs updated:
  upgrades.md, configuration.md, ubuntu-releases.md, testing.md.
- `upgrade-smoke.sh state` prints the installed `jwa` version(s).

**Test on the 24.04 container** (`upgrade-smoke.sh 24.04 webui 26`, from Node.js 24):

| | Before | After |
|---|---|---|
| Node.js | 24.22.3 | 26.13.1 |
| WebUI `jwa` | 1.4.1 | 1.4.2 (the only copy) |
| Stamp | `open5gs 2.8.0 node 24` | `open5gs 2.8.0 node 26 jwa@1.4.2` |
| Data | accounts=1 subscribers=1 sha256=e345d5edf3e57094 | the same |
| WebUI login + subscriber list via its API | PASS | PASS |
| WebUI restarts since start | | 0 |

`changed=10`, 134 s. The new handler needed one retry while the WebUI started.

- **The old build crash-loops for about a minute during the move.** As soon as apt installed
  Node.js 26, the old WebUI was restarted (01:01:08; most likely `needrestart`). The old build,
  with `jwa` 1.4.1, then crashed every 3 s with the `SlowBuffer` error until the rebuild
  replaced it (01:02:25). After that it logged only a MongoDB driver deprecation warning
  (`collection.ensureIndex`). This happens once, on the move off an unpinned build, and the
  WebUI is down during a rebuild anyway. Noted in upgrades.md.
- Read-only preview on the reference Obcell with this branch: `changed=4`, all for the move:
  NodeSource `node_24.x` → `node_26.x`, Node.js 24.22.3 → 26.x, the WebUI rebuild
  (`open5gs 2.8.0 node 24` → `open5gs 2.8.0 node 26 jwa@1.4.2`), and the stamp.
- Seen in passing: on the reference Obcell, `~/.npm` belongs to root (5926 files, all from
  2026-11-18, before the automation existed). Playbook builds use `/root/.npm`, so it doesn't
  come from the role.

**Matrix at 14bf95f** (`nodejs_major: 26`; 24.04 already moved by the test above, 26.04 moved
from Node.js 24 by the matrix run itself, 22.04 fresh):

| Release | ansible-core | Install | Health | Idempotent | NG Setup | UE end-to-end | Minutes |
|---|---|---|---|---|---|---|---|
| 22.04 (fresh) | 2.17.14 (inside) | PASS | PASS | PASS | PASS | PASS | 49 |
| 24.04 (existing) | 2.20.11 (inside) | PASS | PASS | PASS | PASS | PASS | 15 |
| 26.04 (existing, Node.js 24 → 26) | 2.20.11 (inside) | PASS | PASS | PASS | PASS | PASS | 15 |

Afterwards, `upgrade-smoke.sh <release> state` on all three: Node.js 26.13.1, `jwa` 1.4.2,
stamp `open5gs 2.8.0 node 26 jwa@1.4.2`, `login=PASS`, 0 WebUI restarts. The test machine now
holds the 22.04, 24.04 and 26.04 containers.

The reference Obcell is still on Node.js 24. Moving it is a `site.yml` run (about 3 minutes
of WebUI rebuild) with the owner's OK; the preview is above.
