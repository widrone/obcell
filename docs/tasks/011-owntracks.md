---
id: 011
title: OwnTracks location tracking, public through Tailscale Funnel
status: in-progress
where: test machine, then the reference Obcell
needs_human: yes      # the tailnet policy (Funnel), the apply on the reference Obcell, a real phone
depends_on: []
---

## Goal

The crew's phones run the OwnTracks app and report where they are to the Obcell, from the
internet, the tailnet, the LAN and the Obcell's own cell. The map is behind the operator login.

## Context

- Recorder: <https://github.com/owntracks/recorder>, Docker image `owntracks/recorder`.
- Design and settings: [configuration.md, "OwnTracks"](../configuration.md#owntracks-where-the-crew-is).
- HTTP mode, not MQTT: one HTTPS endpoint that fits Caddy and Funnel; no broker.
- No logins on the phones (asked for: onboarding must be one scan). The post URL ends in a
  secret token instead; Caddy maps `/pub/<token>` to the Recorder's `/pub`, and everything
  else goes to Authelia. The app sends its own username and device ID (`X-Limit-U`/`-D`).
- Setup: a QR code with `owntracks:///config?inline=<base64 JSON>` (HTTP mode + URL only).
  Android's app URL-decodes the value before base64, so `+` and `=` must be escaped
  (`urlencode`). The page is also on plain `http://<LAN IP>/join/`, with a second code to the
  page for Android cameras that don't open custom schemes.
- Funnel on `:10000`: Funnel offers only 443, 8443 and 10000, and Caddy already has 443 and
  8443 on the tailnet name. TCP 10000 is free (the Intercom SFU uses UDP 10000).

## Steps

1. LXD test on the test machine: install, verify, idempotent re-run. Post a position to the
   token URL and see it in the API, check that the wrong token and plain `/pub` don't get
   through, and decode the setup link from the page.
2. Human: allow Funnel for the reference Obcell's node in the tailnet policy (`nodeAttrs`,
   `"attr": ["funnel"]`).
3. Human asks: apply on the reference Obcell (`owntracks_funnel: true` in its host vars).
4. A real iPhone and Android phone: scan the setup code (camera), then from mobile data the
   phones show on the map.

## Done when

- [ ] The LXD matrix passes with OwnTracks on (install, verify, idempotent `changed=0`).
- [ ] The reference Obcell runs it; `verify.yml` passes, including the Funnel check.
- [ ] An iPhone and an Android phone are set up from the QR code and show up on the map from
      mobile data. From outside the tailnet, `https://<tailnet name>:10000/` gives 404.

## Findings

### 2026-11-22

Design: first one app login per phone (Caddy basic auth, 5b6d22a). Then, as asked for easy
onboarding, no logins: a secret token in the post URL and a setup page with a QR code
(9b7b667). The token moved from the Caddyfile to Caddy's environment, so `--check --diff`
can't print it (900d6e0).

| Release | ansible-core | Install | Health | Idempotent | NG Setup | UE end-to-end | Minutes |
|---|---|---|---|---|---|---|---|
| 22.04 (obcell-jammy) | 2.17.14 (inside) | PASS | PASS | PASS | SKIP | SKIP | 10 |

(900d6e0, existing container, phases install,idempotent.)

- **End to end in the container:** 18/18 checks.
  - Token URL: 200, and a phone without a username lands as `owntracks/phone`.
  - Wrong token, plain `/pub` or an empty token: 303, sent to the login.
  - Map and API: 302. `/join/`: 200 on HTTPS and plain HTTP.
  - The page's setup link decodes to `{"mode": 3, "url": …, "auth": false}`.
  - The token is not in the Caddyfile, and the store is 0700.
- **Funnel listener** (by hand in the container, as rendered with `owntracks_funnel: true`):
  token post 200, everything else 404, nothing listening on the LAN address.
- **Reference Obcell:** applied 900d6e0 with `--skip-tags srsue` (changed=18), then 985bc59
  with `--tags cli` (changed=1).
  - Re-check: only the srsUE patch file is pending (a rebuild, skipped on purpose).
  - `verify.yml`: OK.
  - Live: `/join/` 200 on LAN HTTPS, LAN HTTP and the tailnet name (Let's Encrypt), a
    `ping/ping` post through the token URL 200, `probe_success{service="owntracks"}` 1.
- **Funnel not on yet:** the node has no `funnel` capability in the tailnet policy. Until it
  does, the setup code holds the tailnet URL, so phones need the Tailscale app.
- **Still to do:** 24.04 and 26.04 with OwnTracks, the Funnel steps, real phones.
