---
id: 008
title: Reboot test on the reference Obcell
status: done
where: reference Obcell
needs_human: yes      # rebooting the live Obcell needs an explicit OK, and someone near the box
depends_on: [007]
---

## Goal

Show that an Obcell comes back by itself after a power cycle, with the cell still **off**.

## Context

- This has never been tested since the Obcell was automated.
- Things that only matter at boot:
  - `/etc/iptables/rules.v4` (UE NAT);
  - `ip_forward`;
  - the Docker cpusets;
  - `gnb-n40` disabled;
  - the n40-control service;
  - tailscaled;
  - the avahi interface setting;
  - the USB autosuspend udev quirk;
  - the rtl-sdr driver blacklist;
  - the Caddy certificates from tailscaled.

## Steps

1. **Ask the human** for a time when nobody is using the Obcell. Make sure the cell is off.
2. `obcell status` and `ansible-playbook verify.yml --limit <host>` beforehand; save the output.
3. `sudo reboot`. Wait, then reconnect.
4. Run `obcell status` and verify.yml again, and compare. Also check:
   - `systemctl is-active gnb-n40` is `inactive`;
   - `sudo iptables -t nat -S POSTROUTING | grep 10.45` shows the UE NAT;
   - Homepage, Grafana, Open Live and Intercom load via the tailnet name;
   - `lsusb` shows the LimeSDR.
5. Record any manual step that was needed, and turn it into a fix task.

## Done when

- [x] After the reboot, verify.yml passes with no manual steps.
- [x] The gNB stayed off.

## Findings

### 2026-11-21: reboot done, passed with no manual steps

The human rebooted the reference Obcell at 12:21 (cell off, radio feed off). Checked ~3 minutes after boot:

| Check | Result |
|---|---|
| `ansible-playbook verify.yml` | ok=9 changed=0 failed=0 |
| `ansible-playbook site.yml --check --diff` | ok=154 changed=0 failed=0 |
| `obcell status` | off air, 18/18 Open5GS services, containers 7/7 + 5/5 + 11/11, 13/13 services answering, no alerts |
| gNB | `gnb-n40` inactive + disabled, CPUAffinity/AllowedCPUs 0-1 |
| UE NAT / forwarding | `-A POSTROUTING -s 10.45.0.0/16 ! -o ogstun -j MASQUERADE`, ip_forward=1, ogstun 10.45.0.1/16 |
| Tailnet | tailscaled up; Homepage (443), Grafana (3443), Open Live (7443), Intercom (8443) answer on the ts.net name with valid certificates |
| USB | `lsusb` shows the LimeSDR Mini and the RTL-SDR; usb1 power/control `on`; no overcurrent messages |
| Snapshot diff | the reboot-test snapshot (`~/obcell-backups/reboot-test/snapshot.sh`) is identical to the one from 2026-11-19 |

No manual steps were needed, so there are no fix tasks.

### 2026-11-22: second reboot, passed with no manual steps

Run again after the Ubuntu release work (tasks 001-005) and OwnTracks (task 011), so the Obcell now also runs an OwnTracks stack. The reference Obcell was rebooted at the human's request at 13:17 (cell off, radio feed off). The before-state was saved at 13:15 and compared about 2 minutes after boot:

| Check | Result |
|---|---|
| Snapshot diff (`snapshot.sh`, now with an OwnTracks section) | identical before and after |
| `ansible-playbook verify.yml` | ok=11 changed=0 failed=0 |
| `ansible-playbook site.yml --check --diff` | ok=168 changed=0 failed=0 |
| `obcell status` | off air, 18/18 Open5GS services, containers 7/7 + 5/5 + 11/11 + 1/1 (OwnTracks), 14/14 services answering, no alerts, radio feed off |
| gNB | `gnb-n40` inactive + disabled, CPUAffinity/AllowedCPUs 0-1 |
| UE NAT / forwarding | `-A POSTROUTING -s 10.45.0.0/16 ! -o ogstun -j MASQUERADE`, ip_forward=1, ogstun 10.45.0.1/16 |
| Tailnet | all nine HTTPS sites answer on the ts.net name with valid certificates (Authelia redirect, or 200 for the Intercom guest page and the OwnTracks `/join/` page) |
| USB | `lsusb` shows the LimeSDR Mini and the RTL-SDR; usb1 power/control `on` |
| Failed units | none |

No manual steps were needed, so there are no fix tasks.

Correction to the 2026-11-21 row "no overcurrent messages": the kernel logs one `usb usb1-port4: over-current condition` at every boot, that boot included. Port 4 is a known dead connector on the reference hardware. That is a hardware fault the playbook cannot fix, so it gets no task.
