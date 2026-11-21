---
id: 007
title: Apply the pending changes on the reference Obcell
status: done
where: reference Obcell
needs_human: yes      # applying to the live Obcell needs an explicit OK in the conversation
depends_on: []
---

## Goal

The reference Obcell matches the repo exactly: `ansible-playbook site.yml --limit <host> --check --diff`
reports `changed=0`.

## Context

Since 2026-11-20 the dry run has shown the same 6 intended changes. They were accepted but
not applied:

| Task | Change |
|---|---|
| base: NAT for the UE pool (at boot) | "Managed by obcell" header in `/etc/iptables/rules.v4` (the rules are the same) |
| ocudu: patch files | adds the SoapySDR clock patch to `~/obcell/patches` |
| obcell_cli: Slides | slide PNG ownership root → the Obcell user |
| openlive: Secret files | header comment in `~/openlive/.env` (values the same; diff hidden) |
| monitoring: Static configs | sdr-exporter learns the LimeSDR USB and USRP B2xx USB ids (restarts sdr-exporter) |
| monitoring: Static configs | `mkdash.py` reads LAN interface/name from env (dashboard output is byte-identical) |

Since 2026-11-21 the dry run also shows the **rename to Obcell** (the box was built as "kit").
On the reference Obcell it reports `changed=29` in total. Besides the 6 changes above:

| Task | Change |
|---|---|
| obcell_cli: Obcell directories, CLI, Runbook, Obcell on PATH | new `~/obcell/obcell` and `~/obcell/README.md`; `~/.local/bin/obcell` |
| obcell_cli: Old command name `kit` | `~/.local/bin/kit` now points at `~/obcell/obcell` (`obcell_legacy_kit_command`) |
| obcell_cli: Backups move | `mv ~/kit-backups ~/obcell-backups` (old `kit-config-*` archives are kept and still restore; `obcell backup` only prunes `obcell-config-*`) |
| obcell_cli: Retire ~/kit (post_tasks) | removes `~/kit/kit`, `~/kit/README.md` and patch copies identical to `~/obcell/patches`; keeps `~/kit` if anything else is in it. Skipped in check mode (shell) |
| obcell_cli: Slide 2 from before the rename | removes `02-the-kit.{html,png}` from `~/presentation` and Homepage's images |
| monitoring: Presentation slides on Homepage | adds `02-the-obcell.png` |
| *: patch directory / patch files | the patch copies move from `~/kit/patches` to `~/obcell/patches` (ocudu, srsue, openlive, intercom) |
| cell_control: control.py (+ Restart control) | metric `kit_unit_state`/`kit_unit_enabled` → `obcell_unit_state`/`obcell_unit_enabled`; comments. Restarts n40-control only, not the gNB |
| monitoring: Alert rules / rules file from before the rename (+ Reload prometheus) | `rules/kit.yml` → `rules/obcell.yml`, using the new metric names. The old metric's history stays under the old name |
| monitoring: Stack files, Blackbox probes config (+ Reload blackbox) | comments; Homepage tile "Kit health" → "Obcell health", title and bookmark text |
| monitoring: Homepage links… (custom.js), Static configs | header/comment text; `mkdash.py` env vars renamed to `OBCELL_*` |
| intercom: Stack files, Radio bridge script | comments; the bridge accepts the CLI's new `Origin: obcell`. The script is baked into the image, so "Stack up" rebuilds and **recreates radio-bridge** (a few seconds without the radio feed). The dry run shows that task as `ok` because check mode doesn't build |

Applied separately already: Homepage link rewriting (`--tags homepage`) and the WebUI
behind the login (`--tags frontdoor`).

## Steps

1. On the reference Obcell: `ansible-playbook site.yml --limit <host> --check --diff`. Confirm the drift is
   exactly the tables above. Anything new must be explained first.
2. **Stop and ask the human** to approve applying it. Check `systemctl is-active gnb-n40`;
   if the cell is on air, apply later.
3. `ansible-playbook site.yml --limit <host>`, then `ansible-playbook verify.yml --limit <host>`.
4. The dry run again must give `changed=0`.

## Done when

- [x] A human approved it (note who and when under Findings).
- [x] verify.yml passes, and the dry run reports `changed=0`.

## Findings

### 2026-11-21

- Approved by the owner (widrone) in the conversation: "apply the rename to the Obcell".
- Before: `gnb-n40` inactive and disabled. Backup taken with the old CLI
  (`kit-config-20261121-1208.tar.gz`, now in `~/obcell-backups`). The dry run showed the tables
  above plus the slide-2 clean-up (`changed=30`).
- `ansible-playbook site.yml --limit <host>`: `ok=164 changed=29 failed=0`. Handlers: Restart
  control, Reload prometheus; radio-bridge rebuilt by "Stack up"; `~/kit` retired.
- After: `verify.yml` `changed=0 failed=0`; the dry run `changed=0`; `gnb-n40` still inactive
  and disabled.
- Checked by hand:
  - `~/kit` and `~/kit-backups` are gone;
  - `kit` and `obcell` both link to `~/obcell/obcell`;
  - Prometheus loads only `rules/obcell.yml` (13 rules) and has `obcell_unit_state` series;
  - only `02-the-obcell` slides are left;
  - `obcell radio` answers.

