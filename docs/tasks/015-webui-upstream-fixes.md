---
id: 015
title: Pick up the upstream WebUI access-control fixes, and keep the WebUI's .env private
status: todo
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

- [ ] A `user`-role account gets a refusal on `POST /api/db/Account` in a test container.
- [ ] The WebUI's `.env` is `0600` after `site.yml`, and existing logins still work.
- [ ] The matrix passes; the reference Obcell has it (with the human's OK), `changed=0` after.

## Findings
