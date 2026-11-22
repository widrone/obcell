---
id: 012
title: OwnTracks from the open internet (Tailscale Funnel), deferred
status: blocked       # deferred by the owner (2026-11-22): don't start it until they ask
where: reference Obcell
needs_human: yes      # the tailnet policy, and the owner asking for it
depends_on: [011]
---

## Goal

Phones without Tailscale report to the Obcell from anywhere with internet, through Tailscale
Funnel. Only the post URL is public.

## Context

- Already built and tested (task 011): `owntracks_funnel: true` makes the role turn Funnel on
  for `https://<tailnet name>:10000/pub/<token>`, aimed at a Caddy listener on 127.0.0.1 that
  passes the post URL and gives 404 for everything else. `verify.yml` checks it.
- The steps, and why port 10000: [configuration.md, "OwnTracks"](../configuration.md#owntracks-where-the-crew-is).
- The reference Obcell's node has no `funnel` capability in the tailnet policy yet; the role
  stops with a pointer when that's missing.

## Steps

1. Human: allow Funnel for the node (`nodeAttrs`, `"attr": ["funnel"]`).
2. Set `owntracks_funnel: true` in the host vars; apply with `--tags owntracks,frontdoor,cli`.
3. Phones set up before hold the tailnet URL: scan the new setup code.

## Done when

- [ ] `verify.yml` passes on the reference Obcell, including the Funnel check.
- [ ] A phone without Tailscale, on mobile data, shows up on the map.
- [ ] From outside the tailnet, `https://<tailnet name>:10000/` gives 404.

## Findings

### 2026-11-22

Deferred by the owner: Funnel is not needed for the reference Obcell for now.
