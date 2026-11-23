---
id: 015
title: Pick up the upstream WebUI access-control fixes, and keep the WebUI's .env private
status: in-progress
where: test machine, reference Obcell
needs_human: yes      # which upstream source to build from (a release, a commit or patches); applying it on the reference Obcell
depends_on: [014]
---

## Goal

The Open5GS WebUI checks account roles on the server, as upstream does since November 2026,
and its `.env` (session and JWT secrets) is readable only by its owner.

## Context

Found during [task 014](014-webui-node26.md) (2026-11-23).

- `open5gs_version` is `2.8.0` (2026-06-20), the latest release. Upstream `main` has three
  WebUI changes since then:
  - `78cb3cb0` (2026-11-14), "webui: enforce account roles in the Account REST API". In
    v2.8.0, `/api/db/Account` is behind the JWT check only. Any logged-in account, even one
    with the `user` role, can create an admin account, overwrite another account's password
    hash, change its own roles, delete accounts, and read password hashes through query
    options.
  - `fe001033` (2026-11-16), "check account rules against the stored account, not the
    token". The JWT has no expiry and carries the roles it was issued with, so a token keeps
    its rights after the account is demoted or deleted.
  - `1a461d63` (2026-10-02), "Restrict .env permissions for generated secrets".
- On an Obcell the WebUI listens on 127.0.0.1 only, behind Caddy and Authelia, so only
  operators reach it. The reference Obcell has one WebUI account. The exposure is small now,
  but real as soon as there is a second account.
- The reference Obcell's `/usr/lib/node_modules/open5gs/.env` is mode `0644`
  (`open5gs:open5gs`), readable by every local user, including service users. It holds the
  JWT secret, so whoever reads it can make WebUI tokens. The WebUI runs as root
  (no `User=` in its unit), so `0600` works.

## Steps

1. Check for an Open5GS release after v2.8.0 that has these commits, and the PPA's version.
   If there is one, moving `open5gs_version` may be all that's needed. Check whether it locks
   `jwa` 1.4.2 or newer: then `open5gs_webui_npm_overrides` can go.
2. Otherwise, **ask the human**: build the WebUI from a pinned upstream commit, or apply the
   three commits as patches to v2.8.0 in the build (`roles/common/tasks/git_patched.yml` does
   this for other sources).
3. Set the `.env` to `0600` in the install step, and on boxes where the WebUI is already
   installed.
4. Test in a container: `upgrade-smoke.sh … webui 26` (login, data unchanged), plus an API
   call showing that a `user`-role account can't create an admin account. Then the matrix.
5. Apply on the reference Obcell with the human's OK (WebUI rebuild, about 3 minutes).

## Done when

- [x] A `user`-role account gets a refusal on `POST /api/db/Account` in a test container.
- [x] The WebUI's `.env` is `0600` after `site.yml`, and existing logins still work.
- [ ] The matrix passes; the reference Obcell has it (with the human's OK), `changed=0` after.
      (Matrix: passes, see Findings. Reference Obcell: waiting for the human's OK.)

## Findings

### 2026-11-23: the three upstream commits applied as patches

The human chose patches. There is still no release after v2.8.0.

**Changes:**

- `roles/open5gs/files/webui-{1a461d63,78cb3cb0,fe001033}.patch`: the upstream commits
  verbatim (`git format-patch` from GitHub, with author and date). They apply to v2.8.0 without
  fuzz. The only difference is a 3-line offset in `server/routes/db.js`, because the EIR commit
  in between (`7953b008`, not taken) adds 3 lines there. The fixes don't depend on it.
- `open5gs_webui_patches` (group_vars) lists them. The build copies them into its directory
  and runs `git apply` for each one before the npm steps: all or nothing, no fuzz, so a patch
  that stops fitting stops the build.
- The build stamp lists them (`… jwa@1.4.2 +1a461d63 +78cb3cb0 +fe001033`), so every box
  rebuilds its WebUI once.
- `.env`: the install step sets the copied file to `0600`. The patched WebUI also tightens an
  existing `.env` at start, and creates a new one as `0600`.
- `tests/lxd/webui-roles.py`, run by `upgrade-smoke.sh … roles`, and the `.env` mode in
  `upgrade-smoke.sh … state`. Docs: testing.md, configuration.md, upgrades.md.

**Role checks on the 24.04 container**, before and after the patched build
(`upgrade-smoke.sh 24.04 webui 26`, 114 s, `changed=10`):

| Check (from a `user`-role account unless noted) | v2.8.0 as before | Patched |
|---|---|---|
| Create an admin account (`POST /api/db/Account`) | **ALLOWED (201)** | refused (403) |
| Read password hashes (`?distinct=hash`, `?select=+hash`, `?select=hash`) | **YES, all three** | no |
| Give itself the admin role (`PATCH` own account) | **YES** | no (200, roles dropped) |
| Change its own password | yes (200) | yes (200) |
| Use its token after the account is deleted | **ALLOWED (200)** | refused (401) |
| Admin: create, list, delete an account | PASS | PASS |
| `.env` mode | 644 | 600 |
| Data fingerprint / WebUI login | 19bb693698260a36 / PASS | the same / PASS |

The test removed every account it made: the fingerprint is the same before and after it. After
the rebuild the WebUI has 0 restarts and its journal is clean.

**A brand-new WebUI** (22.04 container: WebUI tree and accounts removed, then
`upgrade-smoke.sh 22.04 webui 26`, 106 s): the patched WebUI created `.env` as `0600` itself,
the default admin account came back, and the login and all role checks pass.

**Read-only preview on the reference Obcell** with this branch (still on Node.js 24):
`changed=4`, the same four tasks as for the Node.js 26 move. The rebuild now includes the
patches: `WebUI: open5gs 2.8.0 node 24 -> open5gs 2.8.0 node 26 jwa@1.4.2 +1a461d63 +78cb3cb0 +fe001033`.

**Matrix at 4662940** (all existing containers; 26.04 went from the unpatched to the patched
WebUI in this run), then `upgrade-smoke.sh <release> roles` on each:

| Release | ansible-core | Install | Health | Idempotent | NG Setup | UE end-to-end | Minutes | Role checks | `.env` |
|---|---|---|---|---|---|---|---|---|---|
| 22.04 | 2.17.14 (inside) | PASS | PASS | PASS | PASS | PASS | 12 | all as expected | 600 |
| 24.04 | 2.20.11 (inside) | PASS | PASS | PASS | PASS | PASS | 16 | all as expected | 600 |
| 26.04 | 2.20.11 (inside) | PASS | PASS | PASS | PASS | PASS | 17 | all as expected | 600 |

Left: the reference Obcell, with the human's OK. One `site.yml` run moves it to Node.js 26 and
the patched WebUI together (the preview above).
